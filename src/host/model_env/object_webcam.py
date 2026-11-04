"""Live COCO object detection from a Windows camera using official YOLOv8n.

This entry point is intentionally separate from the historical gesture viewer.
It records machine-readable detections and a few annotated snapshots, but does
not save a continuous video by default.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import urllib.request

import cv2
import numpy as np


EVIDENCE_ROOT = Path("E:/competition/4_metrics/logs").resolve()
WEIGHTS_URL = "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="YOLOv8n Windows webcam object detection")
    parser.add_argument("--run-dir", required=True, help="new directory under 4_metrics/logs")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--max-seconds", type=float, default=300.0)
    parser.add_argument("--conf", type=float, default=0.35)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--model", default="", help="optional local .pt path; defaults to run-dir/yolov8n.pt")
    parser.add_argument("--headless", action="store_true", help="capture and infer without an OpenCV window")
    return parser.parse_args()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def ensure_weights(path: Path) -> None:
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading official YOLOv8n weights to {path}", flush=True)
    urllib.request.urlretrieve(WEIGHTS_URL, path)
    if path.stat().st_size < 1_000_000:
        raise RuntimeError(f"Downloaded weight is unexpectedly small: {path.stat().st_size} bytes")


def open_camera(index: int) -> tuple[cv2.VideoCapture, str]:
    candidates = [(cv2.CAP_DSHOW, "DSHOW"), (cv2.CAP_MSMF, "MSMF"), (cv2.CAP_ANY, "ANY")]
    for backend, name in candidates:
        cap = cv2.VideoCapture(index, backend)
        if cap.isOpened():
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            cap.set(cv2.CAP_PROP_FPS, 30)
            return cap, name
        cap.release()
    raise RuntimeError(f"Unable to open camera index {index} with DSHOW/MSMF/ANY")


def detection_rows(result) -> list[dict]:
    rows = []
    if result.boxes is None:
        return rows
    for box in result.boxes:
        class_id = int(box.cls.item())
        rows.append(
            {
                "label": str(result.names[class_id]),
                "class_id": class_id,
                "confidence": round(float(box.conf.item()), 5),
                "xyxy": [round(float(value), 1) for value in box.xyxy[0].tolist()],
            }
        )
    return rows


def main() -> int:
    args = parse_args()
    run = Path(args.run_dir).resolve()
    if not run.is_relative_to(EVIDENCE_ROOT):
        raise SystemExit("--run-dir must be under E:/competition/4_metrics/logs")
    if run.exists() and any(run.iterdir()):
        raise SystemExit(f"Run directory must be new and empty: {run}")
    run.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("YOLO_CONFIG_DIR", str(run / "ultralytics_config"))
    os.environ.setdefault("MPLCONFIGDIR", str(run / "matplotlib_config"))
    os.environ.setdefault("YOLO_AUTOINSTALL", "false")
    os.environ.setdefault("PYTHONNOUSERSITE", "1")
    Path(os.environ["YOLO_CONFIG_DIR"]).mkdir(parents=True, exist_ok=True)
    Path(os.environ["MPLCONFIGDIR"]).mkdir(parents=True, exist_ok=True)
    # Import only after the per-run Ultralytics config path exists.
    from ultralytics import YOLO

    weight = Path(args.model).resolve() if args.model else run / "yolov8n.pt"
    started = time.monotonic()
    frames = 0
    inference_frames = 0
    detections_total = 0
    latencies_ms: list[float] = []
    last_rows: list[dict] = []
    last_annotated = None
    reason = "unknown"
    cap = None
    events_path = run / "detections.jsonl"

    try:
        ensure_weights(weight)
        model = YOLO(str(weight), task="detect")
        cap, backend = open_camera(args.camera)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps_camera = float(cap.get(cv2.CAP_PROP_FPS))
        write_json(
            run / "config.json",
            {
                "result": "OBJECT_WEBCAM_CONFIG",
                "python": sys.executable,
                "model": str(weight),
                "model_sha256": sha256(weight),
                "weights_url": WEIGHTS_URL if weight.name == "yolov8n.pt" else None,
                "camera_index": args.camera,
                "backend": backend,
                "requested_size": [640, 480],
                "actual_size": [width, height],
                "camera_fps_reported": fps_camera,
                "conf": args.conf,
                "imgsz": args.imgsz,
                "device": "cpu",
                "headless": args.headless,
            },
        )
        print(f"CAMERA_OPEN_PASS backend={backend} size={width}x{height}", flush=True)
        print("Press Q or Esc in the preview window to stop; STOP file also stops the run.", flush=True)
        if not args.headless:
            cv2.namedWindow("YOLO object recognition", cv2.WINDOW_NORMAL)
            cv2.resizeWindow("YOLO object recognition", 960, 720)

        with events_path.open("w", encoding="utf-8") as stream:
            while time.monotonic() - started < args.max_seconds:
                if (run / "STOP").exists():
                    reason = "stop_file"
                    break
                ok, frame = cap.read()
                if not ok or frame is None:
                    raise RuntimeError("Camera read failed")
                frames += 1
                tick = time.perf_counter()
                result = model.predict(
                    frame,
                    device="cpu",
                    imgsz=args.imgsz,
                    conf=args.conf,
                    verbose=False,
                    save=False,
                )[0]
                latency = (time.perf_counter() - tick) * 1000.0
                latencies_ms.append(latency)
                inference_frames += 1
                rows = detection_rows(result)
                last_rows = rows
                last_annotated = result.plot()
                detections_total += len(rows)
                now = time.monotonic()
                stream.write(
                    json.dumps(
                        {
                            "elapsed_seconds": round(now - started, 4),
                            "frame": frames,
                            "inference_ms": round(latency, 3),
                            "detections": rows,
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                stream.flush()

                if not args.headless:
                    annotated = last_annotated
                    wall_fps = inference_frames / max(now - started, 1e-6)
                    cv2.putText(
                        annotated,
                        f"YOLOv8n | {wall_fps:.1f} FPS | {latency:.0f} ms | Q/Esc: quit",
                        (12, 28),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.65,
                        (0, 255, 0),
                        2,
                        cv2.LINE_AA,
                    )
                    cv2.imshow("YOLO object recognition", annotated)
                    key = cv2.waitKey(1) & 0xFF
                    if key in (27, ord("q"), ord("Q")):
                        reason = "user_quit"
                        break
                    if cv2.getWindowProperty("YOLO object recognition", cv2.WND_PROP_VISIBLE) < 1:
                        reason = "window_closed"
                        break
                if frames == 1:
                    cv2.imwrite(str(run / "snapshot_first.jpg"), last_annotated)
                if frames % 30 == 0:
                    shown = ", ".join(f"{row['label']}:{row['confidence']:.2f}" for row in rows[:8]) or "none"
                    print(f"FRAME {frames} detections={shown} latency_ms={latency:.1f}", flush=True)
            else:
                reason = "bounded_timeout"
        if last_annotated is not None:
            cv2.imwrite(str(run / "snapshot_last.jpg"), last_annotated)
        marker = "OBJECT_WEBCAM_RUN_PASS"
    except Exception as exc:
        marker = "OBJECT_WEBCAM_RUN_FAIL"
        reason = f"error:{type(exc).__name__}:{exc}"
        (run / "error.txt").write_text(reason + "\n", encoding="utf-8")
        print(reason, file=sys.stderr, flush=True)
    finally:
        if cap is not None:
            cap.release()
        if not args.headless:
            try:
                cv2.destroyAllWindows()
            except cv2.error:
                pass

    elapsed = time.monotonic() - started
    write_json(
        run / "result.json",
        {
            "result": marker,
            "reason": reason,
            "elapsed_seconds": round(elapsed, 3),
            "frames": frames,
            "inference_frames": inference_frames,
            "detections_total": detections_total,
            "last_detections": last_rows,
            "latency_ms": {
                "min": round(min(latencies_ms), 3) if latencies_ms else None,
                "mean": round(sum(latencies_ms) / len(latencies_ms), 3) if latencies_ms else None,
                "max": round(max(latencies_ms), 3) if latencies_ms else None,
            },
        },
    )
    print(json.dumps({"result": marker, "reason": reason, "frames": frames}, ensure_ascii=False), flush=True)
    return 0 if marker == "OBJECT_WEBCAM_RUN_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
