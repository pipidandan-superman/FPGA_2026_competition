import os, mmap, struct, json
BASE = 0xF8000000
OLD = 0x00400800
NEW = 0x00400500
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
def rd(off): return struct.unpack_from('I', m, off)[0]
def wr(off, value):
    struct.pack_into('I', m, off, value)
    if rd(off) != value:
        raise RuntimeError('register readback failed %x' % off)
before = rd(0x170)
if before == OLD:
    struct.pack_into('I', m, 0x008, 0xDF0D)  # SLCR_UNLOCK, readback is zero
    wr(0x170, NEW)     # IOPLL / 5 / 2 = 80 MHz on this board
    struct.pack_into('I', m, 0x004, 0x767B)  # SLCR_LOCK, readback is zero
elif before != NEW:
    raise RuntimeError('unexpected FCLK0 %08x, refuse change' % before)
print(json.dumps({'before': hex(before), 'after': hex(rd(0x170)), 'restore': hex(OLD)}), flush=True)
