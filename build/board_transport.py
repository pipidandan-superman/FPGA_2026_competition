"""Upload one reviewed script into a fresh board directory and retain its output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
from board_preflight import environment

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host',default='xilinx@192.168.240.10')
    parser.add_argument('--script',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--sudo',action='store_true')
    parser.add_argument('--timeout',type=int,default=120)
    parser.add_argument('--script-arg',action='append',default=[])
    args=parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9_.@:-]+',args.host) or args.host.startswith('-'):
        parser.error('Invalid host')
    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=True)
    if (out/'transport.json').exists() or (out/'board_console.txt').exists():
        parser.error('A fresh output directory is required')
    remote='/home/xilinx/amd_verify/'+out.name
    if not re.fullmatch(r'[a-zA-Z0-9_-]+',out.name):parser.error('Invalid run directory name')
    options=['-o','ConnectTimeout=10','-o','StrictHostKeyChecking=yes']
    env=environment()
    ssh=['ssh','-T',*options,args.host]
    subprocess.run([*ssh,'mkdir -p /home/xilinx/amd_verify && mkdir '+shlex.quote(remote)],env=env,check=True,timeout=20,stdin=subprocess.DEVNULL)
    subprocess.run(['scp',*options,str(args.script.resolve()),args.host+':'+remote+'/run.py'],env=env,check=True,timeout=30,stdin=subprocess.DEVNULL)
    cmd='env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 -u '+shlex.quote(remote+'/run.py')
    cmd+=''.join(' '+shlex.quote(arg) for arg in args.script_arg)
    password=env.get('EES331_SSH_PASSWORD') or env.get('BOARD_PW')
    if args.sudo:
        cmd='sudo -S -p "" '+cmd
        if not password:parser.error('sudo requires EES331_SSH_PASSWORD or BOARD_PW')
    with (out/'board_console.txt').open('wb') as log:
        try:
            result=subprocess.run([*ssh,cmd],input=(password+'\n').encode() if args.sudo else b'',
                env=env,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
            code=result.returncode
        except subprocess.TimeoutExpired:
            code=124
    record={'host':args.host,'remote':remote,'exit_code':code,'sudo':args.sudo,
            'script_sha256':hashlib.sha256(args.script.read_bytes()).hexdigest(),
            'timeout_means_remote_state_unknown':code==124}
    (out/'transport.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print((out/'board_console.txt').read_text(encoding='utf-8',errors='replace'))
    sys.exit(code)

if __name__=='__main__':main()
