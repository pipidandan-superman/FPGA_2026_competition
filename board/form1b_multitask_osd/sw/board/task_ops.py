#!/usr/bin/env python3
"""Shared preprocessing, decoders and drawing for the three visual tasks."""
import cv2
import numpy as np

REG_MAX = 7
COCO_NAMES = [
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck',
    'boat', 'traffic_light', 'fire_hydrant', 'stop_sign', 'parking_meter', 'bench',
    'bird', 'cat', 'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra',
    'giraffe', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee',
    'skis', 'snowboard', 'sports_ball', 'kite', 'baseball_bat', 'baseball_glove',
    'skateboard', 'surfboard', 'tennis_racket', 'bottle', 'wine_glass', 'cup',
    'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple', 'sandwich', 'orange',
    'broccoli', 'carrot', 'hot_dog', 'pizza', 'donut', 'cake', 'chair', 'couch',
    'potted_plant', 'bed', 'dining_table', 'toilet', 'tv', 'laptop', 'mouse',
    'remote', 'keyboard', 'cell_phone', 'microwave', 'oven', 'toaster', 'sink',
    'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy_bear',
    'hair_drier', 'toothbrush'
]
NANODET_MEAN_BGR = np.array([103.53, 116.28, 123.675], dtype=np.float32)
NANODET_STD_BGR = np.array([57.375, 57.12, 58.395], dtype=np.float32)
POSE_SKELETON = [(15, 13), (13, 11), (16, 14), (14, 12), (11, 12), (5, 11),
                 (6, 12), (5, 6), (5, 7), (6, 8), (7, 9), (8, 10), (1, 2),
                 (0, 1), (0, 2), (1, 3), (2, 4), (3, 5), (4, 6)]


def nanodet_input(bgr):
    """Official NanoDet-Plus-m 320 val contract: direct resize, BGR normalize."""
    rs = cv2.resize(bgr, (320, 320), interpolation=cv2.INTER_LINEAR)
    x = (rs.astype(np.float32) - NANODET_MEAN_BGR) / NANODET_STD_BGR
    return np.ascontiguousarray(x.transpose(2, 0, 1)[None])


