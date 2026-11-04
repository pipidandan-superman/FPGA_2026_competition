"""BLE1 UART CSR driver. Plain MMIO; AT grammar lives in PS, not in PL."""
import time

IP_ID = 0x424C4531
ABI_VERSION = 0x00010000
CAPS_MASK = 0x00000007
REG = dict(ID=0x00, VERSION=0x04, CAPS=0x08, BT_CONTROL=0x0C, STATUS=0x10,
           UART_DIV=0x14, TX_LEN=0x18, TX_GO=0x1C, TX_COUNT=0x20,
           RX_PROD=0x24, RX_CONS=0x28, RX_DROPPED=0x2C, RX_FRM_ERR=0x30)
TX_BUF_BASE = 0x400
RX_RING_BASE = 0x800
RING_SIZE = 256
FRAME_MAX = 256
DIV_9600 = 5208
CLOCK_HZ = 50_000_000


class BleDriver:
    """The CSR answers SLVERR to bad writes but PYNQ MMIO ignores responses,
    so every rejection case is pre-validated here instead."""

    def __init__(self, io):
        self.io = io
        if self.read("ID") != IP_ID or self.read("VERSION") != ABI_VERSION:
            raise RuntimeError("Wrong IP identity or incompatible ABI")
        if self.read("CAPS") != CAPS_MASK:
            raise RuntimeError("This driver expects TX+RX+SOFT_RST hardware")

    @classmethod
    def from_overlay(cls, overlay, ip_name="ble_uart_0"):
        from pynq import MMIO
        desc = overlay.ip_dict[ip_name]
        size = int(desc["addr_range"])
        if size != 4096 or int(desc["phys_addr"]) % 4096:
            raise RuntimeError("Unexpected HWH CSR mapping")
        return cls(MMIO(desc["phys_addr"], size))

    def read(self, name):
        return self.io.read(REG[name])

    def status(self):
        value = self.read("STATUS")
        return dict(bt_ready=bool(value & 1), tx_busy=bool(value & 2),
                    rx_avail=bool(value & 4), tx_count=self.read("TX_COUNT"),
                    rx_prod=self.read("RX_PROD"), rx_cons=self.read("RX_CONS"),
                    rx_dropped=self.read("RX_DROPPED"),
                    rx_frm_err=self.read("RX_FRM_ERR"), uart_div=self.read("UART_DIV"))

    def wait_bt_ready(self, timeout=2.5):
        if not isinstance(timeout, (int, float)) or not 0 < timeout <= 60:
            raise ValueError("Timeout must be in (0,60] seconds")
        deadline = time.monotonic() + timeout
        while not self.read("STATUS") & 1:
            if time.monotonic() >= deadline:
                raise TimeoutError("bt_ready did not assert within %.1fs" % timeout)
            time.sleep(0.01)
        return True

    def soft_restart(self, timeout=3.0):
        started = time.monotonic()
        self.io.write(REG["BT_CONTROL"], 1)
        deadline = time.monotonic() + 0.5
        while self.read("STATUS") & 1:
            if time.monotonic() >= deadline:
                raise TimeoutError("bt_ready did not drop after restart_req")
            time.sleep(0.005)
        self.io.write(REG["BT_CONTROL"], 0)
        self.wait_bt_ready(timeout)
        return time.monotonic() - started

    def set_baud(self, divisor):
        if type(divisor) is not int or not 1 <= divisor <= 0xFFFF:
            raise ValueError("Divisor must be 1..65535")
        state = self.status()
        if not state["bt_ready"] or state["tx_busy"]:
            raise RuntimeError("Module not ready or a frame is in flight")
        self.io.write(REG["UART_DIV"], divisor)
        if self.read("UART_DIV") != divisor:
            raise RuntimeError("UART_DIV readback mismatch")

    def send_frame(self, data, timeout=None):
        if type(data) is not bytes:
            raise ValueError("Frame must be bytes")
        count = len(data)
        if not 1 <= count <= FRAME_MAX:
            raise ValueError("Frame length must be 1..256")
        state = self.status()
        if not state["bt_ready"] or state["tx_busy"]:
            raise RuntimeError("Module not ready or a frame is in flight")
        divisor = state["uart_div"] & 0xFFFF
        if timeout is None:
            timeout = count * 10 * divisor / CLOCK_HZ * 2 + 0.5
        if not isinstance(timeout, (int, float)) or not 0 < timeout <= 60:
            raise ValueError("Timeout must be in (0,60] seconds")
        for index, byte in enumerate(data):
            self.io.write(TX_BUF_BASE + 4 * index, byte)
        self.io.write(REG["TX_LEN"], count)
        started = time.monotonic()
        self.io.write(REG["TX_GO"], 1)
        deadline = started + timeout
        while self.read("STATUS") & 2:
            if time.monotonic() >= deadline:
                raise TimeoutError("TX frame did not finish within %.2fs" % timeout)
            time.sleep(0.005)
        done = self.read("TX_COUNT")
        if done != count:
            raise RuntimeError("TX_COUNT %d != %d; TX_GO was likely rejected"
                               % (done, count))
        return dict(sent=count, tx_count=done, elapsed=time.monotonic() - started)

    def recv(self, timeout=0.5, poll=0.005, max_bytes=4096):
        if not isinstance(timeout, (int, float)) or timeout < 0:
            raise ValueError("Timeout must be >= 0 seconds")
        if not isinstance(poll, (int, float)) or not 0 < poll <= 0.1:
            raise ValueError("Poll interval must be in (0,0.1] seconds")
        if type(max_bytes) is not int or not 1 <= max_bytes <= 4096:
            raise ValueError("max_bytes must be 1..4096")
        deadline = time.monotonic() + timeout
        while True:
            cons = self.read("RX_CONS")
            prod = self.read("RX_PROD")
            avail = (prod - cons) & 0xFFFFFFFF
            if avail:
                take = min(avail, max_bytes)  # ring never holds more than 256
                data = bytes(self.io.read(RX_RING_BASE + 4 * (i & 0xFF)) & 0xFF
                             for i in range(cons, cons + take))
                self.io.write(REG["RX_CONS"], (cons + take) & 0xFFFFFFFF)
                return data
            if time.monotonic() >= deadline:
                return b""
            time.sleep(poll)

    def at_command(self, cmd, timeout=2.0):
        if type(cmd) is not bytes:
            raise ValueError("Command must be bytes")
        self.send_frame(cmd + b"\r\n")
        time.sleep(0.05)
        return self.recv(timeout)
