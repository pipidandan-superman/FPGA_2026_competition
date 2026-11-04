"""PS/ncnn -> PL heads boundary client.

Protocol extension: model_id bit31 requests the three YOLOv8n neck features.
Reply: final output, then feature_len and model.15/18/21 fp32 CHW planes.
"""
import socket
import struct
from pathlib import Path

import numpy as np

FEATURE_REQUEST = 0x80000000
FEATURE_BYTES = (102400, 51200, 25600)
FEATURE_NODES = ('model.15', 'model.18', 'model.21')
FEATURE_SCALES = (
    0.03632511644385141,
    0.04690737377841389,
    0.055139662684757826,
)


def recv_full(sock, nbytes):
    data = b''
    while len(data) < nbytes:
        chunk = sock.recv(nbytes - len(data))
        if not chunk:
            raise RuntimeError('hybrid server closed connection')
        data += chunk
    return data


def request_hybrid(blob, host='127.0.0.1', port=5002, model_id=1):
    if blob.shape != (1, 3, 320, 320) or blob.dtype != np.float32:
        raise ValueError('Expected fp32 NCHW blob [1,3,320,320]')
    payload = blob.tobytes()
    with socket.create_connection((host, port), timeout=60) as sock:
        sock.settimeout(60)
        sock.sendall(struct.pack('<II', model_id | FEATURE_REQUEST, len(payload)) + payload)
        out_len = struct.unpack('<I', recv_full(sock, 4))[0]
        raw = np.frombuffer(recv_full(sock, out_len), dtype=np.float32).copy()
        feature_len = struct.unpack('<I', recv_full(sock, 4))[0]
        if feature_len != sum(FEATURE_BYTES) * 4:
            raise RuntimeError(f'Unexpected feature_len {feature_len}')
        features = []
        for node, count in zip(FEATURE_NODES, FEATURE_BYTES):
            data = recv_full(sock, count * 4)
            features.append(np.frombuffer(data, dtype=np.float32).copy())
    return raw, features


def quantize_feature(feature, scale):
    quantized = np.clip(np.rint(feature.astype(np.float64) / scale), -128, 127).astype(np.int8)
    return np.ascontiguousarray(quantized)


def export_heads_input(features, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    if len(features) != 3:
        raise ValueError('Expected three neck features')
    paths = []
    for node, feature, scale in zip(FEATURE_NODES, features, FEATURE_SCALES):
        expected = {'model.15': (64, 40, 40), 'model.18': (128, 20, 20), 'model.21': (256, 10, 10)}[node]
        if feature.size != int(np.prod(expected)):
            raise RuntimeError(f'{node} feature size mismatch {feature.size}')
        quantized = quantize_feature(feature.reshape(1, *expected), scale)
        path = out_dir / f'{node}.int8'
        path.write_bytes(quantized.tobytes())
        paths.append(path)
    return paths
