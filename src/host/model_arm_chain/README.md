# model_arm_chain — 模型+机械臂链路（Option 1 PC 纯链路，开发目录）

> 上位计划：`1_docs/doc/模型机械臂演示开发文档_2026-10-16_v2.md`（10-16 用户审核通过，取代阶梯 v1）。
> 本目录=开发资产（脚本/文档）；**运行证据只放 `4_metrics/logs/<run>/`**，回流的只是
> result.json/events.jsonl 等证据，开发件不入 metrics。

## 目录约定

| 位置 | 内容 |
|---|---|
| `3_host/model_arm_chain/`（本目录） | 脚本 + 本 README，开发迭代都在这里 |
| `4_metrics/logs/YYYY-MM-DD_model_arm_opt1_runNN/` | 每次运行的 config/events/result.json 证据 |

## 组成

- `arm_link.py` — PC(bleak/WinRT)→WeBotPi 013a(FFE2 写/FFE1 通知) 链路封装。
  铁律内建：STM32 回声过滤（位置正则天然免疫）、运动帧 PRAD 回读对账重发、
  小行程 T≤500、005 钳位 [1133,1665]。
- `policy.py` — 可替换策略头。`ScriptPolicy`=YOLO 目标类去抖触发安全摆动
  （替身，骨架期用）；`PiPolicy`=pi0 服务适配桩（C2 ckpt 未到，构造即报错，
  是换头点）。
- `opt1_loop.py` — 主环：BLE 先连（bleak×DSHOW 互斥律）→ 相机线程 → YOLO →
  策略 → 执行+逐级时戳 JSONL → 门判定。
- `run_opt1.ps1` — 启动器（venv = 2026-09-21_model_env_rebuild_run03，bleak 已补装）。
- `calib/` — 侧视板载相机标定（L4 前置，10-16 备）：布置检查清单 + 单应标定脚本
  （collect/validate/selfcheck/solve）+ 摘录 FK（kms_math.py）。用法/门/坑全在
  `calib/README.md`。侧视两条约定：标定垂直接触 alpha=-90、运行时喂框底边中点。

## 用法

```powershell
# 干跑（无臂）：只验 相机+YOLO+策略 与时延基线
.\run_opt1.ps1 --run-dir E:/competition/4_metrics/logs/2026-10-16_model_arm_opt1_dry_run01 --no-arm --headless --max-seconds 60

# 实环（需：臂已上电听到舵机锁定声 + FPGA 侧 0214 断电防 BIND 抢连）
.\run_opt1.ps1 --run-dir E:/competition/4_metrics/logs/<new_run_dir> --max-seconds 300
```

运行时把任意 COCO 类物体（默认 bottle，改 `--trigger-class`）举到摄像头前，
去抖 5 帧后臂执行 001 ±80@T500 摆动并回读对账，首环即 `LOOP_PASS`。

## 门

- `ARM_LINK_PASS` 首 PRAD 回读成功（0214 未断电时 connect 会超时→查提示）。
- `LOOP_PASS` 首次 触发→执行→回读 全链闭环。
- result.json 的 `latency_ms` = LATENCY_BASELINE（yolo/ble_rtt/action_e2e）。

## 坑登记（本线新增）

- run_python.ps1 指向的 09-12 venv 已残缺（只剩 Lib），实际可用=
  `2026-09-21_model_env_rebuild_run03/venv`；bleak 为 10-16 补装。
- 手势线数据隔离指令有效：禁用 `3_host/model/best.pt`（手势权重），
  本链只用 COCO yolov8n.pt。
