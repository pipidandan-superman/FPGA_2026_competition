#!/usr/bin/env python3
"""Client for the flexible board ncnn server (multi-input and multi-output)."""
import socket
import struct
import time
import numpy as np


class FlexNcnn:
    def __init__(self, host="127.0.0.1", port=5002):
        self.dest = (host, port)
        self.sock = socket.create_connection(self.dest, timeout=30)
        self.sock.settimeout(30)

    def _recv_full(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise RuntimeError("ncnn server closed connection")
            buf += chunk
        return buf

    def infer(self, model_id, inputs, output_count=1):
        arrays = [np.ascontiguousarray(x, dtype=np.float32) for x in inputs]
        payload = b"".join(x.tobytes() for x in arrays)
        head = struct.pack("<II", model_id, len(payload))
        for attempt in (1, 2):
            try:
                self.sock.sendall(head + payload)
                if output_count > 1:
                    count = struct.unpack("<I", self._recv_full(4))[0]
                    if count != output_count:
                        raise RuntimeError(f"output count {count} != {output_count}")
                else:
                    count = 1
                ans = []
                for _ in range(count):
                    size = struct.unpack("<I", self._recv_full(4))[0]
                    ans.append(np.frombuffer(self._recv_full(size), dtype=np.float32).copy())
                return ans
            except (socket.timeout, TimeoutError, BrokenPipeError,
                    ConnectionResetError, RuntimeError):
                if attempt == 2:
                    raise
                try:
                    self.sock.close()
                except OSError:
                    pass
                time.sleep(0.5)
                self.sock = socket.create_connection(self.dest, timeout=30)
                self.sock.settimeout(30)
