# 2026-11-02 multitask_fix_run01 — 三任务 OSD 三缺陷修复（乱码 / 手势延迟 / 空背景误检）

## 任务输入（用户报告）

1. NanoDet(COCO) 与 YOLO11n-pose 文字乱码无数轮修不好；YOLOv8n 文字始终正常。
2. YOLOv8n 手势识别明显慢于 `13_final/net3_ps_only`（做动作后等 1-2 秒）。
3. YOLOv8n 空背景反复误检 TDown / Tup（net3 时代已存在、验证不充分）。

## 根因（三条独立链）

### R1 乱码 = PL 字体奇数行位段错误 + BIT 陈旧模块网表（双因素）

- **RTL 缺陷**: `task_coco_osd.v` / `task_pose_osd.v` 奇数字形行读 `font_q[4'd15-sel_bit]`（bits[15:8]，恒 0），
  应为 `font_q[5'd23-sel_bit]`（bits[23:16]）。osd_font32.hex 打包为 `(even<<24)|(odd<<16)`，bits[15:0]=0，
  所以偶数行（[31:24]）正常、奇数行全灭 → 竖向隔行缺损 = 乱码。YOLOv8n 的 TLBL 路径字体打包不同，故一直正常。
- **BIT 陈旧（乱码"无数轮修不好"的真凶）**: BD module reference 的 OOC 子综合 run
  （`display_test_task_{coco,pose}_osd_0_0_synth_1`）**不追踪被引用 .v 的修改**；reset+rebuild 顶层后
  模块 DCP（22:16:42 产物）被原样复用，link_design 静默链接旧网表。本 run 两次 BIT（23:21、23:36）
  均中招，显式 `reset_run` 两个模块 OOC run 后第三次构建（23:44）DCP 才再生成。
  已沉淀坑账：`1_docs/eng_pitfall_ledger.md` vivado-bd 2026-11-02 条（三副本 SHA 4ea3d484…）。

### R2 手势延迟 = PS 显示链 3 帧连击门

`three_task_main_split.py` 旧逻辑要求同一类别**连续 3 帧**才显示；帧周期 ~1.07s（板端 HEARTBEAT inf_ms
1071-1185ms）→ 额外 2-3 秒延迟。net3 对照（t1_gesture_main.py）为"检出即显示 + hold"，无连击门。

### R3 空背景误检 TDown/TUp = 显示无 margin 门

旧显示门只有 `score >= 0.55`。net3 的动作门是 `per_cls[c] - max(per_cls[rivals]) >= 0.2`（margin 门），
但只用于动作路径不用于显示（用户确认 net3 验证不充分，同缺陷一直潜伏）。

## 修复内容

| 项 | 文件 | 内容 |
|---|---|---|
| RTL 字体位段 | `rtl/task_{coco,pose}_osd.v` + 工程 imports 双份 | `bit_d<=sel_glyph_y[0]?font_q[5'd23-sel_bit]:font_q[5'd31-sel_bit];`（SHA 与工程逐字节一致） |
| RTL 块搬移 | 同上 | 第二个 aclk always 块移至全部声明后（xvlog VRFC 10-3380，-sv 也不豁免；语义零变化，仅为独立可编译） |
| TB 像素级门 | `tb/tb_task_{coco,pose}_osd.v` | 每个 label 像素 bit_d 对照 osd_font32.hex 期望位，奇数行强制覆盖；负向对照（保留 bug 的 RTL）必须真实 FAIL |
| PS 显示链 | `ps/three_task_main_split.py` | 删连击门；net3 对齐"即时显示+hold"；margin 门上显示（--min-margin 0.2）；拇指类 4/5 加严（--thumb-min-margin 0.25 + --thumb-min-score 0.58）；--box-hold 0.3→1.5s；新增 GESTURE_SHOWN/GESTURE_CLEAR 日志事件 |

## 仿真证据（负向对照 + 像素级）

