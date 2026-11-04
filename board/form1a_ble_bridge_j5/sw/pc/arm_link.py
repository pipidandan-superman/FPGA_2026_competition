# Arm BLE link: PC (WinRT/bleak central) -> WeBotPi 013a (arm socket slave).
# B0 canon GATT: service FFE0, write=FFE2, notify=FFE1, MTU 517, no pairing.
# Laws encoded here (from myarm2/pai lines):
#  - STM32 echoes every TX frame (zx_uart_send_str double-send): real servo answer
#    is #NNNPdddd! with clean '!'; echo of a PRAD frame cannot match the position
#    regex ("PRAD" is not 4 digits), so parsing is echo-safe by construction.
#  - UART silent frame swallow: every motion frame is followed by PRAD read-back
#    reconciliation with retry (read_pos / move verify).
#  - Motion rules: small travel T<=500 and travel/T >= ~150 counts/s; servo range
#    [600,2400]; gripper 005 clamp [1133,1665] and slider-only usage.
import asyncio
import json
import re
import time

from bleak import BleakClient

FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"   # notify
FFE2 = "0000ffe2-0000-1000-8000-00805f9b34fb"   # write

SERVO_MIN = 600
SERVO_MAX = 2400
GRIPPER_ID = 5
GRIPPER_CLAMP = (1133, 1665)

_POS_PAT = {}


def _pos_pat(sid):
    if sid not in _POS_PAT:
        _POS_PAT[sid] = re.compile(r"#%03dP(\d{4})!" % sid)
    return _POS_PAT[sid]


class ArmLink:
    """Async BLE link to the arm's WeBotPi slave module."""

    def __init__(self, mac, on_event=None):
        self.mac = mac
        self.client = None
        self.events = []          # {t, rx_ascii}
        self.tx_count = 0
        self.rx_count = 0
        self._on_event = on_event

    async def connect(self, timeout=12.0):
        self.client = BleakClient(self.mac, timeout=timeout)
        await self.client.connect()
        await self.client.start_notify(FFE1, self._notify)
        return self.client.mtu_size

    async def disconnect(self):
        if self.client and self.client.is_connected:
            await self.client.disconnect()

    def _notify(self, _h, data):
        rec = {"t": time.time(), "rx_ascii": data.decode("latin1")}
        self.rx_count += 1
        self.events.append(rec)
        if self._on_event:
            self._on_event(rec)

    async def _write(self, frame: bytes):
        self.tx_count += 1
        await self.client.write_gatt_char(FFE2, frame, response=False)

    def _answers_after(self, t0):
        return [e for e in self.events if e["t"] >= t0]

    async def read_pos(self, sid, timeout=2.0, retries=3):
        """Send #NNNPRAD! and wait for the servo answer #NNNPdddd!."""
        for attempt in range(1, retries + 1):
            self.events.clear()
            t0 = time.time()
            await self._write(b"#%03dPRAD!" % sid)
            pat = _pos_pat(sid)
            while time.time() - t0 < timeout:
                for e in self._answers_after(t0):
                    m = pat.search(e["rx_ascii"])
                    if m:
                        return {"pos": int(m.group(1)), "attempt": attempt,
                                "rtt_ms": round((e["t"] - t0) * 1000.0, 1)}
                await asyncio.sleep(0.02)
        return None

    def _clamp(self, sid, pos):
        lo, hi = GRIPPER_CLAMP if sid == GRIPPER_ID else (SERVO_MIN, SERVO_MAX)
        return min(max(pos, lo), hi)

    async def move(self, sid, pos, t_ms, verify_tol=10, settle_margin=1.2,
                   max_retry=2):
        """Motion frame with read-back reconciliation (UART swallow law).
        Returns dict with timing + verification, or raises on persistent failure."""
        pos = self._clamp(sid, pos)
        if sid != GRIPPER_ID:
            assert t_ms <= 500, "small-travel rule: T<=500 (manual 2.6)"
        frame = b"#%03dP%04dT%04d!" % (sid, pos, t_ms)
        res = {"sid": sid, "target": pos, "t_ms": t_ms, "attempts": 0}
        t_tx = time.time()
        await self._write(frame)
        res["tx_t"] = t_tx
        await asyncio.sleep(t_ms / 1000.0 * settle_margin)
        for attempt in range(1, max_retry + 2):
            res["attempts"] = attempt
            rb = await self.read_pos(sid)
            if rb is None:
                # link dead or frame swallowed: re-send the motion frame
                await self._write(frame)
                await asyncio.sleep(t_ms / 1000.0 * settle_margin)
                continue
            res["readback"] = rb["pos"]
            res["prad_rtt_ms"] = rb["rtt_ms"]
            res["settled_ms"] = round((time.time() - t_tx) * 1000.0, 1)
            res["ok"] = abs(rb["pos"] - pos) <= verify_tol
            if res["ok"]:
                return res
            # partial move / still interpolating: wait and re-read
            await asyncio.sleep(0.4)
        res["ok"] = False
        return res


def verdict_line(v, **kw):
    return json.dumps({"verdict": v, **kw}, ensure_ascii=True)
