# 形态一B：单 BIT 三网络三任务 OSD

本目录包含 NanoDet-Plus COCO 80 类、YOLOv8n 七手势和 YOLO11n-pose 17 点骨架三任务。网络推理由 PS ncnn 执行，PL 负责摄像头采集、显示和 OSD；可通过 PL 按键或 `model_select` 文件热切换任务，无需重新综合或下载位流。

## 历史板测与已知边界

- 历史有效 BIT 为 `c910f8ce…206542`，三网络后端形状检查、任务热切换及 HDMI 目检已有实测。
- v3 修复了 pose 标签几何和手势显示门：pose 标签字符选择使用 `h_cnt>>4`；手势恢复过阈值即显示并保留 hold，拇指类另有 margin 防翻转门。
- OSD 正向测试使用独立几何期望和字模恒等门，历史错误版本作为负控，必须出现 `POSE_FONT_PIXEL_FAIL`。
- NanoDet COCO 模型未经本 OV5640 场景定向重训练，特定物品可能准确率不高或误检；不得宣称识别率或实时性能达标。
- 三任务 PS 推理历史参考约为 COCO 0.9–1.2 s/帧、pose 2.9–3.9 s/帧、手势约 1.05 s/帧，测量条件以原始日志为准。
- 三网版蓝牙整合和机械臂动作不属于本目录的现役视觉验收。

## 核心制品

| 文件 | SHA-256 |
|---|---|
| `sw/board_artifacts/multitask_osd.bit` | `c910f8ce502f117577bdfa6ff06450991cec3feb02161993336b25727d206542` |
| `sw/board_artifacts/multitask_osd.hwh` | `3e92e4d5e4dc544c6bb743e663d887559590f6b8771b9d2dfaec07c395d930e7` |
| `sw/board_artifacts/multitask_osd.xsa` | 完整值见根目录 `binary_sha256.txt` |

本次已从包内源码完成 BIT/XSA 重建，WNS/WHS +0.153/+0.010 ns。新制品与历史板验 BIT 分开记录，不自动继承历史板证。

## 目录

```text
vivado_project/       源工程与包内依赖
sw/board_artifacts/  历史 BIT/HWH/XSA
sw/board/            三任务主程序、服务端、模型注册表和运行依赖
sw/deploy/           部署辅助及历史留档
models/              三任务模型与拆分权重
logs/                历史板端输出
```

仿真源与结果集中在仓库根目录 `src/form1b_multitask_osd/` 和 `sim/form1b_multitask_osd/`。

## 构建与仿真

```powershell
python build/prepare_build.py --form form1b_multitask_osd --output C:/fpga_runs/<new_run> --stage bitstream
python build/verify_osd.py --vivado-home F:/vivado2025/2025.2/Vivado --output C:/fpga_runs/<new_sim>
```

完整构建必须出现 `PACKAGE_BITSTREAM_BUILD_COMPLETE` 和 `VITA_VIVADO_RESULT PASS`；仿真必须四项全部通过并得到 `OSD_REGRESSION_PASS`。

## 部署

```powershell
python build/stage_submission.py --form form1b_multitask_osd --output C:/fpga_runs/<new_stage> --remote-root /home/xilinx/amd_submission/<new_version>
```

当前部署树含 53 个文件，已离线生成通过。默认只生成文件，`--upload` 才上传并校验，不启动硬件。

`three_task_main_split.py` 会检查 BIT/HWH 和模型哈希，并在明确启动时下载 Overlay。运行前须保证：

1. 5002 为 `t1_ncnn_server_multi` + `c2_registry.conf`；
2. 5003 为 `t1_ncnn_server_flex` + `pose_registry.conf`；
3. 原摄像头服务和其他硬件所有者已按 overlay skill 停止，VDMA 两路 RS=0 且 Halted=1；
4. 使用与部署目录一致的 `--bit`、模型、注册表和证据路径参数。

历史 `launch_board.sh`、`deploy_fix_run*.sh` 含旧目录或增量修补逻辑，已标记 `RETIRED_ENTRY`，不得直接执行。当前部署树的完整启动与恢复流程尚需独立板测，不能由历史板测或部署树成功推断。

## 修改 BD module_ref 时的注意事项

修改被 BD 引用的 `.v` 或 `$readmemh` 数据后，必须重置相应 OOC 和主构建，确认新数据确实进入 DCP/BIT。字体和标签测试须保持三条纪律：独立字模期望、由原始计数器推导几何期望、删除旧仿真状态后复跑。历史来源路径只作溯源，不是本包依赖。
