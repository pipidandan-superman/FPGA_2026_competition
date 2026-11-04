#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""f2_replay_n80.py -- P2 N80 rehearsal: 软件后端全图 104 任务回放 vs G0（纯主机）.

母本 = 2026-09-21_yolo_p2_0_run05_f2_replay/f2_replay.py（手势线正典，只读）。
N80 拷出适配差异（其余逐行等价）：
  N1 ROM: 2_fpga rom_data(手势) → dryrun_run01/out/quant_n80（REHEARSAL_ONLY）
  N2 G0: 手势 run04 golden → dryrun_run01/out/quant_n80/golden（5 帧）
  N3 RUN04: 手势 g0ext 目录 → 2026-10-06_yolo_p2_g0ext_n80_run01
     （from g0_extender_n80 import Artifacts/align_cat，单一源复用本线实现）
  N4 RUN02 buffer_table: 手势 manifests → dryrun_run01/out/p2_manifests_n80
  N5 intref 导入源: 手势 run04 → dryrun_run01/scripts（字节一致，实现遗产）
  N6 标签/报告语境: REHEARSAL_ONLY；运行时零手势数据加载
     （1_docs/gesture_data_isolation_directive_2026-10-06.md）

B2 铁律不变：G0(=本线 golden ∪ g0_ext_n80) 是唯一 oracle，软件后端不得引用
RTL 输出。执行语义与母本一致：conv=GEMM 整数合同（Artifacts.forward），
图算子=software（intref 同源原语），heads 6 源 gather。

F2 通过判据（与母本同）：每可比 tensor nerr=0（103/103）；raw heads 与 G0
一致；owner/range/stride 全零；同帧重复 SHA 稳定。
本轮 = frame0×3 重复 + frame0..4 各一遍。

