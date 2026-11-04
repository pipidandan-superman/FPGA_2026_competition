"""离线调度编译器（PC 侧，一次性）：模型拓扑 + G2 包 -> schedule.json。

**G2-N80 DRYRUN 拷出适配版**（母本 = 2_fpga/3_yolo_zynq/pynq/gen_schedule.py，
git bb5267f；2_fpga 冻结只读，本副本产物全部落 4_metrics run 目录）。

与母本的差异（仅此 4 处，任务遍历逻辑逐行等价）：
  1. ROM <- dryrun_run01/out/quant_n80（本轮 G2-N80 量化包）；
  2. WEIGHTS <- dryrun_run01/weights/yolov8n.pt（nc=80）；
  3. 输出 schedule.json -> out/quant_n80/schedule.json（不触碰 2_fpga）；
  4. 末尾追加审计打印：conv 任务数 / cls 段形状 / heads 体积自算
     （与 p2_compiler 消费面、ONNX 权威 diff 三方互证）。

Run: E:/competition/4_metrics/logs/2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe gen_schedule_n80.py
"""
import json
import os
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
RUN = HERE.parent
ROM = RUN / 'out' / 'quant_n80'          # G2-N80 量化包（quant.json/weights/bias/lut/manifest）
WEIGHTS = RUN / 'weights' / 'yolov8n.pt'  # nc=80 官方权重（冻结副本）
# M4.2 归位：yolo_pkg 只读导入源经 accel_paths（去绝对路径）。本件=
# 产线冻结件：RUN/ROM/WEIGHTS 保持历史 HERE 相对语义（重跑会在新树落
# out/，M4 v1 禁止重跑——量化包/日程=v1.0 冻结输入）。
import sys as _sys
_RT = Path(__file__).resolve().parent.parent          # 12_yolo_accel
if str(_RT) not in _sys.path:
    _sys.path.insert(0, str(_RT))
import accel_paths as _AP                             # noqa: E402
PYNQ = Path(_AP.PYNQ)  # yolo_pkg 只读导入源

os.environ.update(YOLO_OFFLINE='true', YOLO_AUTOINSTALL='false', PYTHONNOUSERSITE='1',
                  PYTHONDONTWRITEBYTECODE='1', OMP_NUM_THREADS='2', MKL_NUM_THREADS='2')
import torch  # noqa: E402
import torch.nn as nn  # noqa: E402
from ultralytics import YOLO  # noqa: E402
from ultralytics.nn.modules import Conv as UConv, C2f, SPPF, Concat, Detect  # noqa: E402

sys.path.insert(0, str(PYNQ))
from yolo_pkg import YoloPackage  # noqa: E402

pkg = YoloPackage(ROM)
SIZE = pkg.size
model = YOLO(str(WEIGHTS)).model.eval()
TOP = model.model

bufs = []


def newbuf(shape, producer):
    bid = len(bufs)
    bufs.append({'id': bid, 'shape': [int(s) for s in shape], 'producer': producer})
    return bid


tasks = []


