#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rehearse_m6_perf.py — M6.1 PC 排演门（P1-P5）→ M6_PERF_REHEARSE_PASS

门表（M6 schema m6-v1 rehearse_gates；全部 PC 侧，板断电中可做）：
  P1 派生拷贝纯度：pl_m6_perf 与 pl_m5 全部同名顶层单元
      inspect.getsource 逐字相等，除 PATCH_SET={main, run_frames,
      board_conv, arm_and_run, _mm2s_seg, wait_pend_clear, BoardHooks}；
      新增单元 ⊆ NEW_UNITS 声明；pl_m5 单元无缺失；继承模块常量等值。
  P2 金根流行走：全 5 档 × rounds=2 PC 行走（PCHooks 引擎模型），
      104×10 任务/档 nerr==0、跨档+跨轮 SHA 同一、warmup 标记正确、
      rounds 缩放（10 帧/档）。
  P3 期望计数律：ΣNB×5×rounds / EXPECT_PROG 阶梯 / segs_per_frame×
      5×rounds / EXPECT_ENG_TOTAL / lut EXP_LUT×rounds（板期望钉存）。
  P4 schema 自检：行走产物 rep+build_report+csv 头对 m6_schema.json
      必填字段核验（PC 可产子集；板全字段=X12）。
  P5 perf 桶恒等：每帧 16 桶齐备非负、frame_wall ≈ task+refs+poison+
      other（±1ms）、Σ桶 ≤ elapsed_s×1e6+容差、warmup 剔除后统计非空
      （frames 面；blocks 面=板专属）。

