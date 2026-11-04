"""EES-331 baseline-only hot-reload test. Requires explicit board-test authority.

Run as root with PYNQ Python in a fresh directory. This profile is restricted
to the recorded camera baseline; it does not validate a new competition BIT.
"""
import hashlib
import json
import mmap
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

BASE=Path('/home/xilinx/ees331_camera')
RUN=Path(__file__).resolve().parent
EXPECTED={'overlay.bit':'0518c46b4dca4dca83b1e94ae5c1e8cbc8bb68fbf4537e5a90c025a10b76db87',
          'overlay.hwh':'96eeba65209e66ac3e05a65907f48cc374dab490b9d88e2e72e22689e939a4dd',
          'camera.py':'c2e8a0da0669b19b3bc8e2c656e5ad693e1a0cf8d16b0c3a9b4c68d453600bcb'}

def emit(event,**data):
    row=dict(event=event,monotonic=time.monotonic(),**data)
    line=json.dumps(row)
    print(line,flush=True)
    with (RUN/'events.jsonl').open('a') as stream:
        stream.write(line+'\n'); stream.flush(); os.fsync(stream.fileno())

def command(args,check=True):
    result=subprocess.run(args,capture_output=True,text=True,timeout=30)
    if check and result.returncode:
        raise RuntimeError(str(args)+': '+result.stderr)
    return result.stdout

def service():
    return dict(line.split('=',1) for line in command(['systemctl','show','ees331-camera',
                '-p','MainPID','-p','ActiveState','-p','SubState']).splitlines() if '=' in line)

def owners():
    result=command(['fuser','/dev/mem','/dev/dri/renderD128'],check=False)
    return sorted({int(p) for p in result.split() if p.isdecimal() and int(p)!=os.getpid()})

def registers(base):
    with open('/dev/mem','r+b',buffering=0) as fd:
        with mmap.mmap(fd.fileno(),4096,offset=base) as mem:
            return {hex(off):struct.unpack_from('<I',mem,off)[0] for off in (0,4,0x30,0x34)}

def halted(base):
    values=registers(base)
    emit('DMA_HALT_CHECK',base=hex(base),registers=values)
    if any(values[hex(off)]&1 for off in (0,0x30)):
        raise RuntimeError('DMA run bit remains set; reload prohibited')
    if not all(values[hex(off)]&1 for off in (4,0x34)):
        raise RuntimeError('DMA status does not confirm halted; reload prohibited')

