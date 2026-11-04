# build/：构建、部署与验证

本目录提供 Vivado 2025.2 可复现入口、部署树生成、板端运输和验证脚本，并保存历史综合/实现报告快照。工程源位于 `board/<form>/vivado_project/`。所有构建和证据输出必须放在仓库之外的全新目录。

## 当前验证矩阵

| 形态 | 包内预检 | Vivado 工程验证 | 完整 BIT/XSA 重建 | 部署树 |
|---|---|---|---|---|
| `form1a_pl_preprocess` | 通过 | `PACKAGE_PROJECT_VALIDATION_PASS` | 未执行 | 按历史说明手动整理 |
| `form1a_ble_bridge_j5` | 通过 | `PACKAGE_PROJECT_VALIDATION_PASS` | 未执行 | 候选流程，未做现役板验 |
| `accelerator_ac1` | 通过 | `PACKAGE_PROJECT_VALIDATION_PASS` | 未执行；历史报告保留 | 按 AC1 专用流程 |
| `form1b_multitask_osd` | 通过 | 已由完整构建覆盖 | 通过，WNS/WHS +0.153/+0.010 ns | 53 文件，离线通过 |
| `form2_pl_continuous` | 通过 | `PACKAGE_PROJECT_VALIDATION_PASS` | 最近一次完整尝试失败，保留日志；历史报告保留 | 109 文件，离线通过 |
| `form3_pspl_resident` | 通过 | 已由完整构建覆盖 | 通过，WNS/WHS +0.030/+0.017 ns | 120 文件，离线通过 |

历史报告位于 `accelerator_ac1/`、`form1b_multitask_osd/`、`form2_pl_continuous/`、`form3_pspl_resident/`。它们对应历史 BIT，不自动描述本次重建制品。形态三历史 72b358ff 位流为 WNS/WHS +0.255/+0.020 ns；形态一B历史资源为 placed 报告，其他形态按各报告阶段解读。

## 1. 构建

```powershell
python build/prepare_build.py --form form3_pspl_resident --output C:/fpga_runs/<new_run> --stage bitstream
vivado -mode batch -source C:/fpga_runs/<new_run>/run.tcl -log C:/fpga_runs/<new_run>/vivado.log -journal C:/fpga_runs/<new_run>/vivado.jou
```

`--stage validate` 只创建工程、检查模块引用、打开并验证 BD、输出 IP 状态，不运行综合/实现。`--stage bitstream` 还生成 BIT/XSA，并检查：

- `synth_1` 与 `impl_1` 均为 100%；
- 无未解析黑盒；
- 已定义时序约束下 max/min 裕量非负；
- DRC 无 Error；
- 最终出现 `PACKAGE_BITSTREAM_BUILD_COMPLETE` 和 `VITA_VIVADO_RESULT PASS`。

进程退出码为零不能替代这些检查。未约束 I/O、CDC 和时钟关系告警仍需人工分析。新 BIT 与历史 BIT 分开管理，不机械要求重建哈希相同。

AC1 的 `module_ref` XCI 是 BD 接口合同，构建器会保留；普通厂商 IP 输出则在隔离目录重新生成。不要删除这类模块引用配置。

## 2. OSD 仿真

```powershell
python build/verify_osd.py --vivado-home F:/vivado2025/2025.2/Vivado --output C:/fpga_runs/<new_sim>
```

必须依次通过 `SIMULATOR_SMOKE_PASS`、`COCO_OSD_ALL_PASS`、`POSE_OSD_ALL_PASS` 和负控 `POSE_FONT_PIXEL_FAIL`，总标记为 `OSD_REGRESSION_PASS`。

## 3. 部署树

```powershell
python build/stage_submission.py --form form2_pl_continuous --output C:/fpga_runs/<new_stage> --remote-root /home/xilinx/amd_submission/<new_version>
```

支持 `form1b_multitask_osd`、`form2_pl_continuous`、`form3_pspl_resident`。默认无网络动作；`--upload` 才执行 SSH 空间检查、全新目录上传和 SHA-256 校验。不会停止服务、加载 Overlay 或启动工作负载。

## 4. 板端验证

形态二固定输入：

```powershell
python build/board_transport.py --script build/verify_form2.py --script-arg /home/xilinx/amd_submission/<new_version> --output C:/fpga_runs/<new_test> --sudo --timeout 420
```

成功门为 `FORM2_FIXED_INPUT_CHECK_PASS`、`C3 SUMMARY 21/21 planes match`，并恢复原摄像头流，最终结果 `FORM2_FIXED_INPUT_AND_RESTORE_PASS`。该入口已做语法和部署树核验，尚未实际板测。

形态三使用 `verify_form3.py`；其 `--gestures` 模式还要求完整严格序列。任何板测都须先取得现场授权，并遵守 `skill/zynq-pynq-overlay-workflow/SKILL.md` 的所有权、DMA 停止和恢复门。超时后远端状态未知，不能按成功处理；应先用只读预检确认状态，再决定恢复动作。

## 5. 历史脚本边界

含 `RETIRED_ENTRY` 的 Shell 文件仅作历史留档，会主动退出。不得删除该标记后继续用于新部署。历史路径、运行日志和报告中的作者工作区只用于溯源，不是本包的执行依赖。
