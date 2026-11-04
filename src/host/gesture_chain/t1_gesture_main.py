#!/usr/bin/env python3
# t1_gesture_main.py -- EES-331 T1 board main: camera -> PL preprocess ->
# NanoDet-Plus v5 (cv2.dnn) -> gesture policy -> BLE -> myArm2 action.
# (2026-10-19) Chain: VDMA snapshot (camera.py proven pattern) ->
# t1_preproc PL (resize+normalize bit-exact, dst = 1x3x320x320 fp32 CHW,
# feeds cv2.dnn directly) -> decode_nanodet (pc_webcam_demo.py proven) ->
# BoxOsd (pix_frame_display V2.0 dynamic box @0x43C30000 on HDMI) ->
# debounce/cooldown policy -> axi_ble_uart TX -> WeBotPi arm frames.
#
# Board contract (t1_overlay HWH, all resolved from ip_dict, not hard-coded):
#   axi_vdma_0   @ 0x43000000  3-slot 640x480x3 ring (camera.py config)
#   ble_uart_0   @ 0x43C10000  V1.1 CSR (ble_csr.v register map)
#   t1_preproc_0 @ 0x43C40000  CSR 0x00 go / 0x04 status(busy|irq w1c) /
#                              0x08 src / 0x0C dst / 0x10 VERSION=0x01000001
#   t1_text_osd_0 @ 0x43C50000 PL static text (V1.0, after pix_frame_display
#                              in the HDMI chain).  0x00 ID "TOVL" / 0x04 VER /
#                              0x08 X / 0x0C Y / 0x10 COLOR RGB / 0x14 NCHAR /
#                              0x18 CTRL en / 0x20+4i CHAR[i].  PL redraws the
#                              string on EVERY frame -> a resident model-name
#                              label costs ONE register write, zero ring
#                              writes, zero flicker (PS-side resident text is
#                              arithmetically impossible, v3.1 board-proven).
# Arm servo protocol (dxbt311_six_servo_demo proven 10-08):
#   frame '#%03dP%04dT%04d!' / read '#%03dPRAD!' answer '#%03dP%04d!'
#   sids 0-5; safe envelope +/-80 @ T500; gripper=5 clamp [1133,1665];
#   STM32 echoes every TX frame -- match 4-digit position for real answer.
#
# Gesture map v1 (user-delegated 10-19 "你来定，先跑起来再改"), all
# read->move->hold->return waves with +/-10 verify, conservative deltas:
#   Up(6)=shoulder up  Down(0)=shoulder down  Left(1)=base left
#   Right(2)=base right  Thumbs up(5)=grip close  Thumbs Down(4)=grip open
#   Stop(3)=no motion (log only -- safest)
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import signal
import socket
import struct
import sys
import threading
import time

import numpy as np

WIDTH, HEIGHT, STRIDE = 640, 480, 1920
FRAME_BYTES, SLOT_BYTES, SLOTS = 921600, 0x100000, 3
MM2S_CONTROL, S2MM_CONTROL = 0x1008B, 0x180CB
VDMA_ERROR_MASK = 0x8FF0
SRC_BYTES = 640 * 480 * 3          # 921600
DST_BYTES = 320 * 320 * 3 * 4      # 1228800 fp32 CHW
EXPECT_VER = 0x01000001

REG_MAX = 7
STRIDES = (8, 16, 32, 64)
# v5 class order (config_gesture_nanodet_plus_m_320_v5.yml class_names)
GESTURE_NAMES = ["Down", "Left", "Right", "Stop",
                 "Thumbs Down", "Thumbs up", "Up"]
DUMP_DIR = os.environ.get("T1_DUMP_DIR", "")
_dump_state = {"last": 0.0, "n": 0}

BIT_HASH = "5382fc78cbc8fa9da08e9ef65388fa7ac87d5210e01af2ec117e43ab2919f339"
HWH_HASH = "cf1b7539b1c3476d4aebe4a7e85e34ecd211d0cd97f38fa30a382d55702b5164"
ONNX_HASH = "dd751eb1fd3ae42fcc1d6d3d01c8aca42f9103d0bfaff46a1874fbd968324ffb"
NCNN_PARAM_HASH = "2c00f7ded2c78a0ed240be7cca0c00d515f5f38c4c544fb970d486af16acf737"
NCNN_BIN_HASH = "bb1692585c908e2deb77c8ab2cb042f90fc4d6ce11cc3bcc4f1cbd77b4b9caf0"

# gesture class index -> action steps [(sid, delta, t_ms, hold_s)]
# v2 BASIC map (user directive 10-19): direct single-servo control -- each
# fire nudges ONE servo by delta and STAYS there (repeated fires accumulate,
# no auto-return; old oscillate-and-return demo behaviour removed).
# Stop (cls 3) -> "HOME": reset all six servos to the factory home posture.
# Home = 1500us everywhere, per official MyArm32 firmware tb_global_init()
# (duoji_doing[i].aim = 1500 for all i) in 1_docs/第三方资料/视觉机械臂MyArm-2.
# gripper entries (sid 5) get the clamp/flip treatment automatically.
GESTURE_ACTIONS = {
    6: [ (1, -80, 500, 0.3) ],   # Up         -> shoulder up (stay)
    0: [ (1, +80, 500, 0.3) ],   # Down       -> shoulder down (stay)
    1: [ (0, -80, 500, 0.3) ],   # Left       -> base left (stay)
    2: [ (0, +80, 500, 0.3) ],   # Right      -> base right (stay)
    5: [ (5, -80, 500, 0.3) ],   # Thumbs up  -> grip close (stay)
    4: [ (5, +80, 500, 0.3) ],   # Thumbs Down-> grip open (stay)
    3: "HOME",                    # Stop       -> reset all servos to 1500
}
HOME_PWM = (1500, 1500, 1500, 1500, 1500, 1500)
HOME_T_MS = 1500
GRIP_SID, GRIP_LO, GRIP_HI = 5, 1133, 1665
GEN_LO, GEN_HI, POS_TOL = 600, 2400, 20

stopping = False


def log(ev, **kw):
    print(json.dumps(dict(event=ev, t=round(time.time(), 3), **kw)),
          flush=True)


def request_stop(signum, frame):
    global stopping
    stopping = True


def sha_ok(path, expect):
    actual = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    if actual != expect:
        raise RuntimeError("sha256 mismatch %s: %s != %s" % (path, actual, expect))
    return actual


