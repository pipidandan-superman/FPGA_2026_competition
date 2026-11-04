# live_gesture7 v2 — 板上七手势验证裁定（单会话全覆盖）

- 日期：2026-11-05（板上会话）/ 2026-11-03（run 建档）。
- 代码基线：本包 v2（`sw/board/`：`pl_heads_runtime.py` + `hybrid_pipeline_resident.py` + `run_live_gesture7.py`，
  含 `LR_CLASS_REMAP={1:2,2:1}`；BIT=`72b358ff…2f7a58` 未变）。
- **用户终审（最高裁定）**：「左右已正确，七手势全部验证通过」——以用户逐项实测为准。

## 会话 124133（最终代码，含 L/R 重映射）——7/7 类全覆盖

- 固化时点快照 488 帧（板上会话仍在继续记录）；mean 2555 / median 2497 / min 2466 / max 4260 ms；
  PS backbone/neck 850 ms；六门铃墙合计 1.44 s；自动恢复 23 帧（err=0x24 慢复位+FSM 重载+重试，
  全部成功，零链崩；恢复帧最大 4260 ms）。
- 判定序列（--judge-conf 0.55，hits=2）：Down f13 0.634 → Left f15 0.713 → Right f25 0.665
  （用户自由测试节奏，未按序列逐项走完，不影响逐类显示证据）。
- 显示门 0.50 下 **7/7 类全部检出**（各类最大置信度）：
  Down 0.713 / Left 0.758 / Right 0.665 / Stop 0.797 / Thumbs Down 0.713 / Thumbs up 0.665 / **Up 0.665**。
  （Up 在会话早段低于显示门，会话继续后于后段补齐——早段拉取的 207 帧快照缺 Up，
  最终 488 帧快照已含；Up 类 id 6 不在 `LR_CLASS_REMAP` 交换范围。）

## 会话 123205（同日早段，显示门 0.50 版本、L/R 重映射之前）——旁证

- 196 帧；mean 2553 / median 2493；Up 0.758（f7/f8 连续 0.758/0.713）。
- L/R 标签为重映射前口径（左右相反），仅取 Up 旁证与速度数据，不取其 L/R 结论。

## 速度（对 v1 冻结基线）

- v1（2026-11-02 三帧实测）：3.4726 / 3.3115 s/帧。
- v2：median 2497 ms ≈ **−24%**；分解：PS backbone/neck ~0.81–0.85 s（模型本征）+
  六门铃 1.44 s（PL 真实计算，@50MHz tick 计数与墙钟一致）+ 驱动 ~0.12 s（prep 71 ms +
  FSM 重放 ~54 ms + 段读 ~1 ms）。**~2.5 s 为该 BIT 上 PS 不可再降的地板**，禁止表述为性能达标。

## 文件

- `session_123205_display_gate/`、`session_124133_final_lrfix/`：session.jsonl、results.jsonl、
  target_*.bgr/.json（板端原件快照拉取；124133 为固化时点 488 帧快照，板上仍在续记）。
- `head_only_run_v2_excerpt.log`：RESIDENT RUNTIME INIT 起的驻留运行时日志节选。
- `live_gesture7_console_v2_excerpt.log`：v2 控制台节选。
- 完整 16 MB 板端证据留在 run：`4_metrics/logs/2026-11-03_pspl_v8n_gesture7_boardprep_run01/board_evidence/`。
