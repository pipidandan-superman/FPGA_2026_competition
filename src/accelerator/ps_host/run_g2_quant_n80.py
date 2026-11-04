"""G2-N80 DRYRUN: W8A8 PTQ + HWINT integer reference on official yolov8n.pt (nc=80).

母本 = 2026-09-15_yolo7020_g2_quant_rne_run04/run_g2_quant.py
(SHA256 a4d54f14060c370f6733ba8ba0b6beec3a19b23883c7d96f37c3fc1369872fcb)。
intref_yolov8.py 与 run04 逐字节一致未改（数值面 nc 无关：n_cls 均从张量形状取）。

相对母本的改动（其余管线逐字保留）：
  1) 权重=官方 yolov8n.pt 冻结副本；names 从模型读取（80 类）；
  2) 校准集=2026-10-05_object_calib_capture_run01（90+3 帧，无 GT 标签）；
  3) 母本 §6/§7 的 mAP50 评测（ap50_per_class）因无 GT 改为 FP-vs-INT8
     检测一致性对拍（同帧 IOU>=0.5+同类贪心匹配）；mAP 门留给正式物料数据轮；
  4) 输出目录=本 run 的 out/quant_n80/；golden(5 npz)/regression(全帧
     boxes+raw_head_sha256)/layer cosine/四件量化包 机制全部保留；
  5) 结果行= G2_N80_DRYRUN_PASS（诚实标签，非 mAP 门）。

Pipeline（与母本同）:
  1. unit tests of integer primitives (hand-computed RNE ties, dyadic INT64 oracle conv)
  2. calibrate per-tensor activation scales on the capture list (max-abs symmetric)
  3. integer graph walk carrying (tensor, scale) pairs; producer scales resolved statically
  4. layerwise LSQ stored-scale refit (fixed-point sweeps over the calibration set)
  5. per-layer FP-vs-INT8 cosine on probe images (layer_error.csv)
  6. export quant.json / weights.bin / bias.bin / lut.bin / manifest.json
  7. one pass over all frames: FP raw heads (torch hooks) + INT8 raw heads through the
     SAME numpy decode+NMS evaluator; agreement table (no GT in dry-run)
  8. golden: 5 deep samples (all-node int8+fp16 tensors, raw heads) as NPZ +
     golden_index.json; all-frame regression outputs (boxes/conf/cls + raw-head hash)

Run: 2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe run_g2_quant_n80.py
(锁定环境 torch 2.10.0+cpu / ultralytics 8.4.142 / numpy 2.2.6，与 G2 run04 一致)
"""
from pathlib import Path
import os, sys, json, time, hashlib
import numpy as np

RUN = Path(__file__).resolve().parent.parent / 'out' / 'quant_n80'
RUN.mkdir(parents=True, exist_ok=True)
# M4.2 归位：标定捕获冻结源经 accel_paths（去绝对路径）。本件=量化包
# 产线冻结件：RUN/WEIGHTS 保持历史 HERE 相对语义（重跑会在新树落
# out/quant_n80，M4 v1 禁止重跑——量化包=冻结输入）。
_RT = Path(__file__).resolve().parent.parent          # 12_yolo_accel
if str(_RT) not in sys.path:
    sys.path.insert(0, str(_RT))
import accel_paths as _AP                             # noqa: E402
CAPTURE = Path(_AP.CAPTURE)
WEIGHTS = Path(__file__).resolve().parent.parent / 'weights' / 'yolov8n.pt'
SIZE = 320
SEED = 20260914
DEEP_SAMPLES = 5

for key, leaf in [('YOLO_CONFIG_DIR', 'ultralytics_config'), ('MPLCONFIGDIR', 'matplotlib_config')]:
    os.environ[key] = str(RUN / leaf)
    (RUN / leaf).mkdir(exist_ok=True)
os.environ.update(YOLO_OFFLINE='true', YOLO_AUTOINSTALL='false', PYTHONNOUSERSITE='1',
                  PYTHONDONTWRITEBYTECODE='1', OMP_NUM_THREADS='2', MKL_NUM_THREADS='2')

import torch
import cv2
import ultralytics
from ultralytics import YOLO, settings
from ultralytics.utils import USER_CONFIG_DIR
from ultralytics.nn.modules import Conv as UConv, C2f, SPPF, Bottleneck, Concat, Detect
import torch.nn as nn

sys.path.insert(0, str(RUN))
from intref_yolov8 import (QConv, rne_shift, requant_to, int_add, maxpool5,
                           upsample_nearest2, softmax_dfl_decode, nms_numpy,
                           ap50_per_class, req_pair)

assert Path(USER_CONFIG_DIR).resolve().is_relative_to(RUN)
settings.update({'sync': False, 'runs_dir': str(RUN / 'predictions'),
                 'datasets_dir': str(RUN / 'datasets'), 'weights_dir': str(RUN / 'weights')})

L = []
def log(m=''):
    print(m, flush=True)
    L.append(str(m))

def sha(p: Path):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

status = {}

# ================= 1. unit tests =================
cases = [(5, 1, 2), (7, 1, 4), (-5, 1, -2), (-7, 1, -4), (3, 0, 3), (1, 1, 0), (-1, 1, 0),
         (2, 1, 1), (6, 1, 3), (-2, 1, -1), (9, 2, 2), (-9, 2, -2), (6, 2, 2), (10, 2, 2)]
