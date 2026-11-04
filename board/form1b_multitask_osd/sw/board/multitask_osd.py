#!/usr/bin/env python3
"""PYNQ descriptor driver for the COCO and pose PL display stages."""


def _percent(value):
    return max(0, min(99, int(round(float(value) * 100.0))))


def _display_box(values, pose=False):
    x0, y0, x1, y1 = [float(v) for v in values]
    if pose:
        coords = (x0 * 2.0, (y0 - 40.0) * 2.0,
                  x1 * 2.0, (y1 - 40.0) * 2.0)
    else:
        coords = (x0 * 2.0, y0 * 1.5, x1 * 2.0, y1 * 1.5)
    l, t, r, b = [int(round(v)) for v in coords]
    l = max(0, min(638, l))
    r = max(l + 1, min(639, r))
    t = max(0, min(478, t))
    b = max(t + 1, min(479, b))
    return l, r, t, b


def _display_point(row):
    x, y = float(row[0]) * 2.0, (float(row[1]) - 40.0) * 2.0
    return (max(0, min(639, int(round(x)))),
            max(0, min(479, int(round(y)))),
            _percent(row[2]))


class MultiTaskOsd:
    """Publish coherent descriptors; no VDMA or inference state is touched."""

    def __init__(self, overlay):
        from pynq import MMIO
        self.blocks = {}
        for name, address, magic in (("task_coco_osd_0", 0x43C70000, 0x434F434F),
                                     ("task_pose_osd_0", 0x43C80000, 0x504F5345)):
            if name not in overlay.ip_dict:
                raise RuntimeError(f"missing {name}")
            desc = overlay.ip_dict[name]
            if int(desc["phys_addr"]) != address or int(desc["addr_range"]) != 4096:
                raise RuntimeError(f"unexpected {name} address map {desc}")
            mmio = MMIO(address, 4096)
            actual = mmio.read(0)
            if actual != magic:
                raise RuntimeError(f"{name} ID {actual:#x} != {magic:#x}")
            self.blocks[name] = mmio
        self.coco = self.blocks["task_coco_osd_0"]
        self.pose = self.blocks["task_pose_osd_0"]
        self.set_mode(1)

    @staticmethod
    def _write(mmio, offset, value):
        mmio.write(int(offset), int(value) & 0xFFFFFFFF)

    def set_mode(self, mode):
        mode = int(mode)
        if mode not in (0, 1, 2):
            raise ValueError("mode must be 0, 1 or 2")
        for mmio in (self.coco, self.pose):
            self._write(mmio, 0x08, mode)
            self._write(mmio, 0x0C, 0)
            self._write(mmio, 0x14, 1)

    def publish_coco(self, detections):
        rows = sorted(detections, key=lambda d: float(d["score"]), reverse=True)[:8]
        self._write(self.coco, 0x08, 0)
        self._write(self.coco, 0x0C, len(rows))
        for index, det in enumerate(rows):
            base = 0x40 + index * 0x20
            l, r, t, b = _display_box(det["xyxy_px"])
            cls = int(det["cls"])
            if not 0 <= cls < 80:
                raise ValueError(f"COCO class out of range: {cls}")
            for offset, value in ((0x00, l), (0x04, r), (0x08, t), (0x0C, b)):
                self._write(self.coco, base + offset, value)
            self._write(self.coco, base + 0x10, cls | (_percent(det["score"]) << 8))
        self._write(self.coco, 0x14, 1)

    def publish_pose(self, detections):
        rows = sorted(detections, key=lambda d: float(d["score"]), reverse=True)[:2]
        self._write(self.pose, 0x08, 2)
        self._write(self.pose, 0x0C, len(rows))
        for person, det in enumerate(rows):
            base = 0x40 + person * 0x200
            l, r, t, b = _display_box(det["xyxy_px"], pose=True)
            for offset, value in ((0x00, l), (0x04, r), (0x08, t), (0x0C, b),
                                  (0x10, _percent(det["score"]))):
                self._write(self.pose, base + offset, value)
            keypoints = det["keypoints"]
            if len(keypoints) != 17:
                raise ValueError(f"expected 17 keypoints, got {len(keypoints)}")
            for k, row in enumerate(keypoints):
                x, y, conf = _display_point(row)
                point_base = base + 0x14 + k * 0x0C
                self._write(self.pose, point_base, x)
                self._write(self.pose, point_base + 0x04, y)
                self._write(self.pose, point_base + 0x08, conf)
        self._write(self.pose, 0x14, 1)

    def close(self):
        self.set_mode(1)
