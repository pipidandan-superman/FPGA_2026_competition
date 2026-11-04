# AC1 C-leg 分段 sim 门 result.md（2026-10-24_cleg_sim_run01）

- 日期：2026-10-24 ｜ 执行：competition-75 主会话放飞的执行代理 ｜ 核验：competition-b6（R92 裁 C 腿=分段 sim 门、与 seg3 无前置、现在起跑；R92 回执锐化令并入判据③）
- 案：AC1 集成 bit C 腿验收（bit 转正双闸之 C）。电池=编译门 16/16 + stage1 冒烟 + 段级门（r12 shadow 全图 TB，分段+checkpoint 律）；golden63 全图门已 R80 退役出放行电池，与 seg3 无前置关系。
- 树/程序口径：merged RTL（filelist=golden63 `files_golden63_r11.f`，S1/S3 在案清单，86 件全在）+ 当前程序头 `tb_setup.mem` sha256 `52aa2bf7ee81ed07…`（R83 S3 修复后形态，生成器 abc77038；从 `scdone_s3_fix_run01\work\r11` 逐字节复制复用，复制后复验 sha）。
- 验收锚（前合并基线）：`2026-10-24_golden63_p0_premeerge_run01`（7 件回退树、原程序 ae9e7c24）——seg1-4 逐 doorbell 字节账、db5 冻结族、golden63 r11 EARLY_ERR 终态字段。
- 判据=回归自由（merged RTL ≡ 前合并基线），不是全图变绿（b6 R92）；seg3/db5 冻结=既存病（R79/R92 判程序/生成器层，RTL/刀无辜），非回归判据。

## 终判行

```
AC1_C_LEG PASS —— 编译门16/16+stage1冒烟+段级门全过: seg1-4字节账8/8与前合并基线逐字节同(24448/48192/68320/109664), A<->B确定性checkpoint链逐字一致, db5冻结族R92全字段钉拍10/10同族(st=23/blk=2/pdone=0/sc-dn=0+err=07 prog=2 yb=109824), RTL零改动sha实证(37/37), 纪律全守
```

## 六判据逐项

| # | 判据 | 结果 | 证据 |
|---|---|---|---|
| ① | 编译门：shadow 清单全件 xvlog/xelab ERROR=0 + BMG 横幅 16/16（S1/S3 在案清单口径） | **PASS** | `logs/banner_compile.txt`（got=16 expect=16 ERRORs=0）、`work/r11/compile.log`；filelist/define 与 golden63 `files_golden63_r11.f` 逐字一致（只读引用）；程序复制后 sha 复验 52aa2bf7… | 
| ② | stage1 冒烟（套件原生冒烟件与标准） | **PASS** | `logs/stage1_smoke.log`：`TB_R12_G5_STAGE1_OK errors=0` + `G5CAP0 cap0=4d390240` 对中（与 golden63 冒烟同标准） |
| ③ | 段级门：seg1-4 逐 doorbell 字节账与前合并基线逐字节同 + seg3/db5 冻结族 R92 全字段同族 | **PASS** | seg1-4：yb/m2w/aw/w/b + expect 8/8 项逐字节同（`seg_a_ledger_compare.txt`）；A↔B checkpoint diff 空=逐字一致（确定性链在跑内复验）；db5 冻结族 10/10 字段同族、签名字段 9/9 逐字节同（`seg_b_sig_compare.txt`、`seg_b_freeze_family.txt`） |
| ④ | 纪律：RTL/TB 零改动、golden63 原锚不动、git/板卡/2_fpga/13_final 零接触、xsim 后台+看守+心跳 | **PASS** | RTL：`filelist_sha256_precheck.txt` 86 件全在、37/37 重叠件与 post-merge manifest（10-23 21:48）sha 全同（0 mismatch）；TB=golden63 r11 正典 11d10d58… 只读引用、零新探针；原锚 ae9e7c24… 未接触；git/板卡/2_fpga/13_final 全程零接触；A/B 双段后台+看守+心跳在案，进程 rc=0 自退零孤儿 |
| ⑤ | 分段律：分段+checkpoint，进程死亡≠FAIL≠PASS | **PASS（含实案执行）** | 分段 A：G5_SETUP_MAXW=1733（TB 自带钩子）干净截断 pi=1734/cyc=14901710；分段 B：确定性重启、穿越 32-35M 死亡区直抵 64.9M err=07 实火、引擎未死；**attempt1 于 cyc=458,752 被兄弟 run（s4_trace）看守退火全局 taskkill 谋杀**——按律定性进程死亡≠FAIL≠PASS、现场保全、看守硬化（守卫杀）后原样重跑成功（`logs/incident_attempt1_killed.txt` + `run_cleg_b_attempt1_killed.log`） |
| ⑥ | 回归自由判据：merged RTL ≡ 前合并基线（非全图变绿） | **PASS** | 全部签名面（字节账/冻结族/计数器族/终态字段）零偏离；唯一程序侧差（desc 2 封顶→5/10/14/20 闭合）= 已批准 R83 S3 修复（b6 R88/R92 判必要且充分），非 RTL 回归 |

