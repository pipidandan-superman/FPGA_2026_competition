#!/usr/bin/env python3
# -*- coding:utf-8 -*-
"""g0_extender_n80.py -- P2 N80 rehearsal run01: G0 oracle 扩展导出（nc=80，纯主机）.

母本 = 2026-09-21_yolo_p2_0_run04_g0ext/g0_extender.py（手势线正典，只读不改）。
本文件为 N80 拷出适配副本，差异逐条列明（其余逐行等价）：
  D1 ROM: 2_fpga rom_data(手势 nc=7) → dryrun_run01/out/quant_n80(官方 n80 演练包，
     REHEARSAL_ONLY)；weights/bias/lut/quant/schedule 全部取自该包
  D2 G0: 手势 run04 golden → dryrun_run01/out/quant_n80/golden(5 帧，物体采集帧)
  D3 intref 导入源: 手势 run04 目录 → dryrun_run01/scripts（字节一致副本，
     nc 无关数值原语=允许复用的实现遗产，符合 2026-10-06 手势数据隔离禁令）
  D4 输出: 本 run 目录 g0_ext_*.npz + g0_ext_report.json，标签 REHEARSAL_ONLY
  D5 证据链语境: 演练模型=官方 yolov8n.pt(nc=80)；heads cls 面 7→80，
     strides 键(40/20/10)与 reg[64,H,W] 结构同母本，映射逻辑不变
手势数据隔离（1_docs/gesture_data_isolation_directive_2026-10-06.md）：
运行时零手势数据加载——ROM/G0/intref 三源全部指向本线物体资产。

验证门（与母本同，每帧全过才 PASS；位级 0 差）：
  V0 model.0 从 canvas 重算 == npz int8_model.0（z_sum_w 链路）
  V1 每个 bottleneck 链 cv1→cv2(→int_add) 终值 == npz int8_model.N.m.B
  V2 每个 C2f：派生 cat 喂 cv2(工件重建) == npz int8_model.N.cv2
  V3 SPPF：p1/p2/p3→cat→cv2 == npz int8_model.9
  V4 视图 = int8_model.N.cv1 切片，shape 逐项核对 schedule
  V5 heads 6 源张量 == npz raw_reg/raw_cls_s{8,16,32} 逐字节
预期产出：50 派生张量 ext（conv 22+concat 9+pool 3+view 16）+ heads 映射
→ 补齐 oracle_manifest 51 悬空行（50 张量+1 heads 映射）。

Run: 2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe g0_extender_n80.py
"""
import hashlib
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：冻结输入经 accel_paths；intref 查找经 accel_bootstrap（tools\）
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
import accel_paths as _AP                               # noqa: E402
DRY = _AP.DRY
ROM = _AP.ROM                                          # D1
from intref_yolov8 import rne_shift, sat_i8, int_add, requant_to, \
    maxpool5                                    # noqa: E402  (实现遗产，字节同母本)

GOLDEN = os.path.join(ROM, 'golden')                    # D2
LABEL = 'REHEARSAL_ONLY(官方 yolov8n.pt nc=80 演练模型，非物料模型)'


