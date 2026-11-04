#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""n80_frames.py -- M3 前置：ppu_replay.load_frames 的 N80 移植（第 7 项支撑）.

母本 = 3_host/yolo_ppu/ppu_replay.py::load_frames（手势线正典，只读；
D-F2f 恢复件 SHA 台账纪律原样保留）。N80 差异：
  N1 golden 源：手势 RUN00/golden（恢复件）→ dryrun_run01/out/quant_n80/
     golden（原件），台账=quant_n80/golden_index.json（G2 实算写入）；
  N2 g0_ext 源：手势 run04 → 2026-10-06_yolo_p2_g0ext_n80_run01
     （g0_ext_report.json ext_sha256 逐文件核验）；
  N3 heads blob SHA 账交叉锁（n80 新增）：golden raws §8 段序组装 sha
     必须等于 f2replay run heads_blob_shas.json 台账（独立产线互锁，
     双侧独立实现——本模块按 HEADS_SEG_ORDER 组装，彼侧 export 脚本
     按 SEGS 表组装）；
  N4 帧合同不变：5 帧 fail-closed；refs/g0_head_blob_sha/lineage 键同母本。
"""
import hashlib
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：冻结输入路径经 accel_paths 正典（替代绝对路径）
import sys as _sys                                    # noqa: E402
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in _sys.path:
    _sys.path.insert(0, _ROOT)
import accel_paths as _AP                             # noqa: E402
DRY = _AP.DRY
G0 = os.path.join(DRY, 'out', 'quant_n80')            # N1
RUN04 = _AP.GEXT
F2RUN = _AP.F2RUN

HEADS_SEG_ORDER = ('reg8', 'reg16', 'reg32', 'cls8', 'cls16', 'cls32')
HEADS_RAWKEY = {'reg8': 'raw_reg_s8', 'reg16': 'raw_reg_s16',
                'reg32': 'raw_reg_s32', 'cls8': 'raw_cls_s8',
                'cls16': 'raw_cls_s16', 'cls32': 'raw_cls_s32'}


class FrameError(Exception):
    """帧装载违例（fail-closed）。"""


def load_frames():
    """5 帧输入：canvas + golden/g0_ext 参考张量 + raw heads + head blob SHA.

    golden 逐文件对 golden_index.json 台账核验；g0_ext 逐文件对
    g0_ext_report.json ext_sha256 核验；heads blob sha 对
    heads_blob_shas.json 台账核验（N3 交叉锁）。任一不符 = fail-closed。
    """
    idx = json.load(open(os.path.join(G0, 'golden_index.json'),
                         encoding='utf-8'))
    ext_rep = json.load(open(os.path.join(RUN04, 'g0_ext_report.json'),
                             encoding='utf-8'))
    blob_rep = json.load(open(os.path.join(F2RUN, 'heads_blob_shas.json'),
                              encoding='utf-8'))
    ext_by_name = {fr['frame']: fr for fr in ext_rep['frames']}
    blob_by_name = blob_rep['frames']
    frames = []
    for ent in idx:                              # 台账序（非目录序）
        gf = ent['file'].split('/', 1)[1]        # golden/golden_XX_….npz
        gp_path = os.path.join(G0, 'golden', gf)
        got = hashlib.sha256(open(gp_path, 'rb').read()).hexdigest()
        if got != ent['sha256']:
            raise FrameError('golden SHA mismatch %s: %s != %s'
                             % (gf, got, ent['sha256']))
        efr = ext_by_name.get(gf)
        if efr is None:
            raise FrameError('g0_ext binding missing for %s' % gf)
        ef = gf.replace('golden_', 'g0_ext_', 1)
        ep_path = os.path.join(RUN04, ef)
        egot = hashlib.sha256(open(ep_path, 'rb').read()).hexdigest()
        if egot != efr['ext_sha256']:
            raise FrameError('g0_ext SHA mismatch %s: %s != %s'
                             % (ef, egot, efr['ext_sha256']))
        gp = np.load(gp_path)
        ep = np.load(ep_path)
        refs = {k[5:]: gp[k] for k in gp.files if k.startswith('int8_')}
        for k in ep.files:
            if k.startswith('int8_'):
                refs.setdefault(k[5:], ep[k])
        raws = {HEADS_RAWKEY[k]: gp[HEADS_RAWKEY[k]]
                for k in HEADS_SEG_ORDER}
        blob = b''.join(np.ascontiguousarray(raws[HEADS_RAWKEY[k]]).tobytes()
                        for k in HEADS_SEG_ORDER)
        blob_sha = hashlib.sha256(blob).hexdigest()
        bfr = blob_by_name.get(gf)               # N3 交叉锁
        if bfr is None or bfr['blob_sha256'] != blob_sha:
            raise FrameError('heads blob SHA cross-lock mismatch %s'
                             % gf)
        frames.append({'name': gf, 'canvas': gp['canvas_u8'], 'refs': refs,
                       'raws': raws, 'g0_head_blob_sha': blob_sha,
                       'lineage': {'g0_sha256': ent['sha256'],
                                   'golden_sha256': got,
                                   'ext_sha256': efr['ext_sha256']}})
    if len(frames) != 5:
        raise FrameError('frame library %d != 5' % len(frames))
    return frames


if __name__ == '__main__':
    frs = load_frames()
    for i, fr in enumerate(frs):
        print('frame%d %s refs=%d blob=%s'
              % (i, fr['name'], len(fr['refs']),
                 fr['g0_head_blob_sha'][:16]))
    print('N80_FRAMES OK (5/5, ledger-verified)')
