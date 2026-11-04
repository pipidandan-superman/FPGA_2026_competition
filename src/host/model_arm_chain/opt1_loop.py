# Option 1 (PC-only golden chain): camera -> YOLO -> policy head -> BLE -> arm.
#   [PC USB camera] -> YOLOv8n(COCO) -> PolicyHead(script stand-in | pi0 later)
#   -> bleak/WinRT -> WeBotPi 013a (FFE2 write / FFE1 notify) -> STM32 -> servo
# Laws honoured:
#  - bleak x DSHOW mutual exclusion: BLE connects BEFORE the camera opens,
#    camera runs in its own thread.
#  - motion frames: read-back reconciliation + retry lives in ArmLink.move.
#  - gesture-line data isolation: COCO yolov8n.pt only, never model/best.pt.
# Verdicts: ARM_LINK_PASS / ARM_LINK_FAIL, LOOP_PASS (first debounced trigger
# executed + verified), run summary + LATENCY_BASELINE in result.json.
import argparse
import asyncio
import json
import os
import sys
import threading
import time
from pathlib import Path

import cv2

# YOLO env must be set BEFORE the ultralytics import below (it reads these at
# import time), and the import must precede any bleak/WinRT BLE activity:
# torch c10.dll init fails with WinError 1114 if loaded while a BleakScanner
# is ACTIVE (10-16, two live runs burned; reverse order coexists fine).
os.environ.setdefault("YOLO_CONFIG_DIR", str(
    Path(__file__).resolve().parent / "var" / "ultralytics_config"))
os.environ.setdefault("MPLCONFIGDIR", str(
    Path(__file__).resolve().parent / "var" / "matplotlib_config"))
os.environ.setdefault("YOLO_AUTOINSTALL", "false")
os.environ.setdefault("YOLO_OFFLINE", "true")
os.environ.setdefault("PYTHONNOUSERSITE", "1")
os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")
Path(os.environ["YOLO_CONFIG_DIR"]).mkdir(parents=True, exist_ok=True)

from ultralytics import YOLO  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from arm_link import ArmLink, verdict_line   # noqa: E402
from policy import build_policy              # noqa: E402

EVIDENCE_ROOT = Path("E:/competition/4_metrics/logs").resolve()
TARGET_MAC = "98:EA:A0:21:01:3A"   # WeBotPi 013a in arm socket (B0 canon)
DEFAULT_WEIGHTS = EVIDENCE_ROOT / "2026-10-05_object_webcam_run01/yolov8n.pt"


def parse_args():
    p = argparse.ArgumentParser(description="Option 1 PC-only model+arm loop")
    p.add_argument("--run-dir", required=True, help="new dir under 4_metrics/logs")
    p.add_argument("--camera", type=int, default=0)
    p.add_argument("--target-mac", default=TARGET_MAC)
    p.add_argument("--weights", default=str(DEFAULT_WEIGHTS))
    p.add_argument("--policy", default="script", choices=["script", "pi0"])
    p.add_argument("--trigger-class", default="bottle")
    p.add_argument("--conf", type=float, default=0.35)
    p.add_argument("--debounce", type=int, default=5)
    p.add_argument("--max-seconds", type=float, default=300.0)
    p.add_argument("--no-arm", action="store_true",
                   help="camera+YOLO+policy only (dry, no BLE, no motion)")
    p.add_argument("--headless", action="store_true")
    return p.parse_args()


def write_json(path, value):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


class CameraThread(threading.Thread):
    """DSHOW grabber: decouples capture from inference so policy sees the
    freshest frame (same pattern as pai teleop CameraGrabber)."""

    def __init__(self, index):
        super().__init__(daemon=True)
        self.index = index
        self.latest = None
        self.latest_t = 0.0
        self.frames = 0
        self.error = None
        self._stop = threading.Event()

    def run(self):
        cap = None
        try:
            for backend in (cv2.CAP_DSHOW, cv2.CAP_MSMF, cv2.CAP_ANY):
                cap = cv2.VideoCapture(self.index, backend)
                if cap.isOpened():
                    break
                cap.release()
                cap = None
            if cap is None:
                self.error = "camera open failed (DSHOW/MSMF/ANY)"
                return
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            cap.set(cv2.CAP_PROP_FPS, 30)
            while not self._stop.is_set():
                ok, frame = cap.read()
                if not ok:
                    self.error = "camera read failed"
                    return
                self.latest = frame
                self.latest_t = time.time()
                self.frames += 1
        finally:
            if cap is not None:
                cap.release()

    def stop(self):
        self._stop.set()


