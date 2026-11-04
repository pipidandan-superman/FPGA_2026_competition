# sim/：仿真与验证

## 目录

- `accelerator/cleg_r97/`：加速器 CLEG R97 历史回归证据。其 PASS 仅表示与旧基线等价，包含既存冻结故障，不等于全图正确性。
- `form1b_multitask_osd/tb/`：OSD 测试台。
- `form1b_multitask_osd/sim_v2/`、`sim_v3/`：历史正向和故障注入证据。

## 当前复现入口

```powershell
python build/verify_osd.py --vivado-home F:/vivado2025/2025.2/Vivado --output C:/fpga_runs/<new_sim>
```

入口执行 Vivado 2025.2 XSim 的 `xvlog → xelab → xsim`，依次要求：

1. `SIMULATOR_SMOKE_PASS`：证明仿真器真正运行；
2. `COCO_OSD_ALL_PASS`；
3. `POSE_OSD_ALL_PASS`；
4. 负控 `POSE_FONT_PIXEL_FAIL`：历史字体错误版本必须失败，且不能出现正向 PASS。

当前复验结果为 `OSD_REGRESSION_PASS`，原始证据在 `2026-11-04_amd_osd_regression_run02`。

## 测试设计与边界

- 几何期望由原始 `h_cnt/v_cnt` 与规格公式独立推导，不回读 DUT 内部选择寄存器。
- `GLYPH_IDENTITY` 防止测试台与 DUT 同源产生自洽假证。
- 仿真 PASS 不等于完整摄像头/HDMI 板级验收；后者以对应板端日志和现场目检为准。
- 本目录不代表 ModelSim 已执行；当前仿真工具为 XSim。