# ---------------- VDMA camera (camera.py pattern, overlay owned by caller) --
class VdmaCam:
    def __init__(self, ol):
        from pynq import MMIO, allocate
        desc = ol.ip_dict["axi_vdma_0"]
        params = desc["parameters"]
        required = {"C_NUM_FSTORES": 3, "C_INCLUDE_SG": 0,
                    "C_M_AXIS_MM2S_TDATA_WIDTH": 24,
                    "C_S_AXIS_S2MM_TDATA_WIDTH": 24,
                    "C_MM2S_GENLOCK_MODE": 3, "C_S2MM_GENLOCK_MODE": 2}
        for key, value in required.items():
            if int(params[key]) != value:
                raise RuntimeError("VDMA param %s=%s" % (key, params[key]))
        self.mmio = MMIO(desc["phys_addr"], desc["addr_range"])
        self.last_slots = [None, None]
        self.same_count = [0, 0]
        self.warned = [False, False]
        self._stall_dumped = False
        self._live_ref = None
        self.reset()
        time.sleep(10.0)  # sensor settle after hot reload (EES-331 canon: SENSOR_SETTLE_SECONDS=10)
        self.buf = allocate(shape=(SLOTS, SLOT_BYTES), dtype="u1")
        base = self.buf.device_address
        if not (0x10000000 <= base and base + self.buf.nbytes <= 0x20000000):
            self.buf.freebuffer()
            self.buf = None
            raise RuntimeError("CMA %x outside proven HP1 window" % base)
        self.buf[:] = 0
        self.buf.flush()
        self.start()

    def read(self, reg):
        return self.mmio.read(reg)

    def write(self, reg, value):
        self.mmio.write(reg, int(value))

    def reset(self):
        for reg in (0, 0x30):
            self.write(reg, 4)
            deadline = time.monotonic() + 2
            while self.read(reg) & 4:
                if time.monotonic() >= deadline:
                    raise RuntimeError("VDMA reset timeout %#x" % reg)
                time.sleep(.001)
            self.write(reg + 4, 0xFFF0)

    def slots(self):
        park = self.read(0x28)
        return [(park >> 16) & 31, (park >> 24) & 31]

    def _ring_content(self, nbytes=4096):
        """Content sample of the S2MM parked slot (camera-side truth that
        the slot INDEX cannot fake -- see status() aliasing note)."""
        slot = self.slots()[1]
        view = self.buf[slot, :nbytes]
        view.invalidate()
        return view.tobytes()

    def status(self):
        """Slot-index movement is sampled at the inference cadence (seconds),
        so a 3-slot ring aliases: P(same index at two samples) = 1/3. Worse,
        when fps_cam / fps_read lands near a multiple of 3 (measured 2026-10-20:
        ~30 fps cam, ~0.89 fps read -> 33.6), the index alias-LOCKS for many
        consecutive samples and recovers when the ratio drifts -- the old
        detector suicided the chain three times on this artifact (frames
        114/231/278), never on a real stall. Stall detection therefore gates
        the index streak on ring CONTENT: index frozen + content frozen =
        real stall; index frozen + content changing = alias, keep running.
        Warn at 4 (~16 s), dump at 8, give up at 16."""
        slots = self.slots()
        for i in (0, 1):
            if self.read((0, 0x30)[i] + 4) & VDMA_ERROR_MASK:
                raise RuntimeError("VDMA_ERROR %#x"
                                   % self.read((0, 0x30)[i] + 4))
            if slots[i] != self.last_slots[i]:
                self.last_slots[i] = slots[i]
                self.same_count[i] = 0
                self.warned[i] = False
                self._live_ref = None
            else:
                if i == 1:
                    cur = self._ring_content()
                    if self._live_ref is None:
                        self._live_ref = cur       # streak-start reference
                    elif cur != self._live_ref:
                        # index alias-locked but the camera is still
                        # writing -- the ring is alive; reset the streak
                        self.same_count = [0, 0]
                        self.warned = [False, False]
                        self._live_ref = None
                        log("VDMA_ALIAS_RECOVERED", slots=slots)
                        continue
                self.same_count[i] += 1
                if self.same_count[i] >= 8:
                    if not self._stall_dumped:
                        # Forensics mode (2026-10-20): the recurring ring
                        # freeze (~5 min, 114-278 frames, PS-burns exonerated
                        # by the --no-text-osd isolation run) must be caught
                        # red-handed. Dump the whole VDMA register file once
                        # per stall episode, then keep sampling so we learn
                        # whether the channel recovers; give up at 16 samples.
                        self._stall_dumped = True
                        dump = {}
                        for r in range(0, 0x100, 4):
                            v = self.read(r)
                            if v:
                                dump[hex(r)] = hex(v)
                        log("VDMA_STALL_DUMP", channel=i, slots=slots,
                            regs=dump)
                    if self.same_count[i] >= 16:
                        raise RuntimeError("VDMA_STREAM_STALLED slots=%s"
                                           % slots)
                if self.same_count[i] >= 4 and not self.warned[i]:
                    self.warned[i] = True
                    log("VDMA_STALL_WARN", channel=i, slots=slots)
        return dict(slots=slots,
                    mm2s_sr=hex(self.read(4)), s2mm_sr=hex(self.read(0x34)))

    def start(self):
        base = self.buf.device_address
        self.write(0x30, S2MM_CONTROL)
        for i in range(SLOTS):
            self.write(0xAC + 4 * i, base + i * SLOT_BYTES)
        self.write(0xA8, STRIDE)
        self.write(0xA4, STRIDE)
        self.write(0xA0, HEIGHT)
        for i in range(SLOTS):
            self.write(0x5C + 4 * i, base + i * SLOT_BYTES)
        self.write(0x58, STRIDE)
        self.write(0x54, STRIDE)
        self.write(0, MM2S_CONTROL)
        self.write(0x50, HEIGHT)
        initial = self.slots()
        seen = [False, False]
        deadline = time.monotonic() + 5
        while not seen[0]:
            for i, current in enumerate(self.slots()):
                seen[i] |= current != initial[i]
            if stopping or time.monotonic() > deadline:
                raise RuntimeError("FIRST_FRAME_TIMEOUT seen=%s" % seen)
            time.sleep(.001)
        time.sleep(.1)
        if self.read(4) & VDMA_ERROR_MASK or self.read(0x34) & 0x60:
            raise RuntimeError("Nonrecoverable startup VDMA error")
        self.write(4, 0xFFF0)
        self.write(0x34, 0xFFF0)
        self.last_slots = self.slots()
        self.same_count = [0, 0]
        self.warned = [False, False]
        self._live_ref = None

    def snapshot(self, retries=6):
        for _ in range(retries):
            started = time.monotonic()
            writer = self.slots()[1]
            slot = (writer + SLOTS - 1) % SLOTS
            view = self.buf[slot, :FRAME_BYTES]
            view.invalidate()
            frame = view.tobytes()
            if self.slots()[1] == writer and time.monotonic() - started < .010:
                return frame
            time.sleep(.005)
        return None

    def close(self):
        if getattr(self, "mmio", None) is None:
            return
        for reg in (0, 0x30):
            self.write(reg, self.read(reg) & ~1)
        deadline = time.monotonic() + 2
        while not all(self.read(r) & 1 for r in (4, 0x34)):
            if time.monotonic() >= deadline:
                self.reset()
                break
            time.sleep(.001)
        if getattr(self, "buf", None) is not None:
            self.buf.freebuffer()
            self.buf = None


# ---------------- t1_preproc PL ------------------------------------------------
class Preproc:
    def __init__(self, ol):
        from pynq import MMIO, allocate
        desc = ol.ip_dict["t1_preproc_0"]
        self.mmio = MMIO(desc["phys_addr"], desc["addr_range"])
        if self.mmio.read(0x10) != EXPECT_VER:
            raise RuntimeError("t1_preproc VERSION %#x" % self.mmio.read(0x10))
        self.src = allocate(SRC_BYTES, dtype=np.uint8)
        self.dst = allocate(DST_BYTES, dtype=np.uint8)
        for b, n in ((self.src, SRC_BYTES), (self.dst, DST_BYTES)):
            lo, hi = b.device_address, b.device_address + n
            if not ((0x10000000 <= lo and hi <= 0x20000000)
                    or (hi <= 0x10000000)):
                raise RuntimeError("t1 buf %#x+%x outside HP windows" % (lo, n))

    def run(self, frame_bytes):
        """frame -> (blob 1x3x320x320 fp32 view, wall_seconds). The returned
        view aliases the PL dst buffer and is valid until the next run()."""
        src_view = np.frombuffer(self.src, dtype=np.uint8)
        src_view[:] = np.frombuffer(frame_bytes, dtype=np.uint8)
        self.src.flush()
        self.mmio.write(0x08, self.src.physical_address)
        self.mmio.write(0x0C, self.dst.physical_address)
        self.mmio.write(0x00, 1)
        t0 = time.monotonic()
        deadline = t0 + 5
        while self.mmio.read(0x04) & 1:
            if time.monotonic() > deadline:
                raise RuntimeError("t1_preproc busy timeout")
            time.sleep(.001)
        wall = time.monotonic() - t0
        self.dst.invalidate()
        blob = np.frombuffer(self.dst, dtype=np.uint8).view(np.float32)
        return blob.reshape(1, 3, 320, 320), wall

    def close(self):
        for name in ("src", "dst"):
            b = getattr(self, name, None)
            if b is not None:
                b.freebuffer()
                setattr(self, name, None)


