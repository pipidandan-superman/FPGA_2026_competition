# data/：测试数据与参考结果

| 内容 | 位置 | 说明 |
|---|---|---|
| YOLOv8n 头部段逐层期望值 | `gold/` | 78 个 hex：各层 int8 权重、激活、输入帧和首帧输出。形态二与形态三共用同一套期望值，部署时映射为板端 `gold/`。 |
| 七手势历史判定结果 | `expected_results/results_seven_gestures.jsonl` | 形态二历史服务逐帧结果，对应 `board/form2_pl_continuous/logs/service_seven_gestures.log`。该文件只有六类记录，缺 Down，不得写成七类全部通过。 |

模型权重按形态放在 `board/<form>/models/`，包括 ncnn param/bin、ONNX 和 int8 量化版。完整哈希收录于根目录 `sha256_manifest.txt` 与 `binary_sha256.txt`。

## 比对合同

- `gold/` 为 W8A8 量化后的期望值，必须使用同一套量化参数和 `layout.json`／`descriptor_table.json`，直接用浮点权重比对会误报。
- 形态二正式固定输入入口为 `build/verify_form2.py`，要求 21/21 个黄金平面一致并恢复原摄像头服务；当前仅完成入口与部署树核验，尚未实际板测。
- 历史结果中的 `timestamp` 是 ISO 墙钟字段，板端时钟可能未校准；`inference_ms` 由单调时钟差计算。两者不能混为同一时间基准，也不能把含显示和 I/O 的帧时当作纯计算时延。
- 训练数据来源和模型许可见根目录 `third_party_notices.md`。本目录不包含完整 HaGRID 或 COCO 数据集，也不存在 `src/host/model_datasets` 这一执行依赖。
