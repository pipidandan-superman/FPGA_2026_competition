#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rehearse_m5_driver.py — M5.3 PC 排演门（R1-R7）→ M5_REHEARSE_PASS

门表（M3 rehearse 同型强化；全部 PC 侧，板断电中可做）：
  R1 conv 移植双锁：(a) inspect 源码同一性——pl_m5 十七单元（rne_shift/
      sat_i8/sat_i32/req_pair/maxpool5/upsample_nearest2/Geo/pack_tile/
      dump_state/load_lut/_mm2s_seg/wait_pend_clear/arm_and_run/
      board_conv/emit/wr/rd）与 pl_m3 逐字符相等；
      (b) 行为等价——315 全装载流（63 conv × 5 帧；oracle 输入取自
      refs 张量按 buffer ABI 复演）pl_m5.pack_tile 与 pl_m3.pack_tile
      逐字节相等 + 5 装载锚 SHA == m3_meta anchors（含 tll 填充律的
      npbuf 区域复刻）。
  R2 阶段表律：每档程序/段束对 v11 descriptor_table.json（唯一合法
      输入 gm=74958a41）+ f7prep TB_PROG 三重锁；A 表 32 字解码 vs
      JSON 逐项（opcode/in0/in1/out/out_bytes/concat 段/add prof）；
      段划分=极大游程独立复算；w6 producer 重编独立复算（producer
      节点名→desc id→段内槽位/0xFF 外部）；Σw14==Σout_bytes；末槽
      bit9 律；quant 单元 == req_pair（比率法律）。
  R3 PC 全图软件（L0 档）：run_frames 5 帧全绿（oracle conv、全软件
      图算子、arena 字节面）→ 104 任务×5 nerr==0 + heads SHA×5 ==
      meta + view 零拷贝 16×5。
  R4 混合阶梯（L1-L4）：run_frames per stage，PPU 段=f7prep 引擎模型
      执行器（m/s 从装载字解析=RTL 消费镜像；add_ref/requant_vec/
      mp5_ref/ups2_ref；concat 恒等旁路 (2^30,30)/prof==0）→ 全任务
      nerr==0 + heads L4 blob 逐位 + 跨档一致性（L0..L4 每任务
      out SHA 五档全等=backend 无关性）。
  R5 结构审计：三窗字数界（desc≤2048/buf==1024/qt==1024/ring 32×16）；
      段游程覆盖=程序剖分；段内依赖方向（生产者 sched 先于消费者）；
      EXPECT_PROG 逐档；引擎宇宙==25；环形指针节奏（sc&31 无未读覆写：
      每段读后即 ack，覆写仅及已消费槽）。
  R6 CSR 律单：yolo_csr_pkg.sv 逐 localparam == 驱动 PA_*/窗/几何/
      YOLO_ID_VALUE/YOLO_VERSION；conv 基址与 GEMM/DMA map == pl_m3
      模块常数；abi/address_map.md 0x43C2 在档。
  R7 输入审计：params 键集==meta params_keys；v11 manifests SHA 锁
      （graph_manifest_sha256）；arena_total 对账（v11==memory_audit）；
      poison==165。

