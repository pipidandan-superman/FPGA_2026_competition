#!/usr/bin/env python3
"""Numpy execution of the original YOLO11 C2PSA block (batch=1, 10x10)."""
import numpy as np


class C2PSA:
    def __init__(self, weights_npz):
        self.w = dict(np.load(weights_npz))

    @staticmethod
    def conv1(x, weight, bias):
        out_ch, in_ch = weight.shape[:2]
        h, w = x.shape[1:]
        y = weight.reshape(out_ch, in_ch) @ x.reshape(in_ch, -1)
        return (y + bias[:, None]).reshape(out_ch, h, w).astype(np.float32)

    @staticmethod
    def silu(x):
        return (x / (1.0 + np.exp(-x))).astype(np.float32)

    @staticmethod
    def depthwise3(x, weight, bias):
        c, h, w = x.shape
        xp = np.pad(x, ((0, 0), (1, 1), (1, 1)), mode="constant")
        out = np.zeros((c, h, w), dtype=np.float32)
        for ky in range(3):
            for kx in range(3):
                out += weight[:, 0, ky, kx][:, None, None] * xp[:, ky:ky + h, kx:kx + w]
        out += bias[:, None, None]
        return out

    def __call__(self, x):
        if x.shape != (1, 256, 10, 10):
            raise ValueError(f"C2PSA expects (1,256,10,10), got {x.shape}")
        x = np.asarray(x[0], dtype=np.float32)
        cv1 = self.silu(self.conv1(x, self.w["cv1_w"], self.w["cv1_b"]))
        a, b = cv1[:128].copy(), cv1[128:].copy()
        qkv = self.conv1(b, self.w["qkv_w"], self.w["qkv_b"]).reshape(2, 128, 100)
        v_all = qkv[:, 64:].reshape(128, 10, 10)
        heads = []
        scale = np.float32(32 ** -0.5)
        for h in range(2):
            q, k, v = qkv[h, :32], qkv[h, 32:64], qkv[h, 64:]
            attn = (q * scale).T @ k
            attn -= attn.max(axis=-1, keepdims=True)
            e = np.exp(attn)
            attn = e / e.sum(axis=-1, keepdims=True)
            heads.append(v @ attn.T)
        attended = np.concatenate(heads, axis=0).reshape(128, 10, 10)
        attended += self.depthwise3(v_all, self.w["pe_w"], self.w["pe_b"])
        b = b + self.conv1(attended, self.w["proj_w"], self.w["proj_b"])
        ffn = self.silu(self.conv1(b, self.w["ffn0_w"], self.w["ffn0_b"]))
        ffn = self.conv1(ffn, self.w["ffn1_w"], self.w["ffn1_b"])
        b = b + ffn
        out = self.silu(self.conv1(np.concatenate([a, b], axis=0),
                                   self.w["cv2_w"], self.w["cv2_b"]))
        return out[None].astype(np.float32)
