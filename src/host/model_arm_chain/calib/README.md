# calib/ — 侧视板载相机标定（L4 前置）

> 上位文档：`1_docs/doc/模型机械臂演示开发文档_2026-10-16_v2.md`（四硬约束+现场铁律）。
> 方法/纪律全在 **`sideview_layout_checklist.md`**（先读它，一页）。

## 组成

- `sideview_layout_checklist.md` — 侧视布置检查清单：A 机位门槛（俯角≥45°/近半场/
  避奇异/防逆光/浅色垫/固连贴线）+ B 验收快照三张 + C 标定验收门 + D 运行期纪律 + E 重标触发。
- `calib_plane_h.py` — 平面单应标定主脚本。collect（N 点→解 H→落盘）/
  validate（5 点验证门，含远场强制点）/ selfcheck（30s 自检仪式）/ solve（离线重解）。
  侧视专属约定内建：垂直接触（alpha=-90，偏差>10°告警确认）+ 指尖贴面。
  取图三模式：`--camera N`（本机相机，干跑）/`--frame-dir`（板窗口正典：板上 v1.4
  相机链路存 PNG→scp→逐点投 point_XX.png）/`--stub-frame`（无相机跑通流程）。
- `kms_math.py` — 从 pai 线 b_teleop_record.py 逐字摘录的纯数学运动学段
  （kms_fk/kms_analysis/kms_solve，MyArm-2 $KMS 同构），本目录独立可用。
- `homography.json` — 标定产物（H 资产，进 git）。证据（points.csv/report.json）
  只落 `4_metrics/logs/<date>_model_arm_calib_runNN/`。

## 用法

```powershell
# 干跑流程（无臂无相机，今天就能验证点击流）
$py='E:/competition/4_metrics/logs/2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe'
& $py calib/calib_plane_h.py --no-arm --stub-auto-xy --stub-frame collect --points 9

# 板窗口实标（先按清单 A/B 布置+拍照）
& $py calib/calib_plane_h.py --frame-dir <pc_frame_dir> collect --points 12
& $py calib/calib_plane_h.py --frame-dir <pc_frame_dir> validate --far 2,5
# 每次上电
& $py calib/calib_plane_h.py --frame-dir <pc_frame_dir> selfcheck
```

## 门

- `CALIB_COLLECT_PASS`（≥9 点全贴面）→ `CALIB_H_PASS`（重投影中位 <2px）。
- `CALIB_VALIDATION_PASS`（5 点逐点 <10mm，且 ≥1 远场点；远场超差=收缩操作区）。
- `SELFCHK_PASS`（自检仪式，err<门；FAIL=相对位姿动过 → 重标，清单 E）。

## 坑登记（本目录新增）

- 侧视下**框中心不能直接喂 H**（高度耦合，漂移 ≈ h/tanθ）——运行时统一用
  **框底边中点**；homography.json 的 conventions 字段已写死这条。
- `--frame-dir` 模式场景必须静止：点到点之间臂在动、画面不能动之外的东西。
- 换相机/换焦距/动支架 = 清单 E 重标，不许沿用旧 H。