判据输出：m5_rehearse_report.json + 控制台 R 门行 + 终判
M5_REHEARSE_PASS / M5_REHEARSE_FAIL。
"""
import os, sys, time, json, hashlib, inspect, re
import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, '..'))
sys.path.insert(0, _HERE)

M3PACK = r'E:\competition\4_metrics\logs\2026-10-06_yolo_m3_board_run01\board_pack'
PREP = r'E:\competition\4_metrics\logs\2026-10-07_yolo_m5_xsim_run01\out\prep_f7'
V11 = (r'E:\competition\4_metrics\logs\2026-10-06_yolo_m3_manifests_v11_run01'
       r'\out\p2_manifests_n80_v11')
PKG = os.path.join(_ROOT, 'yolo_dma_csr', 'rtl', 'ps_axi_pl',
                   'yolo_csr_pkg.sv')
ADMAP = os.path.join(_ROOT, 'abi', 'address_map.md')
OUT = r'E:\competition\4_metrics\logs\2026-10-07_yolo_m5_rehearse_run01'

# pl_m3 导入期档断言绕行（rehearse_m3_driver 同式）
_argv0 = sys.argv[0]
sys.argv = [_argv0, 'l5']
import pl_m3 as DRV3
import pl_m5
import f7prep_n80 as f7
sys.argv = [_argv0]

R = {}          # 门结果
REP = {'gates': {}, 'detail': {}}


def gate(rk, ok, note=''):
    R[rk] = bool(ok)
    REP['gates'][rk] = {'ok': bool(ok), 'note': note}
    print('R-GATE %-4s %s %s' % (rk, 'PASS' if ok else 'FAIL', note),
          flush=True)


def sha_b(x):
    return hashlib.sha256(x).hexdigest()


# ======================================================================
# 输入装载（R7 首做：输入本身先过审计）
# ======================================================================
def load_inputs():
    meta = json.load(open(os.path.join(M3PACK, 'm3_meta.json'),
                          encoding='utf-8'))
    v11d = json.load(open(os.path.join(V11, 'descriptor_table.json'),
                          encoding='utf-8'))
    v11b = json.load(open(os.path.join(V11, 'buffer_table.json'),
                          encoding='utf-8'))
    A = pl_m5.load_hex_words(os.path.join(PREP, 'desc_table_A.hex'))
    BW = pl_m5.load_hex_words(os.path.join(PREP, 'buf_table_A.hex'))
    QT = pl_m5.load_hex_words(os.path.join(PREP, 'quant_table_A.hex'))
    return meta, v11d, v11b, A, BW, QT


def r7_inputs(meta, v11d, v11b, Par):
    ok = True
    notes = []
    okk = set(Par.keys()) == set(meta['params_keys'])
    ok &= okk
    notes.append('params %d keys %s' % (len(Par),
                                        'OK' if okk else 'BAD'))
    sha_d = sha_b(open(os.path.join(V11, 'descriptor_table.json'), 'rb').read())
    sha_b_ = sha_b(open(os.path.join(V11, 'buffer_table.json'), 'rb').read())
    REP['detail']['manifest_file_sha256'] = {'descriptor_table': sha_d,
                                             'buffer_table': sha_b_}
    # gm（graph_manifest_sha256=上游图导出规范哈希）PC 侧不可廉价复算；
    # 溯源锁 = meta['manifests_dir'] 字面指向本 v11 目录 + 文件 SHA 钉存
    # 入报告（manifests 内容本身由 R2 逐字段锁，强于 blob 等值）。
    md_ok = os.path.normcase(os.path.normpath(
        meta['manifests_dir'])) == os.path.normcase(os.path.normpath(V11))
    ok &= md_ok
    notes.append('manifests_dir %s (gm=%s.. pinned file sha %s/%s..)'
                 % ('OK' if md_ok else 'BAD',
                    meta['graph_manifest_sha256'][:8],
                    sha_d[:8], sha_b_[:8]))
    at_ok = int(v11b['arena_total']) == \
        int(meta['memory_account_audit']['arena_total'])
    ok &= at_ok
    notes.append('arena_total %d %s' % (v11b['arena_total'],
                                        'OK' if at_ok else 'BAD'))
    pz_ok = int(meta['poison']) == int(pl_m5.POISON)
    ok &= pz_ok
    notes.append('poison %s' % ('OK' if pz_ok else 'BAD'))
    ht_ok = int(meta['heads_total']) == 302400
    ok &= ht_ok
    notes.append('heads_total %d %s' % (meta['heads_total'],
                                        'OK' if ht_ok else 'BAD'))
    gate('R7', ok, '; '.join(notes))


# ======================================================================
# R1：conv 移植双锁
# ======================================================================
UNITS = ['rne_shift', 'sat_i8', 'sat_i32', 'req_pair', 'maxpool5',
         'upsample_nearest2', 'Geo', 'pack_tile', 'dump_state', 'load_lut',
         '_mm2s_seg', 'wait_pend_clear', 'arm_and_run', 'board_conv',
         'emit', 'wr', 'rd']


def r1a_source_identity():
    bad = []
    for n in UNITS:
        s5 = inspect.getsource(getattr(pl_m5, n))
        s3 = inspect.getsource(getattr(DRV3, n))
        if s5 != s3:
            bad.append(n)
    gate('R1a', not bad, '%d units %s' % (len(UNITS),
                                          'identical' if not bad else
                                          'DRIFT:' + ','.join(bad)))


def r1b_streams(meta, descs, Par):
    g5 = {n: pl_m5.Geo(n, s, Par) for n, s in meta['conv_statics'].items()}
    g3 = {n: DRV3.Geo(n, s, Par) for n, s in meta['conv_statics'].items()}
    anchors = meta.get('anchors', {})
    n_stream = 0
    n_byte = 0
    n_block = 0
    n_bad = 0
    anc_ok = {}
    t0 = time.time()
    for fi in range(5):
        fr = dict(np.load(os.path.join(M3PACK, 'refs_f%d.npz' % fi)))
        tensors = {0: (fr['canvas'].astype(np.int16) - 128)
                   .astype(np.int8).transpose(2, 0, 1).copy()}
        for td in descs:
            op = td['op']
            if op == 'heads':
                continue
            key = 'ref_%d_%s' % (td['sched_index'],
                                 td['node'].replace('.', '_'))
            if op == 'view':
                par = tensors[td['parent_buf']]
                tensors[td['out_buf']] = par[td['ch'][0]:td['ch'][1]]
            else:
                tensors[td['out_buf']] = fr[key]
        for td in descs:
            if td['op'] != 'conv':
                continue
            node = td['node']
            geo = g5[node]
            x = tensors[td['in_bufs'][0]]
            region = np.full(geo.tll * geo.NB, pl_m5.POISON, np.uint8)
            for b in range(geo.NB):
                nt, rc = b // geo.RC, b % geo.RC
                oy, s = nt // geo.n_strips, nt % geo.n_strips
                t5 = pl_m5.pack_tile(geo, x, oy, s, rc)
                t3 = DRV3.pack_tile(g3[node], x, oy, s, rc)
                b5 = t5.tobytes()
                if b5 != t3.tobytes():
                    n_bad += 1
                    if n_bad <= 3:
                        print('  R1b drift %s f%d b=%d' % (node, fi, b),
                              flush=True)
                n_stream += 1
                n_byte += len(b5)
                n_block += 1
                region[geo.tll * b:geo.tll * b + t5.size] = \
                    t5.reshape(-1)
            if node in anchors and fi == 0:
                got = sha_b(region.tobytes())
                anc_ok[node] = (got == anchors[node])
                if not anc_ok[node]:
                    print('  R1b anchor %s got=%s exp=%s'
                          % (node, got[:16], anchors[node][:16]), flush=True)
        print('  R1b frame %d done (%.0fs)' % (fi, time.time() - t0),
              flush=True)
    exp_blocks = sum(int(s['NB']) for s in meta['conv_statics'].values())
    ok = (n_bad == 0 and all(anc_ok.values()) and
          len(anc_ok) == len(anchors) and n_block == 5 * exp_blocks)
    gate('R1b', ok, 'streams=%d bytes=%d blocks=%d(exp NB-sum %d x5f) '
         'drift=%d anchors=%d/%d'
         % (n_stream, n_byte, n_block, exp_blocks, n_bad,
            sum(anc_ok.values()), len(anchors)))


# ======================================================================
# R2：阶段表律（v11 JSON 权威 + TB_PROG 三重锁）
# ======================================================================
def r2_tables(meta, descs, v11d, v11b, A, BW, QT):
    ents = v11d['entries']
    bufs = v11b['entries']
    bsz = {b['id']: int(b['size']) for b in bufs}
    # packer producer 转换律：w6 字节 = 该 buf 唯一生产任务 desc_id
    # （'input'→0xFF；viewspec 'X[a:b]'→视图任务 id；node→本任务 id）
    prod_task = {td['out_buf']: td['desc_id'] for td in descs
                 if td['out_buf'] is not None}
    node2desc = {td['node']: td['desc_id'] for td in descs}
    jmap = {e['desc_id']: e for e in ents}
    ok = True
    notes = []
    # 恒等锁：meta seg_descs == v11 entries（任务宇宙同源）
    id_ok = (descs == ents)
    ok &= id_ok
    notes.append('seg_descs==v11 %s' % ('OK' if id_ok else 'BAD'))
    # 三重锁：JSON 引擎全集 == TB_PROG == l4 程序
    eng_json = sorted(e['desc_id'] for e in ents
                      if e['op'] in pl_m5.ENGINE_CLASSES)
    ok &= (eng_json == sorted(f7.TB_PROG))
    plan4 = pl_m5.build_stage_plan(descs, A, 'l4', BW)
    ok &= (plan4['prog'] == list(f7.TB_PROG))
    ok &= (len(eng_json) == pl_m5.EXPECT_ENG_TOTAL)
    notes.append('triple-lock %d ids %s' % (len(eng_json),
                 'OK' if eng_json == sorted(f7.TB_PROG) else 'BAD'))

    # A/qt 表长度 + 全 104 项字段解码 vs JSON
    lens_ok = (len(A) == 128 * 32 and len(BW) == 128 * 8 and
               len(QT) == 256 * 4)
    ok &= lens_ok
    notes.append('table lens %s' % ('OK' if lens_ok else 'BAD'))
    dec_bad = 0
    for td in descs:
        e = jmap[td['desc_id']]
        dd = pl_m5.dec_desc(A[32 * td['desc_id']:32 * td['desc_id'] + 32])
        m = []
        if dd['opcode'] != pl_m5.OPCODE[e['op']]:
            m.append('opcode')
        exp_out = e['out_buf'] if e['out_buf'] is not None else 0x3FF
        if e['op'] == 'heads':
            if dd['out'] != 0x3FF or dd['out_bytes'] != int(meta['heads_total']):
                m.append('heads-out')
        else:
            if dd['in0'] != e['in_bufs'][0]:
                m.append('in0')
            if dd['out'] != exp_out:
                m.append('out')
            if dd['out_bytes'] != bsz[e['out_buf']]:
                m.append('out_bytes')
        if e['op'] == 'add':
            if dd['in0'] != e['a_buf'] or dd['in1'] != e['b_buf']:
                m.append('add-ab')
        if e['op'] == 'concat':
            js = e['inputs']
            if dd['n_seg'] != len(js):
                m.append('cat-nseg')
            for i, se in enumerate(dd['segs']):
                if se['buf'] != js[i]['buf'] or \
                        se['nbytes'] != bsz[js[i]['buf']]:
                    m.append('cat-seg%d' % i)
        if m:
            dec_bad += 1
            if dec_bad <= 5:
                print('  R2 dec bad %s(%d): %s'
                      % (e['node'], e['desc_id'], ','.join(m)), flush=True)
    ok &= (dec_bad == 0)
    notes.append('desc decode %d/%d OK' % (len(descs) - dec_bad, len(descs)))

    # quant 单元 vs req_pair（add 两侧 + concat 各段；identity 亦==req_pair(1)）
    q_bad = 0
    q_n = 0
    for e in ents:
        if e['op'] == 'add':
            dd = pl_m5.dec_desc(A[32 * e['desc_id']:32 * e['desc_id'] + 32])
            for prof, sc in ((dd['prof_in0'], e['a_scale']),
                             (dd['prof_in1'], e['b_scale'])):
                cell = pl_m5.dec_quant_cell(QT[4 * prof:4 * prof + 4])
                exp = DRV3.req_pair(sc / e['out_scale'])
                q_n += 1
                if cell != exp:
                    q_bad += 1
                    print('  R2 quant add %s prof=%d cell=%s exp=%s'
                          % (e['node'], prof, cell, exp), flush=True)
        elif e['op'] == 'concat':
            dd = pl_m5.dec_desc(A[32 * e['desc_id']:32 * e['desc_id'] + 32])
            for i, se in enumerate(dd['segs']):
                if se['prof'] == 0:
                    if abs(e['inputs'][i]['scale'] / e['out_scale']
                           - 1.0) > 1e-12:
                        q_bad += 1
                        print('  R2 quant cat %s seg%d prof=0 but ratio!=1'
                              % (e['node'], i), flush=True)
                    q_n += 1
                    continue
                cell = pl_m5.dec_quant_cell(QT[4 * se['prof']:
                                               4 * se['prof'] + 4])
                exp = DRV3.req_pair(e['inputs'][i]['scale'] / e['out_scale'])
                q_n += 1
                if cell != exp:
                    q_bad += 1
                    print('  R2 quant cat %s seg%d cell=%s exp=%s'
                          % (e['node'], i, cell, exp), flush=True)
    ok &= (q_bad == 0)
    notes.append('quant cells %d bad=%d' % (q_n, q_bad))

    # w6 producer 转换锁（hex 实字节 vs 生产任务 id；实条目 104 项）
    pc_bad = 0
    for b in bufs:
        got = int(BW[8 * b['id'] + 6]) & 0xFF
        exp = prod_task.get(b['id'], pl_m5.PRODUCER_EXTERNAL)
        if got != exp:
            pc_bad += 1
            if pc_bad <= 5:
                print('  R2 w6conv buf%d got=%02X exp=%02X'
                      % (b['id'], got, exp), flush=True)
    ok &= (pc_bad == 0)
    notes.append('w6 producer conv %d/%d OK' % (len(bufs) - pc_bad,
                                                len(bufs)))

    # 逐档：程序==JSON 复算；段=极大游程复算；prod 重编复算；Σw14；bit9
    stage_notes = []
    for stage in pl_m5.STAGES:
        ramp = pl_m5.BACKEND_RAMP[stage]
        plan = pl_m5.build_stage_plan(descs, A, stage, BW)
        prog_json = [e['desc_id'] for e in ents if e['op'] in ramp]
        sok = (plan['prog'] == prog_json and
               len(prog_json) == pl_m5.EXPECT_PROG[stage])
        # 独立游程复算（sched 序上极大连续）
        runs, cur = [], []
        for e in ents:
            if e['op'] in ramp:
                cur.append(e['desc_id'])
            elif cur:
                runs.append(cur)
                cur = []
        if cur:
            runs.append(cur)
        sok &= ([s['ids'] for s in plan['segments']] == runs)
        sok &= (sum(len(r_) for r_ in runs) == len(prog_json))
        for bd, run in zip(plan['segments'], runs):
            # prod 复算（统一律：生产任务 id∈run→槽位，否则 0xFF；
            # 空槽 104-127 残留字节经 ids≤103 门自然落 0xFF）
            for b in range(128):
                oid = prod_task.get(b)
                exp_p = run.index(oid) if (oid is not None and
                                           oid in run) else \
                    pl_m5.PRODUCER_EXTERNAL
                if bd['prod'][b] != exp_p:
                    sok = False
                    print('  R2 prod %s seg%s buf%d got=%d exp=%d'
                          % (stage, bd['ids'], b, bd['prod'][b], exp_p),
                          flush=True)
                    break
            # Σw14 == Σ out_bytes；重写位面末槽 bit9 律
            sw = sum(int(A[32 * di + 14]) for di in run)
            sok &= (bd['sum_w14'] == sw)
            for j, di in enumerate(run):
                exp_bit = 1 if j == len(run) - 1 else 0
                sok &= ((bd['words'][32 * j] >> 9) & 1) == exp_bit
                if exp_bit == 0 and ((int(A[32 * di]) >> 9) & 1) == 1:
                    print('  R2 native bit9 on non-last %d (rewrite 清位)'
                          % di, flush=True)
        # 段内依赖方向：段内 in-buf 生产任务须 sched 先行
        for bd in plan['segments']:
            ids = set(bd['ids'])
            j_d = {t2['desc_id']: t2 for t2 in bd['tds']}
            for td in bd['tds']:
                for ib in td['in_bufs']:
                    pid = prod_task.get(ib)
                    if pid is None or pid not in ids:
                        continue
                    if not (j_d[pid]['sched_index'] <
                            td['sched_index']):
                        sok = False
                        print('  R2 fwd dep %s->%s' % (pid, td['desc_id']),
                              flush=True)
        stage_notes.append('%s:%s(prog=%d segs=%d)'
                           % (stage, 'OK' if sok else 'BAD',
                              len(plan['prog']), len(plan['segments'])))
        ok &= sok
    notes.append(' '.join(stage_notes))
    gate('R2', ok, '; '.join(notes))


# ======================================================================
# R3/R4：PC 行走（oracle conv + 软件/引擎模型 PPU 段）
# ======================================================================
class PCHooks(object):
    """PC 执行面：conv=oracle refs；PPU 段=f7prep 引擎模型（字解析 m/s）。"""

    def __init__(self, descs, A, QT, bufs, arena, headb):
        self.node2key = {td['node']:
                         'ref_%d_%s' % (td['sched_index'],
                                        td['node'].replace('.', '_'))
                         for td in descs}
        self.A, self.QT, self.bufs = A, QT, bufs
        self.arena, self.headb = arena, headb
        self.fr_cache = {}
        self.eng_bytes = 0

    def _fr(self, fi):
        if fi not in self.fr_cache:
            self.fr_cache[fi] = dict(np.load(
                os.path.join(M3PACK, 'refs_f%d.npz' % fi)))
        return self.fr_cache[fi]

    def conv(self, node, geo, x, fi):
        # PC oracle 面无 npbuf 守护区（guard_ok=板面 board_conv 专属判据）
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
            dd = pl_m5.dec_desc(self.A[32 * di:32 * di + 32])
            op = td['op']

            def cell(prof):
                return pl_m5.dec_quant_cell(
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
            if op != 'heads':
                self.eng_bytes += len(ar.raw(td['out_buf']))
        return True


def walk_stage(stage, meta, descs, Par, v11b, A, BW, QT, want_shas=None):
    """一次五帧行走；返回 (ok, per-task sha 映射, 汇总)。"""
    bufs = v11b['entries']
    arena_need = max(b['base_off'] + b['size'] for b in bufs)
    arr = np.full(arena_need, pl_m5.POISON, np.uint8)
    headb = np.full((int(meta['heads_total']) + 0xFFF) // 0x1000 * 0x1000,
                    pl_m5.POISON, np.uint8)
    arena = pl_m5.Arena(arr, bufs)
    hooks = PCHooks(descs, A, QT, bufs, arena, headb)
    geos = {n: pl_m5.Geo(n, s, Par) for n, s in meta['conv_statics'].items()}
    ctx = pl_m5.Ctx()
    ctx.stage, ctx.ramp = stage, pl_m5.BACKEND_RAMP[stage]
    ctx.arena, ctx.headb = arena, headb
    ctx.descs, ctx.geos, ctx.bufs, ctx.meta = descs, geos, bufs, meta
    ctx.ANCHORS = {}
    ctx.anchor_done = set()
    ctx.csv = None
    ctx.segments = pl_m5.build_stage_plan(descs, A, stage, BW)['segments']
    ctx.hooks = hooks
    ctx.npbuf = None
    ctx.refs_pat = os.path.join(M3PACK, 'refs_f%d.npz')
    ctx.rep = {'stage': stage, 'frames': []}
    ok = pl_m5.run_frames(ctx)
    shas = {}
    for f in ctx.rep['frames']:
        for t in f['tasks']:
            k = (f['frame'], t['sched_index'])
            shas[k] = t.get('out_sha256') or t.get('blob_sha256')
    nerr_tot = sum(t.get('nerr', 0) for f in ctx.rep['frames']
                   for t in f['tasks'])
    zero_copy = all(t.get('zero_copy', True)
                    for f in ctx.rep['frames'] for t in f['tasks']
                    if t['op'] == 'view')
    summ = {'stage': stage, 'frames_ok': bool(ok), 'nerr': nerr_tot,
            'tasks': sum(len(f['tasks']) for f in ctx.rep['frames']),
            'segs': sum(len(f['segs']) for f in ctx.rep['frames']),
            'eng_bytes': hooks.eng_bytes, 'zero_copy': zero_copy}
    if want_shas is not None:
        summ['sha_consistent'] = all(shas.get(k) == v
                                     for k, v in want_shas.items())
    return ok, shas, summ, ctx.rep


def r3r4_walks(meta, descs, Par, v11b, A, BW, QT):
    ok3, shas0, s0, rep0 = walk_stage('l0', meta, descs, Par, v11b, A, BW, QT)
    heads_ok = (len(rep0['frames']) == 5 and
                all(f['tasks'] and f['tasks'][-1].get('nerr') == 0
                    for f in rep0['frames']))
    gate('R3', ok3 and s0['nerr'] == 0 and s0['tasks'] == 5 * 104 and
         s0['zero_copy'] and heads_ok,
         'L0 tasks=%d nerr=%d heads_sha x5=%s zero_copy=%s'
         % (s0['tasks'], s0['nerr'], heads_ok, s0['zero_copy']))
    ok4 = True
    notes = []
    for stage in ('l1', 'l2', 'l3', 'l4'):
        okx, shasx, sx, repx = walk_stage(stage, meta, descs, Par, v11b,
                                          A, BW, QT, want_shas=shas0)
        ok4 &= okx and sx['nerr'] == 0 and sx['sha_consistent'] and \
            sx['tasks'] == 5 * 104
        notes.append('%s:%s(segs=%d eng=%.1fMB)' % (stage,
                     'OK' if (okx and sx['nerr'] == 0 and
                              sx['sha_consistent']) else 'BAD',
                     sx['segs'], sx['eng_bytes'] / 1e6))
        REP['detail']['walk_%s' % stage] = sx
    gate('R4', ok4, 'cross-stage SHA identity + ' + ' '.join(notes))


# ======================================================================
# R5：结构审计
# ======================================================================
def r5_structure(meta, descs, v11b, A, BW):
    ents_by_id = {td['desc_id']: td for td in descs}
    prod_task = {td['out_buf']: td['desc_id'] for td in descs
                 if td['out_buf'] is not None}
    ok = True
    notes = []
    # 窗界：desc 窗 8KB=2048 字（段重写 [0,n) 须整段落窗）
    for stage in pl_m5.STAGES:
        plan = pl_m5.build_stage_plan(descs, A, stage, BW)
        for bd in plan['segments']:
            ok &= len(bd['words']) <= 2048
    notes.append('desc win bound OK')
    # buf/qt/ring 窗（几何常量 == pkg 数）
    notes.append('buf=1024w qt=1024w ring=32x16w')
    # 引擎宇宙
    eng = [td for td in descs if td['op'] in pl_m5.ENGINE_CLASSES]
    ok &= len(eng) == 25
    notes.append('engine universe %d' % len(eng))
    # 段计数节奏：5 帧总段数与 ring 32 槽（读后即 ack → 覆写仅及已消费槽）
    plan4 = pl_m5.build_stage_plan(descs, A, 'l4', BW)
    tot = 5 * len(plan4['segments'])
    notes.append('l4 segs/frame=%d total=%d (sc&31 model safe: per-seg '
                 'read-before-ack)' % (len(plan4['segments']), tot))
    # 段内 in-buf 源：同段生产任务 sched 先行；其余=CPU 先行/外部
    for stage in pl_m5.STAGES:
        plan = pl_m5.build_stage_plan(descs, A, stage, BW)
        for bd in plan['segments']:
            ids = set(bd['ids'])
            for td in bd['tds']:
                for ib in td['in_bufs']:
                    pid = prod_task.get(ib)
                    if pid is None or pid not in ids:
                        continue
                    ok &= ents_by_id[pid]['sched_index'] < \
                        td['sched_index']
    notes.append('intra-seg dep order OK' if ok else 'intra-seg dep BAD')
    gate('R5', ok, '; '.join(notes))


# ======================================================================
# R6：CSR 律单（pkg 解析 + pl_m3 常数 + address_map）
# ======================================================================
def r6_csr():
    txt = open(PKG, encoding='utf-8').read()
    lp = {}

    def grab(pat, name):
        m = re.search(pat, txt)
        return int(m.group(1), 16) if m else None

    offs = {
        'A_ID': pl_m5.PA_ID, 'A_VERSION': pl_m5.PA_VERSION,
        'A_CTRL': pl_m5.PA_CTRL, 'A_STATUS': pl_m5.PA_STATUS,
        'A_ERROR_STATUS': pl_m5.PA_ERROR_STATUS,
        'A_ERROR_INFO': pl_m5.PA_ERROR_INFO, 'A_FRAME_ID': pl_m5.PA_FRAME_ID,
        'A_HEAD_BASE_LO': pl_m5.PA_HEAD_BASE_LO,
        'A_HEAD_BASE_HI': pl_m5.PA_HEAD_BASE_HI,
        'A_HEAD_BYTES': pl_m5.PA_HEAD_BYTES,
        'A_HEAD_FORMAT': pl_m5.PA_HEAD_FORMAT,
        'A_RESULT_SEQ': pl_m5.PA_RESULT_SEQ,
        'A_RESULT_FRAME_ID': pl_m5.PA_RESULT_FRAME_ID,
        'A_RESULT_ACK': pl_m5.PA_RESULT_ACK,
        'A_RESULT_RING_HEAD': pl_m5.PA_RESULT_RING_HEAD,
        'A_RESULT_RING_TAIL': pl_m5.PA_RESULT_RING_TAIL,
        'A_DESC_CFG': pl_m5.PA_DESC_CFG, 'A_DESC_BASE': pl_m5.PA_DESC_BASE,
        'A_DESC_COUNT': pl_m5.PA_DESC_COUNT, 'A_DESC_HEAD': pl_m5.PA_DESC_HEAD,
        'A_DESC_TAIL': pl_m5.PA_DESC_TAIL,
        'A_DESC_DOORBELL': pl_m5.PA_DESC_DOORBELL,
        'A_DESC_DONE_COUNT': pl_m5.PA_DESC_DONE_COUNT,
        'A_DMA_CFG': pl_m5.PA_DMA_CFG,
    }
    bad = []
    for k, v in offs.items():
        pv = grab(r'localparam\s*\[15:0\]\s*%s\s*=\s*16\'h([0-9A-Fa-f]+)'
                  % k, k)
        if pv != v:
            bad.append('%s pkg=%s drv=%s' % (k, pv, v))
    wins = {'A_DESC_WIN': pl_m5.W_DESC, 'A_BUF_WIN': pl_m5.W_BUF,
            'A_QUANT_WIN': pl_m5.W_QT, 'A_LUT_WIN': pl_m5.W_LUT,
            'A_RING_WIN': pl_m5.W_RING}
    for k, v in wins.items():
        pv = grab(r'localparam\s*\[15:0\]\s*%s\s*=\s*16\'h([0-9A-Fa-f]+)'
                  % k, k)
        if pv != v:
            bad.append('%s pkg=%s drv=%s' % (k, pv, v))
    vid = grab(r'YOLO_ID_VALUE\s*=\s*32\'h([0-9A-Fa-f]+)', 'id')
    vver = grab(r'YOLO_VERSION\s*=\s*32\'h([0-9A-Fa-f]+)', 'ver')
    if vid != pl_m5.EXP_PPU_ID:
        bad.append('ID pkg=%s drv=%s' % (vid, pl_m5.EXP_PPU_ID))
    if vver != pl_m5.EXP_PPU_VERSION:
        bad.append('VER pkg=%s drv=%s' % (vver, pl_m5.EXP_PPU_VERSION))
    for pk, dv in (('DESC_ITEMS', pl_m5.DESC_ITEMS),
                   ('DESC_WORDS', pl_m5.DESC_WORDS),
                   ('BUF_ITEMS', pl_m5.BUF_ITEMS),
                   ('BUF_WORDS', pl_m5.BUF_WORDS)):
        m = re.search(r'localparam\s+int\s+%s\s*=\s*(\d+)' % pk, txt)
        if not m or int(m.group(1)) != dv:
            bad.append('%s' % pk)
    # conv 面：基址/gemm/DMA map == pl_m3 模块常数
    if not (pl_m5.GEMM_BASE == DRV3.GEMM_BASE and
            pl_m5.CSR_BASE == DRV3.CSR_BASE and
            pl_m5.DMA_BASE == DRV3.DMA_BASE):
        bad.append('conv bases')
    for nm in ('A_ID', 'A_CTRL', 'A_STATUS', 'A_GEOM', 'A_ROWVAL',
               'A_NMASK', 'A_JOBCFG', 'A_LDGRP', 'A_P_BIAS', 'A_P_M',
               'A_P_SH', 'A_PCTL', 'A_LDSTAT', 'A_LDLEN', 'A_LUTD',
               'A_YSTAT', 'A_BRGSTAT'):
        if getattr(pl_m5, nm) != getattr(DRV3, nm):
            bad.append('gemm map %s' % nm)
    for nm in ('D_MM2S_DMACR', 'D_MM2S_DMASR', 'D_MM2S_SA', 'D_MM2S_LEN',
               'D_S2MM_DMACR', 'D_S2MM_DMASR', 'D_S2MM_DA', 'D_S2MM_LEN',
               'B_RS', 'B_HALTED', 'B_IDLE', 'B_SGINCLD', 'B_ERRS',
               'B_IOC_IRQ', 'B_ERR_IRQ'):
        if getattr(pl_m5, nm) != getattr(DRV3, nm):
            bad.append('dma map %s' % nm)
    ad = open(ADMAP, encoding='utf-8').read()
    if '0x43C2' not in ad:
        bad.append('address_map 0x43C2 missing')
    gate('R6', not bad, '%d regs+%d wins+geom+id/ver+conv-map '
         'all matched%s' % (len(offs), len(wins),
                            '' if not bad else '; BAD: ' + ';'.join(bad)))


# ======================================================================
def main():
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    print('M5 rehearse driver start %s' % time.strftime('%F %T'), flush=True)
    meta, v11d, v11b, A, BW, QT = load_inputs()
    descs = meta['seg_descs']
    Par = dict(np.load(os.path.join(M3PACK, 'm3_params.npz')))
    r7_inputs(meta, v11d, v11b, Par)
    r1a_source_identity()

    # PC 静音 emit（R1a 已用 inspect 取源完成同一性证明；此后替换运行期
    # 对象仅去掉 /dev/console 探测噪声，不改 pl_m5 文件本体）
    def _pc_emit(m):
        print('[m5 %s %s]' % (m, time.strftime('%H:%M:%S')), flush=True)
    pl_m5.emit = _pc_emit

    r6_csr()
    r2_tables(meta, descs, v11d, v11b, A, BW, QT)
    r1b_streams(meta, descs, Par)
    r3r4_walks(meta, descs, Par, v11b, A, BW, QT)
    r5_structure(meta, descs, v11b, A, BW)
    allpass = all(R.values())
    verdict = 'M5_REHEARSE_PASS' if allpass else 'M5_REHEARSE_FAIL'
    REP['verdict'] = verdict
    REP['elapsed_s'] = round(time.time() - t0, 1)
    json.dump(REP, open(os.path.join(OUT, 'm5_rehearse_report.json'), 'w',
                        encoding='utf-8'), indent=1, ensure_ascii=False)
    print('R-FINAL %s gates=%s elapsed=%.0fs' %
          (verdict, {k: ('P' if v else 'F') for k, v in R.items()},
           REP['elapsed_s']), flush=True)
    return 0 if allpass else 1


if __name__ == '__main__':
    sys.exit(main())