def letterbox_bgr(bgr, size=320):
    h, w = bgr.shape[:2]
    r = min(size / h, size / w)
    nw, nh = int(round(w * r)), int(round(h * r))
    rs = cv2.resize(bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
    dw, dh = size - nw, size - nh
    top, left = int(round(dh / 2 - 0.1)), int(round(dw / 2 - 0.1))
    return cv2.copyMakeBorder(rs, top, dh - top, left, dw - left,
                              cv2.BORDER_CONSTANT, value=(114, 114, 114))


def pose_input(bgr):
    """Official YOLO pose contract: letterbox, BGR->RGB, 0..1 fp32 CHW."""
    lb = letterbox_bgr(bgr)
    rgb = lb[:, :, ::-1]
    x = rgb.transpose(2, 0, 1)[None].astype(np.float32) / 255.0
    return np.ascontiguousarray(x), lb


def pose_input_from_rgb320(rgb):
    x = rgb.transpose(2, 0, 1)[None].astype(np.float32) / 255.0
    return np.ascontiguousarray(x)


def build_grids(n_anchors=2125, size=320):
    rows = []
    total = 0
    stride = 8
    while total < n_anchors:
        side = size // stride
        for y in range(side):
            for x in range(side):
                rows.append((x, y, stride))
        total += side * side
        stride *= 2
    if total != n_anchors:
        raise ValueError(f"anchor mismatch {total} != {n_anchors}")
    return np.asarray(rows, dtype=np.float32)


def nms_keep(boxes, scores, score_thr, nms_thr):
    ids = cv2.dnn.NMSBoxes(
        [[float(b[0]), float(b[1]), float(b[2] - b[0]), float(b[3] - b[1])]
         for b in boxes], [float(s) for s in scores], float(score_thr), float(nms_thr))
    return np.asarray(ids).reshape(-1)


def decode_nanodet(raw, score_thr=0.25, nms_thr=0.6, grids=None):
    out = np.asarray(raw).reshape(2125, 112)
    grids = build_grids() if grids is None else grids
    cls = out[:, :80]
    reg = out[:, 80:].reshape(2125, 4, REG_MAX + 1)
    scores = cls.max(axis=1)
    labels = cls.argmax(axis=1)
    reg = reg - reg.max(axis=2, keepdims=True)
    e = np.exp(reg)
    prob = e / e.sum(axis=2, keepdims=True)
    dist = (prob * np.arange(REG_MAX + 1, dtype=np.float32)).sum(axis=2)
    stride = grids[:, 2:3]
    center = (grids[:, :2] + 0.5) * stride
    d = dist * stride
    boxes = np.stack([center[:, 0] - d[:, 0], center[:, 1] - d[:, 1],
                      center[:, 0] + d[:, 2], center[:, 1] + d[:, 3]], axis=1)
    keep = scores >= score_thr
    if not keep.any():
        return []
    boxes, scores, labels = boxes[keep], scores[keep], labels[keep]
    ids = nms_keep(boxes, scores, score_thr, nms_thr)
    ans = [{"cls": int(labels[i]), "score": float(scores[i]),
            "xyxy_px": boxes[i].astype(float).tolist()} for i in ids]
    ans.sort(key=lambda x: -x["score"])
    return ans


def decode_pose(raw, score_thr=0.25, nms_thr=0.7):
    a = np.asarray(raw).reshape(56, 2100)
    xywh = a[:4].T
    # Official pose export already applies sigmoid to both person score and
    # keypoint visibility (unlike the project's custom gesture detector head).
    scores = a[4].copy()
    kpts = a[5:].T.reshape(2100, 17, 3).copy()
    keep = scores >= score_thr
    if not keep.any():
        return []
    xywh, scores, kpts = xywh[keep], scores[keep], kpts[keep]
    cx, cy, w, h = xywh.T
    boxes = np.stack([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], axis=1)
    boxes[:, [0, 2]] = np.clip(boxes[:, [0, 2]], 0, 320)
    boxes[:, [1, 3]] = np.clip(boxes[:, [1, 3]], 0, 320)
    ids = nms_keep(boxes, scores, score_thr, nms_thr)
    ans = [{"cls": 0, "score": float(scores[i]), "xyxy_px": boxes[i].astype(float).tolist(),
            "keypoints": kpts[i].astype(float).tolist()} for i in ids]
    ans.sort(key=lambda x: -x["score"])
    return ans


def draw_dets_320(image, dets, names, color=(40, 220, 40)):
    out = image.copy()
    for d in dets:
        x0, y0, x1, y1 = [int(round(v)) for v in d["xyxy_px"]]
        label = f'{names[d["cls"]]} {d["score"]:.2f}'
        cv2.rectangle(out, (x0, y0), (x1, y1), color, 1)
        cv2.putText(out, label, (x0, max(12, y0 - 3)), cv2.FONT_HERSHEY_SIMPLEX,
                    0.38, color, 1, cv2.LINE_AA)
    return out


def draw_pose_320(image, poses):
    out = draw_dets_320(image, poses, ["person"], (40, 180, 255))
    def point(row):
        xy = row[:2]
        if not np.isfinite(xy).all() or not (0 <= xy[0] < 320 and 0 <= xy[1] < 320):
            return None
        return int(round(float(xy[0]))), int(round(float(xy[1])))
    for pose in poses:
        kp = np.asarray(pose["keypoints"], dtype=np.float32)
        for a, b in POSE_SKELETON:
            pa, pb = point(kp[a]), point(kp[b])
            if pa is not None and pb is not None and kp[a, 2] >= 0.5 and kp[b, 2] >= 0.5:
                cv2.line(out, pa, pb, (255, 100, 30), 1, cv2.LINE_AA)
        for row in kp:
            p = point(row)
            if p is not None and row[2] >= 0.5:
                cv2.circle(out, p, 2, (30, 30, 240), -1, cv2.LINE_AA)
    return out