class ModelBtn:
    """t1_model_btn PL DIP-switch model cycler (@0x43C60000): each toggle
    bumps an internal 0->1->2 counter; PS only polls 0x08 PRESSES delta and
    reads 0x04 MODEL. Absent from the bit (older v6/v7) = silently idle."""
    ID = 0x5442544E  # "TBTN"

    def __init__(self, ol):
        from pynq import MMIO
        desc = ol.ip_dict.get("t1_model_btn_0")
        self.mmio = MMIO(desc["phys_addr"], desc["addr_range"]) if desc else None
        self.presses = self.mmio.read(0x08) & 0xFFFF if self.mmio else 0

    def poll(self):
        """Return the model id once per new toggle, else None."""
        if self.mmio is None or self.mmio.read(0x00) != self.ID:
            return None
        n = self.mmio.read(0x08) & 0xFFFF
        if n == self.presses:
            return None
        self.presses = n
        return self.mmio.read(0x04) & 0x3


# ---------------- HDMI dynamic bounding box (pix_frame_display V2.0) -----------
class BoxOsd:
    """PS-driven dynamic box on the HDMI overlay stage (pix_frame_display_0
    @ 0x43C30000 in t1_overlay). V2.0 RTL has NO static OSD (legacy center
    frame + ROM digit deleted per user directive); it draws nothing until PS
    enables the box.  Register map: 0x00 ID "GBOX", 0x08 L, 0x0C R, 0x10 T,
    0x14 B (10-bit, inclusive, 640x480 pixel domain), 0x18 CTRL bit0 en.
    Safe update: clear en -> write coords -> set en (frame-boundary shadow
    latch in RTL, no tearing)."""

    def __init__(self, ol):
        from pynq import MMIO
        if "pix_frame_display_0" not in ol.ip_dict:
            self.mmio = None
            return
        desc = ol.ip_dict["pix_frame_display_0"]
        self.mmio = MMIO(desc["phys_addr"], desc["addr_range"])
        if self.mmio.read(0x00) != 0x47424F58:      # "GBOX"
            raise RuntimeError("pix_frame_display ID %#x"
                               % self.mmio.read(0x00))
        self.mmio.write(0x18, 0)

    def show(self, det):
        """det: decode_nanodet entry with xyxy_px in 320x320 model space
        (preproc does per-axis direct resize 640x480 -> 320x320, proven
        bit-exact vs cv2 in bringup), so x*2 / y*1.5 maps to display
        pixels. None clears the box."""
        if self.mmio is None:
            return
        if det is None:
            self.mmio.write(0x18, 0)
            return
        x0, y0, x1, y1 = det["xyxy_px"]
        l = max(0, min(639, int(x0 * 2)))
        r = max(0, min(639, int(x1 * 2)))
        t = max(0, min(479, int(y0 * 1.5)))
        b = max(0, min(479, int(y1 * 1.5)))
        if r - l < 4:
            r = min(639, l + 4)
        if b - t < 4:
            b = min(479, t + 4)
        self.mmio.write(0x18, 0)
        self.mmio.write(0x08, l)
        self.mmio.write(0x0C, r)
        self.mmio.write(0x10, t)
        self.mmio.write(0x14, b)
        self.mmio.write(0x18, 1)


# ---------------- PL-side fixed-bitmap label + score (t1_label_osd V2.0) ----
class PlTextOsd:
    """Resident "NET:Gesture + score" strip drawn by PL on every HDMI frame
    (t1_label_osd inside cell t1_text_osd_0, 0x43C50000; 2026-10-21 V2.0
    replaces the general text engine t1_text_gen).  One ROM holds 24 fixed
    "NET:Gesture" bitmaps (3 nets x 8 states: 7 gestures + None) plus 10
    score digits; the PS writes ONE packed CODE register and the PL
    re-rasters the 184x32 strip EVERY FRAME -- zero display-ring writes,
    zero VDMA interaction, flicker-free by construction (same pattern as
    the PL box; the PS-burn TextOsd below is fully retired).

    Register map: 0x00 ID "TLBL", 0x08 CODE [4:0]=label (0=hide strip,
    1..24) [8:5]=digit (0=hide, 1..9), 0x0C X, 0x10 Y, 0x14 FG, 0x18 BG,
    0x1C ROMIDX word-address readback.  label code = net_id*8 + state + 1
    with state 0..6 = gesture class index, 7 = 无手势 (no detection).
    Frame-boundary shadow latch in RTL: a mid-frame write lands on the
    NEXT frame (xsim G5).  Wall-clock holds via show(hold_s=..) + tick()."""

    NSTATES = 8                      # 7 gestures + None

    def __init__(self, ol, x=440, y=16, fg=0x00FF00, bg=0x000000):
        from pynq import MMIO
        self.mmio = None
        self._deadline = 0.0
        self._idle_code = 0      # 0 = blank when idle (CODE 0 gates strip)
        self._last_code = None   # change-guard: AXI write only on change
        if "t1_text_osd_0" not in ol.ip_dict:
            return
        desc = ol.ip_dict["t1_text_osd_0"]
        self.mmio = MMIO(desc["phys_addr"], desc["addr_range"])
        if self.mmio.read(0x00) != 0x544C424C:      # "TLBL"
            raise RuntimeError("t1_label_osd ID %#x" % self.mmio.read(0x00))
        self.mmio.write(0x08, 0)                    # CODE = hidden
        self.mmio.write(0x0C, int(x) & 0x3FF)       # X (default 440)
        self.mmio.write(0x10, int(y) & 0x3FF)       # Y (default 16)
        self.mmio.write(0x14, int(fg) & 0xFFFFFF)   # FG green
        self.mmio.write(0x18, int(bg) & 0xFFFFFF)   # BG black plate

    def _write(self, code):
        if self.mmio is not None and code != self._last_code:
            self.mmio.write(0x08, code)
            self._last_code = code

    def show(self, net_id, state=None, score=None, hold_s=0.0):
        """net_id: 0/1/2.  state: gesture class 0..6, or None (=无手势).
        score: 0..1 -> one-decimal digit (clamped 1..9; the 0.5 box gate
        means 5..9 in practice; None hides the digit).  hold_s > 0 arms a
        wall-clock auto-revert to the idle banner; 0 = stay until the next
        show().  Returns False when the PL block is absent."""
        if self.mmio is None:
            return False
        if net_id is None:
            code = 0
        else:
            state = 7 if state is None else int(state)
            label = int(net_id) * self.NSTATES + state + 1
            digit = 0
            if score is not None:
                digit = min(9, max(1, int(float(score) * 10)))
            code = label | (digit << 5)
        self._write(code)
        self._deadline = (time.monotonic() + hold_s) if hold_s > 0 else 0.0
        return True

    def idle(self, net_id):
        """Persistent idle banner "NET:None" (digit hidden).  After every
        hold expiry tick() reverts to THIS code instead of a blank strip
        (2026-10-21 user ruling: the strip always shows net + none)."""
        self._idle_code = (int(net_id) * self.NSTATES + 7 + 1) \
            if net_id is not None else 0
        self.show(net_id, None, None)

    def clear(self):
        if self.mmio is not None:
            self._write(0)
        self._deadline = 0.0

    def tick(self):
        """Once per main-loop iteration: expire wall-clock holds back to
        the idle banner (never to a blank strip when idle is armed)."""
        if self._deadline and time.monotonic() >= self._deadline:
            self._deadline = 0.0
            self._write(self._idle_code)


