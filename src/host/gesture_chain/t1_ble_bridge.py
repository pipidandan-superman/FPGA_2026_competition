# t1_ble_bridge.py -- PC BLE bridge: UDP <-> bleak GATT -> WeBotPi arm.
# (2026-10-19) User ruling: board lacks the matching BLE module (adapter board
# not arrived); the PC simulates the FPGA-side Bluetooth output. This bridge
# replaces the on-board MLT module: the board's ArmLink transport sends raw
# servo-bus frames ('#NNNPddddTtttt!' / '#NNNPRAD!') as one UDP datagram to
# the PC; the bridge writes them to the arm's FFE2 (proven arm_link.py), then
# returns everything FFE1 notified during a 1.2s window as one UDP datagram.
#
# Run on PC (proven env with bleak):
#   <venv>\python.exe t1_ble_bridge.py [--port 5001] [--target-mac 98:EA:A0:21:01:3A]
# Board side: t1_gesture_main.py --arm-udp 192.168.240.2:5001
import argparse
import asyncio
import json
import socket
import sys
import time
from pathlib import Path

sys.path.insert(0, r"E:\competition\3_host\model_arm_chain")
from arm_link import ArmLink  # noqa: E402

LISTEN = "0.0.0.0"
COLLECT_S = 1.2
IDLE_S = 0.15        # query window closes this long after the last RX chunk
MOVE_GRACE_S = 0.25  # move frames: fire-and-forget (official-app parity) --
                     # brief grace for spontaneous echoes, then ACK back


async def _wait_window(link, t0, deadline, idle_s):
    """Poll link.events until RX goes idle for idle_s (answer complete) or
    the hard deadline passes. Returns nothing; events are read by caller."""
    while time.time() < deadline:
        ev = [e for e in link.events if e["t"] >= t0]
        if ev and time.time() - ev[-1]["t"] >= idle_s:
            return
        await asyncio.sleep(0.02)


async def _ensure_connected(link, attempts=6):
    """Reconnect after a mid-session BLE drop (arm link dies 'Not
    connected'; the fix is reconnect, previously a manual bridge
    restart + arm power cycle)."""
    if link.client is not None and link.client.is_connected:
        return True
    for attempt in range(1, attempts + 1):
        try:
            mtu = await link.connect(timeout=15.0)
            print(json.dumps({"event": "ARM_RECONNECTED", "mtu": mtu,
                              "attempt": attempt}), flush=True)
            return True
        except Exception as e:
            print(json.dumps({"event": "reconn_retry",
                              "attempt": attempt, "err": str(e)}),
                  flush=True)
            await asyncio.sleep(3.0)
    return False


async def udp_loop(link, port, collect_s):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN, port))
    sock.settimeout(None)
    loop = asyncio.get_running_loop()
    print("BRIDGE_READY listen=%s:%d mac=%s" % (LISTEN, port, link.mac),
          flush=True)
    while True:
        data, addr = await loop.run_in_executor(None, sock.recvfrom, 4096)
        link.events.clear()
        t0 = time.time()
        try:
            await link._write(data)
        except Exception as exc:
            if await _ensure_connected(link):
                try:
                    await link._write(data)
                except Exception as exc2:
                    sock.sendto(b"", addr)
                    print(json.dumps({"event": "write_fail",
                                      "err": str(exc2)}), flush=True)
                    continue
            else:
                sock.sendto(b"", addr)
                print(json.dumps({"event": "write_fail", "err": str(exc)}),
                      flush=True)
                continue
        if b"PRAD" in data:
            # position query: arm answers in ms -- close on RX idle instead
            # of burning the full fixed window (was +1.2s PER transact)
            await _wait_window(link, t0, t0 + collect_s, IDLE_S)
        else:
            # move/group frame: the official mini-program never waits for a
            # response either; give echoes a short grace then release the
            # board immediately
            grace_end = t0 + MOVE_GRACE_S
            while time.time() < grace_end:
                if any(e["t"] >= t0 for e in link.events):
                    await _wait_window(link, t0, grace_end + IDLE_S, IDLE_S)
                    break
                await asyncio.sleep(0.02)
        rx = "".join(e["rx_ascii"] for e in link.events if e["t"] >= t0)
        sock.sendto(rx.encode("latin1"), addr)
        print(json.dumps({"event": "frame", "from": "%s:%d" % addr,
                          "ms": round((time.time() - t0) * 1e3, 1),
                          "tx": data.decode("latin1"),
                          "rx": rx}), flush=True)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5001)
    ap.add_argument("--target-mac", default="98:EA:A0:21:01:3A")
    ap.add_argument("--collect-s", type=float, default=COLLECT_S)
    args = ap.parse_args()

    link = ArmLink(args.target_mac)
    for attempt in range(1, 13):
        try:
            mtu = await link.connect(timeout=15.0)
            print("ARM_CONNECTED mac=%s mtu=%d" % (args.target_mac, mtu),
                  flush=True)
            break
        except Exception as e:
            print("CONNECT_RETRY attempt=%d err=%s" % (attempt, e), flush=True)
            if attempt == 12:
                raise
            await asyncio.sleep(5.0)
    await udp_loop(link, args.port, args.collect_s)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
