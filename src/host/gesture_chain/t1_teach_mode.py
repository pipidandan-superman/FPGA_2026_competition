# t1_teach_mode.py -- T1 advanced-chain TEACH MODE (SPEC v1.0 §3.3/§3.4-1,
# 2026-10-19). Terminal REPL: jog the real arm to real poses around a REAL
# object, record six-axis readbacks as keyframes, playback the taught
# sequence. This is the official 动作组编辑软件 philosophy (teach points,
# playback group) mapped onto our brace_move/grip/verify primitives.
#
#   move <sid> <pwm> [t_ms]   single-servo jog (clamped; gripper s5 [1133,1665])
#   rel  <sid> <delta> [t_ms] relative jog (+/-)
#   home [t_ms]               all six -> 1500
#   read                      PRAD all six, print
#   save <name> [t_ms]        read six axes -> keyframe <name> (default t=1200)
#   grip <pwm> [t_ms]         gripper move (clamped 1133..1665)
#   list                      show recorded keyframes
#   run [name]                playback recorded sequence (verify each kf)
#   write <pyfile>            append SEQUENCE python literal to a file
#   q                         quit
#
# Usage:  <model_env venv>\python.exe t1_teach_mode.py
import json
import socket
import sys
import time

BRIDGE = ("127.0.0.1", 5001)
CLAMP = (600, 2400)
GRIP_CLAMP = (1133, 1665)
TOL = 15

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(3.0)

seq = []   # [{"name":..., "pwms":[6], "t_ms":...}, ...]


def tx(frame, retries=2):
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


def read6():
    pos = {}
    for sid in range(6):
        rx = tx("#%03dPRAD!" % sid)
        pre = "#%03dP" % sid
        val = None
        for tok in rx.split("!"):
            if tok.startswith(pre) and tok[len(pre):].isdigit():
                val = int(tok[len(pre):])
        if val is None:
            return None
        pos[sid] = val
    return [pos[i] for i in range(6)]


def clamp6(pwms):
    out = []
    for i, p in enumerate(pwms):
        lo, hi = GRIP_CLAMP if i == 5 else CLAMP
        out.append(max(lo, min(hi, p)))
    return out


def brace_move(pwms, t_ms):
    pwms = clamp6(pwms)
    body = "".join("#%03dP%04dT%04d!" % (i, p, t_ms) for i, p in enumerate(pwms))
    return tx("{%s}" % body)


def playback():
    if not seq:
        print("sequence empty")
        return
    print("PLAYBACK %d keyframes" % len(seq))
    for kf in seq:
        brace_move(kf["pwms"], kf["t_ms"])
        time.sleep(max(0.6, kf["t_ms"] / 1000.0 + 0.3))
        pos = read6()
        if pos is None:
            print("  !! %s: no readback -> $DST! abort" % kf["name"])
            tx("$DST!")
            return
        bad = [s for s in range(6) if abs(pos[s] - kf["pwms"][s]) > TOL]
        mark = " ".join("s%d=%4d%s" % (s, pos[s], "*" if s in bad else "")
                        for s in range(6))
        print("  %-12s t=%4d %s %s" % (kf["name"], kf["t_ms"], mark,
                                       "OK" if not bad else "MISS"))
        if bad:
            print("  !! verify miss -> $DST! abort (arm holds, intervene)")
            tx("$DST!")
            return
    print("PLAYBACK DONE")


HELP = """commands: move <sid> <pwm> [t] | rel <sid> <d> [t] | home [t] | read
          grip <pwm> [t] | save <name> [t] | list | run | write <pyfile> | q"""


def main():
    print("T1 TEACH MODE -- jog to a pose, 'save <name>' records it. " + HELP)
    while True:
        try:
            line = input("teach> ").strip().split()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line:
            continue
        cmd, a = line[0], line[1:]
        if cmd == "q":
            break
        elif cmd == "move" and len(a) >= 2:
            sid, pwm, t = int(a[0]), int(a[1]), int(a[2]) if len(a) > 2 else 800
            if sid == 5:
                pwm = max(GRIP_CLAMP[0], min(GRIP_CLAMP[1], pwm))
            else:
                pwm = max(CLAMP[0], min(CLAMP[1], pwm))
            tx("#%03dP%04dT%04d!" % (sid, pwm, t))
        elif cmd == "rel" and len(a) >= 2:
            sid, d, t = int(a[0]), int(a[1]), int(a[2]) if len(a) > 2 else 800
            pos = read6()
            if pos:
                base = GRIP_CLAMP if sid == 5 else CLAMP
                pwm = max(base[0], min(base[1], pos[sid] + d))
                tx("#%03dP%04dT%04d!" % (sid, pwm, t))
        elif cmd == "grip" and len(a) >= 1:
            pwm = max(GRIP_CLAMP[0], min(GRIP_CLAMP[1], int(a[0])))
            t = int(a[1]) if len(a) > 1 else 800
            tx("#005P%04dT%04d!" % (pwm, t))
        elif cmd == "home":
            t = int(a[0]) if a else 1500
            brace_move([1500] * 6, t)
        elif cmd == "read":
            pos = read6()
            print("  " + (" ".join("s%d=%4d" % (i, p) for i, p in enumerate(pos))
                          if pos else "NO READBACK"))
        elif cmd == "save" and len(a) >= 1:
            t = int(a[1]) if len(a) > 1 else 1200
            pos = read6()
            if pos is None:
                print("  NO READBACK -- keyframe NOT saved")
                continue
            seq.append({"name": a[0], "pwms": pos, "t_ms": t})
            print("  saved %-12s t=%4d  %s" % (a[0], t, pos))
        elif cmd == "list":
            for i, kf in enumerate(seq):
                print("  %d: %-12s t=%4d %s" % (i, kf["name"], kf["t_ms"], kf["pwms"]))
        elif cmd == "run":
            playback()
        elif cmd == "write" and len(a) >= 1:
            lit = "SEQUENCES_TEACHED[%r] = [\n" % "TEACHED_PICK"
            for kf in seq:
                lit += "    (%r, %d, %.1f),   # %s\n" % (
                    tuple(kf["pwms"]), kf["t_ms"], max(0.6, kf["t_ms"] / 1000.0 + 0.3), kf["name"])
            lit += "]\n"
            with open(a[0], "a") as f:
                f.write(lit)
            print("  appended -> %s" % a[0])
        else:
            print(HELP)
    print("bye (%d keyframes in memory)" % len(seq))


if __name__ == "__main__":
    main()
