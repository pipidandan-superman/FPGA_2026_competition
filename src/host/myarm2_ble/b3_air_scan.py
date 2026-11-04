# Quick air scan: is the AT-09 (D0:B5:C2:8D:EB:49) advertising? Is anything else?
import asyncio

from bleak import BleakScanner

AT09 = "d0:b5:c2:8d:eb:49"
MLT = "88:4a:ea:8d:c3:29"


async def main():
    print("--- air scan 12s ---")
    rs = await BleakScanner.discover(timeout=12.0, return_adv=True)
    for addr, (dev, adv) in sorted(rs.items()):
        mark = ""
        if addr.lower() == AT09:
            mark = "  <== AT-09 (arm side)"
        elif addr.lower() == MLT:
            mark = "  <== MLT (board side)"
        print("%s  %-24r rssi=%s%s" % (addr, dev.name,
                                       adv.rssi if adv else "?", mark))
    print("total %d" % len(rs))
    hit = AT09 in [a.lower() for a in rs]
    print("VERDICT: %s" % ("AT09_ADVERTISING" if hit else "AT09_NOT_IN_SCAN"))
    return 0 if hit else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
