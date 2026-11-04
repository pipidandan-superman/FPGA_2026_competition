#!/usr/bin/env python3
"""i4_head_decode.py -- numpy yolov8 head decode for the PPU heads segments.

Mirrors the PC reference decoder (gesture_viewer.py: ultralytics
model.predict(device='cpu', imgsz=640, rect=False, conf=.45, iou=.7))
on the int8 head segments produced by the PPU graph. The PPU graph input
is the 320x320 letterboxed canvas (buf0 3x320x320, (u8-128) int8 NCHW);
head segments per stride (grid H=W, canvas 320):

    reg<stride>: int8 [64, H, W]   DFL: 4 distances x 16 bins
    cls<stride>: int8 [nc, H, W]   nc = 7 gesture classes

    stride 8  -> 40x40, stride 16 -> 20x20, stride 32 -> 10x10

Decode chain: float dequant (x * seg_scale) -> DFL softmax+expectation
-> dist2bbox with grid anchors (ultralytics make_anchors/dist2bbox,
distances in grid units, anchor = idx + 0.5, then * stride) -> sigmoid
class scores -> conf gate -> per-class NMS -> letterbox inverse back to
original camera coordinates (640x480).

All functions are pure host-side numpy; verified against the PC decoder
before board use (i4 self-test frames). Pure ASCII.
"""

import numpy as np

# (name, channels, grid, stride)
REG_SEGS = [("reg8", 40, 8), ("reg16", 20, 16), ("reg32", 10, 32)]
CLS_SEGS = [("cls8", 40, 8), ("cls16", 20, 16), ("cls32", 10, 32)]
NUM_CLASSES = 7
DFL_BINS = 16
_DFL_WEIGHTS = np.arange(DFL_BINS, dtype=np.float32)


def _sigmoid(z):
    return 1.0 / (1.0 + np.exp(-z.astype(np.float32)))


def dfl_distances(reg_i8, scale):
    """reg int8 [64,H,W] -> distances float32 [4,H,W] (l,t,r,b, grid units)."""
    z = reg_i8.astype(np.float32) * np.float32(scale)      # [64,H,W]
    z = z.reshape(4, DFL_BINS, *z.shape[1:])               # [4,16,H,W]
    z = z - z.max(axis=1, keepdims=True)                   # softmax stability
    e = np.exp(z)
    p = e / e.sum(axis=1, keepdims=True)                   # [4,16,H,W]
    return (p * _DFL_WEIGHTS[None, :, None, None]).sum(axis=1)


def seg_candidates(reg_i8, cls_i8, reg_scale, cls_scale, grid, stride, conf):
    """One stride -> (box_xyxy [N,4] canvas px, score [N], cls [N])."""
    d = dfl_distances(reg_i8, reg_scale)                   # [4,H,W]
    s = _sigmoid(cls_i8.astype(np.float32) * np.float32(cls_scale))
    cls_id = s.argmax(axis=0)                              # [H,W]
    score = s.max(axis=0)                                  # [H,W]
    gy, gx = np.nonzero(score > conf)
    if gy.size == 0:
        return np.zeros((0, 4), np.float32), np.zeros((0,), np.float32), \
            np.zeros((0,), np.int32)
    l = d[0, gy, gx]; t = d[1, gy, gx]
    r = d[2, gy, gx]; b = d[3, gy, gx]
    ax = gx.astype(np.float32) + 0.5
    ay = gy.astype(np.float32) + 0.5
    boxes = np.stack([(ax - l) * stride, (ay - t) * stride,
                      (ax + r) * stride, (ay + b) * stride], axis=1)
    return boxes.astype(np.float32), score[gy, gx], cls_id[gy, gx]


