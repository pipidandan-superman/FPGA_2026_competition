"""EES-331 recovery after evidenced first-frame timeout; boot-local override."""
import hashlib
import json
import mmap
import os
from pathlib import Path
import struct
import subprocess
import time
import xml.etree.ElementTree as ET

RUN=Path(__file__).resolve().parent
BASE=Path('/home/xilinx/ees331_camera')
def command(args):
    r=subprocess.run(args,capture_output=True,text=True,timeout=30)
    if r.returncode:raise RuntimeError(str(args)+r.stderr)
    return r.stdout
def emit(event,**details):
    row=dict(event=event,monotonic=time.monotonic(),**details)
    line=json.dumps(row);print(line,flush=True)
    with (RUN/'events.jsonl').open('a') as f:f.write(line+'\n')
def main():
    if os.geteuid()!=0:raise RuntimeError('root required')
    if (RUN/'events.jsonl').exists():raise RuntimeError('fresh run required')
    props=dict(x.split('=',1) for x in command(['systemctl','show','ees331-camera','-p','MainPID','-p','ActiveState']).splitlines())
    if props['MainPID']!='0' or props['ActiveState'] not in ('failed','inactive'):
        raise RuntimeError('Expected stopped/failed camera without process')
    owners=subprocess.run(['fuser','/dev/mem','/dev/dri/renderD128'],capture_output=True,text=True)
    if owners.stdout.strip():raise RuntimeError('Hardware owner exists')
    expected={'camera.py':'c2e8a0da0669b19b3bc8e2c656e5ad693e1a0cf8d16b0c3a9b4c68d453600bcb',
              'overlay.bit':'0518c46b4dca4dca83b1e94ae5c1e8cbc8bb68fbf4537e5a90c025a10b76db87',
              'overlay.hwh':'96eeba65209e66ac3e05a65907f48cc374dab490b9d88e2e72e22689e939a4dd'}
    for name,digest in expected.items():
        if hashlib.sha256((BASE/name).read_bytes()).hexdigest()!=digest:raise RuntimeError('Baseline hash changed')
    bases={int(n.get('BASEVALUE'),0) for n in ET.parse(BASE/'overlay.hwh').findall('.//MEMRANGE') if n.get('INSTANCE')=='axi_vdma_0'}
    if len(bases)!=1:raise RuntimeError('Ambiguous VDMA base')
    with open('/dev/mem','r+b',buffering=0) as fd:
        with mmap.mmap(fd.fileno(),4096,offset=bases.pop()) as mem:
            regs={hex(o):struct.unpack_from('<I',mem,o)[0] for o in (0,4,0x30,0x34)}
    if regs['0x0']&1 or regs['0x30']&1 or not(regs['0x4']&1 and regs['0x34']&1):raise RuntimeError('DMA halt unproven')
    emit('RECOVERY_PREFLIGHT_PASS',registers=regs,baseline=expected)
    source=(BASE/'camera.py').read_text()
    for old,new in [('time.sleep(1.0)','time.sleep(10.0)'),
                    ("log('SENSOR_SETTLE_COMPLETE', seconds=1.0)","log('SENSOR_SETTLE_COMPLETE', seconds=10.0)"),
                    ('deadline = time.monotonic() + 5','deadline = time.monotonic() + 30')]:
        if source.count(old)!=1:raise RuntimeError('Unexpected baseline source')
        source=source.replace(old,new)
    candidate=RUN/'camera_recovery.py';candidate.write_text(source)
    dropin=Path('/run/systemd/system/ees331-camera.service.d/90-amd-recovery.conf')
    if dropin.exists():raise RuntimeError('Recovery override already exists')
    dropin.parent.mkdir(parents=True,exist_ok=True)
    config='[Service]\nEnvironment=XILINX_XRT=/usr\nExecStart=\nExecStart=/usr/local/share/pynq-venv/bin/python3 -u '+str(candidate)+' --bit '+str(BASE/'overlay.bit')+' --peer 192.168.240.2 --port 5000 --fps 5\n'
    dropin.write_text(config);(RUN/'runtime_override.conf').write_text(config)
    emit('BOOT_LOCAL_OVERRIDE_CREATED',path=str(dropin),candidate_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest())
    command(['systemctl','daemon-reload']);command(['systemctl','start','ees331-camera'])
    pid=command(['systemctl','show','ees331-camera','-p','MainPID','--value']).strip()
    deadline=time.monotonic()+85
    while time.monotonic()<deadline:
        journal=command(['journalctl','-b','_PID='+pid,'-n','30','-o','cat','--no-pager'])
        (RUN/'recovery_journal.txt').write_text(journal)
        beats=[]
        for line in journal.splitlines():
            try:row=json.loads(line)
            except ValueError:continue
            if row.get('event')=='HEARTBEAT':beats.append(row)
        if len(beats)>1 and beats[-1]['frames']>beats[-2]['frames'] and all(beats[-1]['observed_transitions']):
            emit('RECOVERY_STREAM_PASS',pid=pid,heartbeats=beats[-2:],physical_hdmi='PENDING_USER')
            return
        time.sleep(2)
    raise RuntimeError('Recovery stream not proven; inspect journal and owners before further changes')
if __name__=='__main__':main()
