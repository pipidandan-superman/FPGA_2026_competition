# AC1：YOLO GEMM + PPU 集成加速器

本目录保存 AC1 正装位流、XSA、历史资源/时序/DRC 报告、模块引用源工程及 A/C 验证证据。AC1 是加速器计算核心集成形态，不包含完整的 PS 推理服务链。

## 核心制品与历史证据

| 文件 | 说明 |
|---|---|
| `hw/m9_v25_integration.bit` | 历史正装位流，SHA 前缀 `2fa0f2e1`；历史 WNS/WHS +0.111/+0.051 ns |
| `hw/m9_v25_integration.xsa` | 配对硬件平台，PYNQ 使用其 BIT 与 `ip_dict` |
| `hw/reports/` | 历史时序、资源、DRC 和网表指纹 |
| `hw/provenance/` | 历史 RTL 与材料哈希 |
| `sw/ac1_window_open.py` | 历史板窗脚本，含下载、CAP0、岛恒等和时钟门 |
| `vivado_project/` | 当前可复现源工程、BD、模块引用 XCI 和独立 IP 配置 |

历史 A 腿板测与 C 腿分段仿真正式用于该位流转正。C-leg PASS 表示与旧基线等价，包含既存冻结故障，不等于任意整网或任意模型的功能正确性。

## 本次工程验证

- 包内 212 个输入文件纳入隔离副本，209 条活动引用参与工程生成。
- 补回 `m9_sys_shim_0` 与 `m9_sys_roms_0` 两个 `module_ref` XCI，保留 BD 接口边界；普通厂商 IP 输出仍在隔离目录重建。
- Vivado 2025.2 实际结果：`PACKAGE_PROJECT_VALIDATION_PASS` 和 `VITA_VIVADO_RESULT PASS`，证据为 `2026-11-04_amd_ac1_validate_run02`。
- 本次未执行完整 BIT/XSA 重建，历史实现报告不得冒充当前重建结果。

## 构建

```powershell
python build/prepare_build.py --form accelerator_ac1 --output C:/fpga_runs/<new_run> --stage validate
```

将 `--stage` 改为 `bitstream` 可执行完整构建。完整成功须同时满足综合/实现完成、无黑盒、已定义约束时序非负、DRC 无 Error 和最终构建标记。

## 历史板窗流程的边界

`sw/ac1_window_open.py` 使用历史板端 `/home/xilinx/integration_ac1` 目录，并会真实下载 Overlay、修改时钟。它不是无条件执行的主机测试脚本。复现前须：

1. 按实际部署目录调整 XSA 路径并核对 SHA；
2. 按 overlay skill 停止原硬件所有者并证明 VDMA 两路停止；
3. 核对 shim CAP0=`0x4D390230`、岛 A_CAP0=`0x07100404` 与实际硬件合同；
4. 保留原始下载、寄存器、时钟和恢复日志，未获得现场授权不得执行。

完整文件哈希见本目录 `sha256_manifest.txt` 和根目录 `binary_sha256.txt`。