ok = all(int(rne_shift(np.array([a], dtype=np.int64), s)[0]) == e for a, s, e in cases)
assert ok, 'RNE hand cases failed'
# NEP50 shift-dtype guard (bug found 2026-09-15 via PS offline regression):
# np.frexp exponents arrive as np.int32; under NEP50 `1 << np.int32(41)` wraps
# to 0, so the tie threshold `full` collapses and RNE degrades to
# round-away-from-zero (+0.5 LSB mean bias) for every shift >= 32 — which this
# net uses for nearly all channels. rne_shift must normalize s to Python int.
n41 = np.array([2**41 * 5 + 2**40, 2**41 * 5 - 2**40, 2**41 * 3 + 3, 1, -1, 0], dtype=np.int64)
ref41 = np.array([6, 4, 3, 0, 0, 0], dtype=np.int64)   # ties 5.5->6, 4.5->4 (to even)
assert np.array_equal(rne_shift(n41, 41), ref41), 'RNE s=41 hand cases failed'
assert np.array_equal(rne_shift(n41, np.int32(41)), ref41), 'np.int32 shift not normalized'
_rng41 = np.random.RandomState(SEED)
_n41 = _rng41.randint(-(2**53), 2**53, 4096, dtype=np.int64)
assert np.array_equal(rne_shift(_n41, np.int32(45)), rne_shift(_n41, 45)), 'np.int32 A/B mismatch'
status['rne_unit'] = 'PASS'

rng = np.random.RandomState(SEED)
x = rng.randint(-100, 100, (1, 3, 9, 9)).astype(np.int8)
w = rng.randint(-127, 127, (5, 3, 3, 3)).astype(np.int8)
b = rng.randint(-1000, 1000, 5).astype(np.int32)
M, SH = 1 << 30, 30
qc = QConv.__new__(QConv)
qc.stride, qc.pad = (1, 1), (1, 1)
qc.w_q, qc.b_q, qc.reqs, qc.lut = w, b, [(M, SH)] * 5, None
acc = qc.acc_i32(x, pad_val=0).astype(np.int64) + b[None, :, None, None]
ref = np.clip(np.round(acc.astype(np.float64) * (M / 2 ** SH)), -128, 127).astype(np.int8)
got = np.clip(rne_shift(acc * M, SH), -128, 127).astype(np.int8)
assert np.array_equal(ref, got), 'dyadic oracle mismatch'
status['int64_oracle_conv'] = 'PASS'
log(f'[1] unit tests PASS (RNE {len(cases)} hand cases + dyadic oracle exact)')

# ================= 2. model + calibration =================
ymodel = YOLO(str(WEIGHTS))
model = ymodel.model.eval()
names = [ymodel.names[i] for i in range(len(ymodel.names))]
assert len(names) == 80, len(names)
STRIDES = [8, 16, 32]