def main():
    if os.geteuid()!=0:raise RuntimeError('root required')
    if (RUN/'events.jsonl').exists():raise RuntimeError('Fresh run directory required')
    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    initial=service()
    emit('PREFLIGHT',boot_id=boot,service=initial,owners=owners())
    if initial.get('ActiveState')!='active':raise RuntimeError('Expected active original service')
    original_pid=int(initial['MainPID'])
    if owners()!=[original_pid]:raise RuntimeError('Unexpected hardware owner')
    for name,expected in EXPECTED.items():
        actual=hashlib.sha256((BASE/name).read_bytes()).hexdigest()
        if actual!=expected:raise RuntimeError('Profile hash mismatch: '+name)
        shutil.copyfile(BASE/name,RUN/name)
        if hashlib.sha256((RUN/name).read_bytes()).hexdigest()!=expected:raise RuntimeError('Copy mismatch')
        emit('ARTIFACT_MATCH',name=name,sha256=actual)
    tree=ET.parse(RUN/'overlay.hwh')
    ranges=[n for n in tree.findall('.//MEMRANGE') if n.get('INSTANCE')=='axi_vdma_0']
    bases={int(n.get('BASEVALUE'),0) for n in ranges}
    if len(bases)!=1:raise RuntimeError('Ambiguous VDMA mapping')
    base=bases.pop()
    # Patch only a copied, hash-pinned baseline to apply the documented
    # hot-reload settle/window. The installed service is never edited.
    source=(RUN/'camera.py').read_text()
    replacements=[('time.sleep(1.0)','time.sleep(10.0)'),
                  ("log('SENSOR_SETTLE_COMPLETE', seconds=1.0)","log('SENSOR_SETTLE_COMPLETE', seconds=10.0)"),
                  ('deadline = time.monotonic() + 5','deadline = time.monotonic() + 30')]
    for old,new in replacements:
        if source.count(old)!=1:raise RuntimeError('Baseline adaptation mismatch')
        source=source.replace(old,new)
    (RUN/'camera_candidate.py').write_text(source)
    emit('CANDIDATE_PREPARED',sha256=hashlib.sha256(source.encode()).hexdigest(),changes=replacements)
    proc=None
    stopped=False
    test_pass=False
    restored=False
    try:
        stopped=True
        command(['systemctl','stop','ees331-camera'])
        if service().get('MainPID')!='0' or owners():raise RuntimeError('Original owner not released')
        halted(base)
        emit('ORIGINAL_STOPPED_DMA_HALTED')
        with (RUN/'candidate_console.txt').open('w') as log:
            proc=subprocess.Popen([sys.executable,'-u',str(RUN/'camera_candidate.py'),
                 '--bit',str(RUN/'overlay.bit'),'--seconds','8','--no-udp',
                 '--evidence',str(RUN/'capture')],stdout=log,stderr=subprocess.STDOUT)
            deadline=time.monotonic()+100
            offset=0
            while proc.poll() is None:
                with (RUN/'candidate_console.txt').open() as reader:
                    reader.seek(offset); content=reader.read(); offset=reader.tell()
                if content:print(content,end='',flush=True)
                if time.monotonic()>deadline:
                    proc.terminate()
                    raise RuntimeError('Candidate timed out; state requires halt verification')
                time.sleep(.5)
        print((RUN/'candidate_console.txt').read_text()[offset:],end='',flush=True)
        if proc.returncode:raise RuntimeError('Candidate application failed')
        result=json.loads((RUN/'capture'/'result.json').read_text())
        if result.get('result')!='CAPTURE_VDMA_RUN_COMPLETE' or result.get('frames',0)<10:
            raise RuntimeError('Insufficient fresh capture frames')
        if not all(result['vdma']['observed_transitions']):raise RuntimeError('No stream progress')
        halted(base)
        test_pass=True
        emit('CANDIDATE_STREAM_PASS',result=result)
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:proc.wait(timeout=12)
            except subprocess.TimeoutExpired:emit('RESTORE_BLOCKED_LIVE_OWNER')
        if stopped:
            if owners():raise RuntimeError('Owner remains; refusing competing restore')
            halted(base)
            command(['systemctl','start','ees331-camera'])
            pid=service()['MainPID']
            deadline=time.monotonic()+50
            while time.monotonic()<deadline:
                text=command(['journalctl','-b','_PID='+pid,'-o','cat','-n','25','--no-pager'])
                beats=[]
                for line in text.splitlines():
                    try:row=json.loads(line)
                    except ValueError:continue
                    if row.get('event')=='HEARTBEAT':beats.append(row)
                if len(beats)>=2 and beats[-1]['frames']>beats[-2]['frames'] and all(beats[-1]['observed_transitions']):
                    emit('RESTORED_STREAM_PASS',pid=pid,heartbeats=beats[-2:]); restored=True; break
                time.sleep(2)
            if not restored:raise RuntimeError('Original stream restoration not proven')
    if Path('/proc/sys/kernel/random/boot_id').read_text().strip()!=boot:raise RuntimeError('Unexpected reboot')
    result=dict(marker='OVERLAY_BASELINE_RELOAD_RESTORE_PASS' if test_pass and restored else 'FAIL',
                boot_id=boot,package_candidate_validated=False,physical_hdmi='PENDING_USER_OBSERVATION',
                candidate_stream_pass=test_pass,restoration_pass=restored)
    (RUN/'result.json').write_text(json.dumps(result,indent=2))
    emit('RESULT',**result)

if __name__=='__main__':main()