Run: 2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe f2_replay_n80.py
"""
import argparse
import hashlib
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：冻结输入经 accel_paths；模块查找经 accel_bootstrap
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
import accel_paths as _AP                               # noqa: E402
DRY = _AP.DRY
ROM = _AP.ROM                                            # N1
G0 = ROM                                                 # N2
RUN04 = _AP.GEXT                                         # N3
RUN02 = os.path.join(DRY, 'out', 'p2_manifests_n80')     # N4
from intref_yolov8 import int_add, requant_to, maxpool5, \
    upsample_nearest2                              # noqa: E402
from g0_extender_n80 import Artifacts, align_cat   # noqa: E402  单一源复用

LABEL = 'REHEARSAL_ONLY(官方 yolov8n.pt nc=80 演练模型，非物料模型)'


def sha_bytes(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()


class SWBackend:
    """schedule.json 驱动的软件后端（A3 首轮全软件/conv=GEMM 合同）。"""

    def __init__(self):
        self.A = Artifacts()
        s = json.load(open(os.path.join(ROM, 'schedule.json'),
                           encoding='utf-8'))
        self.s = s
        self.tasks, self.bufs = s['tasks'], s['buffers']
        self.bt = json.load(open(os.path.join(RUN02, 'buffer_table.json'),
                                 encoding='utf-8'))['entries']
        self.bsz = {e['id']: e['size'] for e in self.bt}
        self.bshape = {e['id']: tuple(e['shape']) for e in self.bt}

    def run_frame(self, canvas, frame_id):
        """执行一帧；返回 (bufs: id->(tensor4d, scale), 逐任务证据行)。"""
        A = self.A
        store = {}        # buf id -> (4D int8 tensor, scale)
        scale = {}        # buf id -> float
        rows = []
        x0 = (canvas.astype(np.int16) - 128).astype(np.int8)[None] \
            .transpose(0, 3, 1, 2).copy()
        store[0], scale[0] = x0, 1.0 / 255.0
        owner_err = range_err = stride_err = 0

        for i, t in enumerate(self.tasks):
            op = t['op']
            node = t['node']
            if op == 'conv':
                x = store[t['in']]
                y = A.forward(node, x, first=('z_sum_w' in t))
                out, os_ = y, A.node(node)['stored_scale']
            elif op == 'view':
                p = store[t['in']]
                out = p[:, t['ch'][0]:t['ch'][1]]
                os_ = scale[t['in']]
            elif op == 'concat':
                parts = [(store[e['buf']], e['scale'])
                         for e in t['inputs']]
                out = align_cat(parts, t['out_scale'])
                os_ = t['out_scale']
            elif op == 'add':
                out = int_add(store[t['a']], t['a_scale'],
                              store[t['b']], t['b_scale'], t['out_scale'])
                os_ = t['out_scale']
            elif op == 'maxpool5':
                out = maxpool5(store[t['in']])
                os_ = scale[t['in']]
            elif op == 'upsample2':
                out = upsample_nearest2(store[t['in']])
                os_ = scale[t['in']]
            elif op == 'heads':
                # gather 语义：heads 无 out buffer；证据行记 6 源
                srcs = []
                for e in t['cls'] + t['reg']:
                    ten, sc = store[e['buf']], e['scale']
                    srcs.append((e['buf'], ten, sc))
                rows.append({
                    'frame_id': frame_id, 'seq': i, 'task_id': i,
                    'node': node, 'opcode': op, 'backend': 'software',
                    'buffer_id': None, 'sources': [
                        b for b, _, _ in srcs],
                })
                continue
            else:
                raise RuntimeError('op %s' % op)
            bid = t['out']
            # owner/range/stride 检查（写入仅限自身 out buffer）
            if bid in store and t['op'] != 'view':
                owner_err += 1          # 静态布局下重写未回收 buffer
            if out.shape[1:] != self.bshape[bid]:
                stride_err += 1
            if int(out[0].nbytes) != self.bsz[bid]:
                range_err += 1
            store[bid], scale[bid] = out, os_
            rows.append({
                'frame_id': frame_id, 'seq': i, 'task_id': i, 'node': node,
                'opcode': op, 'backend': 'gemm' if op == 'conv'
                else 'software',
                'buffer_id': bid, 'shape': list(out.shape[1:]),
                'stride': self.bshape[bid][2], 'byte_len': int(out[0].nbytes),
                'producer': self.bufs[bid]['producer'],
                'generation': frame_id,
                'out_sha256': sha_bytes(out[0]),
            })
        # heads 源张量随 buf 表一并带出
        return store, scale, rows, \
            {'owner': owner_err, 'range': range_err, 'stride': stride_err}


def compare(be, store, refs, frame_id):
    """逐任务 out 对 G0（golden ∪ ext_n80）。返回逐任务比对行。"""
    rows = []
    for i, t in enumerate(be.tasks):
        if t['op'] == 'heads':
            continue
        bid = t['out']
        got = store[bid][0]
        ref = refs.get(t['node'])
        if ref is None:
            rows.append({'node': t['node'], 'compared': False})
            continue
        neq = np.sum(got != ref)
        first_mm = int(np.argmax(got != ref)) if neq else None
        rows.append({
            'node': t['node'], 'op': t['op'], 'compared': True,
            'nerr': int(neq), 'len': int(got.size),
            'first_mismatch_offset': first_mm,
            'got_sha256': sha_bytes(got), 'ref_sha256': sha_bytes(ref),
            'frame_id': frame_id,
        })
    return rows


def main():
    # M4.2：--out 归位（原写死 HERE=F2 run 目录；门跑输出须落新 run 目录，
    # 冻结 F2RUN 只读）
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=HERE,
                    help='输出目录（默认=脚本目录；M4 门跑须指向新 run 目录）')
    args = ap.parse_args()
    be = SWBackend()
    golden_files = sorted(f for f in os.listdir(os.path.join(G0, 'golden'))
                          if f.endswith('.npz'))
    ext_files = sorted(f for f in os.listdir(RUN04)
                       if f.startswith('g0_ext_') and f.endswith('.npz'))
    frames = []
    for gf, ef in zip(golden_files, ext_files):
        gp = np.load(os.path.join(G0, 'golden', gf))
        ep = np.load(os.path.join(RUN04, ef))
        refs = {}
        for k in gp.files:
            if k.startswith('int8_'):
                refs[k[5:]] = gp[k]
        for k in ep.files:
            if k.startswith('int8_'):
                refs.setdefault(k[5:], ep[k])
        frames.append({'name': gf, 'canvas': gp['canvas_u8'],
                       'raw_heads': {k: gp[k] for k in gp.files
                                     if k.startswith('raw_')},
                       'refs': refs})

    all_rows, sha_hist = [], {}
    verdicts = []
    # frame0 ×3（重复稳定性）+ 全 5 帧各一遍
    plan = [('rep%d' % r, 0) for r in range(3)] + \
           [('f%d' % i, i) for i in range(len(frames))]
    for tag, fi in plan:
        fr = frames[fi]
        store, scale, ev_rows, chk = be.run_frame(fr['canvas'],
                                                  frame_id=fi)
        comp = compare(be, store, fr['refs'], fi)
        nerr_tot = sum(r.get('nerr', 0) for r in comp)
        ncmp = sum(1 for r in comp if r.get('compared'))
        # heads：6 源 == raw_reg/raw_cls（stride 映射；cls 面 80）
        strides = {40: 8, 20: 16, 10: 32}
        ht = [t for t in be.tasks if t['op'] == 'heads'][0]
        head_ok = True
        head_detail = []
        for e in ht['reg']:
            raw = fr['raw_heads']['raw_reg_s%d' % strides[e['shape'][1]]]
            ne = int(np.sum(store[e['buf']][0] != raw))
            head_ok &= (ne == 0)
            head_detail.append({'src': be.bufs[e['buf']]['producer'],
                                'nerr': ne})
        for e in ht['cls']:
            raw = fr['raw_heads']['raw_cls_s%d' % strides[e['shape'][1]]]
            ne = int(np.sum(store[e['buf']][0] != raw))
            head_ok &= (ne == 0)
            head_detail.append({'src': be.bufs[e['buf']]['producer'],
                                'nerr': ne})
        # SHA 稳定：同帧重复 -> 每 buffer SHA 一致
        for bid, ten in store.items():
            key = (fi, bid)
            h = sha_bytes(ten[0])
            if key in sha_hist and sha_hist[key] != h:
                head_ok = False
                head_detail.append({'sha_unstable_buf': bid})
            sha_hist[key] = h
        ok = (nerr_tot == 0 and ncmp == 103 and head_ok
              and chk['owner'] == 0 and chk['range'] == 0
              and chk['stride'] == 0)
        verdicts.append(ok)
        print('%-5s frame%d nerr=%d compared=%d/103 heads=%s '
              'owner/range/stride=%d/%d/%d -> %s'
              % (tag, fi, nerr_tot, ncmp, 'OK' if head_ok else 'FAIL',
                 chk['owner'], chk['range'], chk['stride'],
                 'PASS' if ok else 'FAIL'))
        all_rows.append({'tag': tag, 'frame': fi, 'compared': ncmp,
                         'nerr_total': nerr_tot, 'checks': chk,
                         'heads': head_detail, 'rows': comp,
                         'exec_rows': ev_rows, 'pass': ok})

    verdict = 'PASS' if all(verdicts) else 'FAIL'
    out = {'run': 'P2 N80 rehearsal software whole-graph replay',
           'label': LABEL, 'gesture_data_loaded': False,
           'n_frames_touched': len(frames), 'attempts': all_rows,
           'verdict': verdict}
    json.dump(out, open(os.path.join(args.out, 'f2_replay_report.json'), 'w',
               encoding='utf-8'), indent=1, ensure_ascii=False)
    print('F2_REPLAY_N80 %s (%s)' % (verdict, LABEL))
    return 0 if verdict == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
