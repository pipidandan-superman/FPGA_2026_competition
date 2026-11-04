# 形态一A：PL letterbox 预处理 + PS 三网络推理

本目录保存「相机 → PL letterbox 预处理（640×480→320×320 gray114）→ PS ncnn 三网络切换 → HDMI OSD」的历史板验配置。网络推理由 PS 执行，PL 负责采集、预处理和显示。

## 证据边界

- 历史配置包含 NanoDet-mM、YOLOv8n、YOLO11n 三网络及七手势实测，具体结论以对应原始日志为准。
- 本次已从当前包内源工程通过 `PACKAGE_PROJECT_VALIDATION_PASS`，证据为 `2026-11-04_amd_form1a_pl_preprocess_validate_run01`。
- 本次未执行完整 BIT 重建，不能用历史 WNS 或历史位流替代当前重建结果。
- NanoDet int8 试验失败，现役 NanoDet 槽保留 fp32；失败产物不得上板。

## 核心制品

| 文件 | 说明 |
|---|---|
| `hw/t1_letterbox_m_final.bit` | 历史位流，SHA 前缀 `0e9dd312`；历史构建 WNS +6.126 ns |
| `hw/t1_letterbox_m_final.hwh` | 配对 HWH，SHA 前缀 `cf1b7539` |
| `models/` | 三网络现役及回退模型，具体文件名与注册表一致 |
| `vivado_project/` | 当前可复现源工程及包内依赖 |
| `../../src/form1a_pl_preprocess/sw/` | 历史板端链主、注册表、补丁和 VDMA 停止脚本 |

完整文件哈希见本目录 `sha256_manifest.txt` 和根目录 `binary_sha256.txt`。

## 硬件与输入合同

- 预处理为 640×480 → letterbox r=0.5，320×240 内容加 40/40 gray114 边，输出 u8 RGB HWC 307200 B。
- PL 整数双线性结果与 OpenCV 参考逐位一致的历史结论只适用于对应版本和测试输入。
- 三网络统一 `(f32-128)/255` fp32 CHW 归一化；不得恢复旧 BGR+mean/std 分支。
- 位流/HWH 哈希由 `T1_BIT_SHA`、`T1_HWH_SHA` 环境变量钉住；板端需 root 与 `XILINX_XRT=/usr`。

## 工程验证

```powershell
python build/prepare_build.py --form form1a_pl_preprocess --output C:/fpga_runs/<new_run> --stage validate
```

将 `--stage` 改为 `bitstream` 可执行完整构建，但当前状态仍是“未执行完整 BIT 重建”，须以实际构建日志更新。

## 历史部署资料的用法

`../../src/form1a_pl_preprocess/sw/relaunch_chain.sh` 是历史板端 `/home/xilinx/mletterbox` 拓扑的启动示例，不是通用一键部署脚本。复现时应先完成所有权与 VDMA 停止门，再按目标部署目录显式调整 BIT、模型、注册表和证据路径。不得直接照抄作者工作区路径，也不得把历史机械臂或动作链结果扩展为当前集成验收。
