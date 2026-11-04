#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_anchors_n80.py -- M3 前置第 6 项：三面字节锚 n80 重定基生成器.

律（M2_GAP_AUDIT §3 第 6 项裁定）：**保留律、重定值**——锚的布局法
（正典镜像 LUT@0 / loads@0x100 / y 槽 128B 步距 / 尾 0x1000）与掩蔽
lane 律（K576='fetch'，其余 'fill'）逐字继承手势三锚板证正典；锚字节
= 本线权重（官方 yolov8n.pt 量化包）重新生成。手势锚的**板证地位不可
继承**——n80 锚=布局合同回归基线，板证随 M3 阶梯重钉。

生成方式：复用 conv_packer_n80 引擎本身（单一法源），frame0 单次执行
采集三锚 conv 全量 tile（与母本 P5 同采集路径：_anchor_armed=True），
按 build_anchor_mirror 组装，长度=memory_account.mirror_per_conv 的
manifest 台账值（与 graph_manifest 链一致），落 anchors/*.bin +
anchors_meta.json（sha/几何/出处）。

Run: 2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe
     gen_anchors_n80.py --manifests <v11regen>/out/p2_manifests_n80_v11
"""
import argparse
import json
import os

import numpy as np

# M4.2 归位：conv_packer_n80 查找经 accel_bootstrap；锚基址经 accel_paths。
# 注意：本件为锚生成器（冻结输入的产线件）——M4 v1 锚=只读冻结输入，
# 重跑会把再生成物写进 m3_pre run 冻结目录，禁止；须再生成时另开
# run 目录并显式改输出基址。
import sys as _sys
_ROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..'))   # 12_yolo_accel
if _ROOT not in _sys.path:
    _sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
import accel_paths as _AP                               # noqa: E402
import conv_packer_n80 as cp                      # noqa: E402  单一法源

ANCHOR_DIR = _AP.ANCHOR_DIR


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifests', required=True)
    args = ap.parse_args()

    ma = json.load(open(os.path.join(args.manifests,
                                     'memory_account.json'),
                        encoding='utf-8'))
    gm = json.load(open(os.path.join(args.manifests,
                                     'graph_manifest.json'),
                        encoding='utf-8'))
    want_bytes = {n: v['mirror_bytes'] for n, v in
                  ma['mirror_per_conv'].items()}

    eng = cp.PackCheckEngine(args.manifests)
    frames = cp.load_frames()
    eng._anchor_armed = True                  # 母本 P5 同采集路径
    rows, blob, vw = eng.run_frame(frames[0]['canvas'], 0)
    assert vw == 0

    meta = {'run': 'gen_anchors_n80（三锚重定基：保留律、重定值）',
            'weights_sha256': gm['src_sha']['weights.bin'],
            'source': '官方 yolov8n.pt 量化包（dryrun_run01/out/quant_n80）',
            'board_proof': 'PENDING M3（手势锚板证地位不继承）',
            'frame': frames[0]['name'], 'anchors': []}
    ok_all = True
    for node, path in cp.ANCHORS:
        geo = next(g for g in eng.geos.values() if g.node == node)
        tiles = eng.anchor_tiles.get(node, {})
        if not tiles or len(tiles) != geo.NB:
            ok_all = False
            meta['anchors'].append({'node': node, 'pass': False,
                                    'why': 'tiles %d != NB %d'
                                    % (len(tiles), geo.NB)})
            continue
        mine = cp.build_anchor_mirror(geo, tiles)
        nb = want_bytes[node]
        assert mine.size >= nb, (node, mine.size, nb)
        cut = np.ascontiguousarray(mine[:nb])
        cut.tofile(path)
        ent = {'node': node, 'path': os.path.basename(path),
               'K': geo.K, 'chain': geo.chain, 'nb_blocks': geo.NB,
               'tile_load_len': geo.tile_load_len,
               'masked_law': geo.masked_law,
               'mirror_bytes': int(nb),
               'sha256': cp.sha_b(cut.tobytes()),
               'tiles_captured': len(tiles), 'pass': True}
        meta['anchors'].append(ent)
        print('%-18s K=%-4d chain=%-18s NB=%-5d %dB sha=%s'
              % (node, geo.K, geo.chain, geo.NB, nb, ent['sha256'][:16]))

    json.dump(meta, open(os.path.join(ANCHOR_DIR, 'anchors_meta.json'),
                         'w', encoding='utf-8'),
              indent=1, ensure_ascii=False)
    print('GEN_ANCHORS_N80 %s' % ('PASS' if ok_all else 'FAIL'))
    return 0 if ok_all else 1


if __name__ == '__main__':
    raise SystemExit(main())
