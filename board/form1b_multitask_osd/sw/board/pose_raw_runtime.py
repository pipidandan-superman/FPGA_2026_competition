#!/usr/bin/env python3
"""Decode raw YOLO pose heads using the official DFL/anchor/keypoint equations."""
import numpy as np
import task_ops


def anchors_320():
    pts, strides = [], []
    for stride in (8, 16, 32):
        side = 320 // stride
        for y in range(side):
            for x in range(side):
                pts.append((x + 0.5, y + 0.5))
                strides.append(stride)
    return (np.asarray(pts, dtype=np.float32).T,
            np.asarray(strides, dtype=np.float32))


def decode_pose_raw(box_raw, cls_raw, kpt_raw):
    box = np.asarray(box_raw).reshape(4, 16, 2100)
    box -= box.max(axis=1, keepdims=True)
    e = np.exp(box)
    prob = e / e.sum(axis=1, keepdims=True)
    dist = (prob * np.arange(16, dtype=np.float32)[None, :, None]).sum(axis=1)
    anchors, stride = anchors_320()
    x0 = (anchors[0] - dist[0]) * stride
    y0 = (anchors[1] - dist[1]) * stride
    x1 = (anchors[0] + dist[2]) * stride
    y1 = (anchors[1] + dist[3]) * stride
    xywh = np.stack([(x0 + x1) * 0.5, (y0 + y1) * 0.5,
                     x1 - x0, y1 - y0], axis=0).astype(np.float32)
    cls_flat = np.asarray(cls_raw).reshape(2100)
    score = 1.0 / (1.0 + np.exp(-cls_flat))
    k = np.asarray(kpt_raw).reshape(17, 3, 2100).copy()
    k[:, 0, :] = (k[:, 0, :] * 2.0 + anchors[0][None, :] - 0.5) * stride[None, :]
    k[:, 1, :] = (k[:, 1, :] * 2.0 + anchors[1][None, :] - 0.5) * stride[None, :]
    k[:, 2, :] = 1.0 / (1.0 + np.exp(-k[:, 2, :]))
    kpts = k.reshape(51, 2100)
    decoded = np.concatenate([xywh, score[None, :], kpts], axis=0)
    return task_ops.decode_pose(decoded), decoded
