#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""graph_exec_n80.py — 物体线 M3 前置：arena 图执行器 N80 拷出（第 5+7 项）

母本 = 3_host/yolo_p2/graph_exec.py（P2.2/B3-S1 run01 手势线正典，只读；
执行语义逐行等价）。N80 拷出差异（M2_GAP_AUDIT §3 第 5/7 项）：
  N1 heads 布局：ppu_desc_bundle（cls nc=7/149100）→ ppu_desc_bundle_n80
     （cls nc=80/302400；reg 段与段序 ABI 不变）；
  N2 帧源：ppu_replay.load_frames（手势 golden）→ n80_frames.load_frames
     （quant_n80 golden + g0_ext_n80，SHA 台账纪律保留 + blob 账交叉锁）；
  N3 Artifacts：g0_extender（手势）→ g0_extender_n80（本线单一源）；
  N4 intref 导入源：手势 3_host → dryrun_run01/scripts（字节一致实现遗产）；
  N5 manifests = v1.1 view 别名重生成版
     （2026-10-06_yolo_m3_manifests_v11_run01/out/p2_manifests_n80_v11，
     gm=74958a41…；16 view out 父内别名 16/16，supersedes b1regen v1.0
     布局版 gm=9d915ce1…；cv3.x.1 k_chain=[720] 逐字节承袭）。

目的与增量（与母本同文）：Conv 走 GEMM 通路、图算子走软件后端的板上
驱动原型。本轮把执行面从 F2 的张量 store 推进到 buffer_table DDR 地址
空间——每个任务的输入/输出都是 arena 内 base_off 切片，图算子软件内核
按地址读写，conv 经递交接口（主机 stub = GEMM 整数合同
Artifacts.forward；板上实现 = DMA 装载+job 递交）。这是 M3 板级驱动
（graph_exec 板版=mmap arena + conv 真递交）的直接骨架。

  1. arena 地址级执行：读=arena[base:base+size] 视图，写=落 arena；
  2. guard 完整性：arena 全量播种 0xA5，帧末断言非图区字节保持 0xA5
     （地址级越界写检测）；
  3. conv 递交接口化 submit_conv()（backend 证据行 gemm-sw-stub）；
  4. view 零搬运地址级验证：别名几何断言 + 帧内 arena 写区不含 view
     独立写（零字节搬运）；
  5. B2 完整取证行（frame_id/seq/node/op/backend/base_off/generation/
     shape/byte_len/out_sha256/nerr/first_mismatch_offset）。

门判据（与母本同律，G2 字节数随 n80）：
  G1 每帧 103/103 可比张量 nerr=0（5 帧）；
  G2 heads blob 302400B SHA==G0（5/5）；
  G3 view 16 项别名几何全对且零搬运；
  G4 guard 完整：每帧末非图区全 0xA5；
  G5 重复帧（frame0 rep）逐 buf SHA 稳定；
  G6 conv 63 项 descriptor.k_chain == k_block_manifest.chain；
  G7 generation 回退/读新鲜度/owner 提前释放计数器全零。

Run: 2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe
     graph_exec_n80.py --manifests <v11regen>/out/p2_manifests_n80_v11 --out <run>/out
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：冻结输入路径经 accel_paths；模块查找经 accel_bootstrap
# （替代原 run 目录 sys.path 三连插）
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
import accel_paths as _AP

DRY = _AP.DRY
RUN04 = _AP.GEXT

from n80_frames import load_frames                        # noqa: E402  N2
from ppu_desc_bundle import (                             # noqa: E402  N1（abi\ 正典）
    HEADS_LAYOUT, HEADS_SEG_ORDER, HEADS_TOTAL_BYTES, req_pair,
)
from intref_yolov8 import (                              # noqa: E402  N4
    rne_shift, sat_i8, sat_i32, maxpool5, upsample_nearest2,
)
from g0_extender_n80 import Artifacts                    # noqa: E402  N3

POISON = 0xA5
# heads 段 stride(W) → 段名（§8 布局；JSON cls/reg 段 shape=[C,H,W]）
STRIDE2SEG = {'reg': {40: 'reg8', 20: 'reg16', 10: 'reg32'},
              'cls': {40: 'cls8', 20: 'cls16', 10: 'cls32'}}


