# 形态二：纯 PL 连续推理

本目录包含「OV5640 采集 → PS 输入变换 → YOLOv8n 完整 PL 网络计算 → PS decode/NMS 与 JSON → HDMI OSD」连续运行版本，以及固定输入 21/21 黄金参考比对入口。网络主体在 PL，PS 仍负责归一化、量化、装载控制、解码/NMS 和结果服务。

## 实测边界

- 历史连续记录共 **83 帧**，中位 **11023.045 ms**，只覆盖六类，缺 Down；不得描述为七类全部验收通过。
- 当前版本不是实时系统，仍存在背景误检；固定输入计算时间与连续摄像头整机帧时不能混用。
- 历史机械臂单模型链结果不等于本连续推理会话的集成验收。
- 本次已从包内源工程通过 `PACKAGE_PROJECT_VALIDATION_PASS`。最近一次完整 BIT 构建在子 IP 综合阶段失败，故不宣称完整重建通过；历史位流和实现报告保留。

## 核心制品

| 文件 | SHA-256 |
|---|---|
| `sw/board_artifacts/net3_pl_hp_rebalance.bit` | `c1015749f5f6b190fae483cddaeb4dc1d18c300ba752a7cf3a6bd927893957b8` |
| `sw/board_artifacts/display_test.hwh` | `7b0d7c315af715acc11dd08152b36b9106a03958108f80faa9fca07b61ca1873` |
| `prog/tb_setup_d0_s_v1_db4_up2x_meta_quant.txt` | `4b4bfe1d8e4233bd2b71bbcb46792e4081618dfbe4add20abef144649ca5b25f` |
| `prog/layout.json` | `fcf421ceed0f931f251cfb32a2fa0be5019d61b0b0c6b463bb9da212e182fc15` |

## 目录

```text
vivado_project/       源工程与包内依赖
sw/board_artifacts/  历史 BIT/HWH/XSA
sw/board/            连续识别、固定输入比对、驱动、OSD 和 VDMA 脚本
sw/deploy/           包内相对定位的部署入口
prog/                当前程序卷与 layout
logs/                历史连续实测输出
```

共享固定输入和黄金参考位于仓库根目录 `data/gold/`，部署时映射为板端 `gold/`；`src/form2_pl_continuous/descriptor_table.json` 映射为板端 `descriptor_table.json`。

## 构建与部署

```powershell
python build/prepare_build.py --form form2_pl_continuous --output C:/fpga_runs/<new_run> --stage validate
python build/stage_submission.py --form form2_pl_continuous --output C:/fpga_runs/<new_stage> --remote-root /home/xilinx/amd_submission/<new_version>
```

将 `--stage` 改为 `bitstream` 可执行完整构建，但只有全部构建门通过才能标记成功。部署默认只生成文件树，`--upload` 才上传；不会启动硬件。

## 固定输入比对

```powershell
python build/board_transport.py --script build/verify_form2.py --script-arg /home/xilinx/amd_submission/<new_version> --output C:/fpga_runs/<new_test> --sudo --timeout 420
```

`verify_form2.py` 检查部署清单、位流身份、所有权和 VDMA 停止门，随后调用 `sw/board/fixed_input_check.py`。后者加载配对 BIT/HWH，使用 `data/gold` 的固定输入，并要求 `C3 SUMMARY 21/21 planes match`，最后停止 DMA、释放缓冲并恢复原摄像头服务。成功总标记为 `FORM2_FIXED_INPUT_AND_RESTORE_PASS`。

**该入口已完成语法、路径和部署树核验，但尚未实际板测。** 执行前必须取得现场授权；物理 HDMI 仍需人工确认。

## 连续运行

`continuous_gesture.py` 与固定输入运行器均从脚本位置解析部署根目录，不再依赖作者工作区。历史 `launch_continuous.sh` 和 `stop_continuous.sh` 含未复核的所有权逻辑，已标记 `RETIRED_ENTRY`，不得作为新部署入口。连续运行前应使用 overlay skill 核对所有权和 DMA 停止门，并保留 `continuous/results.jsonl` 作为输出证据。

## 软件输入合同

1. 640×480 BGR 直接缩放至 320×320，不使用 letterbox-M。
2. BGR mean/std：mean_milli=`[103530,116280,123675]`，std_milli=`[57375,57120,58395]`。
3. `S_input=0.020787402400820273`，RNE、对称 zp=0、INT8。
4. 每帧记录帧号、耗时、输入/heads SHA、类别、置信度和坐标。
5. 显示质量门为置信度不低于 0.55，并拒绝覆盖超过 90% 画面的异常框；原始结果仍保留。