def detect_rows(result):
    rows = []
    if result.boxes is None:
        return rows
    for box in result.boxes:
        cid = int(box.cls.item())
        rows.append({"label": str(result.names[cid]),
                     "conf": round(float(box.conf.item()), 4),
                     "xyxy": [round(float(v), 1) for v in box.xyxy[0].tolist()]})
    rows.sort(key=lambda r: -r["conf"])
    return rows


async def run(args, run):
    events_path = run / "opt1_events.jsonl"
    evlog = events_path.open("w", encoding="utf-8")

    def log(kind, **kw):
        ev = {"t": round(time.time(), 3), "kind": kind}
        ev.update(kw)
        evlog.write(json.dumps(ev, ensure_ascii=True) + "\n")
        evlog.flush()

    link = None
    if not args.no_arm:
        link = ArmLink(args.target_mac)
        try:
            mtu = await link.connect()
        except Exception as exc:
            log("verdict", v="ARM_LINK_FAIL", err="%s:%s" % (type(exc).__name__, exc))
            print(verdict_line("ARM_LINK_FAIL", err=str(exc)))
            print("hint: is the arm powered (servo lock sound)? is 0214 "
                  "unpowered (its BIND would grab the link)?")
            return 2
        log("link", mtu=mtu, mac=args.target_mac)
        rb = await link.read_pos(1)
        if rb is None:
            log("verdict", v="ARM_LINK_FAIL", stage="initial_prad")
            print(verdict_line("ARM_LINK_FAIL", stage="initial_prad"))
            await link.disconnect()
            return 2
        log("verdict", v="ARM_LINK_PASS", pos0=rb["pos"], rtt_ms=rb["rtt_ms"])
        print(verdict_line("ARM_LINK_PASS", pos0=rb["pos"]))

    # BLE is up (or dry mode): camera may open now (bleak x DSHOW law).
    cam = CameraThread(args.camera)
    cam.start()
    t0 = time.time()
    while cam.latest is None and cam.error is None and time.time() - t0 < 10:
        await asyncio.sleep(0.05)
    if cam.error or cam.latest is None:
        log("verdict", v="CAMERA_FAIL", err=cam.error)
        print(verdict_line("CAMERA_FAIL", err=cam.error))
        cam.stop()
        if link:
            await link.disconnect()
        return 2
    log("camera", frames_so_far=cam.frames)
    print("CAMERA_OPEN_PASS")

    model = YOLO(args.weights, task="detect")
    print("YOLO_LOAD_PASS")

    policy = build_policy(args.policy, trigger_class=args.trigger_class,
                          debounce=args.debounce, conf=max(args.conf, 0.5))
    print("POLICY_READY name=%s" % policy.name)

    loop_pass = False
    fired = 0
    cycles = 0
    yolo_ms_all, e2e_ms_all, rtt_ms_all = [], [], []
    reason = "bounded_timeout"
    started = time.time()

    if not args.headless:
        cv2.namedWindow("opt1 model+arm", cv2.WINDOW_NORMAL)
        cv2.resizeWindow("opt1 model+arm", 960, 720)

    try:
        while time.time() - started < args.max_seconds:
            if (run / "STOP").exists():
                reason = "stop_file"
                break
            frame, t_cap = cam.latest, cam.latest_t
            if frame is None:
                await asyncio.sleep(0.02)
                continue
            tick = time.perf_counter()
            result = model.predict(frame, device="cpu", imgsz=640,
                                   conf=args.conf, verbose=False)[0]
            yolo_ms = (time.perf_counter() - tick) * 1000.0
            rows = detect_rows(result)
            cycles += 1
            yolo_ms_all.append(yolo_ms)

            obs = {"t": t_cap, "frame_id": cam.frames, "detections": rows,
                   "yolo_ms": round(yolo_ms, 2)}
            t_decide = time.time()
            action = policy.act(obs)
            if not args.headless:
                annotated = result.plot()
                cv2.putText(annotated,
                            "opt1 | yolo %.0fms | fired %d | %s" %
                            (yolo_ms, fired, policy.name),
                            (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65,
                            (0, 255, 0), 2, cv2.LINE_AA)
                cv2.imshow("opt1 model+arm", annotated)
                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    reason = "user_quit"
                    break
                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    reason = "user_quit"
                    break

            rec = {"cycle": cycles, "frame_id": cam.frames,
                   "yolo_ms": round(yolo_ms, 2), "hits": policy._hits,
                   "top": rows[:4], "action": action}
            log("cycle", **rec)

            if action and link is not None:
                sid, delta, t_ms = action["sid"], action["delta"], action["t_ms"]
                pos0 = (await link.read_pos(sid))["pos"]
                fwd = await link.move(sid, pos0 + delta, t_ms)
                back = await link.move(sid, pos0, t_ms) if fwd.get("ok") else None
                ok = bool(fwd.get("ok")) and bool(back and back.get("ok"))
                if back:
                    e2e = round((time.time() - t_cap) * 1000.0, 1)
                    e2e_ms_all.append(e2e)
                rtt_ms_all.append(fwd.get("prad_rtt_ms", 0))
                log("action", sid=sid, pos0=pos0, fwd=fwd, back=back, ok=ok,
                    e2e_ms=e2e_ms_all[-1] if e2e_ms_all else None)
                policy.note_executed(action, {"ok": ok})
                if ok:
                    fired += 1
                    if not loop_pass:
                        loop_pass = True
                        log("verdict", v="LOOP_PASS", fired=fired)
                        print(verdict_line("LOOP_PASS", fired=fired))
            await asyncio.sleep(0.01)
    finally:
        cam.stop()
        if not args.headless:
            try:
                cv2.destroyAllWindows()
            except cv2.error:
                pass
        if link:
            await link.disconnect()
        evlog.close()

    summary = {
        "result": "OPTION1_LOOP_PASS" if loop_pass else "OPTION1_NO_TRIGGER",
        "reason": reason,
        "policy": policy.name,
        "trigger_class": args.trigger_class,
        "cycles": cycles,
        "fired": fired,
        "arm_link": "pass" if (args.no_arm or loop_pass or cycles > 0) else "fail",
        "latency_ms": {
            "yolo_mean": round(sum(yolo_ms_all) / len(yolo_ms_all), 1) if yolo_ms_all else None,
            "yolo_max": round(max(yolo_ms_all), 1) if yolo_ms_all else None,
            "ble_prad_rtt_mean": round(sum(rtt_ms_all) / len(rtt_ms_all), 1) if rtt_ms_all else None,
            "action_e2e_mean": round(sum(e2e_ms_all) / len(e2e_ms_all), 1) if e2e_ms_all else None,
            "action_e2e_max": round(max(e2e_ms_all), 1) if e2e_ms_all else None,
        },
    }
    write_json(run / "result.json", summary)
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if loop_pass else 1


def main():
    args = parse_args()
    run_dir = Path(args.run_dir).resolve()
    if not run_dir.is_relative_to(EVIDENCE_ROOT):
        raise SystemExit("--run-dir must be under E:/competition/4_metrics/logs")
    if run_dir.exists() and any(run_dir.iterdir()):
        raise SystemExit(f"run dir must be new and empty: {run_dir}")
    run_dir.mkdir(parents=True, exist_ok=True)
    write_json(run_dir / "config.json", vars(args) | {"python": sys.executable})
    return asyncio.run(run(args, run_dir))


if __name__ == "__main__":
    raise SystemExit(main())
