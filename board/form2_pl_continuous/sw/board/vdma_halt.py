#!/usr/bin/env python3
# vdma_halt.py -- stop a live genlock VDMA (MM2S + S2MM RS=0) through /dev/mem.
# The M13 lesson: killing the OWNER process does NOT halt the fabric VDMA
# (it keeps DMA-ing ownerless on the HP ports); an overlay download in that
# state kills the whole PS.  Run as root AFTER killing the owner, BEFORE
# vdma_halt_check.py and any overlay download.
# Usage: XILINX_XRT=/usr pynq-venv python3 vdma_halt.py <bit-for-hwh>
import sys
import time
from pynq import Overlay, MMIO

bit = sys.argv[1]
ol = Overlay(bit, download=False)
base = ol.ip_dict["axi_vdma_0"]["phys_addr"]
mm = MMIO(base, 0x40)
for off, name in ((0x00, "MM2S"), (0x30, "S2MM")):
    cr = mm.read(off)
    mm.write(off, cr & ~1)          # RS = 0
    print("%s_DMACR 0x%08X -> 0x%08X" % (name, cr, mm.read(off)))
time.sleep(0.2)
ok = True
for off, name in ((0x00, "MM2S"), (0x30, "S2MM")):
    cr = mm.read(off)
    print("%s_check 0x%08X RS=%d" % (name, cr, cr & 1))
    ok = ok and not (cr & 1)
print("VDMA_HALT_OK" if ok else "VDMA_HALT_FAIL")
sys.exit(0 if ok else 1)
