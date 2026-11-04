#!/usr/bin/env python3
# vdma_halt_check.py -- register-level VDMA halt gate (ees331.md quiesce canon).
# Usage (as root): XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 \
#                    vdma_halt_check.py <path-to-bit> [vdma_ip_name]
# Resolves axi_vdma_0 (or named IP) from the matching HWH, reads MM2S_DMACR
# (0x00) and S2MM_DMACR (0x30) RS bits (bit0). Exit 0 only when both RS=0.
import sys
from pynq import Overlay, MMIO

bit = sys.argv[1]
ip = sys.argv[2] if len(sys.argv) > 2 else "axi_vdma_0"
ol = Overlay(bit, download=False)
if ip not in ol.ip_dict:
    print("VDMA_CHECK_FAIL ip %s not in HWH ip_dict: %s" % (ip, sorted(ol.ip_dict)))
    sys.exit(2)
base = ol.ip_dict[ip]["phys_addr"]
mm = MMIO(base, 0x40)
mm2s = mm.read(0x00)
s2mm = mm.read(0x30)
print("VDMA_CHECK %s @0x%08X MM2S_DMACR=0x%08X S2MM_DMACR=0x%08X" % (ip, base, mm2s, s2mm))
if (mm2s | s2mm) & 1:
    print("VDMA_CHECK_FAIL RS bit still set -- DMA live, do NOT download overlay")
    sys.exit(1)
print("VDMA_CHECK_HALTED_OK")
