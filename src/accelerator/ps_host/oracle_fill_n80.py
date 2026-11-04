#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""oracle_fill_n80.py -- 用 g0_ext+F2 结果回填 oracle_manifest 期望侧（纯派生）.

输入（全部本线物体资产，零手势数据）：
  - dryrun_run01/out/p2_manifests_n80/oracle_manifest.json（104 行三列 null）
  - g0ext run01 g0_ext_*.npz（51 悬空行的张量侧，G0_EXTENDER_N80 PASS）
  - 本 run f2_replay_report.json（103/103 nerr=0，ref_sha256=期望侧 sha）
输出：本 run oracle_manifest_filled.json ——
  g0_present: golden npz ∪ g0_ext npz 键存在性（F2 已核对可比性）
  out_sha256: 期望侧 = F2 帧参考张量 sha（== 软件 replay sha，nerr=0 互证）
  first_mismatch_offset: 期望侧自比对 nerr=0 → null（实际侧 M3 板跑填）
  heads 行：如实留 g0_present=false + pending_heads_blob（⑥ 复合 blob 缺口，
  见 M2_GAP_AUDIT §1⑥——组装导出属物料轮/M3 前置，不在此伪造）
不改 dry-run 目录任何文件（graph_manifest 钉的是原 oracle_manifest）。
"""
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：冻结输入经 accel_paths（f2 报告=冻结 F2RUN 产物，只读）。
# 本件为期望侧回填工具：重跑输出落本目录（HERE，非冻结区），门链不复用。
import sys as _sys                                    # noqa: E402
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in _sys.path:
    _sys.path.insert(0, _ROOT)
import accel_paths as _AP                             # noqa: E402
DRY = _AP.DRY
OM = os.path.join(DRY, 'out', 'p2_manifests_n80', 'oracle_manifest.json')
GEXT = _AP.GEXT
F2R = os.path.join(_AP.F2RUN, 'f2_replay_report.json')

LABEL = 'REHEARSAL_ONLY(官方 yolov8n.pt nc=80 演练模型，非物料模型)'


def main():
    om = json.load(open(OM, encoding='utf-8'))
    f2 = json.load(open(F2R, encoding='utf-8'))
    assert f2['verdict'] == 'PASS', 'F2 replay 未过，禁止回填'

    # 键存在性：golden(帧0) ∪ g0_ext(帧0)
    gp = np.load(os.path.join(DRY, 'out', 'quant_n80', 'golden',
                              sorted(f for f in os.listdir(os.path.join(
                                  DRY, 'out', 'quant_n80', 'golden'))
                              if f.endswith('.npz'))[0]))
    ep = np.load(os.path.join(
        GEXT, sorted(f for f in os.listdir(GEXT)
                     if f.startswith('g0_ext_') and f.endswith('.npz'))[0]))
    keys = set(gp.files) | set(ep.files)

    # 期望侧 sha：钉正典帧 frame0（激活逐帧不同，sha 必然逐帧变——
    # 母本同律以 frame0 为对拍帧；其余帧 sha 留在 f2_replay_report 供 M3 多帧）
    sha = {}
    for r in next(a for a in f2['attempts'] if a['tag'] == 'f0')['rows']:
        if r.get('compared') and r.get('nerr', 1) == 0:
            sha[r['node']] = r['ref_sha256']

    n_present = n_sha = 0
    for row in om['rows']:
        if row['g0_key'] in keys:
            row['g0_present'] = True
            n_present += 1
        else:
            row['g0_present'] = False
            row['pending'] = 'heads 复合 blob 期望侧（M2_GAP_AUDIT ①⑥）'
        if row['node'] in sha:
            row['out_sha256'] = sha[row['node']]          # 期望侧
            row['first_mismatch_offset'] = None           # 期望 vs 期望 = 零差
            n_sha += 1

    out = {'source': 'oracle_fill_n80（g0_ext_n80 + f2_replay_n80 期望侧回填）',
           'label': LABEL, 'expected_side': True, 'gesture_data_loaded': False,
           'base_oracle_manifest': OM,
           'rows': om['rows'],
           'stats': {'rows': len(om['rows']), 'g0_present_true': n_present,
                     'expected_sha_filled': n_sha,
                     'heads_blob_pending': len(om['rows']) - n_sha}}
    dst = os.path.join(HERE, 'oracle_manifest_filled.json')
    json.dump(out, open(dst, 'w', encoding='utf-8'), indent=1,
              ensure_ascii=False)
    print('rows=%d g0_present_true=%d sha_filled=%d pending=%d -> %s'
          % (len(om['rows']), n_present, n_sha,
             len(om['rows']) - n_sha, dst))
    ok = (n_present == 103 and n_sha == 103)
    print('ORACLE_FILL_N80 %s' % ('PASS' if ok else 'CHECK'))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