- COCO: `sim/sim_coco_run.log` — COCO_FONT_PIXELS_PASS checks=8840 odd=4488 → COCO_OSD_ALL_PASS
- POSE: `sim_pose/sim_pose_run.log` — POSE_FONT_PIXELS_PASS checks=6415 odd=3200 → POSE_OSD_ALL_PASS
- 负向对照: `sim_negctl/sim_negctl_run.log` — 旧 RTL 首个奇数行像素即 COCO_FONT_PIXEL_MISMATCH 中止（$fatal 带消息形态才真正中止，坑账 vivado-sim 2026-11-02 条）
- 11-01 的 22:13"复验 PASS"为陈旧 xsim.dir 工作库假证据（坑账 vivado-sim 2026-11-02 条）

## BIT 构建（第三次构建 = 有效构建）

- 工程: `2026-11-02_multitask_osd_debug_run01/project_multitask/multitask_osd.xpr`（display_test_wrapper, xc7z020clg484-1）
- 关键动作: `reset_run display_test_task_coco_osd_0_0_synth_1; reset_run display_test_task_pose_osd_0_0_synth_1; reset_run synth_1; reset_run impl_1; launch_runs impl_1 -to_step write_bitstream -jobs 8`
- 模块 DCP 再生成确证: coco 42a5f53f→7b5d464a、pose f328e2c1→6a476db1（mtime 23:39:18/23:39:20 ≥ launch 23:38:26）
- 产物: `candidate/multitask_osd.bit` SHA256 `621e312143ca52507955ef0a70e331ed5138ac4d67725c4b880b8f2d3272ed39`（mtime 23:44:22）
- HWH: BD 结构未变，SHA `3e92e4d5e4dc544c6bb743e663d887559590f6b8771b9d2dfaec07c395d930e7`（与常量一致，未变）
- 时序: cam_pclk WNS +33.247 / WHS +0.076；clk_fpga_0 WNS +6.869 / WHS +0.019（0 违例）
- 作废 BIT（均链接 22:16 陈旧模块 DCP）: 23:21 版 f5f34594…、23:36 版 eac2ab7c…、旧板载 dbf4501c…

## R1b 追加（2026-11-03）：字体表索引基址错 0x20 —— 乱码第三层根因（定罪+修复+已上板）

用户 11-03 反馈：BIT 621e3121 上板后 COCO 标签=「若干 @ 串（名字 8 字符=7 个、7 字符=8 个）+ 末尾两个可读大写字母（"TP"/"RX"）」。

- **根因**: `osd_font32.hex` 生成时从 ASCII 0x20（空格）起连续排槽（`file[k]=glyph(k+0x20)`），RTL 用原始 ASCII `char_code` 直索引 `font_rom[{char_code,…}]` → 基址错 0x20。三重表象逐字吻合：
  - 名字小写 0x61-0x7A → 未定义槽（黑底空白，看似"名字乱码"）；
  - coco80.hex 补位空格 0x20 → glyph(0x40)='@' 槽 → **@ 串**（数量=14-名字长+1）；
  - 分数数字 0x30-0x39 → 'P'-'Y' 槽 → "40"→**"TP"**、"28"→**"RX"**。
