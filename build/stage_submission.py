"""Create a complete deployment tree from this package; optionally upload it.

Staging never stops processes or loads an overlay. Board execution follows
the ownership/DMA gates documented by the overlay skill.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import zipfile
import xml.etree.ElementTree as ET
from board_preflight import environment

ROOT=Path(__file__).resolve().parents[1]
FORMS=('form1b_multitask_osd','form2_pl_continuous','form3_pspl_resident')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--form',choices=FORMS,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--remote-root',required=True,help='New board directory, never an existing deployment')
    p.add_argument('--host',default='xilinx@192.168.240.10')
    p.add_argument('--upload',action='store_true')
    p.add_argument('--bit',type=Path)
    p.add_argument('--hwh',type=Path)
    p.add_argument('--xsa',type=Path)
    a=p.parse_args()
    variants=(a.bit,a.hwh,a.xsa)
    if any(variants):
        if not all(variants) or a.form!='form3_pspl_resident':p.error('Form3 variant requires matched --bit --hwh --xsa')
        with zipfile.ZipFile(a.xsa) as archive:
            bit_members=[n for n in archive.namelist() if n.endswith('.bit')]
            top_hwh=[]
            for name in archive.namelist():
                if name.endswith('.hwh'):
                    tree=ET.fromstring(archive.read(name))
                    instances={node.get('INSTANCE') for node in tree.findall('.//MODULE')}
                    if {'processing_system7_0','axi_vdma_0'} <= instances:
                        top_hwh.append(name)
            if len(bit_members)!=1 or len(top_hwh)!=1:
                p.error('XSA must contain exactly one BIT and one top-level PS7/VDMA HWH')
            for source,member in ((a.bit,bit_members[0]),(a.hwh,top_hwh[0])):
                if hashlib.sha256(source.read_bytes()).digest()!=hashlib.sha256(archive.read(member)).digest():
                    p.error('Selected BIT/top-level HWH do not match XSA members')
    if not re.fullmatch(r'/home/xilinx/[a-zA-Z0-9_/-]+',a.remote_root) or '..' in a.remote_root.split('/'):
        p.error('Use an absolute /home/xilinx/... directory with safe path characters')
    if a.host.startswith('-') or not re.fullmatch(r'[a-zA-Z0-9_.@:-]+',a.host):p.error('Invalid SSH host')
    out=a.output.resolve()
    if out.is_relative_to(ROOT):p.error('Evidence/staging output must be outside package')
    if out.exists() and any(out.iterdir()):p.error('Use a fresh output directory')
    out.mkdir(parents=True,exist_ok=True)
    payload=out/'payload'; payload.mkdir()
    base=ROOT/'board'/a.form
    ledger=[]
    def copy(source,relative):
        if source.is_dir():
            for item in sorted(source.rglob('*')):
                if item.is_file():copy(item,Path(relative)/item.relative_to(source))
            return
        if not source.is_file():raise FileNotFoundError(source)
        target=payload/relative; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,target)
        ledger.append(dict(source=source.relative_to(ROOT).as_posix(),target=target.relative_to(payload).as_posix(),
                           source_sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
    if a.form=='form1b_multitask_osd':
        copy(base/'sw/board','sw/board'); copy(base/'models','models')
        copy(base/'sw/board_artifacts','sw/board_artifacts')
    else:
        copy(base/'sw','sw'); copy(base/'prog','prog'); copy(ROOT/'data/gold','gold')
        if a.form=='form3_pspl_resident':copy(base/'models','models')
        else:
            copy(ROOT/'src/form2_pl_continuous/descriptor_table.json','descriptor_table.json')
            copy(base/'sw/board_artifacts/net3_pl_hp_rebalance.bit','net3_pl_hp_rebalance.bit')
            copy(base/'sw/board_artifacts/display_test.hwh','net3_pl_hp_rebalance.hwh')
    replacements={'/home/xilinx/PSPL_YOLOV8N_RESIDENT':a.remote_root,
                  '/home/xilinx/three_task/models':a.remote_root+'/models'}
    transformations=[]
    if all(variants):
        for source,suffix in zip(variants,('.bit','.hwh','.xsa')):
            relative='sw/board_artifacts/hybrid_heads_ic64_fix'+suffix
            shutil.copyfile(source,payload/relative)
            transformations.append(dict(path=relative,kind='matched rebuilt artifact substitution',
                source=str(source.resolve()),sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
    for conf in sorted(payload.rglob('*.conf')):
        original=conf.read_bytes(); revised=original
        for old,new in replacements.items():revised=revised.replace(old.encode(),new.encode())
        if revised!=original:
            conf.write_bytes(revised)
            transformations.append(dict(path=conf.relative_to(payload).as_posix(),
                kind='model registry deployment-root substitution; bytes/newline otherwise preserved'))
    manifest=[]
    for file in sorted(payload.rglob('*')):
        if file.is_file():manifest.append(dict(path=file.relative_to(payload).as_posix(),
            sha256=hashlib.sha256(file.read_bytes()).hexdigest(),size=file.stat().st_size))
    (payload/'sha256_manifest.txt').write_text(''.join(r['sha256']+'  '+r['path']+'\n' for r in manifest),encoding='utf-8',newline='\n')
    record=dict(form=a.form,remote_root=a.remote_root,files=manifest,sources=ledger,transformations=transformations,
                uploaded=False,board_function_pass=False)
    (out/'staging_manifest.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    if a.upload:
        options=['-o','ConnectTimeout=10','-o','StrictHostKeyChecking=yes']
        ssh=['ssh','-T',*options,a.host]; env=environment()
        root=shlex.quote(a.remote_root)
        parent=shlex.quote(a.remote_root.rsplit('/',1)[0])
        space=subprocess.run([*ssh,'df -Pk /home/xilinx'],capture_output=True,text=True,
                             env=env,check=True,timeout=20,stdin=subprocess.DEVNULL)
        available=int(space.stdout.splitlines()[-1].split()[3])*1024
        required=sum(item['size'] for item in manifest)+32*1024*1024
        (out/'space_preflight.json').write_text(json.dumps(dict(available_bytes=available,
            required_bytes=required,reserve_bytes=32*1024*1024),indent=2),encoding='utf-8')
        if available<required:raise RuntimeError('Insufficient board disk space before upload')
        subprocess.run([*ssh,'mkdir -p '+parent+' && mkdir '+root],check=True,env=env,timeout=20,stdin=subprocess.DEVNULL)
        subprocess.run(['scp',*options,'-r',str(payload)+ '/.',a.host+':'+a.remote_root+'/'],
                       check=True,env=env,timeout=240,stdin=subprocess.DEVNULL)
        with (out/'remote_sha256_check.txt').open('w') as log:
            subprocess.run([*ssh,'cd '+root+' && sha256sum -c sha256_manifest.txt'],env=env,
                           stdout=log,stderr=subprocess.STDOUT,check=True,timeout=90,stdin=subprocess.DEVNULL)
        record['uploaded']=True
        (out/'staging_manifest.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print('PACKAGE_STAGING_PASS',a.form,'files='+str(len(manifest)),'uploaded='+str(record['uploaded']))
    print('No workload or FPGA state was changed by this staging command.')

if __name__=='__main__':main()