def nms_per_class(boxes, scores, cls, iou_thr):
    """Per-class NMS (ultralytics default: agnostic=False)."""
    keep = []
    for c in np.unique(cls):
        idx = np.nonzero(cls == c)[0]
        order = idx[np.argsort(-scores[idx])]
        while order.size:
            i = order[0]
            keep.append(i)
            if order.size == 1:
                break
            rest = order[1:]
            xx1 = np.maximum(boxes[i, 0], boxes[rest, 0])
            yy1 = np.maximum(boxes[i, 1], boxes[rest, 1])
            xx2 = np.minimum(boxes[i, 2], boxes[rest, 2])
            yy2 = np.minimum(boxes[i, 3], boxes[rest, 3])
            w = np.clip(xx2 - xx1, 0, None)
            h = np.clip(yy2 - yy1, 0, None)
            inter = w * h
            a1 = (boxes[i, 2] - boxes[i, 0]) * (boxes[i, 3] - boxes[i, 1])
            a2 = (boxes[rest, 2] - boxes[rest, 0]) * \
                 (boxes[rest, 3] - boxes[rest, 1])
            iou = inter / (a1 + a2 - inter + 1e-9)
            order = rest[iou <= iou_thr]
    if not keep:
        return np.zeros((0,), np.int64)
    return np.array(sorted(keep), dtype=np.int64)


def letterbox_params(src_w, src_h, canvas=320):
    """Ultralytics LetterBox: scale to fit, centered, pad color 114."""
    r = min(canvas / src_w, canvas / src_h)
    new_w, new_h = int(round(src_w * r)), int(round(src_h * r))
    pad_x = (canvas - new_w) / 2.0
    pad_y = (canvas - new_h) / 2.0
    return r, pad_x, pad_y


def make_canvas(frame_bgr, canvas=320):
    """Camera frame HxWx3 BGR uint8 -> canvas uint8 (RGB, letterboxed)."""
    import cv2  # board pynq image ships cv2; fallback below if absent
    h, w = frame_bgr.shape[:2]
    r, pad_x, pad_y = letterbox_params(w, h, canvas)
    new_w, new_h = int(round(w * r)), int(round(h * r))
    resized = cv2.resize(frame_bgr, (new_w, new_h),
                         interpolation=cv2.INTER_LINEAR)
    resized = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
    out = np.full((canvas, canvas, 3), 114, np.uint8)
    x0, y0 = int(round(pad_x)), int(round(pad_y))
    out[y0:y0 + new_h, x0:x0 + new_w] = resized
    return out


def canvas_to_frame(box_xyxy, src_w, src_h, canvas=320):
    """Inverse letterbox: canvas-px box -> source-frame px."""
    r, pad_x, pad_y = letterbox_params(src_w, src_h, canvas)
    x1 = (box_xyxy[0] - pad_x) / r
    y1 = (box_xyxy[1] - pad_y) / r
    x2 = (box_xyxy[2] - pad_x) / r
    y2 = (box_xyxy[3] - pad_y) / r
    return np.array([x1, y1, x2, y2], np.float32)


def decode(regs, clss, reg_scales, cls_scales, conf=0.45, iou=0.7,
           canvas=320):
    """Full decode.

    regs / clss: dicts name -> int8 ndarray [C,H,W] (arena reads).
    reg_scales / cls_scales: dicts name -> float dequant scale.
    Returns list of dicts(label, confidence, xyxy) in CANVAS px,
    sorted by confidence desc (mirrors gesture_viewer detections shape).
    """
    bx, sc, cl = [], [], []
    for name, grid, stride in REG_SEGS:
        b, s, c = seg_candidates(regs[name], clss[name.replace("reg", "cls")],
                                 reg_scales[name],
                                 cls_scales[name.replace("reg", "cls")],
                                 grid, stride, conf)
        bx.append(b); sc.append(s); cl.append(c)
    if not bx or sum(len(b) for b in bx) == 0:
        return []
    boxes = np.concatenate(bx); scores = np.concatenate(sc)
    cls_id = np.concatenate(cl)
    keep = nms_per_class(boxes, scores, cls_id, iou)
    dets = []
    for i in keep:
        dets.append(dict(label=int(cls_id[i]),
                         confidence=float(scores[i]),
                         xyxy=[float(v) for v in boxes[i]]))
    dets.sort(key=lambda d: -d["confidence"])
    return dets


def quantize_canvas(canvas_u8):
    """Canvas HxWx3 uint8 RGB -> graph input int8 [1,3,H,W] ((u8-128))."""
    x = (canvas_u8.astype(np.int16) - 128).astype(np.int8)
    return np.ascontiguousarray(x.transpose(2, 0, 1))[None]