判据输出：m6_rehearse_report.json + 控制台 P 门行 + 终判
M6_PERF_REHEARSE_PASS / M6_PERF_REHEARSE_FAIL。
"""
import os, sys, time, json, hashlib, inspect, ast, re
import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
M3PACK = r'E:\competition\4_metrics\logs\2026-10-06_yolo_m3_board_run01\board_pack'
PREP = r'E:\competition\4_metrics\logs\2026-10-07_yolo_m5_xsim_run01\out\prep_f7'
OUT = r'E:\competition\4_metrics\logs\2026-10-08_yolo_m6_perf_run01\rehearse'
SCHEMA = (r'E:\competition\4_metrics\logs\2026-10-08_yolo_m6_perf_run01'
          r'\scripts\m6_schema.json')

sys.path.insert(0, _HERE)
_argv0 = sys.argv[0]
sys.argv = [_argv0, 'l5']
import pl_m5
import pl_m6_perf as M6
import f7prep_n80 as f7
sys.argv = [_argv0]

ROUNDS = 2
R = {}
REP = {'gates': {}, 'detail': {}}


def gate(rk, ok, note=''):
    R[rk] = bool(ok)
    REP['gates'][rk] = {'ok': bool(ok), 'note': note}
    print('P-GATE %-4s %s %s' % (rk, 'PASS' if ok else 'FAIL', note),
          flush=True)


def sha_b(x):
    return hashlib.sha256(x).hexdigest()


# ======================================================================
# P1：派生拷贝纯度
# ======================================================================
def p1_purity():
    patch = set(M6.M6_PATCH_SET)
    new_decl = set(M6.M6_NEW_UNITS)

    def top(mod):
        out = {}
        for name, val in vars(mod).items():
            if name.startswith('__'):
                continue
            if (inspect.isfunction(val) or inspect.isclass(val)) and \
                    getattr(val, '__module__', None) == mod.__name__:
                out[name] = val
        return out

    u5, u6 = top(pl_m5), top(M6)
    missing = sorted(set(u5) - set(u6))
    extra = sorted(set(u6) - set(u5) - new_decl)
    drift = []
    for n in sorted(set(u5) & set(u6)):
        if n in patch:
            continue
        if inspect.getsource(u5[n]) != inspect.getsource(u6[n]):
            drift.append(n)
    patch_live = sorted(n for n in patch if n in u5 and n in u6 and
                        inspect.getsource(u5[n]) == inspect.getsource(u6[n]))
    new_live = set(u6) - set(u5)
    # 继承模块常量等值（数值/串/元组/frozenset/字典）
    scal = (int, float, str, bool, tuple, frozenset, dict)
    c5 = {k: v for k, v in vars(pl_m5).items()
          if isinstance(v, scal) and not k.startswith('__')}
    uneq, cmiss = [], []
    for k, v in c5.items():
        if k not in vars(M6):
            cmiss.append(k)
        elif vars(M6)[k] != v:
            uneq.append(k)
    ok = (not missing and not extra and not drift and not patch_live and
          new_live == new_decl and not uneq and not cmiss and
          patch <= set(u5))
    REP['detail']['p1'] = {
        'patch_set': sorted(patch), 'new_units': sorted(new_live),
        'n_common': len(set(u5) & set(u6)),
        'missing': missing, 'extra': extra, 'drift': drift,
        'patch_units_unchanged': patch_live,
        'const_unequal': uneq, 'const_missing': cmiss}
    gate('P1', ok, 'common=%d patch=%d new=%d %s'
         % (len(set(u5) & set(u6)), len(patch), len(new_live),
            'pure derived copy' if ok else 'DRIFT'))


# ======================================================================
# P2：金根流行走（PCHooks 引擎模型；rounds=2）
# ======================================================================
class PCHooks(object):
    """PC 执行面：conv=oracle refs；PPU 段=f7prep 引擎模型（字解析 m/s）。
    与 rehearse_m5_driver 同律，但全部走 pl_m6_perf 模块面（派生验证）。"""

    def __init__(self, descs, A, QT, bufs, arena, headb):
        self.node2key = {td['node']:
                         'ref_%d_%s' % (td['sched_index'],
                                        td['node'].replace('.', '_'))
                         for td in descs}
        self.A, self.QT, self.bufs = A, QT, bufs
        self.arena, self.headb = arena, headb
        self.fr_cache = {}

    def _fr(self, fi):
        if fi not in self.fr_cache:
            self.fr_cache[fi] = dict(np.load(
                os.path.join(M3PACK, 'refs_f%d.npz' % fi)))
        return self.fr_cache[fi]

    def conv(self, node, geo, x, fi):
        geo.guard_ok = True
        return np.ascontiguousarray(
            self._fr(fi)[self.node2key[node]]).view(np.uint8)

    def pre_flush(self):
        pass

    def post_invalidate(self, has_heads):
        pass

    def ppu_segment(self, k, bd):
        ar = self.arena
        for td in bd['tds']:
            di = td['desc_id']
            dd = M6.dec_desc(self.A[32 * di:32 * di + 32])
            op = td['op']

            def cell(prof):
                return M6.dec_quant_cell(
                    self.QT[4 * prof:4 * prof + 4])

            if op == 'add':
                m0, s0 = cell(dd['prof_in0'])
                m1, s1 = cell(dd['prof_in1'])
                out = f7.add_ref(ar.raw(td['a_buf']), ar.raw(td['b_buf']),
                                 m0, s0, m1, s1)
                ar.write_raw(td['out_buf'], out)
            elif op == 'maxpool5':
                c, h, w = self.bufs[td['in_bufs'][0]]['shape']
                out = f7.mp5_ref(ar.raw(td['in_bufs'][0]), c, h, w)
                ar.write_raw(td['out_buf'], out)
            elif op == 'upsample2':
                c, h, w = self.bufs[td['in_bufs'][0]]['shape']
                out = f7.ups2_ref(ar.raw(td['in_bufs'][0]), c, h, w)
                ar.write_raw(td['out_buf'], out)
            elif op == 'concat':
                parts = []
                for se in dd['segs']:
                    raw = ar.raw(se['buf'], se['nbytes'])
                    if se['prof'] == 0:
                        parts.append(raw)
                    else:
                        m, s = cell(se['prof'])
                        if (m, s) == (1 << 30, 30):
                            parts.append(raw)      # 恒等旁路
                        else:
                            parts.append(f7.requant_vec(raw, m, s))
                ar.write_raw(td['out_buf'], b''.join(parts))
            elif op == 'heads':
                blob = b''.join(ar.raw(se['buf'], se['nbytes'])
                                for se in dd['segs'])
                self.headb[:len(blob)] = np.frombuffer(blob, np.uint8)
            else:
                raise AssertionError('engine op %s' % op)
        return True


def _m6_reset_state():
    """行走间隔离：保存并清零 M6 模块级计数/桶（per-stage 干净读数）。"""
    snap = {'counts': dict(M6.counts),
            'perf6': {k: (list(v) if isinstance(v, list) else v)
                      for k, v in M6.perf6.items()}}
    for k in M6.counts:
        M6.counts[k] = 0
    for k, v in M6.perf6.items():
        if isinstance(v, list):
            del v[:]
        elif isinstance(v, (int, float)):
            M6.perf6[k] = 0
        elif k == 'fb':
            M6.perf6[k] = None
    return snap


def _m6_restore_state(snap):
    M6.counts.clear()
    M6.counts.update(snap['counts'])
    M6.perf6.update(snap['perf6'])


def walk_stage(stage, meta, descs, Par, v11b, A, BW, QT, want_shas=None):
    """一次 rounds×5 帧行走（M6 模块面）；返回 (ok, sha 映射, 汇总, rep)。"""
    bufs = v11b['entries']
    arena_need = max(b['base_off'] + b['size'] for b in bufs)
    arr = np.full(arena_need, M6.POISON, np.uint8)
    headb = np.full((int(meta['heads_total']) + 0xFFF) // 0x1000 * 0x1000,
                    M6.POISON, np.uint8)
    arena = M6.Arena(arr, bufs)
    hooks = PCHooks(descs, A, QT, bufs, arena, headb)
    geos = {n: M6.Geo(n, s, Par) for n, s in meta['conv_statics'].items()}
    ctx = M6.Ctx()
    ctx.stage, ctx.ramp = stage, M6.BACKEND_RAMP[stage]
    ctx.arena, ctx.headb = arena, headb
    ctx.descs, ctx.geos, ctx.bufs, ctx.meta = descs, geos, bufs, meta
    ctx.ANCHORS = {}
    ctx.anchor_done = set()
    ctx.csv = None
    ctx.segments = M6.build_stage_plan(descs, A, stage, BW)['segments']
    ctx.hooks = hooks
    ctx.npbuf = None
    ctx.refs_pat = os.path.join(M3PACK, 'refs_f%d.npz')
    ctx.rounds = ROUNDS
    ctx.rep = {'stage': stage, 'frames': []}
    snap = _m6_reset_state()
    try:
        ok = M6.run_frames(ctx)
    finally:
        segs_observed = M6.counts['segs']
        _m6_restore_state(snap)
    shas = {}
    for f in ctx.rep['frames']:
        for t in f['tasks']:
            k = (f['round'], f['frame'], t['sched_index'])
            shas[k] = t.get('out_sha256') or t.get('blob_sha256')
    nerr_tot = sum(t.get('nerr', 0) for f in ctx.rep['frames']
                   for t in f['tasks'])
    zero_copy = all(t.get('zero_copy', True)
                    for f in ctx.rep['frames'] for t in f['tasks']
                    if t['op'] == 'view')
    stamps_ok = all('t_start_us' in t and 't_end_us' in t
                    for f in ctx.rep['frames'] for t in f['tasks'])
    rounds_lab = [f['round'] for f in ctx.rep['frames']]
    warm = [bool(f.get('warmup')) for f in ctx.rep['frames']]
    summ = {'stage': stage, 'frames_ok': bool(ok), 'nerr': nerr_tot,
            'tasks': sum(len(f['tasks']) for f in ctx.rep['frames']),
            'segs': sum(len(f['segs']) for f in ctx.rep['frames']),
            'segs_counter': segs_observed, 'zero_copy': zero_copy,
            'stamps_ok': stamps_ok,
            'rounds_labels_ok': rounds_lab == [0] * 5 + [1] * 5,
            'warmup_flags': warm}
    if want_shas is not None:
        summ['sha_consistent'] = all(shas.get(k) == v
                                     for k, v in want_shas.items())
    return ok, shas, summ, ctx.rep


def p2_walks(meta, descs, Par, v11b, A, BW, QT):
    ok0, shas0, s0, rep0 = walk_stage('l0', meta, descs, Par, v11b, A, BW, QT)
    heads_ok = (len(rep0['frames']) == 10 and
                all(f['tasks'] and f['tasks'][-1].get('nerr') == 0
                    for f in rep0['frames']))
    base_ok = (ok0 and s0['nerr'] == 0 and s0['tasks'] == ROUNDS * 5 * 104
               and s0['zero_copy'] and heads_ok and s0['rounds_labels_ok']
               and s0['warmup_flags'] == [True] + [False] * 9
               and s0['stamps_ok'])
    REP['detail']['walk_l0'] = s0
    gate('P2', base_ok,
         'L0 frames=%d tasks=%d nerr=%d heads x10=%s stamps=%s warmup=%s'
         % (len(rep0['frames']), s0['tasks'], s0['nerr'], heads_ok,
            s0['stamps_ok'], s0['warmup_flags'][:1]))
    return shas0


def p2b_ladder(meta, descs, Par, v11b, A, BW, QT, shas0):
    ok = True
    notes = []
    for stage in ('l1', 'l2', 'l3', 'l4'):
        okx, shasx, sx, repx = walk_stage(stage, meta, descs, Par, v11b,
                                          A, BW, QT, want_shas=shas0)
        okx &= (sx['nerr'] == 0 and sx['sha_consistent'] and
                sx['tasks'] == ROUNDS * 5 * 104 and sx['stamps_ok'] and
                sx['rounds_labels_ok'])
        ok &= okx
        notes.append('%s:%s(segs=%d)' % (stage, 'OK' if okx else 'BAD',
                                         sx['segs']))
        REP['detail']['walk_%s' % stage] = sx
    gate('P2b', ok, 'cross-stage+cross-round SHA identity + ' + ' '.join(notes))


# ======================================================================
# P3：期望计数律（meta 复算 == 驱动常数 == 行走观测）
# ======================================================================
def p3_expectations(meta, descs, Par):
    geos = {n: M6.Geo(n, s, Par) for n, s in meta['conv_statics'].items()}
    sum_nb = sum(g.NB for g in geos.values())
    exp_blocks = sum_nb * 5 * ROUNDS
    exp_lut = int(meta['stage_table']['l5']['exp_lut_loads'])
    notes = []
    ok = True
    okb = (exp_blocks == 183500 * ROUNDS)
    ok &= okb
    notes.append('blocks ΣNB=%d ×5×%d = %d %s'
                 % (sum_nb, ROUNDS, exp_blocks, 'OK' if okb else 'BAD'))
    okl = (exp_lut == 315)
    ok &= okl
    notes.append('lut EXP_LUT=%d ×%d=%d %s'
                 % (exp_lut, ROUNDS, exp_lut * ROUNDS,
                    'OK' if okl else 'BAD'))
    n_eng = sum(1 for td in descs if td['op'] in M6.ENGINE_CLASSES)
    oke = (M6.EXPECT_ENG_TOTAL == n_eng == 25)
    ok &= oke
    notes.append('engine universe %d (descs total=%d) %s'
                 % (M6.EXPECT_ENG_TOTAL, len(descs),
                    'OK' if oke else 'BAD'))
    # EXPECT_PROG 阶梯：meta seg_descs 复算 == 驱动常数
    for st in M6.STAGES:
        ramp = M6.BACKEND_RAMP[st]
        n_prog = sum(1 for td in descs if td['op'] in ramp)
        prog_ok = (n_prog == M6.EXPECT_PROG[st])
        ok &= prog_ok
        notes.append('%s prog=%d %s' % (st, n_prog,
                                        'OK' if prog_ok else 'BAD'))
    # segs 缩放：行走观测 == 段束×5×rounds
    for st in M6.STAGES:
        key = 'walk_%s' % st if st in REP['detail'] else None
        if key is None:
            continue
        w = REP['detail'][key]
        plan_segs = w['segs'] // (5 * ROUNDS)
        seg_ok = (w['segs'] == plan_segs * 5 * ROUNDS and
                  w['segs_counter'] == w['segs'])
        ok &= seg_ok
        notes.append('%s segs=%d (%d/frame×%d) %s'
                     % (st, w['segs'], plan_segs, ROUNDS * 5,
                        'OK' if seg_ok else 'BAD'))
    gate('P3', ok, '; '.join(notes))


# ======================================================================
# P4：schema 自检（m6_schema.json 必填字段；PC 可产子集）
# ======================================================================
def p4_schema(meta, descs, Par, v11b, A, BW, QT):
    sch = json.load(open(SCHEMA, encoding='utf-8'))
    ok = True
    notes = []
    # 板可产全量 rep 的 PC 仿形：l0 行走 + build_report（calib 桩）
    okx, shasx, sx, rep = walk_stage('l0', meta, descs, Par, v11b, A, BW, QT)
    rep['seg_evidence'] = [s for f in rep['frames'] for s in f['segs']]
    # 板可产字段 PC 仿形（segments_meta/bit_sha256=板 main 面；probe 注入
    # 占位以验证 walk+build_report 并集覆盖 schema required_top）
    plan0 = M6.build_stage_plan(descs, A, 'l0', BW)
    rep['segments_meta'] = [{'ids': bd['ids'], 'sum_w14': bd['sum_w14']}
                            for bd in plan0['segments']]
    rep['bit_sha256'] = 'PC_PROBE_NOT_BOARD'

    class _CtxShim(object):
        pass
    rep['gates'] = {}
    rep['totals'] = dict(M6.counts)
    rep['anchors_checked'] = []
    rep['verdict'] = 'PC_SCHEMA_PROBE'
    calib_stub = {'gemm_rd_ns_per_op': 0.0, 'ppu_rd_ns_per_op': 0.0,
                  'sleep500us_actual_us': 0.0, 'perf_pair_ns': 0.0}
    M6.build_report(_ctx_shim_rep(rep), ROUNDS, calib_stub, 0)
    art = sch['artifacts']['m6_perf_report']
    # PC 可产子集：env/板位流字段除外（X12 板全字段核）
    pc_top = [k for k in art['required_top'] if k != 'env']
    miss_top = [k for k in pc_top if k not in rep]
    ok &= (not miss_top)
    notes.append('top %d/%d %s' % (len(pc_top) - len(miss_top), len(pc_top),
                                   'OK' if not miss_top else
                                   'MISS:' + ','.join(miss_top)))
    fr_bad = []
    for f in rep['frames']:
        for k in art['frame_required']:
            if k not in f:
                fr_bad.append('f%s:%s' % (f.get('frame'), k))
        for k in art['perf_fields']:
            if k not in f.get('perf', {}):
                fr_bad.append('f%s:perf.%s' % (f.get('frame'), k))
        for t in f['tasks']:
            for k in art['task_fields']:
                if k not in t:
                    fr_bad.append('f%s:t%d.%s' % (f.get('frame'),
                                                  t.get('sched_index'), k))
    ok &= (not fr_bad)
    notes.append('frame/task fields %s' % ('OK' if not fr_bad else
                                           'MISS:%d' % len(fr_bad)))
    st_bad = [k for k in art['stats_required'] if k not in rep['stats']]
    ok &= (not st_bad)
    notes.append('stats %s' % ('OK' if not st_bad else
                               'MISS:' + ','.join(st_bad)))
    # driver_sha256 自证
    dsha = hashlib.sha256(open(os.path.join(_HERE, 'pl_m6_perf.py'), 'rb')
                          .read()).hexdigest()
    okd = (rep['driver_sha256'] == dsha and rep['driver'] == 'pl_m6_perf.py')
    ok &= okd
    notes.append('driver_sha256 %s' % ('OK' if okd else 'BAD'))
    # csv 头静态锁（main 内隐式串接字面量 → ast 单 Constant）
    src = open(os.path.join(_HERE, 'pl_m6_perf.py'), encoding='utf-8').read()
    m = re.search(r'hooks\.csv\.write\(([^)]*)\)', src)
    hdr = ast.literal_eval('(' + m.group(1) + ')') if m else None
    exp_cols = sch['artifacts']['m6_blocks_csv']['columns']
    okc = (hdr is not None and
           hdr.strip().split(',') == exp_cols)
    ok &= okc
    notes.append('csv cols %d %s' % (len(exp_cols),
                                     'OK' if okc else 'BAD:%r' % hdr))
    REP['detail']['p4_rep_probe'] = {'rounds': rep.get('rounds'),
                                     'frames': len(rep['frames']),
                                     'schema_version':
                                         rep.get('schema_version')}
    gate('P4', ok and okx, '; '.join(notes))


def _ctx_shim_rep(rep):
    c = type(str('_ShimCtx'), (), {})()
    c.rep = rep
    return c


# ======================================================================
# P5：perf 桶恒等
# ======================================================================
FBK = ('refs_load_us', 'poison_us', 'pack_us', 'submit_us', 'gather_us',
       'lut_us', 'sw_add_us', 'sw_concat_us', 'sw_mp5_us', 'sw_ups2_us',
       'sw_view_us', 'sw_heads_us', 'ppu_seg_us', 'bridge_us')


def p5_walk(meta, descs, Par, v11b, A, BW, QT):
    ok = True
    notes = []
    n_frames = 0
    n_nw = 0
    worst_ident = 0
    worst_sub = 0
    worst_elapsed_gap = 0
    for stage in M6.STAGES:
        okx, shasx, sx, rep = walk_stage(stage, meta, descs, Par, v11b,
                                         A, BW, QT)
        for f in rep['frames']:
            n_frames += 1
            if not f.get('warmup'):
                n_nw += 1
            perf = f.get('perf', {})
            neg = [k for k, v in perf.items() if v < 0]
            # 恒等面=frame_wall_us（M5 elapsed_s 起点在 refs/poison 之后，
            # 不含装载段——性能钟参照只能用 frame_wall_us）
            ident = abs(f['frame_wall_us'] - (perf['task_us'] +
                                              perf['refs_load_us'] +
                                              perf['poison_us'] +
                                              perf['other_us']))
            worst_ident = max(worst_ident, ident)
            # 包含律：FBK[2:]（pack..bridge）全是任务窗内部子窗，
            # 嵌套计费不得超 task_us（对 frame_wall 求和会双计）
            sub = sum(perf[k] for k in FBK[2:]) - perf['task_us']
            worst_sub = max(worst_sub, sub)
            # 信息核对：task_us 窗 ⊆ elapsed 窗（取证钟覆盖任务段）
            egap = perf['task_us'] - f['elapsed_s'] * 1000000
            worst_elapsed_gap = max(worst_elapsed_gap, egap)
            if neg or ident > 1000 or sub > 2000:
                ok = False
                notes.append('%s r%d f%d neg=%s ident=%d sub_over_task=%d'
                             % (stage, f['round'], f['frame'], neg, ident,
                                sub))
    ok &= (n_frames == 5 * len(M6.STAGES) * ROUNDS and n_nw == 45)
    notes.append('frames=%d non-warmup=%d worst_ident_us=%d '
                 'worst_sub_over_task_us=%d task_vs_elapsed_us=%d'
                 % (n_frames, n_nw, worst_ident, worst_sub,
                    worst_elapsed_gap))
    gate('P5', ok, '; '.join(notes[-4:]))


# ======================================================================
def main():
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    print('M6 rehearse driver start %s' % time.strftime('%F %T'), flush=True)
    meta = json.load(open(os.path.join(M3PACK, 'm3_meta.json'),
                          encoding='utf-8'))
    v11b = json.load(open(r'E:\competition\4_metrics\logs'
                          r'\2026-10-06_yolo_m3_manifests_v11_run01\out'
                          r'\p2_manifests_n80_v11\buffer_table.json',
                          encoding='utf-8'))
    A = M6.load_hex_words(os.path.join(PREP, 'desc_table_A.hex'))
    BW = M6.load_hex_words(os.path.join(PREP, 'buf_table_A.hex'))
    QT = M6.load_hex_words(os.path.join(PREP, 'quant_table_A.hex'))
    descs = meta['seg_descs']
    Par = dict(np.load(os.path.join(M3PACK, 'm3_params.npz')))

    p1_purity()

    # PC 静音 emit（P1 用 inspect 已完成源码同一性证明；此后替换运行期
    # 对象仅去噪声，不改文件本体）
    def _pc_emit(m):
        print('[m6 %s %s]' % (m, time.strftime('%H:%M:%S')), flush=True)
    M6.emit = _pc_emit

    shas0 = p2_walks(meta, descs, Par, v11b, A, BW, QT)
    p2b_ladder(meta, descs, Par, v11b, A, BW, QT, shas0)
    p3_expectations(meta, descs, Par)
    p4_schema(meta, descs, Par, v11b, A, BW, QT)
    p5_walk(meta, descs, Par, v11b, A, BW, QT)

    allpass = all(R.values())
    verdict = 'M6_PERF_REHEARSE_PASS' if allpass else 'M6_PERF_REHEARSE_FAIL'
    REP['verdict'] = verdict
    REP['elapsed_s'] = round(time.time() - t0, 1)
    REP['rounds'] = ROUNDS
    json.dump(REP, open(os.path.join(OUT, 'm6_rehearse_report.json'), 'w',
                        encoding='utf-8'), indent=1, ensure_ascii=False)
    print('P-FINAL %s gates=%s elapsed=%.0fs' %
          (verdict, {k: ('P' if v else 'F') for k, v in R.items()},
           REP['elapsed_s']), flush=True)
    return 0 if allpass else 1


if __name__ == '__main__':
    sys.exit(main())
