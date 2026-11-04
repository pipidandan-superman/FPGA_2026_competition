# PC -> AT-09 FFE1 -> arm UART3 -> servo bus. Authorized MOTION demo.
# Sequence per manual rules (small-travel T<=500, >=150 counts/s, frame pacing):
#   1) #001PRAD!          read current position of servo 001 (upper arm)
#   2) #001P<pos+80>T0500! small move +80 counts @ 500ms (160 counts/s, in rule)
#   3) settle, then #001P<pos>T0500!  back to original position
#   4) #001PRAD!          verify returned position (tolerance +/-10)
# Every TX frame is echoed by the STM32 (zx_uart_send_str double-send);
# PRAD additionally gets the real servo answer (#001P....!). All logged.
import asyncio
import json
import re
import sys
import time
from pathlib import Path

from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"
LOG_DIR = r"E:\competition\4_metrics\logs\2026-10-05_myarm2_pc_motion_run01"
SID = 1                    # servo 001 = upper arm, proven good in recheck
DELTA = 80                 # small travel (recheck: 80@T400/500 precise)
T_MS = 500                 # small-travel rule T<=500; 80/0.5s = 160 counts/s


def log(path, kind, **kw):
    ev = {"t": round(time.time(), 3), "kind": kind}
    ev.update(kw)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(ev, ensure_ascii=True) + "\n")
    return ev


def parse_pos(events, sid):
    # servo answer like #001P1498! (clean '!' terminator, no \r\n)
    pat = re.compile(r"#%03dP(\d{4})!" % sid)
    for e in reversed(events):
        m = pat.search(e.get("rx_ascii", ""))
        if m:
            return int(m.group(1))
    return None


async def main():
    out = Path(LOG_DIR)
    out.mkdir(parents=True, exist_ok=True)
    ev = out / "pc_motion_events.jsonl"
    events = []

    def on_notify(_h, data):
        rec = {"t": round(time.time(), 3), "rx_hex": data.hex(),
               "rx_ascii": data.decode("latin1")}
        events.append(rec)
        print("[notify] %r" % data)

    async def send(frame, listen_s):
        print("[tx] %r" % frame)
        log(ev, "tx", frame=frame.decode())
        await client.write_gatt_char(FFE1, frame, response=False)
        await asyncio.sleep(listen_s)

    print("--- PC motion demo %s  servo=%03d delta=%d T=%d ---" %
          (time.strftime("%F %T"), SID, DELTA, T_MS))
    log(ev, "session", sid=SID, delta=DELTA, t_ms=T_MS)

    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[link] connected mtu=%s" % client.mtu_size)
        log(ev, "link", mtu=client.mtu_size)
        await client.start_notify(FFE1, on_notify)

        # 1) read current position
        await send(b"#%03dPRAD!" % SID, 2.0)
        pos0 = parse_pos(events, SID)
        print("[read] current pos = %s" % pos0)
        log(ev, "read_pos", pos=pos0)
        if pos0 is None:
            print("VERDICT: PC_MOTION_NO_READBACK")
            log(ev, "verdict", v="PC_MOTION_NO_READBACK")
            return 1
        tgt = min(max(pos0 + DELTA, 600), 2400)
        if not (600 <= tgt <= 2400):
            print("[abort] target %d out of safe range" % tgt)
            log(ev, "abort", target=tgt)
            return 1

        # 2) small move forward
        events.clear()
        await send(b"#%03dP%04dT%04d!" % (SID, tgt, T_MS),
                   T_MS / 1000.0 + 1.5)
        moved = parse_pos(events, SID) or tgt
        print("[moved] mid pos = %s (target %d)" % (moved, tgt))
        log(ev, "mid_pos", pos=moved, target=tgt)

        # 3) back to original
        events.clear()
        await send(b"#%03dP%04dT%04d!" % (SID, pos0, T_MS),
                   T_MS / 1000.0 + 1.5)

        # 4) verify
        events.clear()
        await send(b"#%03dPRAD!" % SID, 2.0)
        posf = parse_pos(events, SID)
        print("[final] pos = %s (start %s)" % (posf, pos0))
        log(ev, "final_pos", pos=posf, start=pos0)

        ok = (posf is not None and abs(posf - pos0) <= 10
              and abs(moved - tgt) <= 10)
        v = "PC_MOTION_PASS" if ok else "PC_MOTION_CHECK"
        print("VERDICT: %s  (start=%s mid=%s final=%s)" %
              (v, pos0, moved, posf))
        log(ev, "verdict", v=v, start=pos0, mid=moved, final=posf)
        return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
