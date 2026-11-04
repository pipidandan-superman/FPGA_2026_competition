# r11 board window opener (2026-10-18).  r11 = r10 + scatter->CHW repack
# merge, inert carrier (rp_arm=0), ABI/CAP0 untouched.
# Stage 1 = download gate (g3r10 canon: operating + zocl delta + conv CAP0
#           0x4D390230 at shim CSR slave + fclk pin req75/TICK real 50MHz).
# Stage 2 = island identity YOL2@0x43C20000 v0x300 AND island A_CAP0 hard
#           gate = 0x07100404 (r10 board-proven value, M10.6; r11 ABI must
#           read identical -- drift = wrong bit/ABI regression).
# r11 repack presence is proven at netlist level (760 cells + 4 RAMB36 in
# routed design); board-side this window proves the merged bit behaves
# r10-identically (identity gates + probe legs vs r10 baseline).
import os
import re
import subprocess
import sys

os.environ.setdefault("XILINX_XRT", "/usr")
from pynq import Overlay
from pynq.mmio import MMIO

D = "/home/xilinx/integration_ac1"
ART = os.path.join(D, "m9_v25_integration.xsa")  # pynq 3.0.1 XSA branch extracts bit
ISLAND_BASE = 0x43C20000
CAP0_EXPECT = 0x4D390230
ISLAND_CAP0_EXPECT = 0x07100404

def zocl_locks():
    out = subprocess.run(["dmesg"], capture_output=True, text=True).stdout
    return len(re.findall(r"locked, ref=1", out))

def stage1_download_gate():
    pre = zocl_locks()
    print("ZOCL_LOCKS_PRE=%d" % pre)
    ol = Overlay(ART, download=False)
    print("IP_DICT_KEYS", sorted(ol.ip_dict.keys()))
    if not ol.ip_dict:
        print("DL_GATE_FAIL empty ip_dict")
        sys.exit(2)
    ol.download()
    print("DOWNLOAD_RETURNED")
    state = open("/sys/class/fpga_manager/fpga0/state").read().strip()
    post = zocl_locks()
    print("FPGA_STATE=%s ZOCL_LOCKS_POST=%d DELTA=%d" % (state, post, post - pre))
    # warm re-download law (10-17): second download in same boot can show
    # lock delta 0 with a healthy island; cold boot stays +1.
    if state != "operating" or (post - pre) not in (0, 1):
        print("DL_GATE_FAIL state or lock delta bad")
        sys.exit(1)
    if post - pre == 0:
        print("DL_GATE_WARN warm re-download (lock delta 0)")
    # conv CAP0 in the CONV segment first 1KiB (g3r10 canon); do NOT scan
    # the island segment (DECERR hole 0x300-0xFFF, r9 board law).
    found = []
    mm = MMIO(0x43C10000, 1024)
    for off in range(0, 1024, 4):
        if mm.read(off) == CAP0_EXPECT:
            found.append(("shim", 0x43C10000, off))
            break
    if not found:
        print("DL_GATE_FAIL conv CAP0 0x%08X not found" % CAP0_EXPECT)
        sys.exit(1)
    for k, base, off in found:
        print("IDENTITY_CAP0 name=%s base=0x%08X off=0x%03X" % (k, base, off))
    # fclk x2/3 law (EES-331): pin AFTER download with req 75 to land on a
    # true 50.000 MHz, then TICK-verify at silicon (setpoint readback lies).
    from pynq import Clocks
    Clocks.fclk0_mhz = 75
    rb = Clocks.fclk0_mhz
    print("FCLK0_PIN req=75 setpoint_readback=%.3f MHz" % rb)
    if abs(rb - 75) > 1.0:
        print("DL_GATE_FAIL fclk0 setpoint %.3f != 75" % rb)
        sys.exit(1)
    import mmap, struct, time
    def _tick_mhz():
        CSR, PAGE = 0x43C10000, 0x1000
        fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
        mb = CSR & ~(PAGE - 1)
        m = mmap.mmap(fd, PAGE * 2, mmap.MAP_SHARED, mmap.PROT_READ, offset=mb)
        off = CSR - mb
        t0 = struct.unpack_from("<I", m, off + 0x54)[0]
        w0 = time.time()
        time.sleep(2.0)
        t1 = struct.unpack_from("<I", m, off + 0x54)[0]
        w1 = time.time()
        m.close(); os.close(fd)
        return ((t1 - t0) & 0xFFFFFFFF) / (w1 - w0) / 1e6
    real = _tick_mhz()
    print("FCLK0_TICK real=%.3f MHz" % real)
    if abs(real - 50.0) > 1.0:
        print("DL_GATE_FAIL real fabric clock %.3f != 50" % real)
        sys.exit(1)
    print("DL_GATE_PASS (conv CAP0 confirmed, fclk 50MHz TICK-verified)")
    return ol

def stage2_island_identity():
    mm = MMIO(ISLAND_BASE, 4096)
    ident = {
        "A_ID":      (0x000, 0x594F4C32),
        "A_VERSION": (0x004, 0x00000300),
        "A_CAP0":    (0x008, ISLAND_CAP0_EXPECT),
        "A_CAP1":    (0x00C, None),
        "A_STATUS":  (0x014, None),
        "A_ERR_STAT": (0x018, None),
        "A_ERR_INFO": (0x01C, None),
    }
    rd = {}
    for name, (off, exp) in ident.items():
        rd[name] = mm.read(off)
    for name, val in rd.items():
        print("ISLAND %-10s @0x%03X = 0x%08X" % (name, ident[name][0], val))
    idv = rd["A_ID"]
    if idv == 0x00000000 or idv == 0xFFFFFFFF:
        print("ISLAND_IDENTITY_FAIL dead bus at 0x43C20000 (val=0x%08X)" % idv)
        sys.exit(3)
    ok = True
    for name in ("A_ID", "A_VERSION", "A_CAP0"):
        exp = ident[name][1]
        if rd[name] != exp:
            print("ISLAND_IDENTITY_MISMATCH %s got=0x%08X exp=0x%08X"
                  % (name, rd[name], exp))
            ok = False
    if not ok:
        print("ISLAND_IDENTITY_FAIL")
        sys.exit(3)
    print("ISLAND_IDENTITY_PASS YOL2@0x43C20000 v0x300 cap0=0x%08X cap1=0x%08X status=0x%08X"
          % (rd["A_CAP0"], rd["A_CAP1"], rd["A_STATUS"]))

if __name__ == "__main__":
    ol = stage1_download_gate()
    stage2_island_identity()
    print("R11_WINDOW_OPEN_PASS")