# ---------------- PS-side label text into the live display ring ---------------
class TextOsd(threading.Thread):
    """Burns the current label into the VDMA display ring so the HDMI video
    shows text the PL box cannot draw. Small top-left strip; MM2S may tear
    a line while we write -- tearing-tolerant by design.

    v3 (2026-10-20 night, board-proven bisect): CHANGE-TRIGGERED burning
    only. Per-frame ring annotation freezes the genlocked VDMA ring on this
    board (4/6 chain deaths <=26 s with frame-rate burning, 0/2 with the
    thread absent; camera.py 4/4 stable; C1 survived 48 min only because its
    banner was empty without detections, i.e. TextOsd idled). v3 therefore
    burns ONLY when the label text changes (model rotation / detection
    appear / score text) -- a short flash, never a periodic rewrite.
    Detection-hold frames do re-burn per frame (score text changes) = the
    C1-proven pattern. Poll relaxed 2 ms -> 20 ms. Writes stay UNCACHED
    (/dev/mem O_SYNC alias, no pynq buf.flush() ever -- flush() at frame
    rate is a confirmed ring-killer suspect). Requires root; without
    /dev/mem the banner is silently skipped.

    v3.1 (2026-10-20, 全面修复): two user-visible defects fixed.
    (a) The label vanished the instant the ~1.8 s flash scrolled away while
    a detection was still held -> re-burn while a label is active.
    (b) The box carried no identification -> the strip renders just ABOVE
    the active box (y passed from the caller, display-pixel row), clamped
    to the frame, with the previous strip location cleared on moves.

    v3.2 (2026-10-20, board-proven AGAIN): v3.1's unconditional 1.2 s
    re-burn of a NON-EMPTY banner froze the ring ~5 s after every launch
    (the banner is non-empty whenever the chain idles, so periodic ring
    writes ran with an infinite duty cycle).  Refined law: brief burn
    BURSTS (C1 detection-holds, a handful of burns) are safe; SUSTAINED
    periodic writes at any tested rate (0.83-5/s) kill within seconds.
    Therefore: re-burn exists ONLY for detection-held labels
    (set(persist=True), capped at MAX_REBURNS per episode ~ 15 s) and the
    idle state keeps the label EMPTY -- zero ring writes until the next
    real change.  A model-switch banner is a one-shot flash
    (persist=False), never refreshed."""

    STRIP_ROWS = 27
    REBURN_SECS = 1.5
    MAX_REBURNS = 10               # per episode: ~15 s persistence cap

    def __init__(self, cam):
        super().__init__(daemon=True)
        self.cam = cam
        self._label = ""
        self._y = 0
        self._persist = False
        self._lock = threading.Lock()
        self._dirty = False
        self._strip_dst = None
        self._last_yoff = None
        self._burns = 0

    def set(self, text, y=0, persist=False):
        """text: label ("" = idle, no ring writes).  y: display-pixel row
        for the strip (caller maps the box top into 640x480 space).
        persist=True asks the 1.5 s re-burn (detection-held labels only,
        budget-capped).  Dirty on text/y change OR on a new persist
        episode so a re-appearing identical label re-burns once."""
        with self._lock:
            if (text != self._label or y != self._y
                    or (persist and not self._persist)):
                self._label = text
                self._y = y
                self._dirty = True
                self._burns = 0
            self._persist = persist and bool(text)

    def _open_uncached(self):
        import mmap
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        base = self.cam.buf.device_address
        mem = mmap.mmap(fd, SLOT_BYTES * SLOTS, offset=base)
        os.close(fd)
        self._strip_dst = [np.frombuffer(mem, dtype=np.uint8,
                                         count=SLOT_BYTES, offset=i * SLOT_BYTES)
                           for i in range(SLOTS)]

    def _burn(self, text, y):
        import cv2
        strip = np.zeros((self.STRIP_ROWS, WIDTH, 3), np.uint8)
        cv2.rectangle(strip, (0, 0), (WIDTH - 1, 26), (0, 0, 0), -1)
        cv2.putText(strip, text, (4, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.6,
                    (0, 255, 0), 2)
        flat = strip.reshape(-1)
        n = self.STRIP_ROWS * STRIDE
        yoff = int(max(0, min(HEIGHT - self.STRIP_ROWS, y))) * STRIDE
        for slot in range(SLOTS):   # all slots: flash survives ~1 frame x3
            dst = self._strip_dst[slot]
            if self._last_yoff is not None and self._last_yoff != yoff:
                dst[self._last_yoff:self._last_yoff + n] = 0   # clear old
            dst[yoff:yoff + n] = flat
        self._last_yoff = yoff

    def run(self):
        try:
            self._open_uncached()
        except OSError as e:
            self._strip_dst = None
            log("TEXT_OSD_UNCACHED_FAIL", error=str(e))
        last_burn = 0.0
        while not stopping and self.cam.mmio is not None:
            with self._lock:
                text, y, dirty, persist = (self._label, self._y, self._dirty,
                                           self._persist)
                if dirty:
                    self._dirty = False
            now = time.monotonic()
            if not (text and self._strip_dst is not None):
                time.sleep(0.02)
                continue
            if dirty:
                do_burn = True
            elif persist and self._burns < self.MAX_REBURNS \
                    and now - last_burn >= self.REBURN_SECS:
                do_burn = True          # held-detection persistence, capped
            else:
                do_burn = False         # idle: ZERO ring writes
            if do_burn:
                try:
                    self._burn(text, y)
                    last_burn = now
                    self._burns += 1
                except Exception:
                    pass
            time.sleep(0.02)


# ---------------- inference engines --------------------------------------------
class NcnnTcp:
    """NanoDet via the local t1_ncnn_server (C++ libncnn.a NEON, A9-proven
    0.973s/frame single-thread -- 2x cv2.dnn). Framing: uint32 LE length +
    payload each way. Request = 320*320*3 fp32 CHW blob bytes; reply =
    2125*39 fp32 (same layout as cv2 output reshaped (grids, -1))."""

    def __init__(self, host, port):
        self.dest = (host, port)
        self.sock = socket.create_connection(self.dest, timeout=30)
        self.sock.settimeout(30)

    def _recv_full(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise RuntimeError("ncnn_server closed connection")
            buf += chunk
        return buf

    def infer(self, blob, model_id=None):
        """blob: (1,3,320,320) fp32 -> flat fp32 output (variable length,
        caller decodes per active model). model_id selects the multi-model
        registry entry on t1_ncnn_server_multi (swap = table switch);
        None = legacy single-model framing (backward compatible).
        On timeout/stale socket: one reconnect + resend (the server is
        single-client and serializes requests; a >30 s stall must not kill
        the chain -- board-proven 2026-10-20 when a batch client held the
        server busy)."""
        payload = blob.tobytes()
        head = (struct.pack("<I", len(payload)) if model_id is None
                else struct.pack("<II", model_id, len(payload)))
        for attempt in (1, 2):
            try:
                self.sock.sendall(head + payload)
                (olen,) = struct.unpack("<I", self._recv_full(4))
                return np.frombuffer(self._recv_full(olen), dtype=np.float32)
            except (socket.timeout, TimeoutError, BrokenPipeError,
                    ConnectionResetError, RuntimeError):
                if attempt == 2:
                    raise
                try:
                    self.sock.close()
                except OSError:
                    pass
                time.sleep(0.5)
                self.sock = socket.create_connection(self.dest, timeout=30)
                self.sock.settimeout(30)


def make_engine(args):
    """Returns infer(blob_fp32_1x3x320x320) -> raw fp32 array (caller
    reshapes to (n_anchors, 39) after the zeros probe)."""
    if args.engine == "ncnn":
        host, port = args.ncnn_addr.rsplit(":", 1)
        ncnn = NcnnTcp(host, int(port))
        return ncnn.infer
    import cv2
    cv2.setNumThreads(2)  # cv2 4.5.4: dnn_Net has no setNumThreads; global
    net = cv2.dnn.readNetFromONNX(args.onnx)
    net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
    net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)

    def infer_cv2(blob, model_id=None):
        if model_id not in (None, 0):
            raise RuntimeError("cv2 engine has no multi-model registry")
        net.setInput(blob)
        return np.asarray(net.forward()).reshape(-1)

    return infer_cv2


# ---------------- NanoDet decode (pc_webcam_demo.py proven) -------------------
def dump_maybe(frame, blob, out, dets):
    """Failure forensics: save raw frame + PL blob + per-class scores when the
    TD/TU failure fingerprint appears (both thumb classes moderately high, or
    weak thumb top-1). T1_DUMP_DIR env enables; rate-limited 1.5s, cap 300."""
    if getattr(out, "ndim", 0) < 2 or out.shape[1] < 7:
        return  # NanoDet-shaped fingerprint only; yolo-slot outputs are 1-D
    cls7 = out[:, :7]
    per_cls = cls7.max(axis=0)
    s_td, s_tu = float(per_cls[4]), float(per_cls[5])
    top1_i = int(per_cls.argmax())
    top1 = float(per_cls[top1_i])
    sig = (min(s_td, s_tu) > 0.35
           or top1_i in (4, 5))
    now = time.monotonic()
    if not sig or now - _dump_state["last"] < 1.5 or _dump_state["n"] >= 300:
        return
    if _dump_state["n"] == 0:
        os.makedirs(DUMP_DIR, exist_ok=True)
    _dump_state["last"] = now
    _dump_state["n"] += 1
    ts = time.strftime("%H%M%S") + "_%03d" % _dump_state["n"]
    base = os.path.join(DUMP_DIR, ts)
    np.save(base + ".npy", np.ascontiguousarray(blob))
    with open(base + ".bgr", "wb") as f:
        f.write(frame)
    import json as _json
    with open(base + ".json", "w") as f:
        _json.dump({"per_cls_max": [round(float(v), 4) for v in per_cls],
                    "top1": [GESTURE_NAMES[top1_i], round(top1, 4)],
                    "dets_top3": dets[:3]}, f)
    log("DUMP_SAVED", file=os.path.basename(base),
        td=round(s_td, 3), tu=round(s_tu, 3))


def build_grids(input_size, n_anchors):
    grids = []
    total = 0
    s = 8
    while total < n_anchors and s <= input_size:
        hs = input_size // s
        for y in range(hs):
            for x in range(hs):
                grids.append((x, y, s))
        total += hs * hs
        s *= 2
    if total != n_anchors:
        raise ValueError("no stride ladder matches %d anchors" % n_anchors)
    return np.asarray(grids, dtype=np.float32)


def decode_nanodet(out, grids, score_thr, nms_thr):
    import cv2
    n, channels = out.shape
    n_cls = channels - 4 * (REG_MAX + 1)
    cls = out[:, :n_cls]
    reg = out[:, n_cls:].reshape(n, 4, REG_MAX + 1)
    scores = cls.max(axis=1)          # sigmoid baked into ONNX -- do NOT reapply
    labels = cls.argmax(axis=1)
    reg = reg - reg.max(axis=2, keepdims=True)
    e = np.exp(reg)
    reg_prob = e / e.sum(axis=2, keepdims=True)
    bins = np.arange(REG_MAX + 1, dtype=np.float32)
    dist = (reg_prob * bins).sum(axis=2)
    stride = grids[:, 2:3]
    center = (grids[:, :2] + 0.5) * stride
    dpx = dist * stride
    x0 = center[:, 0] - dpx[:, 0]
    y0 = center[:, 1] - dpx[:, 1]
    x1 = center[:, 0] + dpx[:, 2]
    y1 = center[:, 1] + dpx[:, 3]
    keep = scores >= score_thr
    if not keep.any():
        return []
    boxes = np.stack([x0[keep], y0[keep], x1[keep], y1[keep]], axis=1)
    scores_k, labels_k = scores[keep], labels[keep]
    idxs = cv2.dnn.NMSBoxes(
        [[float(b[0]), float(b[1]), float(b[2] - b[0]), float(b[3] - b[1])]
         for b in boxes],
        [float(s) for s in scores_k], float(score_thr), float(nms_thr))
    idxs = np.asarray(idxs).reshape(-1)
    results = [{"cls": int(labels_k[i]), "score": round(float(scores_k[i]), 4),
                "xyxy_px": [round(float(v), 2) for v in boxes[i]]}
               for i in idxs]
    results.sort(key=lambda r: -r["score"])
    return results


# ---------------- C2 multi-model (baseline arm) -------------------------------
# Server registry ids must match c2_registry.conf on the board. Swap = table
# switch in t1_ncnn_server_multi (all nets preloaded at boot).
C2_MODELS = {
    0: ("NanoDet-v65", "nanodet"),
    1: ("YOLOv8n-v4", "yolo"),
    2: ("YOLO11n-v4", "yolo"),
}
C2_ROTATION = [0, 1, 2]


def decode_yolo(out, score_thr, nms_thr, size=320):
    """output0 layout (zeros-input probe 2026-10-20): ch0-3 = decoded xywh
    in pixels (DFL decode baked into the export graph), ch4-10 = raw cls
    LOGITS (sigmoid applied HERE in PS -- SPEC C4: decode 留 PS).
    Returns the same det dicts as decode_nanodet."""
    import cv2
    a = np.asarray(out).reshape(-1, 2100)            # (11, 2100)
    box = a[:4].T                                    # (2100, 4) xywh px
    logits = a[4:].T                                 # (2100, 7)
    cls = 1.0 / (1.0 + np.exp(-logits))
    scores = cls.max(axis=1)
    labels = cls.argmax(axis=1)
    # Ghost-artifact suppression (board finding 2026-10-20, 全面修复): on an
    # empty background every cls logit ~0, so sigmoid lands at 0.5000-0.5001
    # and a plain `scores >= 0.5` gate admits ALL 2100 anchors to NMS ->
    # flickering phantom boxes with no object present.  Live true detections
    # scored 0.5077-0.62.  Floor the gate just above the ghost band; the
    # exact floor was confirmed against the through-board dataset test TP
    # score distribution (c2_board_run01/eval).
    keep = (scores >= score_thr) & (scores > 0.505)
    if not keep.any():
        return []
    bx = box[keep]
    cx, cy, w, h = bx[:, 0], bx[:, 1], bx[:, 2], bx[:, 3]
    x0 = np.clip(cx - w / 2, 0, size)
    y0 = np.clip(cy - h / 2, 0, size)
    x1 = np.clip(cx + w / 2, 0, size)
    y1 = np.clip(cy + h / 2, 0, size)
    boxes = np.stack([x0, y0, x1, y1], axis=1)
    scores_k, labels_k = scores[keep], labels[keep]
    idxs = cv2.dnn.NMSBoxes(
        [[float(b[0]), float(b[1]), float(b[2] - b[0]), float(b[3] - b[1])]
         for b in boxes],
        [float(s) for s in scores_k], float(score_thr), float(nms_thr))
    idxs = np.asarray(idxs).reshape(-1)
    results = [{"cls": int(labels_k[i]), "score": round(float(scores_k[i]), 4),
                "xyxy_px": [round(float(v), 2) for v in boxes[i]]}
               for i in idxs]
    results.sort(key=lambda r: -r["score"])
    return results


def decode_dispatch(model_id, raw, grids, score_thr, nms_thr):
    """-> (dets, per_cls7, out_for_dump). One entry point per active model."""
    name, dec = C2_MODELS[model_id]
    if dec == "nanodet":
        out = np.asarray(raw).reshape(len(grids), -1)
        return decode_nanodet(out, grids, score_thr, nms_thr), \
            out[:, :7].max(axis=0), out
    cls = 1.0 / (1.0 + np.exp(-np.asarray(raw).reshape(-1, 2100)[4:].T))
    return decode_yolo(raw, score_thr, nms_thr), cls.max(axis=0), \
        np.asarray(raw)


# ---------------- BLE UART + arm frames ---------------------------------------
class UdpBle:
    """Arm-transport shim over UDP to the PC BLE bridge (user ruling 10-19:
    board lacks the matching BLE module; the PC simulates the FPGA Bluetooth
    output). send_frame() does a request/response round trip; the bridge
    returns everything the arm notified during its collect window, which
    rx_drain() hands out once."""

    def __init__(self, host, port, timeout=4.0):
        import socket
        self.dest = (host, port)
        self.timeout = timeout
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._pending = b""

    def send_frame(self, frame, timeout=None):
        self.sock.settimeout(timeout or self.timeout)
        self._pending = b""
        self.sock.sendto(bytes(frame), self.dest)
        try:
            rx, _ = self.sock.recvfrom(4096)
            self._pending = rx
        except Exception:
            self._pending = b""
        return len(frame)

    def rx_drain(self):
        # Drain the OS UDP buffer for real. The old version only handed out
        # the single datagram captured by send_frame's recvfrom; anything
        # that arrived while no recvfrom was blocked stayed stranded and was
        # consumed by the NEXT transaction, so position reads lagged one
        # response behind and final readbacks always timed out
        # (ACTION_DONE ok=false, final=null over the PC bridge).
        out, self._pending = self._pending, b""
        try:
            self.sock.setblocking(False)
            while True:
                try:
                    d, _ = self.sock.recvfrom(4096)
                    out += d
                except OSError:
                    break
        finally:
            self.sock.settimeout(self.timeout)
        return out


class BleUart:
    """axi_ble_uart V1.1 CSR. Transport: write frame bytes to 0x400 page,
    TX_LEN, TX_GO; RX ring drained from 0x800 page by RX_PROD/RX_CONS."""

    def __init__(self, ol):
        from pynq import MMIO
        desc = ol.ip_dict["ble_uart_0"]
        self.mmio = MMIO(desc["phys_addr"], desc["addr_range"])
        if self.mmio.read(0x00) != 0x424C4531:
            raise RuntimeError("ble_uart ID %#x" % self.mmio.read(0x00))
        # release restart hold -> power FSM runs (~1.1 s to bt_ready)
        self.mmio.write(0x0C, 0)
        deadline = time.monotonic() + 5
        while not (self.mmio.read(0x10) & 1):
            if time.monotonic() > deadline:
                raise RuntimeError("bt_ready timeout")
            time.sleep(.05)

    def send_frame(self, frame, timeout=3.0):
        """Blocking byte-by-byte page write + TX_GO; returns TX_COUNT."""
        if not 1 <= len(frame) <= 256:
            raise ValueError("frame len %d" % len(frame))
        deadline0 = time.monotonic() + timeout
        while self.mmio.read(0x10) & 2:      # tx_busy
            if time.monotonic() > deadline0:
                raise RuntimeError("tx_busy stuck")
            time.sleep(.005)
        for i, b in enumerate(frame):
            self.mmio.write(0x400 + 4 * i, b)
        self.mmio.write(0x18, len(frame))
        self.mmio.write(0x1C, 1)
        deadline = time.monotonic() + timeout
        while self.mmio.read(0x10) & 2:
            if time.monotonic() > deadline:
                raise RuntimeError("tx timeout")
            time.sleep(.005)
        return self.mmio.read(0x20)

    def rx_drain(self):
        prod, cons = self.mmio.read(0x24), self.mmio.read(0x28)
        out = bytearray()
        while cons != prod:
            out.append(self.mmio.read(0x800 + 4 * (cons & 0xFF)) & 0xFF)
            cons += 1
        if out:
            self.mmio.write(0x28, prod)
        return bytes(out)


class ArmLink:
    """WeBotPi servo-bus frames over ble_uart. STM32 echoes every TX frame;
    a real answer is '#NNNPdddd!' with 4-digit position (echo of a PRAD
    frame never matches -- 'PRAD' is not 4 digits)."""

    POS_PAT = {s: re.compile(rb"#%03dP(\d{4})!" % s) for s in range(6)}

    def __init__(self, ble):
        self.ble = ble

    def _transact(self, frame, listen_s):
        self.ble.send_frame(frame)
        t0 = time.monotonic()
        buf = b""
        while time.monotonic() - t0 < listen_s:
            buf += self.ble.rx_drain()
            if buf:
                time.sleep(0.05)
            else:
                time.sleep(0.02)
        return buf

    def read_pos(self, sid, timeout=2.0):
        """Position readback with EARLY RETURN (user latency directive
        10-19): send PRAD once, poll until the answer pattern actually
        arrives. The old path burned the full 1.2s listen window on EVERY
        read (~2.4s dead time per action, action latency ~8s end-to-end)."""
        self.ble.send_frame(b"#%03dPRAD!" % sid)
        deadline = time.monotonic() + timeout
        buf = b""
        while time.monotonic() < deadline:
            buf += self.ble.rx_drain()
            m = self.POS_PAT[sid].search(buf)
            if m:
                time.sleep(0.1)                    # grace for trailing bytes
                m2 = self.POS_PAT[sid].search(buf + self.ble.rx_drain())
                return int((m2 or m).group(1))
            time.sleep(0.02)
        return None

    def move(self, sid, pos, t_ms):
        frame = b"#%03dP%04dT%04d!" % (sid, pos, t_ms)
        self.ble.send_frame(frame)
        time.sleep(t_ms / 1000.0 + 0.15)
        return self.ble.rx_drain()


def run_action(link, steps):
    """BASIC direct control (user directive 10-19): each step moves ONE
    servo by delta and STAYS there -- repeated gesture fires accumulate
    (no oscillate-and-return). "HOME" resets all servos to factory 1500us.
    Every end state is verified by position readback (POS_TOL)."""
    if steps == "HOME":
        return run_home(link)
    results = []
    for sid, delta, t_ms, hold_s in steps:
        pos0 = link.read_pos(sid)
        if pos0 is None:
            results.append(dict(sid=sid, ok=False, reason="no_readback"))
            continue
        lo, hi = (GRIP_LO, GRIP_HI) if sid == GRIP_SID else (GEN_LO, GEN_HI)
        tgt = min(max(pos0 + delta, lo), hi)
        link.move(sid, tgt, t_ms)
        time.sleep(hold_s)
        fin = link.read_pos(sid)
        ok = fin is not None and abs(fin - tgt) <= POS_TOL
        if not ok and fin is not None:
            # settle retry: servo still creeping toward target -- wait and
            # re-read once, keep whichever read is closer to target
            time.sleep(0.25)
            fin2 = link.read_pos(sid)
            if fin2 is not None and abs(fin2 - tgt) < abs(fin - tgt):
                fin = fin2
            ok = fin is not None and abs(fin - tgt) <= POS_TOL
        results.append(dict(sid=sid, pos0=pos0, target=tgt, final=fin, ok=ok))
    return results


def run_home(link):
    """Stop=reset: all six servos to factory home 1500us (official MyArm32
    tb_global_init), sent as ONE braced simultaneous frame
    {#000P1500T1500!...#005P1500T1500!} (official multi-servo syntax), then
    per-servo readback verify."""
    frame = (b"{" + b"".join(b"#%03dP%04dT%04d!" % (sid, HOME_PWM[sid],
                                                   HOME_T_MS)
                             for sid in range(6)) + b"}")
    link.ble.send_frame(frame)
    time.sleep(HOME_T_MS / 1000.0 + 0.5)
    results = []
    for sid in range(6):
        fin = link.read_pos(sid)
        ok = fin is not None and abs(fin - HOME_PWM[sid]) <= POS_TOL
        if not ok and fin is not None:
            time.sleep(0.25)
            fin2 = link.read_pos(sid)
            if fin2 is not None and abs(fin2 - HOME_PWM[sid]) < abs(fin - HOME_PWM[sid]):
                fin = fin2
            ok = fin is not None and abs(fin - HOME_PWM[sid]) <= POS_TOL
        results.append(dict(sid=sid, target=HOME_PWM[sid], final=fin, ok=ok))
    return results


class ActionWorker(threading.Thread):
    """Continuity fix (user directive 10-19): arm actions run HERE while the
    main loop keeps inferring -- detection, box and label never freeze
    during a move. ble is used only by this thread (no locking needed)."""

    def __init__(self, ble):
        super().__init__(daemon=True)
        self.ble = ble
        self.q = queue.Queue()

    def submit(self, gesture, steps):
        self.q.put((gesture, steps))

    def run(self):
        while True:
            gesture, steps = self.q.get()
            if gesture is None:
                break
            try:
                act = run_action(self.ble, steps)
                ok = all(s.get("ok") for s in act) if steps else True
                log("ACTION_DONE", name=GESTURE_NAMES[gesture], ok=ok,
                    detail=act)
            except Exception as exc:
                log("ACTION_FAIL", name=GESTURE_NAMES[gesture],
                    error=str(exc))


# ---------------- C2 unified letterbox preprocessing (PS-cv2 tier) -------------
# Contract authority: 4_metrics/logs/2026-10-20_c2_letterbox_retrain_run01/
# scripts/letterbox_v4_dataset.py — the C4 PL letterbox RTL is verified against
# THIS convention (对拍门). Input = raw VDMA snapshot 640x480x3 BGR bytes.
NANODET_MEAN_BGR = (103.53, 116.28, 123.675)   # v65 training epilogue (BGR)
NANODET_STD_BGR = (57.375, 57.12, 58.395)


def letterbox_rgb(frame, size=320):
    """640x480x3 BGR raw bytes -> (1,3,size,size) float32 RGB letterboxed.
    r=min scale, cv2 INTER_LINEAR half-pixel, gray-114 symmetric pad with
    ultralytics round(half-0.1) split (identical to v4 dataset script; for
    640x480 -> r=0.5, 320x240 content + 40px gray bars top/bottom)."""
    import cv2
    img = np.frombuffer(frame, np.uint8).reshape(480, 640, 3)
    r = min(size / img.shape[0], size / img.shape[1])
    nw, nh = int(round(img.shape[1] * r)), int(round(img.shape[0] * r))
    rs = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LINEAR)
    dw, dh = size - nw, size - nh
    top = int(round(dh / 2 - 0.1))
    left = int(round(dw / 2 - 0.1))
    pad = cv2.copyMakeBorder(rs, top, dh - top, left, dw - left,
                             cv2.BORDER_CONSTANT, value=(114, 114, 114))
    return pad[:, :, ::-1].transpose(2, 0, 1)[None].astype(np.float32)


