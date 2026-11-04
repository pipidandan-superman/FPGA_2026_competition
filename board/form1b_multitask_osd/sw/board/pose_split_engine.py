#!/usr/bin/env python3
"""Validated board pose engine: ncnn pre -> NumPy C2PSA -> ncnn raw heads."""
from c2psa_runtime import C2PSA
from pose_raw_runtime import decode_pose_raw
import numpy as np


class PoseSplitEngine:
    def __init__(self, ncnn, weights_path):
        self.ncnn = ncnn
        self.c2psa = C2PSA(weights_path)

    def _pre(self, blob):
        pre = [self.ncnn.infer(2, [blob])[0], self.ncnn.infer(4, [blob])[0],
               self.ncnn.infer(5, [blob])[0]]
        if [v.size for v in pre] != [25600, 51200, 204800]:
            raise RuntimeError(f"bad pose pre sizes {[v.size for v in pre]}")
        return [pre[0].reshape(1, 256, 10, 10), pre[1].reshape(1, 128, 20, 20),
                pre[2].reshape(1, 128, 40, 40)]

    def _post(self, pre):
        mid = self.c2psa(pre[0])
        inputs = [mid, pre[1], pre[2]]
        raw = [self.ncnn.infer(3, inputs)[0], self.ncnn.infer(6, inputs)[0],
               self.ncnn.infer(7, inputs)[0]]
        if [v.size for v in raw] != [64 * 2100, 2100, 51 * 2100]:
            raise RuntimeError(f"bad pose raw sizes {[v.size for v in raw]}")
        return [raw[0].reshape(1, 64, 2100), raw[1].reshape(1, 1, 2100),
                raw[2].reshape(1, 51, 2100)]

    def probe(self):
        blob = np.zeros((1, 3, 320, 320), np.float32)
        pre = self._pre(blob)
        raw = self._post(pre)
        return {"pre": [list(v.shape) for v in pre], "raw": [list(v.shape) for v in raw]}

    def infer(self, blob):
        pre = self._pre(blob)
        raw = self._post(pre)
        dets, _ = decode_pose_raw(*raw)
        return dets
