"""Run a staged resident package for bounded live inference and restore camera.

Board use requires authority to interrupt the current camera baseline.
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
import sys
import time
import xml.etree.ElementTree as ET

RUN=Path(__file__).resolve().parent
BASE=Path('/home/xilinx/ees331_camera')

def emit(event,**details):
    line=json.dumps(dict(event=event,monotonic=time.monotonic(),**details))
    print(line,flush=True)
    with (RUN/'events.jsonl').open('a') as stream:
        stream.write(line+'\n'); stream.flush(); os.fsync(stream.fileno())

def run(args,check=True,timeout=30):
    r=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
    if check and r.returncode:raise RuntimeError(str(args)+': '+r.stdout+r.stderr)
    return r.stdout

def status():
    return dict(x.split('=',1) for x in run(['systemctl','show','ees331-camera','-p','MainPID','-p','ActiveState']).splitlines())

def owners():
    return {int(x) for x in run(['fuser','/dev/mem','/dev/dri/renderD128'],False).split() if x.isdecimal() and int(x)!=os.getpid()}

def base_of(hwh):
    values={int(n.get('BASEVALUE'),0) for n in ET.parse(hwh).findall('.//MEMRANGE') if n.get('INSTANCE')=='axi_vdma_0'}
    if len(values)!=1:raise RuntimeError('Ambiguous VDMA metadata')
    return values.pop()

def halt_gate(base):
    with open('/dev/mem','r+b',buffering=0) as fd:
        with mmap.mmap(fd.fileno(),4096,offset=base) as mem:
            regs={hex(o):struct.unpack_from('<I',mem,o)[0] for o in (0,4,0x30,0x34)}
    emit('DMA_HALT',base=hex(base),registers=regs)
    if regs['0x0']&1 or regs['0x30']&1 or not (regs['0x4']&1 and regs['0x34']&1):
        raise RuntimeError('DMA halt not proven')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root',type=Path)
    parser.add_argument('--gestures',action='store_true')
    parser.add_argument('--bit-sha256',default='72b358ff75a8d1c1bda519da248bd94fb4bdc236dd16fcca36eb4fc1262f7a58')
    args=parser.parse_args()
    if os.geteuid()!=0:raise RuntimeError('root required')
    root=args.root.resolve()
    if (RUN/'events.jsonl').exists():raise RuntimeError('fresh run required')
    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    props=status()
    if props['ActiveState']!='active' or owners()!={int(props['MainPID'])}:raise RuntimeError('Unexpected original owner')
    emit('PREFLIGHT',boot_id=boot,service=props,package=str(root))
    for name,expected in {'overlay.bit':'0518c46b4dca4dca83b1e94ae5c1e8cbc8bb68fbf4537e5a90c025a10b76db87',
                          'overlay.hwh':'96eeba65209e66ac3e05a65907f48cc374dab490b9d88e2e72e22689e939a4dd'}.items():
        actual=hashlib.sha256((BASE/name).read_bytes()).hexdigest()
        if actual!=expected:raise RuntimeError('Restoration baseline changed')
        emit('RESTORE_ARTIFACT',name=name,sha256=actual)
    manifest=(root/'sha256_manifest.txt').read_text().splitlines()
    for line in manifest:
        expected,rel=line.split('  ',1)
        p=(root/rel).resolve()
        if not p.is_relative_to(root) or hashlib.sha256(p.read_bytes()).hexdigest()!=expected:
            raise RuntimeError('Staged hash mismatch: '+rel)
    original_base=base_of(BASE/'overlay.hwh')
    candidate_base=base_of(root/'sw/board_artifacts/hybrid_heads_ic64_fix.hwh')
    if original_base!=candidate_base:raise RuntimeError('This recovery profile requires same VDMA aperture')
    bit=root/'sw/board_artifacts/hybrid_heads_ic64_fix.bit'
    if hashlib.sha256(bit.read_bytes()).hexdigest()!=args.bit_sha256:
        raise RuntimeError('Unexpected competition BIT')
    env=os.environ.copy();env.update(PSPL_ROOT=str(root),CURRENT_BIT=str(BASE/'overlay.bit'),XILINX_XRT='/usr',EXPECTED_BIT_SHA256=args.bit_sha256)
    compiler=subprocess.run(['sh',str(root/'sw/board/build_hybrid_server.sh')],env=env,capture_output=True,text=True,timeout=120)
    (RUN/'server_build.txt').write_text(compiler.stdout+compiler.stderr)
    if compiler.returncode:raise RuntimeError('Server build failed before hardware interruption')
    emit('SERVER_BUILD_PASS',sha256=hashlib.sha256((root/'sw/board/t1_ncnn_server_hybrid').read_bytes()).hexdigest())
    proc=None; stopped=False; functional=False; restored=False
    try:
        stopped=True;run(['systemctl','stop','ees331-camera'])
        if status()['MainPID']!='0' or owners():raise RuntimeError('Original owner remains')
        halt_gate(original_base)
        emit('ORIGINAL_STOPPED')
        with (RUN/'candidate_console.txt').open('w') as stream:
            proc=subprocess.Popen(['bash',str(root/'sw/board/run_live_gesture7.sh'),
                '--max-frames','200' if args.gestures else '8',
                '--seconds','600' if args.gestures else '120','--evidence',str(RUN/'capture')],env=env,
                stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
            offset=0; deadline=time.monotonic()+(660 if args.gestures else 180)
            while proc.poll() is None:
                with (RUN/'candidate_console.txt').open() as reader:
                    reader.seek(offset); content=reader.read(); offset=reader.tell()
                if content:print(content,end='',flush=True)
                if time.monotonic()>deadline:raise RuntimeError('Candidate timeout')
                time.sleep(.5)
        print((RUN/'candidate_console.txt').read_text()[offset:],end='',flush=True)
        if proc.returncode:raise RuntimeError('Candidate failed with exit '+str(proc.returncode))
        summary=json.loads((RUN/'capture/summary.json').read_text())
        if summary.get('frames',0)<5:raise RuntimeError('Insufficient live inference frames')
        rows=[json.loads(line) for line in (RUN/'capture/results.jsonl').read_text().splitlines()]
        hashes={row['input_sha256'] for row in rows}
        if len(hashes)<2 or summary.get('unique_input_frames',0)<2:
            raise RuntimeError('Camera input did not change')
        if summary.get('startup_progress')!=[True,True]:
            raise RuntimeError('Both-channel startup progress unproven')
        for name in ('first_input.bgr','last_input.bgr'):
            frame=(RUN/'capture'/name).read_bytes()
            if len(frame)!=640*480*3 or hashlib.sha256(frame).hexdigest() not in hashes:
                raise RuntimeError('Raw input evidence does not match inference records')
        functional=True
        sequence=(summary.get('result')=='GESTURE7_SEQUENCE_OBSERVED'
                  and [r['class_id'] for r in summary.get('observed',[])]==list(range(7)))
        emit('LIVE_INFERENCE_SMOKE_PASS',summary=summary,seven_class_acceptance=sequence)
    finally:
        if proc is not None:
            # Only the process group created above is signaled, including its
            # private ncnn server. Never stop a system-wide name pattern.
            try:os.killpg(proc.pid,signal.SIGTERM)
            except ProcessLookupError:pass
            try:proc.wait(timeout=15)
            except subprocess.TimeoutExpired:emit('OWNER_TERMINATION_TIMEOUT')
        if stopped:
            deadline=time.monotonic()+12
            while owners() and time.monotonic()<deadline:time.sleep(.5)
            if owners():raise RuntimeError('Hardware owner remains; restore prohibited')
            halt_gate(candidate_base)
            run(['systemctl','start','ees331-camera'])
            pid=status()['MainPID']; deadline=time.monotonic()+50
            while time.monotonic()<deadline:
                beats=[]
                for line in run(['journalctl','-b','_PID='+pid,'-o','cat','-n','25','--no-pager']).splitlines():
                    try:row=json.loads(line)
                    except ValueError:continue
                    if row.get('event')=='HEARTBEAT':beats.append(row)
                if len(beats)>1 and beats[-1]['frames']>beats[-2]['frames'] and all(beats[-1]['observed_transitions']):
                    restored=True;emit('RESTORED_STREAM_PASS',heartbeats=beats[-2:]);break
                time.sleep(2)
            if not restored:raise RuntimeError('Restoration stream not proven')
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip()!=boot:raise RuntimeError('Unexpected boot change')
    result=dict(marker='FORM3_LIVE_SMOKE_AND_RESTORE_PASS',functional=functional,restored=restored,
                seven_class_acceptance=sequence,physical_hdmi='PENDING_USER',boot_id=boot)
    (RUN/'result.json').write_text(json.dumps(result,indent=2));emit('RESULT',**result)
    if args.gestures and not sequence:raise RuntimeError('Seven-gesture sequence incomplete; baseline restored')

if __name__=='__main__':main()