def letterbox_u8_rgb(img_bgr, sz):
    h, w = img_bgr.shape[:2]
    r = min(sz / h, sz / w)
    nh, nw = round(h * r), round(w * r)
    res = cv2.resize(img_bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((sz, sz, 3), 114, dtype=np.uint8)
    top, left = (sz - nh) // 2, (sz - nw) // 2
    canvas[top:top + nh, left:left + nw] = res
    return canvas[:, :, ::-1].copy()

absmax = {}
def _absmax_max(name, t):
    v = float(t.detach().abs().max())
    if v > absmax.get(name, 0):
        absmax[name] = v

def mk_hook(name):
    def hook(mod, inp, out):
        _absmax_max(name, out[0] if isinstance(out, (tuple, list)) else out)
    return hook

# For activated UConv nodes TWO scales matter:
#   - requant domain = post-BN PRE-activation absmax (the SiLU LUT input; using
#     the post-SiLU absmax here would clip pre-activations every layer)
#   - stored tensor = module output at the POST-activation absmax (the LUT
#     output feeds downstream; a single pre-act scale wastes up to ~2 bits when
#     the pre-act range is negative-dominated)
# Pitfalls: 'model.N.conv' output is PRE-BN (conv->bn->act) — mismatches the
# folded-BN node by the per-channel BN gain. And Conv.default_act is a SHARED
# class-level nn.SiLU — hooks on mod.act would fire for every SiLU in the
# network and poison all keys. So hook each module's own BatchNorm2d output
# (= act input) under a distinct '|pre' key.
hooked = []
for name, mod in model.named_modules():
    if isinstance(mod, (UConv, Concat, Bottleneck)) or (isinstance(mod, nn.Conv2d) and 'dfl' not in name):
        mod.register_forward_hook(mk_hook(name))
        hooked.append(name)
    if isinstance(mod, UConv) and getattr(mod, 'bn', None) is not None:
        mod.bn.register_forward_hook(mk_hook(f'{name}|pre'))
        hooked.append(f'{name}|pre')

# 校准集 = 采集 run 的 calib/ 90 帧（夜间弱光，dry-run 用途；正式物料轮日间重采）
cal_imgs = sorted((CAPTURE / 'calib').glob('frame_*.jpg'))
assert len(cal_imgs) == 90, len(cal_imgs)
t0 = time.time()
with torch.no_grad():
    for p in cal_imgs:
        x = torch.from_numpy(letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
                             .astype(np.float32) / 255.0).permute(2, 0, 1)[None]
        model(x)

# ---- MSE-optimal clipping (plan r3 G2 failure handling: adjust calibration) ----
# Pass-1 absmax is outlier-dominated: per-tensor grids end up 1.5-3x coarser than
# the bulk needs, and C2f cat requants saturate (bottleneck/cv1 scale ratios up
# to 1.51). Pass 2 histograms |v| per node; per node pick the clip c minimizing
# clip_mse(c) + (c/127)^2/12 * N_total (rounding noise), c in bin right-edges.
HIST_BINS = 2048
amax = {n: absmax.get(n, 1e-8) for n in hooked}
hists = {n: np.zeros(HIST_BINS, dtype=np.int64) for n in hooked}

def mk_hist_hook(name):
    def hook(mod, inp, out):
        t = out[0] if isinstance(out, (tuple, list)) else out
        v = t.detach().abs().ravel().numpy()
        a = amax[name]
        idx = np.minimum((v / a * (HIST_BINS - 1)).astype(np.int64), HIST_BINS - 1)
        hists[name] += np.bincount(idx, minlength=HIST_BINS).astype(np.int64)
    return hook

for name, mod in model.named_modules():
    if isinstance(mod, (UConv, Concat, Bottleneck)) or (isinstance(mod, nn.Conv2d) and 'dfl' not in name):
        mod.register_forward_hook(mk_hist_hook(name))
    if isinstance(mod, UConv) and getattr(mod, 'bn', None) is not None:
        mod.bn.register_forward_hook(mk_hist_hook(f'{name}|pre'))

with torch.no_grad():
    for p in cal_imgs:
        x = torch.from_numpy(letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
                             .astype(np.float32) / 255.0).permute(2, 0, 1)[None]
        model(x)

def clip_scale(name):
    """99.99th-percentile clip. Raw-MSE optima collapse to ~absmax/1000 here:
    post-SiLU tensors are dominated by near-zero negatives, so the MSE objective
    weights the huge zero mass and sacrifices the strong activations that carry
    the detections (measured: mAP50 -> 0.0002). A 99.99% percentile clips only
    the extreme 1e-4 tail — mild range shrink, finer grid, features intact."""
    h = hists[name].astype(np.float64)
    if h.sum() == 0:
        return amax[name]
    a = amax[name]
    edges = np.arange(1, HIST_BINS + 1) / HIST_BINS * a
    Wc = np.cumsum(h[::-1])[::-1]          # Wc[i] = mass of bins j >= i
    tail = Wc / Wc[0]                       # fraction of elements above edges[i-1]
    keep = np.nonzero(tail <= 1e-4)[0]      # at most 0.01% of elements clipped
    i = int(keep[0]) if len(keep) else HIST_BINS - 1
    return float(max(edges[i] if i < HIST_BINS else a, 1e-8))

clipv = {n: clip_scale(n) for n in hooked}
# UConv tensor scales land on the post-BN PRE-activation absmax via the bn
# output hooks above (plan r3 §4.2: SiLU LUT at pre-activation scale; requant
# domain, downstream in_scale, golden dequant and quant.json all agree).
scales = {n: clipv[n] / 127.0 for n in hooked}
clipped = sum(1 for n in hooked if clipv[n] < amax[n] * 0.999)
med_shrink = float(np.median([clipv[n] / amax[n] for n in hooked]))
status['calibration'] = (f'PASS ({len(cal_imgs)} imgs, {len(scales)} tensors, '
                         f'p99.99 clip on {clipped}/{len(hooked)}, median shrink {med_shrink:.3f}, '
                         f'{time.time()-t0:.0f}s)')
log(f'[2] calibrated {len(cal_imgs)} images -> {len(scales)} tensor scales '
    f'(p99.99 clip: {clipped}/{len(hooked)} nodes, median shrink {med_shrink:.3f})')

def S(n):
    return scales[n]

def SP(n):
    """post-BN pre-activation (requant/LUT-input) scale of an activated node."""
    return scales[f'{n}|pre']

# ================= 3. build QConv nodes =================
TOP = model.model
nodes = {}

def mk_qconv(name, tc, bn, has_act, in_scale):
    # requant domain = post-BN PRE-act absmax for activated nodes (LUT input
    # contract, S = SP(name)); stored tensor = post-act absmax (S(name)).
    # Linear tips: requant domain == stored == raw output absmax.
    nd = QConv(name, tc, bn, has_act, in_scale,
               SP(name) if has_act else S(name), S(name) if has_act else None)
    nodes[name] = nd
    return nd

def conv_u(name, mod, in_scale):
    return mk_qconv(name, mod.conv, mod.bn, True, in_scale)

def conv_plain(name, mod, in_scale):
    return mk_qconv(name, mod, None, False, in_scale)

# patch QConv to retain folded bias for scale rebinding

def set_in(node_name, in_scale):
    nd = nodes[node_name]
    nd.x_scale = in_scale
    nd.b_q = np.clip(np.round(nd._b_fold / (in_scale * nd.w_scales)).astype(np.int64),
                     -2**31, 2**31 - 1).astype(np.int32)
    nd.reqs = [req_pair((in_scale * ws) / nd.y_scale) for ws in nd.w_scales]

# patch QConv to retain folded bias for scale rebinding
_orig_init = QConv.__init__
def _init_keep(self, name, tc, bn, has_act, in_scale, out_scale, act_out_scale=None):
    import numpy as _np
    w = tc.weight.detach().numpy().astype(_np.float64)
    b = tc.bias.detach().numpy().astype(_np.float64) if tc.bias is not None else _np.zeros(w.shape[0])
    if bn is not None:
        g = bn.weight.detach().numpy().astype(_np.float64)
        bb = bn.bias.detach().numpy().astype(_np.float64)
        mu = bn.running_mean.detach().numpy().astype(_np.float64)
        var = bn.running_var.detach().numpy().astype(_np.float64)
        sb = g / _np.sqrt(var + float(bn.eps))
        w = w * sb[:, None, None, None]
        b = bb + (b - mu) * sb
    self._b_fold = b
    self._w_fold = w
    _orig_init(self, name, tc, bn, has_act, in_scale, out_scale, act_out_scale)
    # re-derive from kept folds so in_scale rebinding is consistent
    oc = w.shape[0]
    mx = _np.max(_np.abs(w).reshape(oc, -1), axis=1)
    self.w_scales = mx / 127.0
    self.w_scales[self.w_scales == 0] = 1e-12
    self.w_q = _np.stack([_np.round(w[c] / self.w_scales[c]) for c in range(oc)]).astype(_np.int8)
QConv.__init__ = _init_keep

# rebuild with patched init (keeps _b_fold)
nodes = {}
for i, mod in enumerate(TOP):
    pre = f'model.{i}'
    if isinstance(mod, UConv):
        conv_u(pre, mod, 1.0)
    elif isinstance(mod, C2f):
        conv_u(f'{pre}.cv1', mod.cv1, 1.0)
        conv_u(f'{pre}.cv2', mod.cv2, 1.0)
        for bi, bt in enumerate(mod.m):
            conv_u(f'{pre}.m.{bi}.cv1', bt.cv1, 1.0)
            conv_u(f'{pre}.m.{bi}.cv2', bt.cv2, 1.0)
    elif isinstance(mod, SPPF):
        conv_u(f'{pre}.cv1', mod.cv1, 1.0)
        conv_u(f'{pre}.cv2', mod.cv2, 1.0)
    elif isinstance(mod, Detect):
        for br in range(3):
            for li, layer in enumerate(mod.cv2[br]):
                (conv_u if isinstance(layer, UConv) else conv_plain)(f'{pre}.cv2.{br}.{li}', layer, 1.0)
            for li, layer in enumerate(mod.cv3[br]):
                (conv_u if isinstance(layer, UConv) else conv_plain)(f'{pre}.cv3.{br}.{li}', layer, 1.0)

status['graph_build'] = f'PASS ({len(nodes)} QConv nodes)'
log(f'[3] built {len(nodes)} QConv nodes')

# ================= 4. integer forward carrying (tensor, scale) =================
FIRST_ZS = None

def run_c2f_int(idx, x, xs, t):
    m = TOP[idx]; pre = f'model.{idx}'
    set_in(f'{pre}.cv1', xs)
    y = nodes[f'{pre}.cv1'].forward(x)
    y_s = nodes[f'{pre}.cv1'].s_stored          # C2f internal cat adopts cv1's stored scale
    t[f'{pre}.cv1'] = y
    c = getattr(m, 'c', None) or (y.shape[1] // 2)
    parts = [(a, y_s) for a in np.split(y, [y.shape[1] - c], axis=1)]
    for bi, bt in enumerate(m.m):
        h, hs = parts[-1]
        set_in(f'{pre}.m.{bi}.cv1', hs)
        h = nodes[f'{pre}.m.{bi}.cv1'].forward(h)
        set_in(f'{pre}.m.{bi}.cv2', nodes[f'{pre}.m.{bi}.cv1'].s_stored)
        h = nodes[f'{pre}.m.{bi}.cv2'].forward(h)
        if bt.add:
            h = int_add(h, nodes[f'{pre}.m.{bi}.cv2'].s_stored, parts[-1][0], parts[-1][1], S(f'{pre}.m.{bi}'))
            hs = S(f'{pre}.m.{bi}')
        else:
            hs = nodes[f'{pre}.m.{bi}.cv2'].s_stored   # non-add: stored tensor is cv2's post-LUT output
        t[f'{pre}.m.{bi}'] = h
        parts.append((h, hs))
    aligned = [(requant_to(p, ps, y_s) if abs(ps - y_s) > 1e-15 else p) for p, ps in parts]
    cat = np.concatenate(aligned, axis=1)
    set_in(f'{pre}.cv2', y_s)
    out = nodes[f'{pre}.cv2'].forward(cat)
    t[f'{pre}.cv2'] = out
    return out, nodes[f'{pre}.cv2'].s_stored

def int_forward(canvas_u8):
    """canvas_u8 RGB uint8 [S,S,3] -> (regs, clss, t) with t = name->int8 tensor."""
    global FIRST_ZS
    t = {}
    ts = {}
    x0 = (canvas_u8.astype(np.int16) - 128).astype(np.int8)[None].transpose(0, 3, 1, 2).copy()
    n0 = nodes['model.0']
    set_in('model.0', 1.0 / 255.0)
    if FIRST_ZS is None:
        FIRST_ZS = (128 * n0.w_q.reshape(n0.w_q.shape[0], -1).sum(axis=1)).astype(np.int64)
    x = n0.forward(x0, z_sum_w=FIRST_ZS)
    xs = n0.s_stored
    t['model.0'] = x; ts['model.0'] = xs
    for i in range(1, len(TOP)):
        mod = TOP[i]
        pre = f'model.{i}'
        if isinstance(mod, UConv):
            set_in(pre, xs)
            x = nodes[pre].forward(x)
            xs = nodes[pre].s_stored; t[pre] = x; ts[pre] = xs
        elif isinstance(mod, C2f):
            x, xs = run_c2f_int(i, x, xs, t)
            t[pre] = x; ts[pre] = xs
        elif isinstance(mod, SPPF):
            set_in(f'{pre}.cv1', xs)
            y = nodes[f'{pre}.cv1'].forward(x)
            p1 = maxpool5(y); p2 = maxpool5(p1); p3 = maxpool5(p2)
            cat = np.concatenate([y, p1, p2, p3], axis=1)
            set_in(f'{pre}.cv2', nodes[f'{pre}.cv1'].s_stored)
            x = nodes[f'{pre}.cv2'].forward(cat)
            xs = nodes[f'{pre}.cv2'].s_stored; t[pre] = x; ts[pre] = xs
        elif isinstance(mod, nn.Upsample):
            x = upsample_nearest2(x)          # scale kept
            t[pre] = x; ts[pre] = xs
        elif isinstance(mod, Concat):
            srcs = mod.f if isinstance(mod.f, list) else [mod.f]
            gathered = []
            for s_ in srcs:
                j = (i + s_) if s_ < 0 else s_   # negative = relative, non-negative = absolute index
                gathered.append((t[f'model.{j}'], ts[f'model.{j}']))
            aligned = [(requant_to(g, gs, S(pre)) if abs(gs - S(pre)) > 1e-15 else g) for g, gs in gathered]
            x = np.concatenate(aligned, axis=1)
            xs = S(pre); t[pre] = x; ts[pre] = xs
        elif isinstance(mod, Detect):
            d = mod
            fin = [t['model.15'], t['model.18'], t['model.21']]
            fins = [ts['model.15'], ts['model.18'], ts['model.21']]
            regs, clss = [], []
            for br in range(3):
                h, hs = fin[br], fins[br]
                for li, layer in enumerate(d.cv2[br]):
                    nm = f'{pre}.cv2.{br}.{li}'
                    set_in(nm, hs)
                    h = nodes[nm].forward(h)
                    hs = nodes[nm].s_stored
                    t[nm] = h
                regs.append(h)
                h3, hs3 = fin[br], fins[br]
                for li, layer in enumerate(d.cv3[br]):
                    nm = f'{pre}.cv3.{br}.{li}'
                    set_in(nm, hs3)
                    h3 = nodes[nm].forward(h3)
                    hs3 = nodes[nm].s_stored
                    t[nm] = h3
                clss.append(h3)
            return regs, clss, t
    raise RuntimeError('Detect not reached')

# fp capture hooks
fp_caps = {}
def mk_cap(name):
    def h(mod, i_, o):
        tt = o[0] if isinstance(o, (tuple, list)) else o
        fp_caps[name] = tt.detach().clone()
    return h
for name, mod in model.named_modules():
    if isinstance(mod, (UConv, Bottleneck, Concat)) or (isinstance(mod, nn.Conv2d) and 'dfl' not in name):
        mod.register_forward_hook(mk_cap(name))

def fp_forward(canvas_u8):
    x = torch.from_numpy(canvas_u8.astype(np.float32) / 255.0).permute(2, 0, 1)[None]
    with torch.no_grad():
        model(x)

# ---- layerwise LSQ stored-scale refit (plan r3 G2 failure handling: 调整校准) ----
# Golden-npz regression diagnosis: with p99.99 grids the per-node cascade slope
# int->fp sits systematically off 1 (0.81..1.13, consistent across images) and
# compounds through the chain. Closed-form fix per fit-site:
#     S' = argmin_S ||v*S - fp||^2  =  <v,fp>/<v,v>
# accumulated over a calibration subsample, v taken from the INT pipeline output
# itself (so the fit absorbs both fresh and inherited gain error). Fixed-point
# sweeps: all scales applied simultaneously after each pass; requant domains
# (|pre) and quantized weights untouched — pure stored-scale recalibration.
FIT_SUBSAMPLE = min(420, len(cal_imgs))   # dry-run: 全量 90 帧LSQ
_rng = np.random.default_rng(SEED)
_fit_imgs = [cal_imgs[i] for i in np.sort(_rng.choice(len(cal_imgs), FIT_SUBSAMPLE, replace=False))]
fit_sites = list(nodes.keys())
for i, mod in enumerate(TOP):
    pre = f'model.{i}'
    if isinstance(mod, C2f):
        fit_sites += [f'{pre}.m.{bi}' for bi, bt in enumerate(mod.m) if bt.add]
    elif isinstance(mod, Concat):
        fit_sites.append(pre)
REFIT_ITERS = 3   # run04: 真 RNE 下收敛比~0.995/iter，安全加一轮
refit_trace = []
for it in range(REFIT_ITERS):
    _t0 = time.time()
    num = {k: 0.0 for k in fit_sites}
    den = {k: 0.0 for k in fit_sites}
    for p in _fit_imgs:
        canvas = letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
        fp_caps.clear(); fp_forward(canvas)
        _, _, tv = int_forward(canvas)
        for k in fit_sites:
            f_ = fp_caps.get(k)
            v_ = tv.get(k)
            if f_ is None or v_ is None:
                continue
            f_ = f_[0].numpy().astype(np.float64).ravel()
            v_ = v_.astype(np.float64).ravel()
            num[k] += float(v_ @ f_)
            den[k] += float(v_ @ v_)
    ratios = []
    for k in fit_sites:
        if den[k] <= 0:
            continue
        old = nodes[k].s_stored if k in nodes else scales[k]
        s_new = float(np.clip(num[k] / den[k], 0.25 * old, 4.0 * old))   # runaway guard
        if k in nodes:
            nd = nodes[k]
            if nd.has_act:
                with np.errstate(over='ignore'):
                    x_ = np.arange(-128, 128, dtype=np.float64) * nd.y_scale
                    silu = x_ / (1.0 + np.exp(-x_))
                nd.lut = np.clip(np.round(silu / s_new), -128, 127).astype(np.int8)
                nd.s_stored = s_new
            else:   # linear tip: stored == requant domain -> rebuild reqs too
                nd.y_scale = s_new
                nd.s_stored = s_new
                nd.reqs = [req_pair((nd.x_scale * ws) / s_new) for ws in nd.w_scales]
        scales[k] = s_new
        ratios.append(s_new / old)
    ratios = np.array(ratios)
    refit_trace.append({'iter': it, 'median': float(np.median(ratios)),
                        'min': float(ratios.min()), 'max': float(ratios.max())})
    log(f'[3b] refit iter {it}/{REFIT_ITERS}: scale/old median {np.median(ratios):.4f} '
        f'range [{ratios.min():.4f}, {ratios.max():.4f}] ({time.time()-_t0:.0f}s)')
status['scale_refit'] = (f'PASS ({REFIT_ITERS} iters x {FIT_SUBSAMPLE} calib imgs, '
                         f'{len(fit_sites)} sites, final median ratio {refit_trace[-1]["median"]:.4f})')

# 探针图 = extra 3 张（亮度较宽）+ 首帧 calib（无 GT 依赖）
PROBE_IMGS = sorted((CAPTURE / 'extra').glob('*.jpg')) + [cal_imgs[0]]
snr_rows = []
for p in PROBE_IMGS:
    canvas = letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
    fp_caps.clear(); fp_forward(canvas)
    regs, clss, t = int_forward(canvas)
    for name, xq in t.items():
        if name in fp_caps:
            fp = fp_caps[name][0].numpy().astype(np.float64)
            dq = xq[0].astype(np.float64) * scales.get(name, 1.0)
            a_, b_ = fp.ravel(), dq.ravel()
            cos = float(a_ @ b_ / (np.linalg.norm(a_) * np.linalg.norm(b_) + 1e-12))
            snr_rows.append({'img': p.name, 'node': name, 'cosine': round(cos, 6)})
worst = min(snr_rows, key=lambda r: r['cosine'])
status['int_vs_fp_layers'] = f'PASS (worst cosine {worst["cosine"]:.4f} @ {worst["node"]}, {len(snr_rows)} checks)'
log(f'[4] layer cosine: worst={worst["cosine"]:.4f} @ {worst["node"]} over {len(snr_rows)} checks')

# ================= 5. export package =================
order = sorted(nodes)
wchunks, bchunks, lchunks, qmeta = [], [], [], []
wo = bo = lo = 0
for n in order:
    nd = nodes[n]
    w = nd.w_q.reshape(nd.w_q.shape[0], -1)
    wchunks.append(w.astype(np.int8).tobytes())
    bchunks.append(nd.b_q.astype('<i4').tobytes())
    lutb = nd.lut.astype(np.int8).tobytes() if nd.lut is not None else b''
    lchunks.append(lutb)
    qmeta.append({'node': n, 'in_scale': float(nd.x_scale), 'out_scale': float(nd.y_scale),
                  'stored_scale': float(nd.s_stored),
                  'w_shape': list(nd.w_q.shape), 'stride': list(nd.stride), 'pad': list(nd.pad),
                  'w_scales': [float(v) for v in nd.w_scales],
                  'req': [[int(m), int(s)] for m, s in nd.reqs], 'has_act': nd.has_act,
                  'w_off': wo, 'b_off': bo, 'l_off': lo})
    wo += w.nbytes; bo += nd.b_q.nbytes; lo += len(lutb)   # b_q int32: nbytes 已含 ×4
(RUN / 'weights.bin').write_bytes(b''.join(wchunks))
(RUN / 'bias.bin').write_bytes(b''.join(bchunks))
(RUN / 'lut.bin').write_bytes(b''.join(lchunks))
quant = {'contract': 'W8A8 per-channel symmetric weights / per-tensor symmetric activations / '
                     'INT32 accumulate / per-channel M+shift RNE requant / SiLU 256-entry LUT '
                     '(input pre-activation domain, output post-act calibrated scale) / '
                     'first layer uint8-128 z-term folded to bias / conv pad = input zp / '
                     'C2f internal cat adopts cv1 stored scale / Add saturates once',
         'input': {'size': SIZE, 'domain': 'uint8 RGB letterbox 114', 'stored_int8': 'u-128', 'scale': 1.0 / 255.0},
         'nodes': qmeta, 'tensor_scales': {k: float(v) for k, v in scales.items()}}
(RUN / 'quant.json').write_text(json.dumps(quant, indent=1), encoding='utf-8')
status['package_export'] = f'PASS ({len(order)} nodes, w{wo}B b{bo}B l{lo}B)'
log(f'[5] exported: {len(order)} nodes')

# ================= 6+7. one pass: FP/INT8 agreement + regression + golden =================
# dry-run 无 GT 标签：母本 ap50_per_class mAP 门不可用，改为同帧 FP-vs-INT8
# 检测一致性对拍（conf>=0.30、IOU>=0.5、同类、INT->FP 贪心匹配）。
# mAP 门（drop<=0.02）留给正式物料数据轮。
def decode_all(regs, clss, rs, cs_):
    allb, allc, allk = [], [], []
    for b in range(3):
        bx, cf, ki = softmax_dfl_decode(regs[b], rs[b], clss[b], cs_[b], STRIDES[b])
        allb.append(bx); allc.append(cf); allk.append(ki)
    bx = np.concatenate(allb); cf = np.concatenate(allc); ki = np.concatenate(allk)
    keep = nms_numpy(bx, cf, ki)
    return bx[keep], cf[keep], ki[keep]

ALL_IMGS = cal_imgs + sorted((CAPTURE / 'extra').glob('*.jpg'))

def iou_xywh(a, b):
    iw = max(0.0, min(a[0]+a[2]/2, b[0]+b[2]/2) - max(a[0]-a[2]/2, b[0]-b[2]/2))
    ih = max(0.0, min(a[1]+a[3]/2, b[1]+b[3]/2) - max(a[1]-a[3]/2, b[1]-b[3]/2))
    inter = iw * ih
    return inter / (a[2]*a[3] + b[2]*b[3] - inter + 1e-9)

def agreement(fp_dets, int_dets, conf=0.30, iou_thr=0.5):
    fbx, fcf, fki = fp_dets; ibx, icf, iki = int_dets
    fbx, fcf, fki = fbx[fcf >= conf], fcf[fcf >= conf], fki[fcf >= conf]
    ibx, icf, iki = ibx[icf >= conf], icf[icf >= conf], iki[icf >= conf]
    used = np.zeros(len(fbx), dtype=bool)
    ious, dconfs = [], []
    for t in np.argsort(-icf):
        best, bj = 0.0, -1
        for s in range(len(fbx)):
            if used[s] or fki[s] != iki[t]:
                continue
            v = iou_xywh(ibx[t], fbx[s])
            if v > best:
                best, bj = v, s
        if bj >= 0 and best >= iou_thr:
            used[bj] = True
            ious.append(best); dconfs.append(float(fcf[bj]) - float(icf[t]))
    return {'n_fp': int(len(fbx)), 'n_int': int(len(ibx)), 'n_matched': len(ious),
            'mean_iou': round(float(np.mean(ious)) if ious else 0.0, 4),
            'mean_dconf': round(float(np.mean(dconfs)) if dconfs else 0.0, 4),
            'fp_classes': {names[c]: int((fki == c).sum()) for c in np.unique(fki)} if len(fki) else {},
            'int_classes': {names[c]: int((iki == c).sum()) for c in np.unique(iki)} if len(iki) else {}}

t0 = time.time()
reg_out = []
golden_index = []
frames_out = []
gdir = RUN / 'golden'; gdir.mkdir(exist_ok=True)
deep_set = set(range(DEEP_SAMPLES))

for fi, p in enumerate(ALL_IMGS):
    canvas = letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
    # FP
    fp_caps.clear(); fp_forward(canvas)
    regs_fp = [fp_caps[f'model.22.cv2.{b}.2'].numpy() for b in range(3)]
    clss_fp = [fp_caps[f'model.22.cv3.{b}.2'].numpy() for b in range(3)]
    bx, cf, ki = decode_all(regs_fp, clss_fp, [1.0] * 3, [1.0] * 3)
    # INT8
    regs, clss, t = int_forward(canvas)
    rs = [S(f'model.22.cv2.{b}.2') for b in range(3)]
    cs_ = [S(f'model.22.cv3.{b}.2') for b in range(3)]
    bx2, cf2, ki2 = decode_all(regs, clss, rs, cs_)
    agr = agreement((bx, cf, ki), (bx2, cf2, ki2))
    frames_out.append({'image': p.name, **agr})
    # regression record（字段与母本一致，去 split）
    hh = hashlib.sha256()
    for r in regs + clss:
        hh.update(r.tobytes())
    reg_out.append({'image': p.name, 'raw_head_sha256': hh.hexdigest(),
                    'boxes': np.round(bx2, 2).tolist(), 'conf': np.round(cf2, 4).tolist(),
                    'cls': ki2.tolist()})
    # deep golden
    if fi in deep_set:
        store = {'canvas_u8': canvas}
        for name, xq in t.items():
            store[f'int8_{name}'] = xq[0]
            if name in fp_caps:
                store[f'fp_{name}'] = fp_caps[name][0].numpy().astype(np.float16)
        for b in range(3):
            store[f'raw_reg_s{STRIDES[b]}'] = regs[b][0]
            store[f'raw_cls_s{STRIDES[b]}'] = clss[b][0]
        fn = f'golden_{fi:02d}_{p.stem[:12]}.npz'
        np.savez_compressed(gdir / fn, **store)
        golden_index.append({'sample': fi, 'image': p.name, 'file': f'golden/{fn}',
                             'sha256': sha(gdir / fn), 'nodes': len(t),
                             'classes_present': sorted(int(x) for x in np.unique(ki2[cf2 >= 0.30])) if len(ki2) else []})

tot_fp = sum(f['n_fp'] for f in frames_out); tot_int = sum(f['n_int'] for f in frames_out)
tot_m = sum(f['n_matched'] for f in frames_out)
match_rate = tot_m / tot_fp if tot_fp else 0.0
_iou_fr = [f['mean_iou'] for f in frames_out if f['n_matched']]
agr_out = {'note': 'dry-run no-GT: FP-vs-INT8 same-frame detection agreement, conf>=0.30, IOU>=0.5, same class, greedy INT->FP',
           'frames': len(frames_out), 'total_fp_dets': tot_fp, 'total_int_dets': tot_int,
           'total_matched': tot_m, 'match_rate_vs_fp': round(match_rate, 4),
           'mean_iou_over_matched_frames': round(float(np.mean(_iou_fr)) if _iou_fr else 0.0, 4),
           'per_frame': frames_out}
(RUN / 'agreement_fp_vs_int8.json').write_text(json.dumps(agr_out, indent=1), encoding='utf-8')
(RUN / 'golden_index.json').write_text(json.dumps(golden_index, indent=2), encoding='utf-8')
(RUN / 'regression_frames.json').write_text(json.dumps(reg_out, indent=1), encoding='utf-8')
import csv
with open(RUN / 'layer_error.csv', 'w', newline='', encoding='utf-8') as f:
    wr = csv.DictWriter(f, fieldnames=['img', 'node', 'cosine']); wr.writeheader(); wr.writerows(snr_rows)

status['agreement'] = (f'{tot_m}/{tot_fp} matched ({match_rate:.1%}), mean IoU '
                       f'{agr_out["mean_iou_over_matched_frames"]:.4f} over {len(frames_out)} frames (no-GT dry-run metric)')
status['golden'] = f'PASS ({len(golden_index)} deep + {len(reg_out)} regression frames, {time.time()-t0:.0f}s)'

manifest = {'schema': 'yolo7020_g2_quant_v1',
            'model': {'weights': 'yolov8n.pt', 'sha256': sha(WEIGHTS), 'nc': 80,
                      'source': 'ultralytics official yolov8n.pt (frozen copy, toolchain dry-run)'},
            'calibration': {'capture': str(CAPTURE),
                            'list': 'calib/frame_*.jpg (90 frames, night static scene)', 'images': len(cal_imgs), 'seed': SEED,
                            'method': 'p99.99 percentile clip per-tensor symmetric + layerwise LSQ '
                                      'stored-scale refit (S\'=<v,fp>/<v,v> on the int-pipeline outputs '
                                      f'vs FP module outputs, {REFIT_ITERS} fixed-point sweeps over a '
                                      f'{FIT_SUBSAMPLE}-img subsample; raw-MSE clip rejected: collapses '
                                      'to ~absmax/1000 on near-zero-dominated post-SiLU tensors)',
                            'clipped_nodes': clipped, 'total_nodes': len(hooked),
                            'median_shrink': med_shrink,
                            'refit_sites': len(fit_sites), 'refit_trace': refit_trace},
            'input_contract': {'size': SIZE, 'preprocess': 'letterbox 114 BGR->RGB uint8, stored u-128'},
            'files': {f: sha(RUN / f) for f in ['weights.bin', 'bias.bin', 'lut.bin', 'quant.json']},
            'env': {'python': sys.executable, 'torch': torch.__version__,
                    'ultralytics': ultralytics.__version__, 'numpy': np.__version__},
            'dryrun': True,
            'note': 'DRYRUN: no GT labels; mAP50 gate (drop<=0.02) reserved for labeled-data round; '
                    'agreement_fp_vs_int8.json carries the no-GT proxy metric',
            'status': 'DRYRUN_CANDIDATE'}
(RUN / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')

soft_ok = (match_rate >= 0.80) and (agr_out['mean_iou_over_matched_frames'] >= 0.90)
final = {'result': 'G2_N80_DRYRUN_PASS' if soft_ok else 'G2_N80_DRYRUN_SOFT_FAIL',
         'soft_gate': {'match_rate_vs_fp': round(match_rate, 4), 'match_floor': 0.80,
                       'mean_iou': agr_out['mean_iou_over_matched_frames'], 'iou_floor': 0.90,
                       'note': 'heuristic no-GT proxy gate, dry-run only'},
         'status': status}
(RUN / 'summary.json').write_text(json.dumps(final, indent=2), encoding='utf-8')
(RUN / 'console.log').write_text('\n'.join(L) + '\n', encoding='utf-8')
log('# FINAL: ' + json.dumps(final))
