#!/usr/bin/env python3
"""Three visual tasks with descriptor-driven PL display on multitask_osd BIT.

slot 0: NanoDet COCO, up to eight labelled boxes.
slot 1: existing YOLOv8n gesture path, unchanged GBOX/TLBL display.
slot 2: split-ncnn YOLO11n-pose, up to two 17-keypoint skeletons.

No PS display-ring writes and no actuator output. Board download occurs only
when this script is explicitly launched on the board, never by host tests.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import time

import cv2
import numpy as np

import t1_gesture_main as base
import task_ops
from flex_ncnn import FlexNcnn
from pose_split_engine import PoseSplitEngine
from multitask_osd import MultiTaskOsd

BIT_SHA256 = "c910f8ce502f117577bdfa6ff06450991cec3feb02161993336b25727d206542"
HWH_SHA256 = "3e92e4d5e4dc544c6bb743e663d887559590f6b8771b9d2dfaec07c395d930e7"

TASKS = {
    0: ("NanoDet-COCO-Material", "material"),
    1: ("YOLOv8n-Gesture7", "gesture"),
    2: ("YOLO11n-Pose", "pose"),
}


def preprocess(model_id, frame, pre):
    if model_id == 0:
        bgr = np.frombuffer(frame, np.uint8).reshape(480, 640, 3)
        return task_ops.nanodet_input(bgr), None
    if model_id == 1:
        return pre.run(frame)
    bgr = np.frombuffer(frame, np.uint8).reshape(480, 640, 3)
    blob, _ = task_ops.pose_input(bgr)
    return blob, None


def decode(model_id, raw, grids, gesture_score, new_task_score, nms):
    if model_id == 0:
        out = np.asarray(raw).reshape(2125, 112)
        dets = task_ops.decode_nanodet(out, new_task_score, nms, grids)
        return dets, out[:, :80].max(axis=0)
    if model_id == 1:
        dets = base.decode_yolo(raw, gesture_score, nms)
        cls = 1.0 / (1.0 + np.exp(-np.asarray(raw).reshape(-1, 2100)[4:].T))
        return dets, cls.max(axis=0)
    return task_ops.decode_pose(raw, new_task_score, 0.7), np.asarray(raw).reshape(56, 2100)[4:5].max(axis=1)


def label(model_id, det):
    if model_id == 0:
        return task_ops.COCO_NAMES[det["cls"]]
    if model_id == 1:
        return base.GESTURE_NAMES[det["cls"]]
    return "person"


def box_for_osd(model_id, det):
    if det is None or model_id != 2:
        return det
    mapped = dict(det)
    # PL BoxOsd applies y*1.5. Invert that after mapping letterbox y to the
    # original 640x480 image with (y-40)*2.
    mapped["xyxy_px"] = [det["xyxy_px"][0],
                         (det["xyxy_px"][1] - 40.0) * 4.0 / 3.0,
                         det["xyxy_px"][2],
                         (det["xyxy_px"][3] - 40.0) * 4.0 / 3.0]
    return mapped


def save_detection_evidence(model_id, frame, dets, evidence, sequence):
    if not dets or sequence > 3:
        return
    bgr = np.frombuffer(frame, np.uint8).reshape(480, 640, 3)
    if model_id == 0:
        small = cv2.resize(bgr, (320, 320), interpolation=cv2.INTER_LINEAR)
        annotated = task_ops.draw_dets_320(small, dets, task_ops.COCO_NAMES)
    elif model_id == 1:
        small = cv2.resize(bgr, (320, 320), interpolation=cv2.INTER_LINEAR)
        annotated = task_ops.draw_dets_320(small, dets, base.GESTURE_NAMES)
    else:
        _, lb = task_ops.pose_input(bgr)
        annotated = task_ops.draw_pose_320(lb, dets)
    annotated = cv2.resize(annotated, (640, 480), interpolation=cv2.INTER_NEAREST)
    stem = f"task{model_id}_det{sequence}"
    cv2.imwrite(str(evidence / f"{stem}.jpg"), annotated)
    serializable = [{"cls": d["cls"], "name": label(model_id, d), "score": d["score"],
                     "xyxy_px": d["xyxy_px"], **({"keypoints": d["keypoints"]} if model_id == 2 else {})}
                    for d in dets]
    (evidence / f"{stem}.json").write_text(json.dumps(serializable, indent=2), encoding="utf-8")
    base.log("TASK_EVIDENCE_SAVED", task=TASKS[model_id][1], file=stem)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bit", required=True)
    ap.add_argument("--ncnn-addr", default="127.0.0.1:5002")
    ap.add_argument("--pose-ncnn-addr", default="127.0.0.1:5003")
    ap.add_argument("--ncnn-param", required=True)
    ap.add_argument("--ncnn-bin", required=True)
    ap.add_argument("--ncnn-param-sha", required=True)
    ap.add_argument("--ncnn-bin-sha", required=True)
    ap.add_argument("--c2psa-weights", required=True)
    ap.add_argument("--c2psa-sha", required=True)
    ap.add_argument("--model", type=int, default=0, choices=[0, 1, 2])
    ap.add_argument("--model-select", default="/home/xilinx/three_task/model_select")
    ap.add_argument("--score", type=float, default=0.55, help="gesture threshold")
    ap.add_argument("--min-margin", type=float, default=0.15,
                    help="thumb classes 4/5 display guard: top-class score "
                         "minus best rival (net3 anti TD/TU flip value)")
    ap.add_argument("--new-task-score", type=float, default=0.25)
    ap.add_argument("--nms", type=float, default=0.6)
    ap.add_argument("--box-hold", type=float, default=1.5)
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--evidence", type=Path, required=True)
    args = ap.parse_args()
    if os.geteuid() != 0:
        ap.error("run as root")

    from pynq import Overlay
    args.evidence.mkdir(parents=True, exist_ok=True)
    bit, hwh = Path(args.bit), Path(args.bit).with_suffix(".hwh")
    base.sha_ok(bit, BIT_SHA256)
    base.sha_ok(hwh, HWH_SHA256)
    base.sha_ok(args.ncnn_param, args.ncnn_param_sha)
    base.sha_ok(args.ncnn_bin, args.ncnn_bin_sha)
    base.sha_ok(args.c2psa_weights, args.c2psa_sha)

    ol = Overlay(str(bit), download=False)
    for name in ("axi_vdma_0", "t1_preproc_0", "task_coco_osd_0", "task_pose_osd_0"):
        if name not in ol.ip_dict:
            raise RuntimeError(f"{name} missing")
    ol.download()
    state = Path("/sys/class/fpga_manager/fpga0/state").read_text().strip()
    if state != "operating":
        raise RuntimeError(f"fpga state {state}")
    base.log("PL_LOADED", bit_sha256=BIT_SHA256[:16], state=state)
    base.log("ACTION_DISABLED", reason="three-task visual validation; all slots")

    ncnn_host, ncnn_port = args.ncnn_addr.rsplit(":", 1)
    ncnn = FlexNcnn(ncnn_host, int(ncnn_port))
    pose_host, pose_port = args.pose_ncnn_addr.rsplit(":", 1)
    pose_ncnn = FlexNcnn(pose_host, int(pose_port))
    pose_engine = PoseSplitEngine(pose_ncnn, args.c2psa_weights)
    probe = np.zeros((1, 3, 320, 320), np.float32)
    shapes = {}
    for mid in (0, 1):
        shapes[str(mid)] = list(ncnn.infer(mid, [probe])[0].shape)
    shapes["2"] = pose_engine.probe()
    expected_pose = {"pre": [[1, 256, 10, 10], [1, 128, 20, 20], [1, 128, 40, 40]],
                     "raw": [[1, 64, 2100], [1, 1, 2100], [1, 51, 2100]]}
    if shapes["0"] != [2125 * 112] or shapes["1"] != [11 * 2100] or shapes["2"] != expected_pose:
        raise RuntimeError(f"unexpected model outputs {shapes}")
    base.log("ENGINE_READY", backend0="ncnn", backend1="ncnn",
             backend2="split-ncnn+numpy-c2psa+ps-decode", shapes=shapes)

    task_osd = MultiTaskOsd(ol)
    task_osd.set_mode(args.model)
    cam = base.VdmaCam(ol)
    pre = base.Preproc(ol)
    mbtn = base.ModelBtn(ol)
    osd = base.BoxOsd(ol)
    plosd = base.PlTextOsd(ol)
    plosd.clear()
    base.log("BOARD_BLOCKS_READY", preproc=hex(base.EXPECT_VER), model_btn=mbtn.mmio is not None,
             box_osd=osd.mmio is not None, multitask_osd=True)
    signal.signal(signal.SIGTERM, base.request_stop)
    signal.signal(signal.SIGINT, base.request_stop)

    grids = task_ops.build_grids()
    active_id = args.model
    started = time.monotonic()
    last_report = started
    held_det = None
    hold_until = 0.0
    shown_cls = None
    n = rejected = 0
    evidence_counts = {0: 0, 1: 0, 2: 0}
    frame_counts = {0: 0, 1: 0, 2: 0}
    result = {"result": "NOT_COMPLETED"}
    try:
        while not base.stopping and (not args.seconds or time.monotonic() - started < args.seconds):
            want = mbtn.poll()
            src = "pl_btn"
            if want is None:
                src = "file"
                try:
                    want = int(Path(args.model_select).read_text().strip())
                    os.remove(args.model_select)
                except (OSError, ValueError):
                    want = None
            if want in TASKS and want != active_id:
                base.log("MODEL_SELECT", src=src, **{"from": TASKS[active_id][0], "to": TASKS[want][0]})
                active_id = want
                held_det = None
                hold_until = 0.0
                shown_cls = None
                osd.show(None)
                plosd.clear()
                task_osd.set_mode(active_id)
            st = cam.status()
            frame = cam.snapshot()
            if frame is None:
                rejected += 1
                continue
            if n == 0:
                (args.evidence / "first_frame.bgr").write_bytes(frame)
            t0 = time.monotonic()
            if active_id == 1:
                blob, pl_ms = pre.run(frame)
            else:
                lb0 = time.monotonic()
                blob, _ = preprocess(active_id, frame, pre)
                pl_ms = time.monotonic() - lb0
            if active_id == 2:
                dets = pose_engine.infer(blob)
            else:
                raw = np.asarray(ncnn.infer(active_id, [blob])[0])
                dets, per_cls = decode(active_id, raw, grids, args.score, args.new_task_score, args.nms)
            if active_id == 0:
                osd.show(None)
                plosd.clear()
                task_osd.publish_coco(dets)
            elif active_id == 2:
                osd.show(None)
                plosd.clear()
                task_osd.publish_pose(dets)
            else:
                # net3-parity display (2026-11-03 gate fix): net3's HDMI-proven
                # UX shows EVERY decode-passing detection immediately (score
                # gate lives at decode, plus wall-clock flicker hold). Its
                # 0.15 min-margin was the ACTION anti-flip guard (t1_gesture_
                # main.py:1350), never a display gate. The 11-02 port moved
                # that gate onto display and tightened it (0.2 all classes,
                # thumbs 0.25 + score 0.58); live 11-03 board evidence
                # (board_chain_gate_suppression_1103.log): Up 0.66-0.69 and
                # Thumbs up 0.60-0.66 decoded frame after frame while
                # GESTURE_SHOWN almost never fired = user-visible "gestures
                # not recognized". Restore immediate display; keep a margin
                # guard ONLY for thumb classes 4/5 (the empty-background FP
                # family the 11-02 gate was built to kill) at net3's 0.15.
                margin_ok = True
                if dets:
                    det = dets[0]
                    c = int(det["cls"])
                    if c in (4, 5):  # Thumbs Down / Thumbs up
                        scores = [float(s) for s in np.asarray(per_cls).ravel()]
                        rival = max((s for i, s in enumerate(scores) if i != c), default=0.0)
                        margin_ok = (scores[c] - rival) >= args.min_margin
                if dets and margin_ok:
                    if shown_cls != int(dets[0]["cls"]):
                        base.log("GESTURE_SHOWN", name=base.GESTURE_NAMES[int(dets[0]["cls"])],
                                 score=round(float(dets[0]["score"]), 4), hold=args.box_hold)
                        shown_cls = int(dets[0]["cls"])
                    held_det = dets[0]
                    hold_until = time.monotonic() + args.box_hold
                if held_det is not None and time.monotonic() < hold_until:
                    osd.show(held_det)
                    plosd.show(active_id, held_det["cls"], held_det["score"])
                else:
                    held_det = None
                    if shown_cls is not None:
                        base.log("GESTURE_CLEAR", name=base.GESTURE_NAMES[shown_cls])
                        shown_cls = None
                    osd.show(None)
                    plosd.show(active_id, None, None)
            plosd.tick()
            inf_ms = (time.monotonic() - t0) * 1000.0
            n += 1
            frame_counts[active_id] += 1
            if dets:
                evidence_counts[active_id] += 1
                save_detection_evidence(active_id, frame, dets, args.evidence,
                                        evidence_counts[active_id])
            now = time.monotonic()
            if now - last_report >= 5:
                top = [{"name": label(active_id, d), "score": round(d["score"], 4)} for d in dets[:3]]
                base.log("HEARTBEAT", task=TASKS[active_id][1], model=TASKS[active_id][0],
                         frames=n, rejected=rejected, inf_ms=round(inf_ms, 1),
                         pl_ms=round(pl_ms * 1000.0, 1), detections=len(dets), top=top, **st)
                last_report = now
        result = {"result": "THREE_TASK_RUN_COMPLETE", "frames": n, "rejected": rejected,
                  "frame_counts": frame_counts, "detection_evidence_counts": evidence_counts,
                  "seconds": round(time.monotonic() - started, 1)}
        base.log("RUN_COMPLETE", **result)
    except Exception as exc:
        result = {"result": "FAIL", "error": str(exc)}
        base.log("FAIL", error=str(exc))
        raise
    finally:
        task_osd.close()
        osd.show(None)
        plosd.clear()
        pre.close()
        cam.close()
        (args.evidence / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
