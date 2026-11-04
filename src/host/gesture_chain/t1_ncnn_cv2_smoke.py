# t1_ncnn_cv2_smoke.py -- in-process coexistence smoke test (2026-10-19).
# Pitfall #2 was cv2 5.0.0 (pip) segfaulting with self-built ncnn. The board
# main program runs system cv2 4.5.4; if this passes, inference swaps to
# ncnn in the SAME process (no two-process complexity).
# Verdict: print SMOKE_PASS only after cv2.dnn forward AND ncnn extract
# both complete in one process (and again interleaved x3).
import time

import cv2
import numpy as np

import ncnn

ONNX = "/home/xilinx/t1_models/nanodet-plus-m_320-gesture7-v5-cv2.onnx"
PARAM = "/home/xilinx/t1_models/nanodet-plus-m_320-gesture7-v5.ncnn.param"
BIN = "/home/xilinx/t1_models/nanodet-plus-m_320-gesture7-v5.ncnn.bin"

net = cv2.dnn.readNetFromONNX(ONNX)
net.setInput(np.zeros((1, 3, 320, 320), np.float32))
out_cv2 = net.forward()
print("CV2_OK shape=%s" % (out_cv2.shape,), flush=True)

net2 = ncnn.Net()
net2.load_param(PARAM)
net2.load_model(BIN)
net2.opt.num_threads = 1

for i in range(3):
    blob = np.zeros((3, 320, 320), np.float32)   # CHW, preproc output form
    t0 = time.time()
    ex = net2.create_extractor()
    ex.input("data", ncnn.Mat(blob))
    ret, out = ex.extract("output")
    dt = time.time() - t0
    # keep cv2 alive in the same process across iterations
    out_cv2 = net.forward()
    print("NCNN_OK iter=%d out_w=%d out_h=%d out_c=%d dims=%d (%.3fs)"
          % (i, out.w, out.h, out.c, out.dims, dt), flush=True)
print("SMOKE_PASS", flush=True)
