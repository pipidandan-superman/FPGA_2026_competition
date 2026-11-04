#!/usr/bin/env python3
"""User-driven live-camera seven-gesture validation for the frozen V8 PS+PL path.

v2 (2026-11-03 pspl_v8n_gesture7_boardprep_run01 A/B/C knives):
- speed: the PL heads run through the in-process pl_heads_runtime (init once
  per process; soft reset + FSM replay + doorbells per frame, no runpy
  re-execution, no per-frame fixed 0.05 s sleeps -- the runtime owns reset
  pacing and retries a failed frame once with a full FSM reload).
- display: every decode-passing detection draws a bounding box via
  pix_frame_display_0 (BoxOsd, net3 immediate-show law: show now, hold
  ~2 frame periods, never gate display on an action margin) plus the PL text
  strip; boxes use the inverse-letterbox geometry (the driver decode now
  returns display-pixel xyxy).
- sensitivity: decode/display confidence is parameterized (default 0.50,
  measured to sit inside the empty gap between empty-background Stop false
  positives <=0.454 and real gestures >=0.612), the seven-gesture judgment
  gate stays >= --judge-conf (0.55), and every frame records the
  pre-threshold top-1 baseline (int8 record).

Still no actuator output; still an additional validation candidate -- not a
modification of the frozen PSPL_YOLOV8N_RESIDENT package.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import sys
import time

import numpy as np

ROOT = Path(os.environ.get("PSPL_ROOT", str(Path(__file__).resolve().parents[2])))
BOARD_SW = ROOT / "sw/board"
sys.path.insert(0, str(BOARD_SW))

import hybrid_pipeline_resident as pipeline
from t1_gesture_main import (GESTURE_NAMES, BoxOsd, PlTextOsd, VdmaCam,
                             letterbox_rgb, model_input)

BIT = ROOT / "sw/board_runtime/hybrid_heads_ic64_fix.bit"
EXPECTED_BIT_SHA256 = os.environ.get("EXPECTED_BIT_SHA256", "72b358ff75a8d1c1bda519da248bd94fb4bdc236dd16fcca36eb4fc1262f7a58")
STOPPING = False


def request_stop(signum, frame):
    global STOPPING
    STOPPING = True


def safe_name(text):
    return text.replace(" ", "_")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=float, default=0.0,
                        help="0 means no wall-clock limit")
    parser.add_argument("--max-frames", type=int, default=0,
                        help="0 means no inference-frame limit")
    parser.add_argument("--hits-per-gesture", type=int, default=2,
                        help="consecutive matching top-1 frames before advancing")
    parser.add_argument("--display-conf", type=float, default=0.50,
                        help="decode/display confidence gate (0.50: empty-bg "
                             "Stop false positives measured <=0.454, real "
                             "gestures >=0.612, gap 0.46-0.60 empty)")
    parser.add_argument("--judge-conf", type=float, default=0.55,
                        help="seven-gesture judgment gate (target progression)")
    parser.add_argument("--hold-s", type=float, default=5.0,
                        help="box/strip hold after a detection (>= 2 frame periods)")
    parser.add_argument("--evidence", type=Path, default=None)
    args = parser.parse_args()
    if args.hits_per_gesture < 1:
        parser.error("--hits-per-gesture must be >= 1")

    stamp = time.strftime("%Y%m%d_%H%M%S", time.gmtime())
    evidence = args.evidence or ROOT / "evidence" / ("live_gesture7_" + stamp)
    evidence.mkdir(parents=True, exist_ok=False)
    session_path = evidence / "session.jsonl"
    results_path = evidence / "results.jsonl"

    from pynq import MMIO, Overlay

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    cam = None
    osd = None
    box_osd = None
    frame_index = 0
    target_index = 0
    target_hits = 0
    observed = []
    complete = False
    input_hashes = set()
    started = time.monotonic()
    held_det = None
    hold_until = 0.0

    with session_path.open("a", encoding="utf-8") as session:
        def emit(event, **fields):
            record = dict(event=event, monotonic=round(time.monotonic(), 3), **fields)
            line = json.dumps(record, ensure_ascii=False)
            print(line, flush=True)
            session.write(line + "\n")
            session.flush()

        def show_box_display(det):
            """Safe-update box on pix_frame_display_0; xyxy already in 640x480
            display pixels (inverse letterbox done at decode)."""
            if box_osd is None or box_osd.mmio is None:
                return
            x0, y0, x1, y1 = det["xyxy"]
            l = max(0, min(639, int(x0)))
            r = max(0, min(639, int(x1)))
            t = max(0, min(479, int(y0)))
            b = max(0, min(479, int(y1)))
            if r - l < 4:
                r = min(639, l + 4)
            if b - t < 4:
                b = min(479, t + 4)
            m = box_osd.mmio
            m.write(0x18, 0)
            m.write(0x08, l)
            m.write(0x0C, r)
            m.write(0x10, t)
            m.write(0x14, b)
            m.write(0x18, 1)

        def clear_box():
            if box_osd is not None and box_osd.mmio is not None:
                box_osd.mmio.write(0x18, 0)

        try:
            boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
            emit("GESTURE7_SESSION_START", boot_id=boot_id,
                 bit_sha256=EXPECTED_BIT_SHA256, evidence=str(evidence),
                 sequence=GESTURE_NAMES, hits_per_gesture=args.hits_per_gesture,
                 display_conf=args.display_conf, judge_conf=args.judge_conf,
                 hold_s=args.hold_s, action_output="disabled")
            ol = Overlay(str(BIT), download=False)
            required = {"axi_vdma_0", "pix_frame_display_0", "t1_text_osd_0"}
            missing = sorted(required.difference(ol.ip_dict))
            if missing:
                raise RuntimeError("HWH missing required IP: %s" % missing)
            if "t1_preproc_0" in ol.ip_dict:
                raise RuntimeError("Unexpected t1_preproc_0; this candidate owns PS preprocessing")
            emit("HWH_LIVE_CONTRACT_PASS", required=sorted(required),
                 box_osd="pix_frame_display_0", preprocessing="PS letterbox RGB /255")
            ol.download()
            state = Path("/sys/class/fpga_manager/fpga0/state").read_text().strip()
            if state != "operating":
                raise RuntimeError("FPGA state is %s" % state)
            emit("RESIDENT_OVERLAY_DOWNLOAD_PASS", fpga_state=state)

            cam = VdmaCam(ol)
            osd = PlTextOsd(ol)
            box_osd = BoxOsd(ol)
            emit("BOX_OSD_READY", present=box_osd.mmio is not None)
            osd.idle(1)  # NET1 = YOLOv8n in the existing three-model label ROM
            emit("LIVE_CAMERA_READY", next_target=GESTURE_NAMES[target_index],
                 instruction="Hold the requested gesture; change gesture only after GESTURE_TARGET_OBSERVED")

            consecutive_failures = 0
            while not STOPPING:
                if args.seconds and time.monotonic() - started >= args.seconds:
                    break
                if args.max_frames and frame_index >= args.max_frames:
                    break
                vdma = cam.status()
                frame = cam.snapshot()
                if frame is None:
                    emit("CAMERA_FRAME_RETRY", frame_index=frame_index)
                    time.sleep(0.01)
                    continue

                input_sha256 = hashlib.sha256(frame).hexdigest()
                blob = model_input(letterbox_rgb(frame), "yolo")
                blob = np.ascontiguousarray(blob, dtype=np.float32)
                frame_started = time.monotonic()
                try:
                    result = pipeline.run_once(blob, conf=args.display_conf)
                except RuntimeError as exc:
                    if "structural heads PL execution failed" not in str(exc):
                        raise
                    consecutive_failures += 1
                    target_hits = 0
                    emit("LIVE_GESTURE_FRAME_ERROR_RECOVER", error=str(exc),
                         consecutive_failures=consecutive_failures,
                         action="runtime recovery already reloaded FSM; next frame retries")
                    if consecutive_failures >= 3:
                        raise
                    continue
                consecutive_failures = 0
                total_ms = (time.monotonic() - frame_started) * 1000.0
                input_hashes.add(input_sha256)
                if frame_index == 0:
                    (evidence / 'first_input.bgr').write_bytes(frame)
                (evidence / 'last_input.bgr').write_bytes(frame)
                frame_index += 1
                detections = result["detections"]
                top1 = result["top1_baseline"]
                top = max(detections, key=lambda d: d["confidence"]) if detections else None

                # net3 display law: show every decode-passing detection now,
                # hold ~2 frame periods, never let an action gate hide it.
                if top is not None:
                    held_det = top
                    hold_until = time.monotonic() + args.hold_s
                if held_det is not None and time.monotonic() < hold_until:
                    show_box_display(held_det)
                    osd.show(1, held_det["class_id"], held_det["confidence"])
                else:
                    held_det = None
                    clear_box()
                    osd.show(1, None, None)   # resident idle strip
                osd.tick()

                record = dict(frame_index=frame_index, total_ms=round(total_ms, 3),
                              ps_backbone_neck_ms=round(result["ps_backbone_neck_ms"], 3),
                              pl_driver_ms=result["pl_driver_ms"],
                              pl_replay_ms=result["pl_replay_ms"],
                              pl_doorbell_wall_s=result["pl_doorbell_wall_s"],
                              pl_recovered=result["pl_recovered"],
                              display_conf=result["display_conf"],
                              top1_baseline=top1,
                              detections=detections, vdma=vdma,
                              input_sha256=input_sha256)
                with results_path.open("a", encoding="utf-8") as results:
                    results.write(json.dumps(record, ensure_ascii=False) + "\n")
                emit("LIVE_GESTURE_FRAME", **record)
                if top is None:
                    emit("GESTURE_BELOW_THRESHOLD", top1=top1,
                         note="pre-threshold int8 baseline; judgment gate %.2f"
                              % args.judge_conf)

                target = target_index if target_index < len(GESTURE_NAMES) else None
                judged = (top is not None and top["class_id"] == target
                          and top["confidence"] >= args.judge_conf)
                if target is not None and judged:
                    target_hits += 1
                else:
                    target_hits = 0
                if target is not None:
                    emit("GESTURE_TARGET_PROGRESS", target=GESTURE_NAMES[target],
                         consecutive_hits=target_hits, required=args.hits_per_gesture,
                         judged=bool(judged))
                if target is not None and target_hits >= args.hits_per_gesture:
                    class_id = target
                    class_name = GESTURE_NAMES[class_id]
                    stem = "target_%d_%s_frame_%06d" % (class_id, safe_name(class_name), frame_index)
                    (evidence / (stem + ".bgr")).write_bytes(frame)
                    (evidence / (stem + ".json")).write_text(
                        json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
                    observed.append(dict(class_id=class_id, label=class_name,
                                         frame_index=frame_index, confidence=top["confidence"],
                                         evidence=stem + ".json"))
                    emit("GESTURE_TARGET_OBSERVED", class_id=class_id, label=class_name,
                         frame_index=frame_index, confidence=top["confidence"],
                         judged_at_conf=args.judge_conf)
                    target_index += 1
                    target_hits = 0
                    if target_index < len(GESTURE_NAMES):
                        emit("GESTURE_NEXT_TARGET", target=GESTURE_NAMES[target_index])
                    else:
                        complete = True
                        emit("GESTURE7_SEQUENCE_OBSERVED", observed=observed,
                             note="User observation marker; inspect raw frames and JSON before final PASS")
                        break

            summary = dict(result="GESTURE7_SEQUENCE_OBSERVED" if complete else "INCOMPLETE",
                           frames=frame_index, observed=observed,
                           unique_input_frames=len(input_hashes),
                           startup_progress=cam.startup_progress,
                           elapsed_s=round(time.monotonic() - started, 3),
                           display_conf=args.display_conf, judge_conf=args.judge_conf,
                           results="results.jsonl", session="session.jsonl")
            (evidence / "summary.json").write_text(
                json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
            emit("GESTURE7_SESSION_END", **summary)
            return 0
        except Exception as exc:
            emit("GESTURE7_SESSION_FAIL", error=str(exc), frames=frame_index,
                 observed=observed)
            raise
        finally:
            try:
                if box_osd is not None and box_osd.mmio is not None:
                    box_osd.mmio.write(0x18, 0)
                if osd is not None:
                    osd.clear()
            finally:
                if cam is not None:
                    cam.close()
            emit("GESTURE7_RESOURCES_RELEASED")


if __name__ == "__main__":
    sys.exit(main())
