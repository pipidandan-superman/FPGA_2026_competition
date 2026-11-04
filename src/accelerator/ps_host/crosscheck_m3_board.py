#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""crosscheck_m3_board.py — M3 板级五档阶梯的 PC 侧交叉核对（板证收割后）

对 board_back/ 收割证据逐档复核（独立于 pl_m3 板上判据，重打字核对）：

  X1 判据/stage/frames：verdict==BOARD_M3_<L>_PASS 且 5 帧；
  X2 bit_sha == pack 位流 SHA（fabric 血统）；
  X3 九门全 True（CK*/DB*/SGi/SGa）；
  X4 totals：timeouts==0；lut_loads==stage_table 期望（LUT 跨帧驻留律：
     n>=2 档 n*5，n==1 档全程 1——attempt3 假阴性已修正）；blocks==5*ΣNB；
  X5 逐任务：conv nerr==0 且 out==oracle==PC 侧重算 refs npz 字节 SHA、
     blocks==NB、guard_ok；非 conv out==oracle==refs 重算；heads==meta
     heads_blob（302400B）；
  X6 anchors_checked == anchors_in_stage（档内前缀锚分布）；
  X7 csv：行数==totals.blocks，nerr/status/ystat 三列恒 0（定律：后两
     列仅失败时回读），node 集==档内 conv 集，每帧每 conv 恰 NB 行；
  X8 五档 l5 全图：n_tasks==104、convs==63、含 heads。

Run: <model venv python> crosscheck_m3_board.py [run_dir]
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.path.abspath(sys.argv[1] if len(sys.argv) > 1
                     else os.path.join(HERE, '..'))
PACK = os.path.join(RUN, 'board_pack')
BACK = os.path.join(RUN, 'board_back')
STAGES = ('l1', 'l2', 'l3', 'l4', 'l5')


def sha_b(b):
    return hashlib.sha256(b).hexdigest()


