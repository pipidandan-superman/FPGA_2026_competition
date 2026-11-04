# t1_udp_watch.py -- PC-side OV56 UDP receiver + v5-cv2 detector (2026-10-19).
# Reassembles the ees331-camera UDP stream (proven camera.py datagrams),
# runs the SAME NanoDet decode as the board chain, saves annotated frames.
# Use: aim-check / detection ground truth while the camera service owns VDMA.
#   <model_env venv>\python.exe t1_udp_watch.py [--seconds 45]
import argparse
import json
import socket
import struct
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, r"E:\competition\4_metrics\logs\2026-10-18_t1_nanodet_run01")
from pc_webcam_demo import build_grids, decode_nanodet  # noqa: E402

MODEL = r"E:\competition\4_metrics\logs\2026-10-18_t1_nanodet_run01\models\nanodet-plus-m_320-gesture7-v5-cv2.onnx"
LABELS = ["Down", "Left", "Right", "Stop", "Thumbs Down", "Thumbs up", "Up"]
HDR = struct.Struct(">4sBBHIHHHHHHII")
OUT = Path(r"E:\competition\4_metrics\logs\2026-10-18_t1_bd_bit_run01\udp_watch")
PACKETS, PAYLOAD = 640, 1440


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=45.0)
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--score", type=float, default=0.35)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    net = cv2.dnn.readNetFromONNX(MODEL)
    net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
    net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
    probe = np.zeros((1, 3, 320, 320), np.float32)
    net.setInput(probe)
    out_shape = net.forward().shape
    n_anchors = out_shape[1] if out_shape[0] == 1 else out_shape[2]
    grids = build_grids(320, n_anchors)
    print("WATCH_READY anchors=%d, waiting for frames..." % len(grids), flush=True)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind(("0.0.0.0", args.port))
    sock.settimeout(2.0)

    frames = {}       # fid -> {pid: payload}
    done = 0
    det_count = {}
    t0 = time.time()
    while time.time() - t0 < args.seconds:
        try:
            pkt, _ = sock.recvfrom(2048)
        except socket.timeout:
            continue
        if len(pkt) < HDR.size or pkt[:4] != b"OV56":
            continue
        (magic, ver, codec, flags, fid, pid, npk, pay, w, h, stride,
         ts, crc) = HDR.unpack(pkt[:HDR.size])
        if pid >= PACKETS:
            continue
        frames.setdefault(fid, {})[pid] = pkt[HDR.size:]
        if len(frames[fid]) == PACKETS:
            parts = frames.pop(fid)
            raw = b"".join(parts[i] for i in range(PACKETS))
            if len(raw) != 640 * 480 * 3:
                continue
            done += 1
            img = np.frombuffer(raw, np.uint8).reshape(480, 640, 3).copy()
            small = cv2.resize(img, (320, 320), interpolation=cv2.INTER_LINEAR)
            blob = (small.astype(np.float32) - np.array([103.53, 116.28, 123.675],
                   np.float32)) / np.array([57.375, 57.12, 58.395], np.float32)
            blob = blob.transpose(2, 0, 1)[np.newaxis]
            net.setInput(blob)
            out = np.asarray(net.forward()).reshape(len(grids), -1)
            dets = decode_nanodet(out, grids, args.score, 0.6, 320)
            for d in dets:
                det_count[LABELS[d["cls"]]] = det_count.get(LABELS[d["cls"]], 0) + 1
            for d in dets:
                x0, y0, x1, y1 = [int(v * 2) for v in d["xyxy_px"]]
                cv2.rectangle(img, (x0, y0), (x1, y1), (0, 255, 0), 2)
                cv2.putText(img, "%s %.2f" % (LABELS[d["cls"]], d["score"]),
                            (x0, max(14, y0 - 4)), cv2.FONT_HERSHEY_SIMPLEX,
                            0.6, (0, 255, 0), 2)
            cv2.imwrite(str(OUT / ("frame_%04d.png" % done)), img)
            print("frame %d top=%s" % (done, json.dumps(
                [{"n": LABELS[d["cls"]], "s": d["score"]} for d in dets[:3]])),
                flush=True)
    print("WATCH_DONE frames=%d det_histogram=%s" % (done, det_count),
          flush=True)


if __name__ == "__main__":
    main()