def model_input(blob_rgb, kind):
    """Per-model input epilogue on the unified letterbox blob (RGB 0-255).
    yolo = /255 (M contract, no mean/std); nanodet = RGB->BGR then
    (x-mean)/std (mathematically identical to the proven conv1 fold)."""
    if kind == "nanodet":
        bgr = blob_rgb[:, ::-1]
        mean = np.array(NANODET_MEAN_BGR, np.float32).reshape(1, 3, 1, 1)
        std = np.array(NANODET_STD_BGR, np.float32).reshape(1, 3, 1, 1)
        return (bgr - mean) / std
    return blob_rgb / 255.0


# ---------------- main ---------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bit", required=True)
    ap.add_argument("--onnx", required=True)
    ap.add_argument("--engine", choices=["cv2", "ncnn"], default="cv2",
                    help="ncnn = local t1_ncnn_server (TCP), ~2x faster")
    ap.add_argument("--ncnn-addr", default="127.0.0.1:5002")
    ap.add_argument("--ncnn-param", default="/home/xilinx/t1_models/"
                    "nanodet-plus-m_320-gesture7-v65.ncnn.param")
    ap.add_argument("--ncnn-bin", default="/home/xilinx/t1_models/"
                    "nanodet-plus-m_320-gesture7-v65.ncnn.bin")
    ap.add_argument("--model", type=int, default=0, choices=[0, 1, 2],
                    help="C2 registry id: 0=NanoDet-v65 1=YOLOv8n-v3 "
                         "2=YOLO11n-mC2PSA (ncnn server multi-model)")
    ap.add_argument("--rotate-secs", type=float, default=0.0,
                    help="C2 demo: rotate through all models every N seconds "
                         "(0 = stay on --model; demo ruling 10-20: rotation "
                         "disabled, switching is user-directed only)")
    ap.add_argument("--model-select", default="/home/xilinx/t1_c2/model_select",
                    help="control file for user-directed model switching: "
                         "operator writes one integer 0/1/2 over ssh, the "
                         "chain consumes it and swaps the resident model")
    ap.add_argument("--ps-preproc", action="store_true",
                    help="C2: unified letterbox in PS-cv2 (PL t1_preproc idles);"
                         " per-model input epilogue by registry kind")
    ap.add_argument("--score", type=float, default=0.7,
                    help="decode/display threshold. ALIGNED with the fire "
                         "gate (--conf) on purpose: a label on screen means "
                         "it can fire (user report 10-19: sub-conf labels "
                         "created 'recognized but no response' confusion)")
    ap.add_argument("--nms", type=float, default=0.6)
    ap.add_argument("--conf", type=float, default=0.4)
    ap.add_argument("--min-margin", type=float, default=0.15,
                    help="fire only if top1 per-class max beats every other "
                         "class by this margin (anti TD/TU flip guard)")
    ap.add_argument("--debounce", type=int, default=3)
    ap.add_argument("--box-hold", type=float, default=0.3,
                    help="wall-clock seconds the box+label stay after the "
                         "last detection (user ruling 10-21: 0.8 -> 0.3)")
    ap.add_argument("--cooldown", type=float, default=5.0)
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--no-ble", action="store_true")
    ap.add_argument("--no-text-osd", action="store_true",
                    help="kill-switch for the PS-side TextOsd ring writer "
                    "(isolation experiments for the genlock-ring freeze: "
                    "with the thread never started, set() marks state but "
                    "ZERO bytes are ever written to the VDMA ring; the PL "
                    "static network label (t1_text_osd) is unaffected)")
    ap.add_argument("--arm-udp", default=None, metavar="HOST:PORT",
                    help="PC BLE bridge address (replaces on-board ble_uart)")
    ap.add_argument("--ble-probe", action="store_true",
                    help="only verify arm link: PRAD read on all six servos")
    ap.add_argument("--evidence", type=Path)
    args = ap.parse_args()
    if os.geteuid() != 0:
        ap.error("run as root (sudo)")

    from pynq import Overlay
    import cv2

    bit, hwh = Path(args.bit), Path(args.bit).with_suffix(".hwh")
    sha_ok(bit, BIT_HASH)
    sha_ok(hwh, HWH_HASH)
    sha_ok(args.onnx, ONNX_HASH)
    if args.engine == "ncnn":
        sha_ok(args.ncnn_param, NCNN_PARAM_HASH)
        sha_ok(args.ncnn_bin, NCNN_BIN_HASH)
    if args.evidence is None:
        args.evidence = Path("/home/xilinx/t1_overlay/evidence")
    args.evidence.mkdir(parents=True, exist_ok=True)

    ol = Overlay(str(bit), download=False)
    need = ["axi_vdma_0"]
    if not args.ps_preproc:
        need.append("t1_preproc_0")          # PL preproc tier only
    if not args.arm_udp and not args.no_ble:
        need.append("ble_uart_0")            # arm link tier only
    for name in need:
        if name not in ol.ip_dict:
            raise RuntimeError("%s missing from ip_dict: %s"
                               % (name, list(ol.ip_dict.keys())))
    ol.download()
    state = Path("/sys/class/fpga_manager/fpga0/state").read_text().strip()
    if state != "operating":
        raise RuntimeError("fpga state %s" % state)
    log("PL_LOADED", bit_sha256=BIT_HASH[:16], state=state)

    if args.arm_udp:
        host, port = args.arm_udp.rsplit(":", 1)
        ble = ArmLink(UdpBle(host, int(port)))
        log("ARM_UDP_TRANSPORT", dest=args.arm_udp)
    elif args.no_ble:
        ble = None
        log("BT_SKIPPED", reason="--no-ble")
    else:
        ble = ArmLink(BleUart(ol))
        log("BT_READY")
    if args.ble_probe:
        ok = 0
        for sid in range(6):
            p = ble.read_pos(sid, timeout=3.0)
            log("BLE_PROBE", sid=sid, pos=p)
            ok += p is not None
        verdict = "BLE_LINK_PASS" if ok == 6 else "BLE_LINK_PARTIAL"
        log("VERDICT", v=verdict, ok="%d/6" % ok)
        sys.exit(0 if ok == 6 else 1)

    worker = ActionWorker(ble)
    worker.start()

    infer = make_engine(args)
    if args.model != 0 and args.engine != "ncnn":
        raise RuntimeError("multi-model (--model) needs --engine ncnn")
    probe = np.zeros((1, 3, 320, 320), np.float32)
    arr = np.asarray(infer(probe, model_id=args.model))
    grids_cache = None             # built lazily when a nanodet model goes
    log("ENGINE_READY", engine=args.engine, model=C2_MODELS[args.model][0],
        anchors=2100 if C2_MODELS[args.model][1] == "yolo" else "nanodet",
        out_shape=list(arr.shape))

    cam = VdmaCam(ol)
    log("VDMA_STREAM_STARTED", **cam.status())
    pre = None
    if args.ps_preproc:
        log("PS_PREPROC_READY", contract="letterbox_rgb_gray114")
    else:
        pre = Preproc(ol)
        log("PREPROC_READY", version=hex(EXPECT_VER))
    mbtn = ModelBtn(ol)
    log("MODEL_BTN", present=mbtn.mmio is not None, presses=mbtn.presses)
    osd = BoxOsd(ol)
    log("BOX_OSD_READY", present=osd.mmio is not None)
    plosd = PlTextOsd(ol)
    log("PL_TEXT_OSD_READY", present=plosd.mmio is not None)
    # Startup identity banner: "NET:None" for 3 s, then auto-clear.  The
    # PS-burn TextOsd is retired (v4 label OSD needs zero ring writes).
    plosd.idle(args.model)          # 常态常驻 "NET:None"（用户裁定 10-21）

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    started = time.monotonic()
    n = fired = rejected = 0
    hits, last_fire, need_release = 0, 0.0, False
    last_report = started
    active_id = args.model
    last_rotate = started
    result = dict(result="NOT_COMPLETED")
    # display hold: bridge detection flicker so the label/box do not flash
    # on/off when a marginal detection oscillates around the score gate
    # (user report 2026-10-20 "标题一直在闪").  WALL-CLOCK based since
    # 2026-10-21: the old HOLD_FRAMES=8 counted INFERENCE frames, and the
    # loop runs at the ~0.87 fps inference cadence -> the ghost box
    # lingered ~9 s after the hand dropped (user report "框还会存在3-5s").
    # While held, box+label stay frozen at the last real detection; the
    # label strip is PL-resident (zero ring writes), so holding costs
    # nothing.  None/expired -> strip hidden, box cleared.
    HOLD_SECS = args.box_hold
    hold_until = 0.0
    held_det = None
    try:
        while not stopping and (not args.seconds
                                or time.monotonic() - started < args.seconds):
            if args.rotate_secs and time.monotonic() - last_rotate >= args.rotate_secs:
                nxt = C2_ROTATION[(C2_ROTATION.index(active_id) + 1)
                                  % len(C2_ROTATION)]
                log("MODEL_ROTATE", **{"from": C2_MODELS[active_id][0],
                                       "to": C2_MODELS[nxt][0]})
                active_id = nxt
                last_rotate = time.monotonic()
            # User-directed model switch (ruling 2026-10-20: the demo NEVER
            # rotates on its own). Two sources, one path: the PL DIP switch
            # (t1_model_btn, each toggle = next model) wins over the ssh
            # control file, which is consumed on read.
            want = mbtn.poll()
            src = "pl_btn"
            if want is None:
                src = "file"
                try:
                    with open(args.model_select) as f:
                        want = int(f.read().strip())
                    os.remove(args.model_select)
                except (OSError, ValueError):
                    want = None
            if want in C2_MODELS and want != active_id:
                log("MODEL_SELECT", src=src, presses=mbtn.presses,
                    **{"from": C2_MODELS[active_id][0],
                       "to": C2_MODELS[want][0]})
                active_id = want
                held_det = None
                hold_until = 0.0
                # "NET:None" identity banner, persistent (idle ruling)
                plosd.idle(want)
            st = cam.status()
            frame = cam.snapshot()
            if frame is None:
                rejected += 1
                continue
            t0 = time.monotonic()
            if args.ps_preproc:
                lb0 = time.monotonic()
                blob = model_input(letterbox_rgb(frame),
                                   C2_MODELS[active_id][1])
                pl_ms = time.monotonic() - lb0
            else:
                blob, pl_ms = pre.run(frame)
            raw = np.asarray(infer(blob, model_id=active_id))
            if C2_MODELS[active_id][1] == "nanodet" and grids_cache is None:
                grids_cache = build_grids(320, np.asarray(raw).reshape(-1, 39)
                                          .shape[0])
                log("NANODET_GRIDS", anchors=len(grids_cache))
            dets, per_cls, out = decode_dispatch(active_id, raw, grids_cache,
                                                 args.score, args.nms)
            if DUMP_DIR:
                dump_maybe(frame, blob, out, dets)
            # ---- display with wall-clock flicker hold (box + label) ----
            # Label strip = PL-resident bitmap (t1_label_osd): the PS only
            # writes the packed CODE register (label|digit<<5); PL re-rasters
            # every frame -> absolutely stable, zero display-ring writes.
            if dets:
                held_det = dets[0]
                hold_until = time.monotonic() + HOLD_SECS
            if held_det is not None and time.monotonic() < hold_until:
                osd.show(held_det)
                plosd.show(active_id, held_det["cls"], held_det["score"])
            else:
                held_det = None
                osd.show(None)
                plosd.show(active_id, None, None)   # 常驻 idle 条带
            plosd.tick()
            inf_ms = (time.monotonic() - t0) * 1e3
            n += 1

            gesture = None
            if dets and dets[0]["score"] >= args.conf:
                c = dets[0]["cls"]
                rival = max(float(per_cls[i]) for i in range(7) if i != c)
                if float(per_cls[c]) - rival >= args.min_margin:
                    gesture = c
            now = time.monotonic()
            # Edge-trigger (remote-control semantics, user concern 10-19):
            # ONE gesture appearance = ONE action. While a gesture is held,
            # debounce+cooldown would still refire every ~cooldown seconds
            # (periodic stepping = "twitching"). need_release forces the
            # gesture to disappear (or change class) before the next fire.
            if gesture is None:
                hits = 0
                need_release = False
            elif (gesture in GESTURE_ACTIONS
                    and now - last_fire >= args.cooldown
                    and not need_release):
                hits = hits + 1 if gesture == getattr(run_action, "_last_cls",
                                                      None) else 1
                run_action._last_cls = gesture
                if hits >= args.debounce:
                    last_fire = now
                    hits = 0
                    need_release = True
                    steps = GESTURE_ACTIONS[gesture]
                    log("GESTURE_FIRED", cls=gesture,
                        name=GESTURE_NAMES[gesture], score=dets[0]["score"],
                        steps=("HOME" if steps == "HOME" else len(steps)))
                    fired += 1
                    if not args.no_ble:
                        worker.submit(gesture, steps)   # async: inference
                    else:                               # never freezes
                        log("ACTION_SKIPPED", reason="--no-ble")

            if n == 1:
                (args.evidence / "first_frame.bgr").write_bytes(frame)
            if now - last_report >= 5:
                top = [{"name": GESTURE_NAMES[d["cls"]], "score": d["score"]}
                       for d in dets[:3]]
                log("HEARTBEAT", frames=n, rejected=rejected, fired=fired,
                    inf_ms=round(inf_ms, 1), pl_ms=round(pl_ms * 1e3, 1),
                    top=top, **st)
                last_report = now
        result = dict(result="T1_GESTURE_RUN_COMPLETE", frames=n,
                      rejected=rejected, fired=fired,
                      seconds=round(time.monotonic() - started, 1))
        log("RUN_COMPLETE", **result)
    except Exception as exc:
        result = dict(result="FAIL", error=str(exc))
        log("FAIL", error=str(exc))
        raise
    finally:
        osd.show(None)
        worker.submit(None, None)
        worker.join(timeout=5)
        if pre is not None:
            pre.close()
        cam.close()
        (args.evidence / "result.json").write_text(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