def sha_f(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


class Artifacts:
    """从 N80 量化包重建 conv 前向（数值合同 = intref QConv.forward）。"""

    def __init__(self):
        q = json.load(open(os.path.join(ROM, 'quant.json'), encoding='utf-8'))
        self.q = {n['node']: n for n in q['nodes']}
        self.W = np.frombuffer(open(os.path.join(ROM, 'weights.bin'), 'rb')
                               .read(), dtype=np.int8)
        self.B = np.frombuffer(open(os.path.join(ROM, 'bias.bin'), 'rb')
                               .read(), dtype=np.int32)
        self.L = np.frombuffer(open(os.path.join(ROM, 'lut.bin'), 'rb')
                               .read(), dtype=np.int8)
        self._zsum = {}

    def node(self, name):
        return self.q[name]

    def w(self, nd):
        n = int(np.prod(nd['w_shape']))
        return self.W[nd['w_off']:nd['w_off'] + n].reshape(
            nd['w_shape']).astype(np.int32)

    def b(self, nd):
        oc = nd['w_shape'][0]
        o = nd['b_off'] // 4                  # b_off 是字节偏移，int32 元素化
        return self.B[o:o + oc].astype(np.int64)

    def lut(self, nd):
        return self.L[nd['l_off']:nd['l_off'] + 256]

    def z_sum_w(self, name):
        """首层 +128*colsum(w_q)（intref FIRST_ZS 同式）。"""
        if name not in self._zsum:
            wq = self.w(self.node(name))
            self._zsum[name] = (128 * wq.reshape(wq.shape[0], -1)
                                .sum(axis=1)).astype(np.int64)
        return self._zsum[name]

    def forward(self, name, x_q, first=False):
        """intref QConv.forward 同式：acc_i32(+pad) → (+b)×M>>s RNE sat → LUT."""
        nd = self.node(name)
        wq = self.w(nd)
        sh, sw = nd['stride']
        ph, pw = nd['pad']
        kh, kw = nd['w_shape'][2], nd['w_shape'][3]
        pad_val = -128 if first else 0
        N, C, H, W = x_q.shape
        Ho = (H + 2 * ph - kh) // sh + 1
        Wo = (W + 2 * pw - kw) // sw + 1
        xp = np.full((N, C, H + 2 * ph, W + 2 * pw), pad_val, dtype=np.int8)
        if ph or pw:
            xp[:, :, ph:ph + H, pw:pw + W] = x_q
        else:
            xp = x_q.copy()
        cols = np.empty((C * kh * kw, Ho * Wo), dtype=np.int32)
        pos = 0
        for c in range(C):
            for i in range(kh):
                for j in range(kw):
                    patch = xp[:, c, i:i + sh * Ho:sh, j:j + sw * Wo:sw]
                    cols[pos] = patch.reshape(N, -1)[0]
                    pos += 1
        acc = wq.reshape(wq.shape[0], -1) @ cols
        acc = acc.reshape(1, -1, Ho, Wo)
        bias = self.b(nd)
        if first:
            bias = bias + self.z_sum_w(name)
        out = np.empty(acc.shape, dtype=np.int8)
        for c in range(acc.shape[1]):
            M, s = nd['req'][c]
            n = (acc[:, c].astype(np.int64) + bias[c]) * M
            out[:, c] = sat_i8(rne_shift(n, s))
        if nd['has_act']:
            out = self.lut(nd)[(out.astype(np.int16) + 128).astype(np.uint8)]
        return out


def align_cat(parts, out_scale):
    """walk 同式：scale 不同才 requant_to，然后 concat（通道维）。"""
    aligned = [requant_to(p, ps, out_scale) if abs(ps - out_scale) > 1e-15
               else p for p, ps in parts]
    return np.concatenate(aligned, axis=1)


def make_resolver(G, ext):
    """producer 名 -> 4D 张量：ext 命中 / 切片语法 / npz 直取。"""
    def resolve(prod):
        if prod in ext:
            return ext[prod]
        if prod.endswith(']') and '[' in prod:
            base, rng = prod[:-1].split('[')
            c0, c1 = (int(x) if x else None for x in rng.split(':'))
            return G[base][None][:, c0:c1]
        if prod in G:
            return G[prod][None]
        return None
    return resolve


def main():
    A = Artifacts()
    s = json.load(open(os.path.join(ROM, 'schedule.json'), encoding='utf-8'))
    tasks, bufs = s['tasks'], s['buffers']
    tmap = {t['node']: t for t in tasks}
    errs = []
    frames = sorted(f for f in os.listdir(GOLDEN) if f.endswith('.npz'))
    report = {'run': 'P2 N80 rehearsal run01 G0 extension', 'label': LABEL,
              'rom': ROM, 'g0_readonly': GOLDEN, 'gesture_data_loaded': False,
              'frames': [], 'errors': errs}

    # ---- schedule↔quant req 交叉门（63 conv，另加一道）----
    req_mismatch = []
    for t in tasks:
        if t['op'] != 'conv':
            continue
        if t.get('req') != A.node(t['node'])['req']:
            req_mismatch.append(t['node'])
    if req_mismatch:
        errs.append('E_REQ_MISMATCH %s' % ','.join(req_mismatch[:5]))
    print('REQ cross-check: %d convs %s'
          % (63, 'OK' if not req_mismatch else 'MISMATCH'))

    for fn in frames:
        npz = np.load(os.path.join(GOLDEN, fn))
        G = {k[5:]: npz[k] for k in npz.files
             if k.startswith('int8_')}       # name -> int8 tensor
        ext = {}
        resolve = make_resolver(G, ext)      # 每帧重建（ext 闭包可变）
        v = {'V0': None, 'V1': 0, 'V2': 0, 'V3': None, 'V4': 0, 'V5': 0}
        v1_n = v2_n = 0

        # ---- V0：model.0 从 canvas 重算 ----
        canvas = npz['canvas_u8']
        x0 = (canvas.astype(np.int16) - 128).astype(np.int8)[None] \
            .transpose(0, 3, 1, 2).copy()
        y0 = A.forward('model.0', x0, first=True)
        d0 = int(np.sum(y0[0] != G['model.0']))
        v['V0'] = d0

        # ---- C2f（8 个）----
        for N in (2, 4, 6, 8, 12, 15, 18, 21):
            pre = 'model.%d' % N
            cv1_out = G[pre + '.cv1'][None]          # 统一 4D [1,C,H,W]
            cv1_s = A.node(pre + '.cv1')['stored_scale']

            # V4 视图 = 切片
            for si in (0, 1):
                t = tmap['%s.split%d' % (pre, si)]
                c0, c1 = t['ch']
                ext['%s.split%d' % (pre, si)] = cv1_out[:, c0:c1]

            # bottleneck 链（schedule 逐 conv 任务存在性驱动）
            t1 = tmap['%s.split1' % pre]
            bi = 0
            h_prev, h_prev_s = None, None
            while '%s.m.%d.cv1' % (pre, bi) in tmap:
                bnode = '%s.m.%d' % (pre, bi)
                if h_prev is None:
                    h_in = cv1_out[:, t1['ch'][0]:t1['ch'][1]]
                    h_in_s = cv1_s
                else:
                    h_in, h_in_s = h_prev, h_prev_s
                h1 = A.forward(bnode + '.cv1', h_in)
                ext[bnode + '.cv1'] = h1
                h2 = A.forward(bnode + '.cv2', h1)
                ext[bnode + '.cv2'] = h2
                if bnode in tmap and tmap[bnode]['op'] == 'add':
                    hs = int_add(h2, A.node(bnode + '.cv2')['stored_scale'],
                                 h_in, h_in_s, tmap[bnode]['out_scale'])
                    ext[bnode] = hs
                    tgt, out_s = hs, tmap[bnode]['out_scale']
                else:
                    tgt = h2
                    out_s = A.node(bnode + '.cv2')['stored_scale']
                if bnode not in G:
                    errs.append('E_NO_REF %s %s' % (fn, bnode))
                else:
                    v['V1'] += int(np.sum(tgt[0] != G[bnode]))
                    v1_n += 1
                h_prev, h_prev_s = tgt, out_s
                bi += 1

            # cat（V2：cat→cv2 == stash）
            tc = tmap[pre + '.cat']
            parts = []
            for e in tc['inputs']:
                ten = resolve(bufs[e['buf']]['producer'])
                if ten is None:
                    errs.append('E_CAT_SRC %s %s' % (
                        fn, bufs[e['buf']]['producer']))
                    ten = np.zeros_like(cv1_out[:, :1])
                parts.append((ten, e['scale']))
            cat = align_cat(parts, tc['out_scale'])
            ext[pre + '.cat'] = cat
            cv2_out = A.forward(pre + '.cv2', cat)
            v['V2'] += int(np.sum(cv2_out[0] != G[pre + '.cv2']))
            v2_n += 1

        # ---- V3：SPPF model.9（cat→cv2 == stash model.9 把 pool/cat/cv1 钉死）----
        y = A.forward('model.9.cv1', G['model.8'][None])
        ext['model.9.cv1'] = y
        p1 = maxpool5(y)
        p2 = maxpool5(p1)
        p3 = maxpool5(p2)
        ext['model.9.pool0'], ext['model.9.pool1'], ext['model.9.pool2'] = \
            p1, p2, p3
        tc = tmap['model.9.cat']
        parts = []
        for e in tc['inputs']:
            ten = resolve(bufs[e['buf']]['producer'])
            if ten is None:
                errs.append('E_SPPF_SRC %s %s' % (
                    fn, bufs[e['buf']]['producer']))
                ten = y[:, :1]
            parts.append((ten, e['scale']))
        cat9 = align_cat(parts, tc['out_scale'])
        ext['model.9.cat'] = cat9
        o9 = A.forward('model.9.cv2', cat9)
        ext['model.9.cv2'] = o9
        v['V3'] = int(np.sum(o9[0] != G['model.9']))

        # ---- V5：heads 6 源 == raw_reg/raw_cls（D5: cls 面 80，映射同式）----
        strides = {40: 8, 20: 16, 10: 32}
        ht = tmap['model.22']
        heads_map = {}
        for bidx, e in enumerate(ht['reg']):
            raw = npz['raw_reg_s%d' % strides[e['shape'][1]]][0]
            src = G[bufs[e['buf']]['producer']]
            v['V5'] += int(np.sum(src[0] != raw))
            heads_map['reg%d' % bidx] = bufs[e['buf']]['producer']
        for bidx, e in enumerate(ht['cls']):
            raw = npz['raw_cls_s%d' % strides[e['shape'][1]]][0]
            src = G[bufs[e['buf']]['producer']]
            v['V5'] += int(np.sum(src[0] != raw))
            heads_map['cls%d' % bidx] = bufs[e['buf']]['producer']

        # ---- V4 记账：视图 shape 逐项核对 ----
        for t in tasks:
            if t['op'] != 'view':
                continue
            ten = ext.get(t['node'])
            if ten is None:
                errs.append('E_VIEW_MISSING %s %s' % (fn, t['node']))
                continue
            c0, c1 = t['ch']
            want = (c1 - c0, *bufs[t['out']]['shape'][1:])
            if ten.shape[1:] != tuple(want):
                errs.append('E_VIEW_SHAPE %s %s %s vs %s'
                            % (fn, t['node'], ten.shape[1:], want))
                v['V4'] += 1

        # ---- 位级门判定 + 落盘 ----
        ok = (v['V0'] == 0 and v['V1'] == 0 and v['V2'] == 0
              and v['V3'] == 0 and v['V4'] == 0 and v['V5'] == 0)
        out_npz = os.path.join(HERE, 'g0_ext_%s' % fn.replace('golden_', ''))
        np.savez_compressed(out_npz,
                            **{'int8_' + k: x[0] for k, x in ext.items()})
        report['frames'].append({
            'frame': fn, 'g0_sha256': sha_f(os.path.join(GOLDEN, fn)),
            'n_ext': len(ext), 'v': v, 'v1_chains': v1_n, 'v2_cats': v2_n,
            'heads_map': heads_map,
            'ext_sha256': sha_f(out_npz + '.npz'
                                if not out_npz.endswith('.npz') else out_npz),
            'pass': ok,
        })
        print('%s ext=%d V0=%d V1=%d(%d chains) V2=%d(%d cats) V3=%d V4=%d '
              'V5=%d -> %s' % (fn, len(ext), v['V0'], v['V1'], v1_n,
                               v['V2'], v2_n, v['V3'], v['V4'], v['V5'],
                               'PASS' if ok else 'FAIL'))

    allp = all(f['pass'] for f in report['frames'])
    report['verdict'] = 'PASS' if (allp and not errs) else 'FAIL'
    json.dump(report, open(os.path.join(HERE, 'g0_ext_report.json'), 'w',
              encoding='utf-8'), indent=1, ensure_ascii=False)
    print('G0_EXTENDER_N80 %s (%s)' % (report['verdict'], LABEL))
    for e in errs[:10]:
        print('  ERR', e)
    return 0 if report['verdict'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
