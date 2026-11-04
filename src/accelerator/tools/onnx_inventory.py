#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""onnx_inventory.py -- yolov8n.onnx 全图算子/Conv 形状清单

产出 evidence/onnx_inventory_'+TAG+'.json：
  - 逐 Conv 节点：name / (OC,IC,kh,kw) / strides / pads / groups / 输入输出 shape
  - 非 Conv 算子计数（Concat/Add/MaxPool/Resize/Slice/Sigmoid/Mul/...）
  - 输入/输出张量
用途：nc=80 schedule.json 重生成的权威形状源（与手势 63 conv 逐项 diff 的底稿）。

Run: cuda_env venv python onnx_inventory.py
"""
import json
import os
import sys

import onnx

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.path.dirname(HERE)
ONNX_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(RUN, "weights", "yolov8n.onnx")
TAG = sys.argv[2] if len(sys.argv) > 2 else "yolov8n80"


def dims(t, info):
    vi = info.get(t)
    if vi is None or vi.type.tensor_type.shape.dim:
        pass
    d = vi.type.tensor_type.shape.dim if vi is not None else []
    return [int(x.dim_value) if x.dim_value else str(x.dim_param or "?") for x in d] if vi is not None else None


def main():
    m = onnx.load(ONNX_PATH)
    info = {}
    for vi in m.graph.value_info:
        info[vi.name] = vi
    for vi in list(m.graph.input) + list(m.graph.output):
        info[vi.name] = vi

    # weight 形状从 initializer 拿
    init = {i.name: list(i.dims) for i in m.graph.initializer}

    minit = {i.name: list(i.dims) for i in m.graph.initializer}
    convs, others = [], {}
    for n in m.graph.node:
        if n.op_type == "Conv":
            wname = n.input[1]
            wd = init.get(wname)
            attrs = {a.name: list(a.ints) if a.ints else a.i for a in n.attribute}
            convs.append({
                "name": n.name,
                "w": wd,
                "in_shape": dims(n.input[0], info) if n.input[0] in info else None,
                "out_shape": dims(n.output[0], info) if n.output[0] in info else None,
                "attrs": {k: v for k, v in attrs.items()},
            })
        else:
            others[n.op_type] = others.get(n.op_type, 0) + 1

    # 与手势图理论 conv 数（63）对账
    out = {
        "onnx": os.path.basename(ONNX_PATH),
        "conv_count": len(convs),
        "other_ops": others,
        "inputs": [{"name": i.name, "shape": dims(i.name, info)} for i in m.graph.input],
        "outputs": [{"name": o.name, "shape": dims(o.name, info)} for i in [0] for o in m.graph.output],
        "convs": convs,
    }
    with open(os.path.join(RUN, "evidence", "onnx_inventory_%s.json" % TAG), "w",
              encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print(f"conv_count={len(convs)} other_ops={others}")
    khist = {}
    for c in convs:
        oc, ic, kh, kw = c["w"]
        k = ic * kh * kw
        khist[k] = khist.get(k, 0) + 1
    print("K histogram:", dict(sorted(khist.items())))
    print("ONNX_INVENTORY_PASS tag=" + TAG)


if __name__ == "__main__":
    main()
