#!/usr/bin/env python3
# T1_Board_Collector -- board-camera (OV5640 UDP) gesture capture GUI, v1.0
# (2026-10-19, T1 gesture line). EXE form so it double-click runs anywhere.
#
# Unified with tools/capture_gestures.py: ONLY the frame source differs
# (board OV56 UDP stream instead of a local webcam); output contract is
# byte-identical and the existing relabel_mp_v5.py / yolo2coco_v2.py /
# merge flow consumes the output directory unchanged:
#   * 640x480 BGR jpg frames (same geometry as the board chain)
#   * label = one YOLO line "cls 0.5 0.5 1.0 1.0" (full frame)
#   * key 0 (background) saves image with NO label file (hard negatives)
#   * NO mirroring anywhere (flip=0.0 in the train config)
#
# GUI = tkinter + PIL ImageTk, the exact pattern of the board-proven
# EES331_UDP_Viewer (udp_video_gui.py) -- no cv2.imshow anywhere.
#
# Keys (click the window first):
#   1..7  arm class (1=Down 2=Left 3=Right 4=Stop 5=ThumbsDown 6=ThumbsUp 7=Up)
#   0     arm background (no label)
#   SPACE capture burst (--burst frames, --gap s apart)
#   q     quit
import argparse
import json
import os
import queue
import socket
import struct
import threading
import time
import tkinter as tk
from tkinter import ttk

import numpy as np
from PIL import Image, ImageDraw, ImageTk

CLASSES = ['Down', 'Left', 'Right', 'Stop',
           'Thumbs Down', 'Thumbs up', 'Up']   # ids 0..6, keys 1..7
HDR = struct.Struct(">4sBBHIHHHHHHII")
PACKETS, PAYLOAD = 640, 1440
W, H = 640, 480


class UdpCam(threading.Thread):
    """Background receiver; q carries the latest complete frame (BGR bytes)."""

    def __init__(self, port, q):
        super().__init__(daemon=True)
        self.q = q
        self.alive = threading.Event()
        self.alive.set()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF,
                             4 * 1024 * 1024)
        self.sock.bind(("0.0.0.0", port))
        self.sock.settimeout(0.2)
        self.parts = {}
        self.status = "listening :%d" % port

    def run(self):
        while self.alive.is_set():
            try:
                pkt, _ = self.sock.recvfrom(2048)
            except socket.timeout:
                continue
            except OSError:
                break
            if len(pkt) < HDR.size or pkt[:4] != b"OV56":
                continue
            (_, _, _, _, fid, pid, npk, pay, w, h, stride, ts, crc) = \
                HDR.unpack(pkt[:HDR.size])
            if npk != PACKETS or pid >= PACKETS:
                continue
            self.parts.setdefault(fid, {})[pid] = pkt[HDR.size:]
            if len(self.parts[fid]) == PACKETS:
                fr = self.parts.pop(fid)
                if all(len(fr.get(i, b"")) == PAYLOAD
                       for i in range(PACKETS)):
                    try:
                        self.q.put_nowait(
                            b"".join(fr[i] for i in range(PACKETS)))
                    except queue.Full:
                        pass
            if len(self.parts) > 32:
                self.parts.pop(next(iter(self.parts)))

    def stop(self):
        self.alive.clear()
        try:
            self.sock.close()
        except OSError:
            pass


