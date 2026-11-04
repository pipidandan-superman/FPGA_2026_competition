# t1_seq_player.py -- T1 advanced-chain sequence player (SPEC v1.0 §3.1
# primitives, first light 2026-10-19). PC-direct issue through the BLE
# bridge UDP port (bridge owns the bleak GATT link; board not involved).
#
#   primitives: brace_move(pwms[6], t_ms)  -- official {#000P..!..} group frame
#               grip(pos, t_ms)            -- single-servo clamped [1133,1665]
#               verify(tol=15)             -- PRAD poll all 6, miss -> $DST! abort
#   sequences:  pure data, keyframe = ((pwm0..pwm5), t_ms, settle_s)
#
# DEMO_PICK keyframes are CONSERVATIVE untaught deltas around the 1500
# factory mid (SPEC §3.3 says real keyframes come from the teach mode;
# this sequence is a flow-shape demo, amplitudes intentionally small).
import socket
import sys
import time

BRIDGE = ("127.0.0.1", 5001)
CLAMP = (600, 2400)
GRIP_CLAMP = (1133, 1665)
TOL = 15          # PRAD readback tolerance (observed noise ~±7)
SOCK_TIMEOUT = 3.0

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(SOCK_TIMEOUT)


def tx(frame, retries=2):
    """One frame -> bridge -> FFE1 rx window. Empty rx (idle-link drop or
    reconnect race) retries before giving up. Returns rx ascii or ''."""
    rx = ""
    for _ in range(retries + 1):
        sock.sendto(frame.encode("latin1"), BRIDGE)
        try:
            rx = sock.recv(4096).decode("latin1")
        except socket.timeout:
            rx = ""
        if rx:
            return rx
    return ""


def brace_move(pwms, t_ms):
    pwms = [max(CLAMP[0], min(CLAMP[1], p)) for p in pwms]
    body = "".join("#%03dP%04dT%04d!" % (i, p, t_ms) for i, p in enumerate(pwms))
    return tx("{%s}" % body)


def grip(pos, t_ms):
    pos = max(GRIP_CLAMP[0], min(GRIP_CLAMP[1], pos))
    return tx("#005P%04dT%04d!" % (pos, t_ms))


def verify():
    """Poll all six servos. Returns {sid: pos} or None on dead link."""
    pos = {}
    for sid in range(6):
        rx = tx("#%03dPRAD!" % sid)
        if not rx:
            return None
        try:
            for tok in rx.split("!"):
                pre = "#%03dP" % sid
                if tok.startswith(pre) and tok[len(pre):].isdigit():
                    pos[sid] = int(tok[len(pre):])
                    break
            else:
                return None
        except (IndexError, ValueError):
            return None
    return pos


def estop():
    print("  !! verify fail -> $DST! abort (human-intervenable hold)")
    tx("$DST!")


def run(name, seq):
    print("SEQ %s start (%d keyframes)" % (name, len(seq)))
    for k, (pwms, t_ms, settle) in enumerate(seq):
        if len(pwms) == 6:
            brace_move(pwms, t_ms)
            expect = list(pwms)
        else:
            grip(pwms[0], t_ms)
            # clamp expectation exactly like grip() does, else a clamped
            # target reads as a verify miss (kf4: 1700->1665, got 1661)
            expect = [max(GRIP_CLAMP[0], min(GRIP_CLAMP[1], pwms[0]))]
        time.sleep(settle)
        pos = verify()
        if pos is None:
            estop()
            return False
        row = " ".join("s%d=%4d%s" % (s, pos[s], "" if abs(pos[s] - (pwms[s] if len(pwms) == 6 else (pos[5] if s == 5 else 1500))) <= TOL else "*") for s in range(6))
        print("  kf%d t=%4dms %s" % (k, t_ms, row))
        if len(pwms) == 6:
            bad = [s for s in range(6) if abs(pos[s] - expect[s]) > TOL]
            if bad:
                estop()
                return False
        else:
            if abs(pos[5] - expect[0]) > TOL:
                estop()
                return False
    print("SEQ %s DONE" % name)
    return True


# keyframe = ((pwm0..pwm5) or (gripper_pwm,), t_ms, settle_s)
SEQUENCES = {
    "DEMO_PICK": [
        ((1500, 1500, 1500, 1500, 1500, 1500), 1500, 1.6),   # HOME
        ((1440, 1580, 1500, 1500, 1500, 1500), 1000, 1.2),   # AIM+Dip
        ((1350,), 800, 1.0),                                  # GRIP close
        ((1440, 1500, 1500, 1500, 1500, 1500), 1000, 1.2),   # LIFT
        ((1500,), 800, 1.0),                                  # RELEASE
        ((1500, 1500, 1500, 1500, 1500, 1500), 1500, 1.6),   # HOME
    ],
    # DEMO_PICK_BOLD: same flow, amplitudes you can actually SEE
    # (base -200us ~27deg, shoulder +200 dip, gripper near-full travel).
    # Still inside clamps; direction per v1 chain convention (low pwm =
    # close on gripper). Flow-shape demo -- real keyframes = teach mode.
    "DEMO_PICK_BOLD": [
        ((1500, 1500, 1500, 1500, 1500, 1500), 1500, 1.6),   # HOME
        ((1300, 1700, 1500, 1500, 1500, 1500), 1200, 1.4),   # AIM+Dip (big)
        ((1250,), 1000, 1.2),                                 # GRIP close (bold)
        ((1300, 1450, 1500, 1500, 1500, 1500), 1200, 1.4),   # LIFT (above mid)
        ((1700,), 1000, 1.2),                                 # RELEASE (wide)
        ((1500, 1500, 1500, 1500, 1500, 1500), 1500, 1.6),   # HOME
    ],
}

if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "DEMO_PICK"
    ok = run(name, SEQUENCES[name])
    sys.exit(0 if ok else 1)
