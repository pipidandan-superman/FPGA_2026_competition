"""Run form2 fixed-input golden comparison and restore the camera baseline.

Board use requires authority to interrupt the current camera service.
Argument: fresh deployment directory from stage_submission.py.
"""
import argparse
import hashlib
import json
import mmap
import os
from pathlib import Path
import signal
import struct
import subprocess
import time
import xml.etree.ElementTree as ET

RUN = Path(__file__).resolve().parent
BASE = Path('/home/xilinx/ees331_camera')
BIT_SHA256 = 'c1015749f5f6b190fae483cddaeb4dc1d18c300ba752a7cf3a6bd927893957b8'


def emit(event, **details):
    line = json.dumps(dict(event=event, monotonic=time.monotonic(), **details))
    print(line, flush=True)
    with (RUN / 'events.jsonl').open('a') as stream:
        stream.write(line + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def run(args, check=True, timeout=30):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(str(args) + ': ' + result.stdout + result.stderr)
    return result.stdout


def status():
    return dict(x.split('=', 1) for x in run([
        'systemctl', 'show', 'ees331-camera', '-p', 'MainPID', '-p', 'ActiveState'
    ]).splitlines())


def owners():
    return {int(x) for x in run(['fuser', '/dev/mem', '/dev/dri/renderD128'], False).split()
            if x.isdecimal() and int(x) != os.getpid()}


def base_of(hwh):
    values = {int(node.get('BASEVALUE'), 0) for node in ET.parse(hwh).findall('.//MEMRANGE')
              if node.get('INSTANCE') == 'axi_vdma_0'}
    if len(values) != 1:
        raise RuntimeError('Ambiguous VDMA metadata')
    return values.pop()


def halt_gate(base):
    with open('/dev/mem', 'r+b', buffering=0) as fd:
        with mmap.mmap(fd.fileno(), 4096, offset=base) as mem:
            regs = {hex(offset): struct.unpack_from('<I', mem, offset)[0]
                    for offset in (0, 4, 0x30, 0x34)}
    emit('DMA_HALT', base=hex(base), registers=regs)
    if regs['0x0'] & 1 or regs['0x30'] & 1 or not (regs['0x4'] & 1 and regs['0x34'] & 1):
        raise RuntimeError('DMA halt not proven')


def restore_stream(pid):
    deadline = time.monotonic() + 50
    while time.monotonic() < deadline:
        beats = []
        for line in run(['journalctl', '-b', '_PID=' + pid, '-o', 'cat', '-n', '25',
                         '--no-pager']).splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get('event') == 'HEARTBEAT':
                beats.append(row)
        if (len(beats) > 1 and beats[-1]['frames'] > beats[-2]['frames']
                and all(beats[-1]['observed_transitions'])):
            emit('RESTORED_STREAM_PASS', heartbeats=beats[-2:])
            return True
        time.sleep(2)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--bit-sha256', default=BIT_SHA256)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError('root required')
    root = args.root.resolve()
    if (RUN / 'events.jsonl').exists():
        raise RuntimeError('fresh run required')
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    props = status()
    if props['ActiveState'] != 'active' or owners() != {int(props['MainPID'])}:
        raise RuntimeError('Unexpected original owner')
    emit('PREFLIGHT', boot_id=boot, service=props, package=str(root))
    for name, expected in {
        'overlay.bit': '0518c46b4dca4dca83b1e94ae5c1e8cbc8bb68fbf4537e5a90c025a10b76db87',
        'overlay.hwh': '96eeba65209e66ac3e05a65907f48cc374dab490b9d88e2e72e22689e939a4dd',
    }.items():
        actual = hashlib.sha256((BASE / name).read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError('Restoration baseline changed')
        emit('RESTORE_ARTIFACT', name=name, sha256=actual)
    for line in (root / 'sha256_manifest.txt').read_text().splitlines():
        expected, rel = line.split('  ', 1)
        path = (root / rel).resolve()
        if not path.is_relative_to(root) or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError('Staged hash mismatch: ' + rel)
    original_base = base_of(BASE / 'overlay.hwh')
    candidate_base = base_of(root / 'net3_pl_hp_rebalance.hwh')
    if original_base != candidate_base:
        raise RuntimeError('This recovery profile requires the same VDMA aperture')
    bit = root / 'net3_pl_hp_rebalance.bit'
    if hashlib.sha256(bit.read_bytes()).hexdigest() != args.bit_sha256:
        raise RuntimeError('Unexpected competition BIT')
    env = os.environ.copy()
    env.update(XILINX_XRT='/usr')
    proc = None
    stopped = False
    functional = False
    restored = False
    try:
        stopped = True
        run(['systemctl', 'stop', 'ees331-camera'])
        if status()['MainPID'] != '0' or owners():
            raise RuntimeError('Original owner remains')
        halt_gate(original_base)
        emit('ORIGINAL_STOPPED')
        with (RUN / 'candidate_console.txt').open('w') as stream:
            proc = subprocess.Popen([
                '/usr/local/share/pynq-venv/bin/python3', '-u',
                str(root / 'sw/board/fixed_input_check.py')
            ], env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            offset = 0
            deadline = time.monotonic() + 360
            while proc.poll() is None:
                with (RUN / 'candidate_console.txt').open() as reader:
                    reader.seek(offset)
                    content = reader.read()
                    offset = reader.tell()
                if content:
                    print(content, end='', flush=True)
                if time.monotonic() > deadline:
                    raise RuntimeError('Candidate timeout')
                time.sleep(.5)
        print((RUN / 'candidate_console.txt').read_text()[offset:], end='', flush=True)
        if proc.returncode:
            raise RuntimeError('Candidate failed with exit ' + str(proc.returncode))
        console = (RUN / 'candidate_console.txt').read_text()
        if 'FORM2_FIXED_INPUT_CHECK_PASS' not in console or 'C3 SUMMARY 21/21 planes match' not in console:
            raise RuntimeError('Fixed-input golden marker missing')
        functional = True
        emit('FIXED_INPUT_GOLDEN_PASS', planes='21/21', bit_sha256=args.bit_sha256)
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                emit('OWNER_TERMINATION_TIMEOUT')
        if stopped:
            deadline = time.monotonic() + 12
            while owners() and time.monotonic() < deadline:
                time.sleep(.5)
            if owners():
                raise RuntimeError('Hardware owner remains; restore prohibited')
            halt_gate(candidate_base)
            run(['systemctl', 'start', 'ees331-camera'])
            pid = status()['MainPID']
            restored = restore_stream(pid)
            if not restored:
                raise RuntimeError('Restoration stream not proven')
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip() != boot:
        raise RuntimeError('Unexpected boot change')
    result = dict(marker='FORM2_FIXED_INPUT_AND_RESTORE_PASS', functional=functional,
                  restored=restored, physical_hdmi='PENDING_USER', boot_id=boot)
    (RUN / 'result.json').write_text(json.dumps(result, indent=2))
    emit('RESULT', **result)


if __name__ == '__main__':
    main()