def shape_after(in_shape, nd):
    _, _, kh, kw = nd['w_shape']
    sh, sw = nd['stride']
    ph, pw = nd['pad']
    return [(in_shape[1] + 2 * ph - kh) // sh + 1,
            (in_shape[2] + 2 * pw - kw) // sw + 1]


def conv_task(name, in_buf, in_shape, first=False):
    nd = pkg.node(name)
    oc = nd['w_shape'][0]
    Ho, Wo = shape_after(in_shape, nd)
    ob = newbuf([oc, Ho, Wo], name)
    t = {'op': 'conv', 'node': name, 'in': in_buf, 'out': ob,
         'out_shape': [oc, Ho, Wo], 'stride': nd['stride'], 'pad': nd['pad'],
         'k': nd['w_shape'][2:4], 'has_act': nd['has_act'], 'first': first,
         'req': nd['req']}
    tasks.append(t)
    return ob, [oc, Ho, Wo]


def view_task(name, in_buf, in_shape, ch_lo, ch_hi, producer):
    ob = newbuf([ch_hi - ch_lo] + list(in_shape[1:]), producer)
    tasks.append({'op': 'view', 'node': name, 'in': in_buf, 'out': ob,
                  'ch': [ch_lo, ch_hi]})
    return ob, [ch_hi - ch_lo] + list(in_shape[1:])


def add_task(name, a_buf, a_s, b_buf, b_s, out_s, shape):
    ob = newbuf(shape, name)
    tasks.append({'op': 'add', 'node': name, 'a': a_buf, 'a_scale': a_s,
                  'b': b_buf, 'b_scale': b_s, 'out': ob, 'out_scale': out_s})
    return ob


def pool_task(name, in_buf, in_shape):
    C, H, W = in_shape
    ob = newbuf([C, H, W], name)
    tasks.append({'op': 'maxpool5', 'node': name, 'in': in_buf, 'out': ob})
    return ob


def up_task(name, in_buf, in_shape):
    C, H, W = in_shape
    ob = newbuf([C, H * 2, W * 2], name)
    tasks.append({'op': 'upsample2', 'node': name, 'in': in_buf, 'out': ob})
    return ob, [C, H * 2, W * 2]


def cat_task(name, inputs, out_scale, shape):
    """inputs: [(buf, scale)]。尺度全一致时执行器跳过重量化（与 int_forward 相同）。"""
    ob = newbuf(shape, name)
    tasks.append({'op': 'concat', 'node': name,
                  'inputs': [{'buf': b, 'scale': s} for b, s in inputs],
                  'out': ob, 'out_scale': out_scale})
    return ob


outs = {}   # 'model.N' -> (buf, shape, scale)；顶层顺序输出即下一模块输入

b_in = newbuf([3, SIZE, SIZE], 'input')
n0 = pkg.node('model.0')
z_sum_w = (128 * pkg.w('model.0').reshape(n0['w_shape'][0], -1)
           .sum(axis=1)).astype(np.int64).tolist()
b0, s0 = conv_task('model.0', b_in, [3, SIZE, SIZE], first=True)
tasks[-1]['z_sum_w'] = z_sum_w
outs['model.0'] = (b0, s0, pkg.stored_scale('model.0'))

for i in range(1, len(TOP)):
    mod = TOP[i]
    pre = f'model.{i}'
    src = outs[f'model.{i - 1}']      # v8 顶层为顺序执行，i 的输入 = i-1 的输出
    if isinstance(mod, UConv):
        ob, sh = conv_task(pre, src[0], src[1])
        outs[pre] = (ob, sh, pkg.stored_scale(pre))
    elif isinstance(mod, C2f):
        b_cv1, s_cv1 = conv_task(f'{pre}.cv1', src[0], src[1])
        sc_cv1 = pkg.stored_scale(f'{pre}.cv1')
        c = s_cv1[0] // 2
        pa, sa = view_task(f'{pre}.split0', b_cv1, s_cv1, 0, c, f'{pre}.cv1[0:{c}]')
        pb, sb = view_task(f'{pre}.split1', b_cv1, s_cv1, c, 2 * c, f'{pre}.cv1[{c}:]')
        parts = [(pa, sa, sc_cv1), (pb, sb, sc_cv1)]
        for bi, bt in enumerate(mod.m):
            h_buf, h_shape, h_s = parts[-1]
            b1, s1 = conv_task(f'{pre}.m.{bi}.cv1', h_buf, h_shape)
            b2, s2 = conv_task(f'{pre}.m.{bi}.cv2', b1, s1)
            sc2 = pkg.stored_scale(f'{pre}.m.{bi}.cv2')
            if bt.add:
                out_s = pkg.tensor_scales[f'{pre}.m.{bi}']
                ba = add_task(f'{pre}.m.{bi}', b2, sc2, parts[-1][0], parts[-1][2],
                              out_s, s2)
                parts.append((ba, s2, out_s))
            else:
                parts.append((b2, s2, sc2))
        cat_ch = sum(p[1][0] for p in parts)
        b_cat = cat_task(f'{pre}.cat', [(p[0], p[2]) for p in parts], sc_cv1,
                         [cat_ch] + s_cv1[1:])
        b_cv2, s_cv2 = conv_task(f'{pre}.cv2', b_cat, [cat_ch] + s_cv1[1:])
        outs[pre] = (b_cv2, s_cv2, pkg.stored_scale(f'{pre}.cv2'))
    elif isinstance(mod, SPPF):
        b1, s1 = conv_task(f'{pre}.cv1', src[0], src[1])
        sc1 = pkg.stored_scale(f'{pre}.cv1')
        pools = [b1]
        for pi in range(3):
            nb = pool_task(f'{pre}.pool{pi}', pools[-1], s1)
            pools.append(nb)
        b_cat = cat_task(f'{pre}.cat', [(p, sc1) for p in pools], sc1,
                         [4 * s1[0]] + s1[1:])
        b2, s2 = conv_task(f'{pre}.cv2', b_cat, [4 * s1[0]] + s1[1:])
        outs[pre] = (b2, s2, pkg.stored_scale(f'{pre}.cv2'))
    elif isinstance(mod, nn.Upsample):
        ob, sh = up_task(pre, src[0], src[1])
        outs[pre] = (ob, sh, src[2])
    elif isinstance(mod, Concat):
        srcs = mod.f if isinstance(mod.f, list) else [mod.f]
        gathered, ch = [], 0
        for s_ in srcs:
            j = (i + s_) if s_ < 0 else s_
            bufj, shj, scj = outs[f'model.{j}']
            gathered.append((bufj, scj))
            ch += shj[0]
        ref_shape = outs[f'model.{(i + srcs[0]) if srcs[0] < 0 else srcs[0]}'][1]
        out_s = pkg.tensor_scales[pre]
        b_cat = cat_task(pre, gathered, out_s, [ch] + ref_shape[1:])
        outs[pre] = (b_cat, [ch] + ref_shape[1:], out_s)
    elif isinstance(mod, Detect):
        heads = {'reg': [], 'cls': []}
        fins = [outs['model.15'], outs['model.18'], outs['model.21']]
        for br in range(3):
            h, hs_, hsc = fins[br]
            for li in range(len(mod.cv2[br])):
                nm = f'{pre}.cv2.{br}.{li}'
                h, hs_ = conv_task(nm, h, hs_)
                hsc = pkg.stored_scale(nm)
            heads['reg'].append({'buf': h, 'scale': hsc, 'shape': hs_})
            h, hs_, hsc = fins[br]
            for li in range(len(mod.cv3[br])):
                nm = f'{pre}.cv3.{br}.{li}'
                h, hs_ = conv_task(nm, h, hs_)
                hsc = pkg.stored_scale(nm)
            heads['cls'].append({'buf': h, 'scale': hsc, 'shape': hs_})
        tasks.append({'op': 'heads', 'node': pre, 'reg': heads['reg'], 'cls': heads['cls']})
    else:
        raise RuntimeError(f'unhandled module {pre}: {type(mod)}')

schedule = {
    'schema': 'yolo7020_sched_v1',
    'input': {'buf': b_in, 'shape': [3, SIZE, SIZE], 'scale': pkg.input_scale,
              'stored': 'uint8-128', 'letterbox': 114},
    'buffers': bufs,
    'tasks': tasks,
    'strides': [8, 16, 32],
    'source': {'package': 'out/quant_n80 (G2-N80 object model, this run)',
               'quant_contract': pkg.quant['contract']},
}
OUT = ROM / 'schedule.json'
OUT.write_text(json.dumps(schedule, indent=1), encoding='utf-8')

# ---- src_pin.json：schedule+quant 实算 SHA（p2_compiler_n80 的防漂移比对源，
# 免手工转录，见仓库铁律"单行逐字转录自 sha256sum 实算输出"）----
import hashlib
pin = {'schedule.json': hashlib.sha256(OUT.read_bytes()).hexdigest(),
       'quant.json': hashlib.sha256(
           (ROM / 'quant.json').read_bytes()).hexdigest(),
       'pinned_by': 'gen_schedule_n80.py (dry-run, runtime-computed)'}
(ROM / 'src_pin.json').write_text(json.dumps(pin, indent=1), encoding='utf-8')
print(f'schedule.json: {len(tasks)} tasks, {len(bufs)} buffers, input {SIZE}')
for t in tasks[:6]:
    print(' ', t['op'], t['node'], '->', t.get('out'))

# ---- dry-run 审计段（母本无）----
n_conv = sum(1 for t in tasks if t['op'] == 'conv')
heads_t = [t for t in tasks if t['op'] == 'heads'][0]
cls_shapes = [c['shape'] for c in heads_t['cls']]
reg_shapes = [r['shape'] for r in heads_t['reg']]
heads_bytes = sum(int(np.prod(s)) for s in reg_shapes + cls_shapes)
n_buf = len(bufs)
audit = {'tasks': len(tasks), 'buffers': n_buf, 'conv_tasks': n_conv,
         'cls_shapes': cls_shapes, 'reg_shapes': reg_shapes,
         'heads_bytes_selfcomputed': heads_bytes,
         'expect': {'tasks': 104, 'buffers': 104, 'conv': 63,
                    'cls_shapes': [[80, 40, 40], [80, 20, 20], [80, 10, 10]],
                    'heads_bytes': 302400}}
(RUN / 'evidence' / 'schedule_n80_audit.json').write_text(
    json.dumps(audit, indent=1), encoding='utf-8')
ok = (len(tasks) == 104 and n_buf == 104 and n_conv == 63
      and cls_shapes == [[80, 40, 40], [80, 20, 20], [80, 10, 10]]
      and heads_bytes == 302400)
print(f'[audit] conv={n_conv} buffers={n_buf} cls={cls_shapes} '
      f'heads_bytes={heads_bytes} (reg {sum(int(np.prod(s)) for s in reg_shapes)} + '
      f'cls {sum(int(np.prod(s)) for s in cls_shapes)})')
print('SCHEDULE_N80_' + ('PASS' if ok else 'MISMATCH'))
