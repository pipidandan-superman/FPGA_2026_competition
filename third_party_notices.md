# 第三方组件、模型与数据许可说明

核对日期：2026-11-04。

本仓库的 `license.txt`（MIT）只适用于队伍拥有相应权利的原创代码和原创文档，不改变下列第三方组件、模型、转换制品或数据的许可。上游条款与本说明不一致时，以上游正式条款为准。本说明用于交付溯源，不构成法律意见。

## 运行与硬件依赖

| 组件 | 本包中的形态 | 许可与处理 |
|---|---|---|
| AMD/Xilinx Vivado、PS7、VDMA、时钟、互连及其他厂商 IP | BD/XCI 配置、约束和集成源码；不包含 Vivado 工具或可执行程序 | 遵循用户所持 AMD/Xilinx 工具与 IP 许可。重建必须使用 Vivado 2025.2；MIT 不覆盖这些厂商组件。 |
| PYNQ 3.0.1 | 板端运行环境依赖；本包不重发完整镜像 | 从 PYNQ 官方渠道获取镜像并遵循其许可：https://github.com/Xilinx/PYNQ 。 |
| ncnn | 板端推理库及本队适配的服务端源码；预编译 ncnn 库不随包提供 | ncnn 主体采用 BSD 3-Clause，部分组件另有条款，见 `licenses/ncnn-bsd-and-third-party.txt` 和 https://github.com/Tencent/ncnn 。 |
| OpenCV、NumPy、Python 及板端系统库 | 构建和运行依赖，不随包重发 | 分别遵循各上游许可；通过目标镜像的包管理环境安装。 |

## 模型及转换制品

| 来源 | 本包中的形态 | 许可与再分发要求 |
|---|---|---|
| Ultralytics YOLOv8n、YOLO11n | 原始/微调模型、ONNX、ncnn param/bin、量化权重及对应硬件任务数据 | 上游许可为 AGPL-3.0，原文见 `licenses/agpl-3.0.txt`。上游项目与许可说明：https://github.com/ultralytics/ultralytics 、https://www.ultralytics.com/license 。格式转换、量化或微调不改变上游许可边界；这些模型及其派生制品不适用本队 MIT。本包同时提供相应源工程、训练/转换脚本和模型，使用方修改、再分发或网络提供服务时须自行履行 AGPL-3.0 的相应义务。 |
| NanoDet-Plus | 原始/微调模型、ONNX、ncnn param/bin 及量化制品 | 上游采用 Apache-2.0，原文见 `licenses/apache-2.0.txt`。来源：https://github.com/RangiLyu/nanodet 。保留归属和变更说明；不适用本队 MIT。 |

本包保留模型文件名、哈希、转换脚本和实测记录，以便识别具体制品。未将第三方模型或权重声明为队伍原创成果。

## 数据集

| 数据集 | 本包使用情况 | 许可与边界 |
|---|---|---|
| HaGRID / HaGRID v2 | 用于手势模型训练、合并与评测；完整第三方数据集不随包重发 | 上游标注为 Creative Commons Attribution-ShareAlike 4.0 International 的特定版本，作者与条款入口：https://github.com/hukenovs/hagrid/tree/Hagrid_v2 。使用相关数据、微调模型或再发布衍生材料时须核对归属、相同方式共享及其他上游要求。 |
| COCO | 用于检测模型预训练、量化和评测；完整图片集不随包重发 | COCO 标注通常为 CC BY 4.0，图片仍受各自 Flickr/来源条款约束。官方条款：https://cocodataset.org/#termsofuse 。不得把图片或标注统一改标为 MIT。 |

队伍自采图片、日志和报告的授权范围以 `license.txt` 为准；其中若出现第三方人员、标识、屏幕内容或资料，不表示相关第三方权利被放弃。

## 构建与分发约定

1. 不随包上传 Vivado、PYNQ 镜像、ncnn 预编译库、完整 HaGRID 或 COCO 数据集。
2. 再分发本仓库时必须同时保留 `license.txt`、本文件和 `licenses/` 中适用的许可原文。
3. 对第三方文件进行修改时，应在相应文件或随附记录中注明修改；不得删除已有版权和许可声明。
4. 若无法确定某个模型、数据集或组件的再分发权限，应停止公开分发该部分，而不是默认按 MIT 处理。
