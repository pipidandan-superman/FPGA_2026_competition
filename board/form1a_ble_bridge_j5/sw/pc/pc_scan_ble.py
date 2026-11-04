"""PC-side BLE scan: find the board's MLT-BT05 family module.

Flags candidates by name (mlt/bt05) or advertised FFE0 service.
Saves all discovered devices to JSON for the evidence dir.
Windows bleak; run with D:\\work\\Python\\python.exe.
"""
import asyncio
import json
import sys
import time
from pathlib import Path

from bleak import BleakScanner


def is_candidate(name, uuids):
    low = (name or "").lower()
    if "mlt" in low or "bt05" in low or "bt-05" in low:
        return True
    return any("ffe0" in u.lower() for u in uuids)


async def run(seconds, out_path):
    print("[scan] discovering for %ds ..." % seconds)
    found = await BleakScanner.discover(timeout=seconds, return_adv=True)
    rows = []
    for addr in sorted(found):
        dev, adv = found[addr]
        uuids = [str(u) for u in (adv.service_uuids or [])]
        name = adv.local_name or dev.name or ""
        cand = is_candidate(name, uuids)
        rows.append(dict(address=addr, name=name, rssi=adv.rssi,
                         uuids=uuids, candidate=cand))
        tag = "[cand]" if cand else "      "
        print("%s %s  %-28s rssi=%4d  %s" % (tag, addr, name, adv.rssi, uuids))
    cands = [r for r in rows if r["candidate"]]
    print("[scan] %d devices total, %d candidates" % (len(rows), len(cands)))
    out_path.write_text(json.dumps(
        dict(t=round(time.time(), 3), seconds=seconds, devices=rows),
        indent=1), encoding="utf-8")
    print("[scan] saved %s" % out_path)
    return len(cands)


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("pc_scan.json")
    n = asyncio.run(run(seconds, out))
    print("PC_SCAN_CANDIDATES=%d" % n)
    return 0 if n >= 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
