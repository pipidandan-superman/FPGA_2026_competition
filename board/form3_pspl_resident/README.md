# 形态三：PS+PL 驻留混合推理

本目录包含「PS YOLOv8n backbone/neck → PL 六段 heads → PS decode/JSON」驻留混合路径。历史 BIT/HWH/XSA 未因纯 PS 侧更新而改变，当前打包 BIT SHA-256 为 `72b358ff…2f7a58`。

## 当前版本与证据

- 最终历史会话 `session_124133_final_lrfix` 共 **488 帧**，中位 **2496.7375 ms**、均值 **2554.553 ms**，记录 **23 次恢复**并检出七类手势。早段 196 帧会话不得与该会话混算。
- 七类检出不等同严格七项自动验收流程全部走完；严格序列以相应板测记录为准。
- 另一轮严格展示记录为 **69 帧、69 个不同输入哈希**，七类均达到连续两帧置信度不低于 0.55；它证明该次七类展示，不是统计数据集准确率，也不是新重建 BIT 的板证。
- 包内历史 83 帧纯 PL 数据缺 Down，不能借本混合路径的七类结果替代。
- 本包只交付驻留混合路径。其他标签固化或双后端版本的时序、照片和切换展示不计入本包验收。
- 文件名或历史文档中的 2026-11-05 日期保留为原始归档标识，不据此推断新的实际执行日期；板端 2022 年墙钟也不是主机测试日期。

## 核心制品

| 文件 | SHA-256 |
|---|---|
| `sw/board_artifacts/hybrid_heads_ic64_fix.bit` | `72b358ff75a8d1c1bda519da248bd94fb4bdc236dd16fcca36eb4fc1262f7a58` |
| `sw/board_artifacts/hybrid_heads_ic64_fix.xsa` | `4713e50eba88dcc113a4106d12db1d25b4ab9d58a678b295e9577cfdcd20d78b` |
| `sw/board_artifacts/hybrid_heads_ic64_fix.hwh` | `5f5f98927e1d29411b5c386d3a9878a98e0b05ff211061f4be26efbd9c0c7f37` |
| `prog/tb_setup_six_branches.txt` | `b25a05c0862eeccdd6ee7aa9ef66b67e910460afe571a26a7bf7e94dbd4c4932` |
| `prog/layout.json` | `625041ff9f77ce6a513c0b0089334a12bb4c0478932184629953f011f85198eb` |

历史位流的布线后资源为 LUT 31515、FF 27570、BRAM 96.5、DSP 91，WNS/WHS +0.255/+0.020 ns。本次从包内源码重建 BIT/XSA 已通过，WNS/WHS +0.030/+0.017 ns；重建 LUT 为 31512，属于另一制品，不能混用历史报告。

## 目录

```text
vivado_project/       源工程与包内依赖
sw/board_artifacts/  历史 BIT/HWH/XSA
sw/board/            驻留驱动、PS 客户端/服务端和运行脚本
sw/deploy/           包内相对定位的部署入口
prog/                程序卷、layout、descriptor 和 COE
models/              PS backbone/neck 模型与注册表
logs/                历史连续帧与严格序列实测输出
```

共享固定输入和黄金参考位于仓库根目录 `data/gold/`。

## 构建与部署

```powershell
python build/prepare_build.py --form form3_pspl_resident --output C:/fpga_runs/<new_run> --stage bitstream
python build/stage_submission.py --form form3_pspl_resident --output C:/fpga_runs/<new_stage> --remote-root /home/xilinx/amd_submission/<new_version>
```

完整构建须同时通过综合、实现、DRC、时序和导出标记。部署默认只生成文件树，`--upload` 才上传并校验，不启动硬件。

## 板端验证

```powershell
python build/board_transport.py --script build/verify_form3.py --script-arg /home/xilinx/amd_submission/<new_version> --output C:/fpga_runs/<new_test> --sudo --timeout 420
```

七手势严格序列增加 `--script-arg=--gestures` 并提高运输超时。板测会暂停摄像头服务，须取得现场授权并核对所有权、DMA 停止和恢复门。恢复原服务后必须出现新帧，HDMI 由现场确认。

历史 `deploy_live_gesture7.sh` 等脚本可能包含作者工作区或旧服务拓扑，只作溯源留档；以 `build/stage_submission.py`、`build/board_transport.py` 和 `build/verify_form3.py` 为正式入口。

## 运行依赖

- 板端 PYNQ Python 与 `pynq` 包；现有 PYNQ 3.0.1 镜像。
- 板端 ncnn 静态库及头文件，默认位置 `/home/xilinx/ncnn_build`；缺失时须先按 `sw/board/build_hybrid_server.sh` 的依赖说明安装，不能把本机已有库当作包内组件。
- PS 服务端监听 `127.0.0.1:5003`，客户端使用 feature 扩展协议读取三个尺度特征。
- 模型注册表末行不得多余换行，以免服务端把换行读入 blob 名。
