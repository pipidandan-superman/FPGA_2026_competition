# B3 end-to-end probe from the air: PC -> AT-09 FFE1 (write-no-response)
# -> AT-09 UART TX -> arm UART3 wire -> STM32 (115200) -> echo + servo reply
# -> AT-09 UART RX -> notify -> PC.
# If the AT-09 UART is 115200 (matching the arm) we get the frame echo and/or
# the servo answer back over the air. Silence => baud mismatch (AT-09 at 9600).
import asyncio
import json
import sys
import time
from pathlib import Path

from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"
LOG_DIR = r"E:\competition\4_metrics\logs\2026-10-04_myarm2_b3_at09_air_config_run01"
FRAME = b"#001PRAD!"   # '#' servo-bus read frame (canonical; '$1PRAD!' is NOT
                       # in the STM32 $-table and is silently dropped)


def log(path, kind, **kw):
    ev = {"t": round(time.time(), 3), "kind": kind}
    ev.update(kw)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(ev, ensure_ascii=True) + "\n")
    return ev


async def main():
    out = Path(LOG_DIR)
    out.mkdir(parents=True, exist_ok=True)
    ev = out / "arm_probe_events.jsonl"
    events = []

    def on_notify(_h, data):
        events.append({"t": round(time.time(), 3), "rx_hex": data.hex(),
                       "rx_ascii": data.decode("latin1")})
        print("[notify] %r" % data)

    print("--- B3 arm probe %s  frame=%r ---" % (time.strftime("%F %T"),
                                                 FRAME))
    log(ev, "session", frame=FRAME.decode())
    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[link] connected mtu=%s" % client.mtu_size)
        await client.start_notify(FFE1, on_notify)
        for attempt in range(3):
            await client.write_gatt_char(FFE1, FRAME, response=False)
            print("[tx %d] %r sent, listening 6s..." % (attempt + 1, FRAME))
            await asyncio.sleep(6.0)
            if events:
                break
        print("[summary] %d notification(s)" % len(events))
        for e in events:
            log(ev, "notify", **e)
        v = "B3_AIR_ARM_ECHO_SEEN" if events else "B3_AIR_ARM_SILENT"
        print("VERDICT: %s" % v)
        log(ev, "verdict", v=v)
        return 0 if events else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
