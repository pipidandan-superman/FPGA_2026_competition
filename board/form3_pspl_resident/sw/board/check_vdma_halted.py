#!/usr/bin/env python3
"""Read-only VDMA ownership gate using metadata for the currently loaded design."""
import argparse
import json
from pathlib import Path

from pynq import MMIO, Overlay


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bit", type=Path, required=True)
    args = parser.parse_args()
    ol = Overlay(str(args.bit), download=False)
    desc = ol.ip_dict.get("axi_vdma_0")
    if desc is None:
        raise RuntimeError("Current-design metadata has no axi_vdma_0; refuse reconfiguration")
    mmio = MMIO(desc["phys_addr"], desc["addr_range"])
    mm2s = mmio.read(0x00)
    s2mm = mmio.read(0x30)
    mm2s_status = mmio.read(0x04)
    s2mm_status = mmio.read(0x34)
    print(json.dumps(dict(event="VDMA_PREFLIGHT", phys_addr=hex(desc["phys_addr"]),
                          mm2s_dmacr=hex(mm2s), s2mm_dmacr=hex(s2mm),
                          mm2s_rs=mm2s & 1, s2mm_rs=s2mm & 1,
                          mm2s_status=hex(mm2s_status), s2mm_status=hex(s2mm_status))), flush=True)
    if (mm2s & 1) or (s2mm & 1) or not (mm2s_status & 1 and s2mm_status & 1):
        print("FATAL_VDMA_STILL_RUNNING", flush=True)
        return 1
    print("VDMA_HALTED_PASS", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