def main():
    meta = json.load(io.open(os.path.join(PACK, 'm3_meta.json'),
                             encoding='utf-8'))
    bit_sha = sha_b(open(os.path.join(PACK, 'display_test_wrapper.bit'),
                         'rb').read())
    refs = [dict(np.load(os.path.join(PACK, 'refs_f%d.npz' % fi)))
            for fi in range(5)]
    descs = meta['seg_descs']
    di_of = {d['node']: d['sched_index'] for d in descs}
    geo_nb = {d['node']: meta['conv_statics'][d['node']]['NB']
              for d in descs if d['op'] == 'conv'}
    ok_all = True

    for st in STAGES:
        e = meta['stage_table'][st]
        rep_p = os.path.join(BACK, 'm3_%s_board_report.json' % st)
        csv_p = os.path.join(BACK, 'm3_%s_blocks.csv' % st)
        if not os.path.exists(rep_p):
            print('X %s report missing: %s' % (st, rep_p))
            ok_all = False
            continue
        r = json.load(io.open(rep_p, encoding='utf-8'))
        x = []

        # X1 判据/stage/frames
        x.append(('verdict', r['verdict'] == 'BOARD_M3_%s_PASS'
                  % st.upper() and r['stage'] == st and len(r['frames']) == 5))

        # X2 位流血统
        x.append(('bit_sha', r['bit_sha'] == bit_sha))

        # X3 门全 True；SGa=逐锚独立门（attempt4 实测口径：8 基础门
        # CK0/CK1/CK4/CK5/CK6/DB1/DB2/SGi + 每锚一门 SGa:<node>）
        g = r['gates']
        sg_exp = {'SGa:%s' % a for a in e['anchors_in_stage']}
        sg_got = {k for k in g if k.startswith('SGa:')}
        x.append(('gates', all(v is True for v in g.values()) and
                  len(g) == 8 + len(sg_exp) and sg_got == sg_exp))

        # X4 totals（修正后的 LUT 律）
        t = r['totals']
        exp_blocks = 5 * sum(geo_nb[d['node']] for d in descs[e['lo']:e['hi']]
                             if d['op'] == 'conv')
        x.append(('timeouts', t['timeouts'] == 0))
        x.append(('lut_loads', t['lut_loads'] == e['exp_lut_loads']))
        x.append(('blocks', t['blocks'] == exp_blocks))

        # X5 逐任务字节律
        x5 = True
        for fi, fr in enumerate(r['frames']):
            for tk in fr['tasks']:
                node, op = tk['node'], tk['op']
                if op == 'heads':
                    good = (tk['out_sha256'] == tk['oracle_sha256'] ==
                            meta['heads_blob_sha256']['f%d' % fi] and
                            tk.get('byte_len', meta['heads_total']) ==
                            meta['heads_total'])
                elif op == 'conv':
                    key = 'ref_%d_%s' % (di_of[node], node.replace('.', '_'))
                    good = (tk['nerr'] == 0 and tk['guard_ok'] and
                            tk['blocks'] == geo_nb[node] and
                            tk['out_sha256'] == tk['oracle_sha256'] ==
                            sha_b(refs[fi][key].tobytes()))
                else:
                    key = 'ref_%d_%s' % (di_of[node], node.replace('.', '_'))
                    good = (tk.get('nerr', 0) == 0 and
                            tk['out_sha256'] == tk['oracle_sha256'] ==
                            sha_b(refs[fi][key].tobytes()))
                if not good:
                    x5 = False
                    print('  X5 FAIL %s %s f%d' % (op, node, fi))
        x.append(('tasks', x5))

        # X6 锚分布（anchors_checked 板上按字母序返回：集合+数相等即律）
        x.append(('anchors', sorted(r['anchors_checked']) ==
                  sorted(e['anchors_in_stage'])))

        # X7 csv 三列定律
        x7 = True
        if os.path.exists(csv_p):
            rows = list(csv.DictReader(io.open(csv_p, encoding='utf-8')))
            nodes_st = sorted(d['node'] for d in descs[e['lo']:e['hi']]
                              if d['op'] == 'conv')
            x7 = (len(rows) == t['blocks'] and
                  all(rr['nerr'] == '0' and rr['status'] == '0' and
                      rr['ystat'] == '00000000' for rr in rows) and
                  sorted(set(rr['node'] for rr in rows)) == nodes_st and
                  all(sum(1 for rr in rows if rr['node'] == n and
                          rr['frame'] == str(fi)) == geo_nb[n]
                      for n in nodes_st for fi in range(5)))
        else:
            x7 = False
            print('  X7 csv missing: %s' % csv_p)
        x.append(('csv', x7))

        bad = [k for k, v in x if not v]
        ok_all &= not bad
        print('X %s %s%s' % (st, 'PASS' if not bad else 'FAIL %s' % bad,
                             ' (blocks=%d lut=%d/%d)' %
                             (t['blocks'], t['lut_loads'],
                              e['exp_lut_loads'])))

    # X8 l5 全图闭包
    l5e = meta['stage_table']['l5']
    r5p = os.path.join(BACK, 'm3_l5_board_report.json')
    if os.path.exists(r5p):
        r5 = json.load(io.open(r5p, encoding='utf-8'))
        n_tk = len(r5['frames'][0]['tasks'])
        n_cv = sum(1 for tk in r5['frames'][0]['tasks'] if tk['op'] == 'conv')
        n_hd = sum(1 for tk in r5['frames'][0]['tasks'] if tk['op'] == 'heads')
        x8 = (n_tk == l5e['n_tasks'] == 104 and n_cv == l5e['n_convs'] == 63
              and n_hd == 1)
        ok_all &= x8
        print('X l5 全图（tasks=%d convs=%d heads=%d）%s'
              % (n_tk, n_cv, n_hd, 'PASS' if x8 else 'FAIL'))
    else:
        ok_all = False
        print('X l5 全图 FAIL report missing')

    print('M3_BOARDCROSS %s' % ('PASS' if ok_all else 'FAIL'))
    return 0 if ok_all else 1


if __name__ == '__main__':
    raise SystemExit(main())