class App:
    def __init__(self, root, args):
        self.root = root
        self.args = args
        root.title("T1 板载相机手势采集  |  统一格式 collected_board_v6")
        root.resizable(False, False)
        self.photo = None

        os.makedirs(os.path.join(args.out, "images"), exist_ok=True)
        os.makedirs(os.path.join(args.out, "labels"), exist_ok=True)
        self.img_dir = os.path.join(args.out, "images")
        self.lbl_dir = os.path.join(args.out, "labels")
        self.counts = {c: 0 for c in CLASSES}
        self.bg_count = 0
        self.armed = None
        self.latest = None
        self.session_t0 = time.time()

        bar = ttk.Frame(root, padding=6)
        bar.pack(fill="x")
        self.arm_var = tk.StringVar(value="按 1-7 预选手势, 0=背景")
        ttk.Label(bar, textvariable=self.arm_var).pack(side="left")
        ttk.Button(bar, text="退出(q)", command=self.close).pack(side="right")

        self.frame_label = ttk.Label(root)
        self.frame_label.pack(padx=8, pady=4)
        self.show_placeholder("等待板卡 OV56 数据流…")

        hint = ("按键: 1=Down 2=Left 3=Right 4=Stop 5=ThumbsDown 6=ThumbsUp "
                "7=Up  0=背景(无手势,含头发日常状态)  空格=连拍%d张  "
                "手占画面1/2 | Up/Down多换手踝角度和距离" % args.burst)
        ttk.Label(root, text=hint, wraplength=660, foreground="#555",
                  padding=(8, 0)).pack(fill="x")

        stat = ttk.Frame(root, padding=(8, 4, 8, 8))
        stat.pack(fill="x")
        self.count_var = tk.StringVar()
        ttk.Label(stat, textvariable=self.count_var).pack(side="left")
        self.log_var = tk.StringVar(value="")
        ttk.Label(stat, textvariable=self.log_var,
                  foreground="#070").pack(side="right")

        self.q = queue.Queue(maxsize=4)
        self.cam = UdpCam(args.port, self.q)
        self.cam.start()
        self.refresh_counts()

        root.bind("<Key>", self.on_key)
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.poll()

    def show_placeholder(self, text):
        img = Image.new("RGB", (W, H), (24, 24, 24))
        d = ImageDraw.Draw(img)
        d.text((W // 2 - 150, H // 2 - 10), text, fill=(220, 220, 220))
        self.photo = ImageTk.PhotoImage(img)
        self.frame_label.config(image=self.photo)

    def overlay(self, frame_bgr):
        img = Image.frombytes("RGB", (W, H), frame_bgr, "raw", "BGR")
        d = ImageDraw.Draw(img)
        if self.armed == 'bg':
            txt = "ARMED: BACKGROUND -- SPACE to shoot"
        elif self.armed is not None:
            txt = "ARMED: %d=%s -- SPACE to shoot" % (self.armed + 1,
                                                      CLASSES[self.armed])
        else:
            txt = "press 1-7 to arm a class, 0 for background"
        d.rectangle([0, 0, W, 24], fill=(0, 0, 0))
        d.text((6, 6), txt, fill=(255, 255, 0))
        return img

    def poll(self):
        got = False
        try:
            while True:
                self.latest = self.q.get_nowait()
                got = True
        except queue.Empty:
            pass
        if self.latest is not None:
            self.photo = ImageTk.PhotoImage(self.overlay(self.latest))
            self.frame_label.config(image=self.photo)
        self.root.after(60, self.poll)

    def refresh_counts(self):
        cs = "  ".join("%s:%d" % (c, self.counts[c]) for c in CLASSES)
        self.count_var.set(cs + "  bg:%d" % self.bg_count)

    def on_key(self, ev):
        k = ev.char
        if k == 'q':
            self.close()
        elif k and k in "1234567":
            self.armed = int(k) - 1
            self.arm_var.set("预选: %s" % CLASSES[self.armed])
        elif k == '0':
            self.armed = 'bg'
            self.arm_var.set("预选: 背景(无标签)")
        elif k == ' ' and self.armed is not None and self.latest is not None:
            threading.Thread(target=self.burst, daemon=True).start()

    def burst(self):
        for i in range(self.args.burst):
            if self.latest is None:
                break
            ts = time.strftime("%Y%m%d_%H%M%S")
            if self.armed == 'bg':
                name = "bg_%s_%04d" % (ts, self.bg_count)
                self.bg_count += 1
            else:
                slug = CLASSES[self.armed].lower().replace(' ', '_')
                name = "%s_%s_%04d" % (slug, ts,
                                       self.counts[CLASSES[self.armed]])
                self.counts[CLASSES[self.armed]] += 1
            arr = np.frombuffer(self.latest, np.uint8).reshape(H, W, 3)
            Image.fromarray(arr[:, :, ::-1]).save(
                os.path.join(self.img_dir, name + ".jpg"), quality=92)
            if self.armed != 'bg':
                with open(os.path.join(self.lbl_dir, name + ".txt"), "w") as f:
                    f.write("%d 0.5 0.5 1.0 1.0\n" % self.armed)
            self.log_var.set("saved %s (%d/%d)" % (name, i + 1,
                                                   self.args.burst))
            self.refresh_counts()
            if i + 1 < self.args.burst:
                time.sleep(self.args.gap)

    def close(self):
        session = {
            "when": time.strftime("%Y-%m-%d %H:%M:%S"),
            "seconds": round(time.time() - self.session_t0, 1),
            "classes": self.counts, "background": self.bg_count,
            "res": [W, H],
            "source": "board OV5640 UDP stream (ees331-camera)",
        }
        try:
            with open(os.path.join(self.args.out, "SESSION.json"), "w") as f:
                json.dump(session, f, indent=2)
        except OSError:
            pass
        self.cam.stop()
        self.root.destroy()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "collected_board_v6"))
    ap.add_argument("--burst", type=int, default=4)
    ap.add_argument("--gap", type=float, default=0.25)
    args, _ = ap.parse_known_args()
    root = tk.Tk()
    App(root, args)
    root.mainloop()


if __name__ == "__main__":
    main()