def sha_b(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha_t(a: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()


class GraphExecError(Exception):
    """执行期违例（fail-closed，携首错定位）。"""


class ArenaEngine:
    """buffer_table 地址空间上的 104 task 顺序执行引擎（软件后端）。"""

    def __init__(self, manifests_dir: str):
        j = lambda n: json.load(           # noqa: E731
            open(os.path.join(manifests_dir, n), encoding='utf-8'))
        self.graph = j('graph_manifest.json')
        self.bt = j('buffer_table.json')
        self.dt = j('descriptor_table.json')
        self.kbm = j('k_block_manifest.json')
        self.backend = j('backend_map.json')['map']
        # SHA 绑定：六 sub manifest 对 graph_manifest 台账逐份核验
        for name, want in self.graph['sub_manifest_sha256'].items():
            got = sha_b(open(os.path.join(manifests_dir, name), 'rb').read())
            if got != want:
                raise GraphExecError('manifest SHA 失绑 %s' % name)
        self.bufs = {e['id']: e for e in self.bt['entries']}
        self.descs = self.dt['entries']
        self.kc = {int(k): v for k, v in self.kbm['convs'].items()}
        self.arena = np.full(self.bt['arena_total'], POISON, np.uint8)
        # 可写域 = ∪图 buf 数据区（view 别名项与父同区，集合天然去重）
        self.span_of = {b: (e['base_off'], e['size']) for b, e in
                        self.bufs.items()}
        self.wr_frames = {}       # (base,size) -> 最后一写 frame_id
        self.gen = {}             # bid -> 当前世代（写时=frame_id）
        self.max_gen = {}         # bid -> 历史最大世代（回退检测）
        self.last_wf = {}         # bid -> 最后写 frame（新鲜度检测）
        self.alias = {}           # view out bid -> parent bid
        self.write_log = []       # (frame, bid, base, nbytes)
        self.premature_free = 0
        self.A = Artifacts()

    # -- 地址空间原语 ------------------------------------------------------
    def _t(self, bid: int) -> np.ndarray:
        e = self.bufs[bid]
        c, h, w = e['shape']
        return self.arena[e['base_off']:e['base_off'] + e['size']] \
            .reshape(c, h, w).view(np.int8)[None]

    def read(self, bid: int, frame_id: int, di: int) -> np.ndarray:
        # 新鲜度：读到的必须是本帧产物（D-F2e cache 交接遗漏检测；
        # 外部输入 buf0 与 view 别名沿父除外）
        src = self.alias.get(bid, bid)
        if self.last_wf.get(src, -1) not in (frame_id, -1):
            raise GraphExecError(
                '读非本帧产物 desc%d buf%d (last_wf=%s frame=%d)'
                % (di, bid, self.last_wf.get(src), frame_id))
        return self._t(bid)

    def write(self, bid: int, ten: np.ndarray, frame_id: int, di: int):
        e = self.bufs[bid]
        c, h, w = e['shape']
        if tuple(ten.shape[1:]) != (c, h, w) or int(ten[0].nbytes) != e['size']:
            raise GraphExecError(
                '写形状/长度违例 desc%d buf%d %s vs %s'
                % (di, bid, ten.shape[1:], (c, h, w)))
        if frame_id <= self.max_gen.get(bid, -1):
            raise GraphExecError('generation 回退 desc%d buf%d' % (di, bid))
        self.gen[bid] = frame_id
        self.max_gen[bid] = frame_id
        self.last_wf[bid] = frame_id
        self.arena[e['base_off']:e['base_off'] + e['size']] = \
            np.ascontiguousarray(ten[0]).view(np.uint8).ravel()
        self.write_log.append((frame_id, bid, e['base_off'], e['size']))

    # -- conv 递交接口（B3-S1 板上换 DMA 装载+job 递交；run02 换载荷对拍）--
    def submit_conv(self, node: str, x: np.ndarray, first: bool) -> np.ndarray:
        return self.A.forward(node, x, first=first)

    # -- 帧执行 ------------------------------------------------------------
    def run_frame(self, canvas: np.ndarray, frame_id: int):
        rows, heads_blob, heads_src = [], None, []
        x0 = (canvas.astype(np.int16) - 128).astype(np.int8)[None] \
            .transpose(0, 3, 1, 2).copy()
        self.write(0, x0, frame_id, -1)           # 外部输入（producer=input）
        view_writes = 0
        for d in self.descs:
            di, op, node = d['sched_index'], d['op'], d['node']
            bk = 'gemm-sw-stub' if op == 'conv' else 'software'
            if op == 'conv':
                kb = self.kc[di]
                if d['k_chain'] != kb['chain'] or d['n_blocks'] != \
                        len(kb['blocks']):
                    raise GraphExecError('k_chain 失绑 desc%d' % di)
                x = self.read(d['in_bufs'][0], frame_id, di)
                y = self.submit_conv(node, x, first=bool(kb['z_sum_w']))
                self.write(d['out_buf'], y, frame_id, di)
            elif op == 'view':
                par, vb = self.bufs[d['parent_buf']], self.bufs[d['out_buf']]
                c0, c1 = d['ch']
                _, h, w = par['shape']
                # 别名几何（A1.1：base=parent+c0·H·W；不新增 DDR）
                if vb['base_off'] != par['base_off'] + c0 * h * w or \
                        vb['shape'] != [c1 - c0, h, w] or \
                        vb['size'] != (c1 - c0) * h * w:
                    raise GraphExecError('view 别名几何违例 desc%d' % di)
                base0 = self.arena[vb['base_off']:vb['base_off'] +
                                   vb['size']].tobytes()
                # 零搬运：不写 arena；沿父新鲜度（别名即父切片）
                self.alias[d['out_buf']] = d['parent_buf']
                self.last_wf[d['out_buf']] = self.last_wf.get(
                    d['parent_buf'], -2)
                self.gen[d['out_buf']] = self.gen.get(d['parent_buf'])
                self.max_gen[d['out_buf']] = self.max_gen.get(
                    d['parent_buf'], -1)
                after = self.arena[vb['base_off']:vb['base_off'] +
                                   vb['size']].tobytes()
                view_writes += (base0 != after)
            elif op == 'add':
                a = self.read(d['a_buf'], frame_id, di)
                b = self.read(d['b_buf'], frame_id, di)
                qa = self.qpair(d['a_scale'], d['out_scale'])
                qb = self.qpair(d['b_scale'], d['out_scale'])
                A_ = rne_shift(a.astype(np.int64) * qa[0], qa[1])
                B_ = rne_shift(b.astype(np.int64) * qb[0], qb[1])
                y = sat_i8(sat_i32(A_ + B_))       # intref 同式
                self.write(d['out_buf'], y, frame_id, di)
            elif op == 'concat':
                parts = []
                for s in d['inputs']:
                    p = self.read(s['buf'], frame_id, di)
                    q = self.qpair(s['scale'], d['out_scale'])  # 恒等段自然恒等对
                    p = sat_i8(rne_shift(
                        p.astype(np.int64) * q[0], q[1]))
                    parts.append(p)
                y = np.concatenate(parts, axis=1)
                self.write(d['out_buf'], y, frame_id, di)
            elif op == 'maxpool5':
                y = maxpool5(self.read(d['in_bufs'][0], frame_id, di))
                self.write(d['out_buf'], y, frame_id, di)
            elif op == 'upsample2':
                y = upsample_nearest2(self.read(d['in_bufs'][0], frame_id, di))
                self.write(d['out_buf'], y, frame_id, di)
            elif op == 'heads':
                blob_parts = []
                for grp in ('reg', 'cls'):
                    for e in d[grp]:
                        seg = STRIDE2SEG[grp][e['shape'][2]]
                        ten = self.read(e['buf'], frame_id, di)
                        want = HEADS_LAYOUT[seg][0]
                        if tuple(ten.shape[1:]) != want:
                            raise GraphExecError(
                                'heads 段 %s 形状违例 desc%d' % (seg, di))
                        blob_parts.append((seg, np.ascontiguousarray(ten[0])))
                        heads_src.append((seg, e['buf']))
                blob_parts.sort(key=lambda x: HEADS_SEG_ORDER.index(x[0]))
                heads_blob = b''.join(a.tobytes() for _, a in blob_parts)
                if len(heads_blob) != HEADS_TOTAL_BYTES:
                    raise GraphExecError('heads blob != 302400')
                rows.append({'seq': di, 'node': node, 'op': op,
                             'backend': bk, 'buffer_id': None,
                             'sources': [b for _, b in heads_src],
                             'blob_sha256': sha_b(heads_blob)})
                continue
            else:
                raise GraphExecError('未知 op %s desc%d' % (op, di))
            bid = d['out_buf']
            rows.append({
                'seq': di, 'node': node, 'op': op, 'backend': bk,
                'buffer_id': bid, 'base_off': self.bufs[bid]['base_off'],
                'generation': self.gen.get(bid),
                'shape': self.bufs[bid]['shape'],
                'byte_len': self.bufs[bid]['size'],
                'out_sha256': sha_t(self._t(bid)[0]),
            })
        return rows, heads_blob, view_writes

    def qpair(self, scale_in: float, scale_out: float):
        """requant 对 (M,shift)=req_pair(in/out)——§2.1 公共原语，
        与 ppu_desc_bundle.QuantTable.id_of 同源（31 唯一对/50 引用律）。"""
        return req_pair(scale_in / scale_out)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifests', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    eng = ArenaEngine(args.manifests)
    frames = load_frames()

    report = {'run': 'M3-pre n80 graph_exec_n80 (arena address-space)',
              'manifests': {n: v for n, v in
                            eng.graph['sub_manifest_sha256'].items()},
              'arena_total': eng.bt['arena_total'],
              'attempts': [], 'checks': []}
    sha_hist = {}
    verdicts = []

    def guard_intact(frame_id):
        writable = np.zeros(eng.bt['arena_total'], bool)
        for base, size in eng.span_of.values():
            writable[base:base + size] = True
        bad = int(np.count_nonzero(eng.arena[~writable] != POISON))
        return bad

    # frame0 rep + 5 帧各一遍。frame_id=执行序号（单调递增，A1.2/B4 律：
    # 禁止把源帧序当 frame_id——rep 模式输入相同但每次执行是新世代）；
    # 源帧 fi 仅决定输入 canvas 与对拍 refs，SHA 稳定性按源帧分桶。
    plan = [('rep', 0, 0)] + [('f%d' % i, 1 + i, i)
                              for i in range(len(frames))]
    for tag, exec_id, fi in plan:
        fr = frames[fi]
        rows, blob, vw = eng.run_frame(fr['canvas'], exec_id)
        # 逐任务对拍 G0
        comp, nerr_tot = [], 0
        for r in rows:
            if r['op'] == 'heads':
                continue
            bid = r['buffer_id']
            got = eng._t(bid)[0]
            ref = fr['refs'].get(r['node'])
            if ref is None:
                comp.append({'node': r['node'], 'compared': False})
                continue
            neq = int(np.sum(got != ref))
            nerr_tot += neq
            comp.append({'node': r['node'], 'op': r['op'], 'compared': True,
                         'nerr': neq, 'len': int(got.size),
                         'first_mismatch_offset':
                             int(np.argmax(got != ref)) if neq else None})
        heads_ok = sha_b(blob) == fr['g0_head_blob_sha']
        # 重复稳定性：同帧逐 buf SHA
        unstable = []
        for bid in eng.bufs:
            h = sha_t(eng._t(bid)[0])
            k = (fi, bid)
            if k in sha_hist and sha_hist[k] != h:
                unstable.append(bid)
            sha_hist[k] = h
        bad_guard = guard_intact(fi)
        gen_back = sum(1 for b, g in eng.gen.items()
                       if g is not None and g > eng.max_gen.get(b, -1))
        ok = (nerr_tot == 0 and sum(1 for c in comp if c.get('compared'))
              == 103 and heads_ok and vw == 0 and bad_guard == 0
              and not unstable and gen_back == 0
              and eng.premature_free == 0)
        verdicts.append(ok)
        print('%-4s frame%d nerr=%d compared=%d/103 heads=%s view_wr=%d '
              'guard_bad=%d sha_unstable=%d gen_back=%d -> %s'
              % (tag, fi, nerr_tot, sum(1 for c in comp if c.get('compared')),
                 'OK' if heads_ok else 'FAIL', vw, bad_guard,
                 len(unstable), gen_back, 'PASS' if ok else 'FAIL'))
        report['attempts'].append({
            'tag': tag, 'frame': fi, 'nerr_total': nerr_tot,
            'compared': sum(1 for c in comp if c.get('compared')),
            'heads_blob_ok': heads_ok, 'view_writes': vw,
            'guard_violations': bad_guard, 'sha_unstable': unstable,
            'exec_rows': rows, 'compare_rows': comp, 'pass': ok})

    verdict = 'PASS' if all(verdicts) else 'FAIL'
    report['verdict'] = verdict
    g_checks = [
        ('G1 5帧 103/103 nerr=0',
         all(a['nerr_total'] == 0 and a['compared'] == 103
             for a in report['attempts'])),
        ('G2 heads blob SHA==G0 5/5',
         all(a['heads_blob_ok'] for a in report['attempts'])),
        ('G3 view 零搬运', all(a['view_writes'] == 0
                               for a in report['attempts'])),
        ('G4 guard 完整',
         all(a['guard_violations'] == 0 for a in report['attempts'])),
        ('G5 重复帧 SHA 稳定',
         all(not a['sha_unstable'] for a in report['attempts'])),
        ('G6 k_chain 自洽（执行期断言）', verdict != 'FAIL'),
        ('G7 generation/owner 计数器零',
         all(a.get('gen_back', 0) == 0 for a in report['attempts'])),
    ]
    for name, okk in g_checks:
        report['checks'].append({'check': name, 'pass': bool(okk)})
        print('  %s %s' % ('PASS' if okk else 'FAIL', name))
    json.dump(report, open(os.path.join(args.out, 'graph_exec_report.json'),
              'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    print('GRAPH_EXEC_N80 %s' % verdict)
    return 0 if verdict == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