- **为什么全链仿真 PASS**: TB 的 `exp_font` 与 DUT 加载同一文件、同一地址公式 → 错位自洽；`check_char` 只验 char_code ASCII 值不验字形身份。综合无警告（`readmemh ... read successfully`，ROM 落 LUT 保组合读，数据正确——错的是索引约定）。
- **修复**: 字表重排 ASCII 直索引（`new[k]=old[k-0x20]`、前 0x20 槽清零），五活动副本 SHA 齐一 `536ce2920f6da325…`（rtl/sim/sim_pose/sim_negctl/工程 imports；**11-01 历史运行目录副本保留旧表**以保全该 run 证据链）；两个 TB 新增 GLYPH_IDENTITY 门（'T'/'0'/'k'/'P' 硬编码字模独立断言）。坑账 rtl 2026-11-03 条（三副本 SHA `f655fff1…`）。
- **复验（v2 仿真）**: COCO `GLYPH_IDENTITY_PASS`+`COCO_FONT_PIXELS_PASS checks=8840 odd=4488`；POSE `GLYPH_IDENTITY_PASS`+`checks=6415 odd=3200`；负向对照（保留行 bug 的 RTL）新表下 `GLYPH_IDENTITY_PASS` 后首奇数行即 `COCO_FONT_PIXEL_MISMATCH code=98 gy=3` 中止。日志：`sim/sim_coco_run_v2_fontbase.log`、`sim_pose/sim_pose_run_v2_fontbase.log`、`sim_negctl/sim_negctl_run_v2_fontbase.log`。
- **v2 构建**（工程不变、仅换 hex；铁律=hex 变更同样不触发 module_ref OOC 失效，显式 reset 四 run）: 模块 DCP 再生成确证 coco `7b5d464a→74a15ee5`、pose `6a476db1→f7fbc6a5`（mtime 08:22:26/27 ≥ launch 08:21:49）。有效 BIT=**`b698378f8e2e79636420b91c0bf8e0b95f02c6163c770bf8c4b34878bd6a7dcd`**（08:26:24，4045696B）；XSA=`f298d3ca947dafa9080fe4b683fc31c7000e83e3d166add61e4fb10ba8b27757`；HWH 不变 `3e92e4d5…`。时序零违例：cam_pclk WNS+34.781/WHS+0.025、clk_fpga_0 +6.182/+0.014。**作废 BIT 追加 621e3121**（乱码仅部分缓解：行修复生效但基座错位仍在）。
- **v2 上板**（`scripts/deploy_fix_run02.sh`）: 板端备份 `multitask_osd.bit.bak_621e3121`/`three_task_main_split.py.bak_v2`；新 BIT+新脚本（`0cc5d2d3…`，仅 BIT_SHA256 常量更新）SHA 复核一致；链 PID 22953、`PL_LOADED bit_sha256=b698378f…`、ENGINE_READY、COCO 实时心跳（tv/chair 检出正常）。
- **待用户 HDMI 目检**: COCO 长标签小写全拼 + 两位分数数字；pose（需人入镜）"P"+两位数字。

## 上板部署（`scripts/deploy_fix_run01.sh`，凭据通道=BOARD_PW→EES331_SSH_PASSWORD→ssh_askpass）

1. SIGTERM 停旧链（PID 3393，处理器正常关 VDMA）→ CHAIN_STOPPED
2. 板端备份 `three_task_main_split.py.bak_streak` / `multitask_osd.bit.bak_dbf4501c`
3. scp 新 BIT(621e3121) + 新脚本 → 板端 sha 复核一致
4. `sudo bash launch_board.sh` 重启链 → PID 10649
5. 门: `PL_LOADED bit_sha256=621e312143ca5250 state=operating` + `ENGINE_READY` + `BOARD_BLOCKS_READY`（见 `board_chain_initial.log`）

## 板上验证

- 修复前基线: `board_pre_fix_baseline.log`（gesture 任务 inf_ms 1071-1185ms，空场景 detections 0）
- 任务切换 0→2→1 全部 MODEL_SELECT 正常（pose 2.86s/帧为 split 引擎已知特性）
- 空背景浸泡（gesture 任务 ≥10 分钟）: 见 `board_soak_gesture.log` — 门 = GESTURE_SHOWN 中 TDown/Tup 计数为 0
- 屏幕文字目检（COCO 长标签 + pose P 分数条）: 需人眼收口，见会话报告

## 文件清单

```
rtl/    task_coco_osd.v  task_pose_osd.v          （修复版 RTL，与工程 imports 逐字节一致）
tb/     tb_task_coco_osd.v  tb_task_pose_osd.v    （像素级字体门 TB）
sim/    sim_*_xvlog/xelab/run.log                 （COCO 正向证据）
sim_pose/                                        （POSE 正向证据）
sim_negctl/ negctl_axi_lite_slave.v negctl_task_coco_osd.v（负向对照：旧 RTL 保留 bug）
ps/     three_task_main_split.py（修复版，BIT_SHA256=621e3121…）+ 全套依赖
candidate/ multitask_osd.bit(621e3121) multitask_osd.hwh(3e92e4d5)
scripts/ deploy_fix_run01.sh
board_pre_fix_baseline.log board_chain_initial.log board_soak_gesture.log
```