## 关键事实链

- seg1-4 字节账（C-leg A，vs P0 前合并基线）：db1 24448/3056、db2 48192/6024、db3 68320/8540、db4 109664/13708（yb/m2w/aw/w/b 全字段）+ expect 1868800/2112000/2291200/2700800——8/8 逐字节同；与 R83 S3 run 的 seg A 连 cyc/span 都逐字相同（3114277/9241834/11845196/14901682）。
- desc 面：本 run db1-4 无 desc FAIL 行（5/10/14/20 闭合，S3 修复形态）；基线 desc_done=2 封顶=修复前同一既存病的程序面 manifestation——判据面是字节账+RTL 签名，程序修复面不构成回归。
- db5 冻结族（b6 R92 回执锐化令全字段钉拍）：冻结入口 st 22->23（cyc=14906845，基线 13149412 同族异时=程序时序）、blk=2、pdone=0、sc dn=0（入口与 23->26 收尸线双双=0）、冻结带 G5ST 逐字同、计数器族 m0ar/m1ar=488018/411692 排空对称、FINE ck=26/xk=27、WRD hit=cap=411692 + ha/pa/wb=02181d7e/10c0ec50/10c0eb80 全逐字同；看门狗 err=07 终态 `EARLY_ERR cyc=64906103 err=07 prog=2 yb=109824` 与基线字段逐字节同（cyc=各自冻结起点+50M TIMEOUT，程序时序依赖）。
- 跨 run 确定性：EARLY_ERR 行与 R83 S3 run seg B 逐字相同（含 cyc=64906103）——同树同程序跨 run 确定链第三次复现。
- xsim 死亡区：本次 seg B 全程推进 2M→64.9M cyc 无引擎死亡（死亡区未发作，与 S3 run seg B 同）；谋杀事件为进程级外部击杀，已归工具链面（台账新条目）。

## 事故与处置（attempt1 谋杀案）

- 事实：attempt1（14:37:42 起跑）于 14:38:52、cyc=458,752 被 `2026-10-24_scdone_s4_trace_run01` 的 run_s4.sh 看守退火全局 `taskkill //F //IM xsimk.exe/xsim.exe` 谋杀（对方 verdict 落盘秒=我方死亡秒，逐秒对齐）；日志零错误零终态戛然而止。
- 定性：进程死亡≠FAIL≠PASS（分段律）；非 DUT/RTL/TB 事件；run 无效原样重跑。
- 处置：被杀现场改名 attempt1 保全；看守脚本改守卫杀（仅进程仍在才 taskkill）；attempt2 全程干净 rc=0 自退。
- 台账：新变体条目 vivado-sim [2026-10-24]「兄弟 run 看守退火全局 taskkill 谋杀在飞 xsim」三副本同批同步（1_docs≡6_skill 逐字节同 47116b66…，.claude 副本并集一致），同族原条 [2026-10-18] toolchain 复发 3→4 双向互链。

## 证据索引

| 件 | 路径（本 run 内） |
|---|---|
| 编译门 | `logs/banner_compile.txt`、`work/r11/compile.log` |
| stage1 冒烟 | `logs/stage1_smoke.log`、`logs/stage1_smoke.tail.txt` |
| 分段 A 日志/裁决/心跳 | `logs/run_cleg_a.log`、`run_cleg_a.verdict.txt`、`heartbeat_a.log` |
| 分段 B 日志/裁决/心跳 | `logs/run_cleg_b.log`、`run_cleg_b.verdict.txt`、`heartbeat_b.log` |
| attempt1 谋杀现场 | `logs/run_cleg_b_attempt1_killed.log`、`run_cleg_b_attempt1_killed.verdict.txt`、`logs/incident_attempt1_killed.txt` |
| seg1-4 字节账对拍 | `seg_a_ledger_compare.txt` |
| db5 冻结族全字段对拍 | `seg_b_sig_compare.txt`、`seg_b_freeze_family.txt` |
| RTL 零改动 sha 实证 | `filelist_sha256_precheck.txt`（86 件全在；37/37 vs post-merge manifest 0 mismatch） |
| 基线引用件 | `baseline_ref_p0.txt` |
| 程序头 | `work/r11/evidence/tb_setup.mem`（52aa2bf7…）+ `plan_hex/`（12 件，从 S3 fix run 复用） |
| 脚本链 | `scripts/compile_cleg.sh`、`stage1_smoke.sh`、`run_cleg_a.sh`、`run_cleg_b.sh`、`xsim_cleg_a.opt`、`xsim_cleg_b.opt`、`xsim_stage1.opt`、`runall_cleg.tcl` |
| sha 全件清单 | `sha256_manifest.txt` |

## 移交

- `result_marker_acceptance_c.txt`（候选销项留痕）：**最终销项须 b6 亲验**。
- C 腿全过 → 按 b6 R80/R92 口径 bit 转正（A 腿已 R89 销）由主会话/b6 执行，本代理不越权。
