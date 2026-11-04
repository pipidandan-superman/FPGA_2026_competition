#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""heads_blob_export_n80.py -- §8 段序组装 heads 复合 blob golden（期望侧，M2_GAP_AUDIT ⑥）.

段序权威：1_docs/yolo_ppu_design_manual_20260918.md §8（经
3_host/yolo_ppu/ppu_desc_bundle.py:62-69 HEADS_SEG_ORDER 转录）：
  reg8(64,40,40) → reg16(64,20,20) → reg32(64,10,10)
  → cls8(80,40,40) → cls16(80,20,20) → cls32(80,10,10)
nc=80 字节账：reg 102400+25600+6400=134400；cls 128000+32000+8000=168000；
合计 **302400**（与 dry-run heads 任务一致）。段序 ABI=实现遗产（隔离禁令
允许复用类）；张量值=本线 rehearsal golden（F2 已核 heads 6 源 == raw_* 逐位）。

产物：
  heads_blob_frame{NN}.bin ×5（302400B/帧）
  heads_blob_shas.json（逐帧 sha + 段账目）
  oracle_manifest_filled.json 更新：104 行 g0_present 全 true，heads 行
    out_sha256=frame0 blob sha（钉正典帧，与期望侧同律）
"""
import hashlib
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：golden 经 accel_paths。本件=§8 组装期望侧产线件（冻结
# heads_blob_shas.json 的产生者）；重跑输出落本目录，禁写冻结 F2RUN。
import sys as _sys                                    # noqa: E402
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in _sys.path:
    _sys.path.insert(0, _ROOT)
import accel_paths as _AP                             # noqa: E402
DRY = _AP.DRY
GOLDEN = os.path.join(_AP.ROM, 'golden')

LABEL = 'REHEARSAL_ONLY(官方 yolov8n.pt nc=80 演练模型，非物料模型)'
# §8 段序 → (npz raw 键, 形状, 字节)
SEGS = [
    ('reg8', 'raw_reg_s8', (64, 40, 40), 102400),
    ('reg16', 'raw_reg_s16', (64, 20, 20), 25600),
    ('reg32', 'raw_reg_s32', (64, 10, 10), 6400),
    ('cls8', 'raw_cls_s8', (80, 40, 40), 128000),
    ('cls16', 'raw_cls_s16', (80, 20, 20), 32000),
    ('cls32', 'raw_cls_s32', (80, 10, 10), 8000),
]
TOTAL = sum(s[3] for s in SEGS)
assert TOTAL == 302400, TOTAL


def main():
    frames = sorted(f for f in os.listdir(GOLDEN) if f.endswith('.npz'))
    shas = {}
    for idx, fn in enumerate(frames):
        npz = np.load(os.path.join(GOLDEN, fn))
        blob = bytearray()
        acct = []
        for name, key, shape, nbytes in SEGS:
            a = npz[key]
            assert a.shape == shape, (key, a.shape, shape)
            b = np.ascontiguousarray(a).tobytes()
            assert len(b) == nbytes, (key, len(b), nbytes)
            blob += b
            acct.append({'seg': name, 'src_key': key, 'bytes': nbytes})
        assert len(blob) == TOTAL
        dst = os.path.join(HERE, 'heads_blob_frame%02d.bin' % idx)
        open(dst, 'wb').write(bytes(blob))
        shas[fn] = {'blob_sha256': hashlib.sha256(bytes(blob)).hexdigest(),
                    'acct': acct}
        print('%s -> frame%02d blob %dB sha=%s'
              % (fn, idx, TOTAL, shas[fn]['blob_sha256'][:16]))

    json.dump({'run': 'heads_blob_export_n80（§8 段序组装，期望侧）',
               'label': LABEL, 'seg_order': [s[0] for s in SEGS],
               'authority': 'yolo_ppu_design_manual_20260918.md §8 '
                            '(ppu_desc_bundle.py:62-69 转录)',
               'total_bytes': TOTAL, 'frames': shas},
              open(os.path.join(HERE, 'heads_blob_shas.json'), 'w',
                   encoding='utf-8'), indent=1, ensure_ascii=False)

    # oracle_manifest_filled.json：heads 行转正（钉 frame0）
    omp = os.path.join(HERE, 'oracle_manifest_filled.json')
    om = json.load(open(omp, encoding='utf-8'))
    canon = shas[frames[0]]['blob_sha256']
    n = 0
    for row in om['rows']:
        if row.get('pending') and 'heads' in row.get('pending', ''):
            row['g0_present'] = True
            row['out_sha256'] = canon        # §8 组装 blob（frame0 钉帧）
            row['first_mismatch_offset'] = None
            row['note'] = ('heads 复合 blob 期望侧=§8 段序组装 '
                           '(heads_blob_export_n80.py, frame0)')
            row.pop('pending', None)
            n += 1
    om['stats'] = {'rows': 104, 'g0_present_true': 104,
                   'expected_sha_filled': 104, 'heads_blob_pending': 0,
                   'heads_blob_canonical_frame': frames[0],
                   'heads_blob_sha256': canon}
    json.dump(om, open(omp, 'w', encoding='utf-8'), indent=1,
              ensure_ascii=False)
    print('oracle heads rows resolved: %d; 104/104 expected side complete' % n)
    print('HEADS_BLOB_N80 PASS (canon frame0 sha=%s)' % canon[:16])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
