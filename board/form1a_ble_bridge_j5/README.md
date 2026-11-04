# 形态一A BLE J5 候选工程

本工程保留三网络手势识别、PL 预处理、HDMI OSD 和 SW0 切模型，将蓝牙 UART 接口改为 EES-331 扩展 IO J5 的两线连接。它是开发候选，不是现役机械臂集成验收版本。

## 当前状态

- 历史 Vivado 2025.2 完整综合、布局布线和 BIT 生成通过；器件为 `xc7z020clg484-1`。
- 历史时序为 WNS +7.550 ns、WHS +0.016 ns，DRC 0 Error；实现引脚为 `bt_uart_rxd=V13`、`bt_uart_txd=W13`，均 LVCMOS33。
- 本次从当前包内源工程通过 `PACKAGE_PROJECT_VALIDATION_PASS`，证据为 `2026-11-04_amd_form1a_ble_bridge_j5_validate_run01`。
- 本次未执行完整 BIT 重建；J5 蓝牙收发和机械臂动作未进行本版板测，不能宣称板测 PASS。

## 接线与串口

| 蓝牙模块 | 开发板 | 方向 |
|---|---|---|
| TX | J5 / V13 / `bt_uart_rxd` | 模块 → FPGA |
| RX | J5 / W13 / `bt_uart_txd` | FPGA → 模块 |
| GND | J5 GND | 必须共地 |

串口默认 9600 baud、8N1、无流控。FPGA IO 仅允许 3.3 V TTL，不得接传统 RS-232 正负电压。J5 没有 5 V；带 LDO 的蓝牙底板须按自身规格独立供电，不能把 3.3 V 加到其 LDO 输入。

## 控制链

```text
相机 → PL 预处理 → PS 三网络手势推理与动作策略
     → PS MMIO（ble_uart_0 @ 0x43C10000）
     → PL UART TX/RX → J5 蓝牙模块 → 机械臂
```

PL 负责字节级 UART 收发和缓冲；手势判断与机械臂 ASCII 协议仍在 PS。任何动作验证前必须保证机械臂处于安全空间，并另行建立停止和恢复证据。

## 核心制品

| 文件 | SHA-256 |
|---|---|
| `sw/board_artifacts/t1_overlay_ble_j5.bit` | `b939ef67a6a3a285a73cd4f2fc1fc8d826941dc9114a31e9913e0a2ab1edbbac` |
| `sw/board_artifacts/t1_overlay_ble_j5.hwh` | `91a82bd5e7a0f9a3c27ac511d6782eeb75a384ab55d6acd1cc2392f686e56efe` |
| `net3_ps_only_pl_ble_j5.xsa` | `eb59480a5b04105ab3dec0cf9d343e85f50163a98ac5213c90284cdc0d50b9cd` |

源工程位于 `vivado_project/`，模型位于 `models/`，板端历史文件位于 `sw/`。完整文件哈希见本目录 `sha256_manifest.txt`。

## 构建与部署边界

```powershell
python build/prepare_build.py --form form1a_ble_bridge_j5 --output C:/fpga_runs/<new_run> --stage validate
```

`deploy_net3_from_package.sh` 含不安全的 host-key 策略、固定凭据辅助路径、宽泛进程匹配和未复核的 J5/机械臂恢复逻辑，现已标记 `RETIRED_ENTRY`，不得执行。复现候选工程时须根据实际部署目录重新生成文件清单，并按 overlay skill 先完成所有权、VDMA 停止和恢复验证。
