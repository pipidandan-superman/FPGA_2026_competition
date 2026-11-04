# Make a Zynq fpga_manager compatible .bin from a Vivado .bit:
# strip the bit header (locate sync word FFFFFFFF AA995566) then swap each
# 32-bit word to little-endian (zynq-fpga has_sync requirement).
# Canonical method per 2026-09-18 yolo7020 M13 evidence.
import struct, sys, hashlib

src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()

SYNC = bytes.fromhex('FFFFFFFFAA995566')
off = data.find(SYNC)
if off < 0:
    sys.exit('sync word not found — not a .bit?')
# header must be 4-byte aligned region start; sync begins the body
body = data[off:]
if len(body) % 4:
    body = body + b'\x00' * (4 - len(body) % 4)
words = struct.unpack('>%dI' % (len(body) // 4), body)
out = struct.pack('<%dI' % len(words), *words)
open(dst, 'wb').write(out)
print('src_bytes=%d hdr_stripped=%d body=%d out=%d' % (len(data), off, len(body), len(out)))
print('sha256=%s' % hashlib.sha256(out).hexdigest())
