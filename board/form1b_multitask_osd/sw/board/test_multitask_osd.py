#!/usr/bin/env python3
"""Host-only CSR contract tests; never opens FPGA hardware."""
import sys
import types


class FakeMMIO:
    def __init__(self, address, registers):
        self.address = address
        self.registers = registers

    def read(self, offset):
        if offset == 0:
            return 0x434F434F if self.address == 0x43C70000 else 0x504F5345
        return self.registers.get((self.address, offset), 0)

    def write(self, offset, value):
        self.registers[(self.address, offset)] = value


registers = {}
sys.modules["pynq"] = types.SimpleNamespace(
    MMIO=lambda address, size: FakeMMIO(address, registers))

from multitask_osd import MultiTaskOsd

overlay = types.SimpleNamespace(ip_dict={
    "task_coco_osd_0": {"phys_addr": 0x43C70000, "addr_range": 4096},
    "task_pose_osd_0": {"phys_addr": 0x43C80000, "addr_range": 4096},
})
osd = MultiTaskOsd(overlay)
osd.publish_coco([{"cls": 1, "score": 0.88, "xyxy_px": [10, 20, 30, 40]}])
assert registers[(0x43C70000, 0x0C)] == 1
assert registers[(0x43C70000, 0x40)] == 20
assert registers[(0x43C70000, 0x44)] == 60
assert registers[(0x43C70000, 0x48)] == 30
assert registers[(0x43C70000, 0x4C)] == 60
assert registers[(0x43C70000, 0x50)] == (88 << 8) | 1

keypoints = [[160, 240, 0.66] for _ in range(17)]
poses = [
    {"score": 0.91, "xyxy_px": [100, 140, 120, 200], "keypoints": keypoints},
    {"score": 0.77, "xyxy_px": [100, 140, 120, 200], "keypoints": keypoints},
]
osd.publish_pose(poses)
assert registers[(0x43C80000, 0x0C)] == 2
assert registers[(0x43C80000, 0x240)] == 200
assert registers[(0x43C80000, 0x248)] == 200
assert registers[(0x43C80000, 0x250)] == 77
assert registers[(0x43C80000, 0x314)] == 320
assert registers[(0x43C80000, 0x318)] == 400
assert registers[(0x43C80000, 0x31C)] == 66
assert registers[(0x43C80000, 0x14)] == 1

osd.publish_coco([])
assert registers[(0x43C70000, 0x0C)] == 0
osd.close()
assert registers[(0x43C70000, 0x08)] == 1
assert registers[(0x43C80000, 0x08)] == 1
print("PS_DESCRIPTOR_CONTRACT_PASS")
