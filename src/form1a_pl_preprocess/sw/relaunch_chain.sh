#!/bin/bash
# PL_pre_NET3 链重拉正典（三闸后执行；在板端 root 下运行）
# 用法: bash relaunch_chain.sh   （需先完成闸A/B/C，见 README）
set -u
cd /home/xilinx/mletterbox
export XILINX_XRT=/usr
export T1_BIT_SHA=0e9dd31276d2ce7abb94c6c3910d838b9a7aa0b50ca640c891abe988eb557341
export T1_HWH_SHA=cf1b7539b1c3476d4aebe4a7e85e34ecd211d0cd97f38fa30a382d55702b5164
# NanoDet v3 bin（链内默认 sha 为 v1 旧值，必须覆盖）
export T1_NCNN_BIN_SHA=e802c737b2a355b93a09ac204563e3eec54387d5f4d7382fcde183fdbd2355d6
nohup setsid /usr/local/share/pynq-venv/bin/python3 t1_gesture_main.py \
  --bit /home/xilinx/mletterbox/mletterbox.bit \
  --onnx /home/xilinx/net3_ps_only/models/nanodet-plus-m_320-gesture7-v65-cv2.onnx \
  --engine ncnn --ncnn-addr 127.0.0.1:5002 \
  --ncnn-param /home/xilinx/mcontract/models/nanodet-plus-m_320-gesture7-mcontract-v3.ncnn.param \
  --ncnn-bin   /home/xilinx/mcontract/models/nanodet-plus-m_320-gesture7-mcontract-v3.ncnn.bin \
  --model 0 --rotate-secs 0 --model-select /home/xilinx/mletterbox/model_select \
  --no-ble --score 0.55 --conf 0.55 --debounce 2 --min-margin 0.2 \
  --evidence /home/xilinx/mletterbox/evidence \
  </dev/null > /home/xilinx/mletterbox/chain_relaunch.log 2>&1 & disown
echo "chain relaunched, log: /home/xilinx/mletterbox/chain_relaunch.log"
