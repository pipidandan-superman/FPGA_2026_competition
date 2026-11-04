import os, mmap, struct, json
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0xF8000000)
def rd(off): return struct.unpack_from('I', m, off)[0]
before = rd(0x170)
if before == 0x00400500:
    struct.pack_into('I', m, 0x008, 0xDF0D)
    struct.pack_into('I', m, 0x170, 0x00400800)
    struct.pack_into('I', m, 0x004, 0x767B)
elif before != 0x00400800:
    raise RuntimeError('unexpected FCLK0 %08x, refuse restore' % before)
if rd(0x170) != 0x00400800:
    raise RuntimeError('FCLK0 restore readback failed')
print(json.dumps({'before': hex(before), 'restored': hex(rd(0x170))}), flush=True)
