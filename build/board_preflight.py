"""Read-only board inventory over native OpenSSH; never stops or loads hardware."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

COMMAND = '''uname -a
cat /proc/sys/kernel/random/boot_id
cat /proc/uptime
df -h /home/xilinx
df -i /home/xilinx
du -sh /home/xilinx/amd_submission/* /home/xilinx/amd_verify/* 2>/dev/null
cat /sys/class/fpga_manager/fpga0/state
systemctl show ees331-camera --property=ActiveState,SubState,MainPID,ExecStart
ps -eo pid,ppid,etimes,args
ss -lntup
ls -l /home/xilinx/ees331_camera /home/xilinx/PSPL_YOLOV8N_RESIDENT /home/xilinx/multitask_osd
test -x /usr/local/share/pynq-venv/bin/python3 && /usr/local/share/pynq-venv/bin/python3 --version
sudo -n true && echo SUDO_NONINTERACTIVE_OK
'''

def environment():
    env = os.environ.copy()
    if env.get('EES331_SSH_PASSWORD') or env.get('BOARD_PW'):
        env.update(SSH_ASKPASS=str(Path(__file__).with_name('ssh_askpass.cmd')),
                   SSH_ASKPASS_REQUIRE='force', DISPLAY=':0', BOARD_PYTHON=sys.executable)
    return env

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='xilinx@192.168.240.10')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if args.host.startswith('-') or any(c.isspace() for c in args.host):
        parser.error('Invalid SSH host')
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    log = out/'board_preflight.txt'
    if log.exists():
        parser.error('Use a fresh evidence directory')
    cmd = ['ssh','-T','-o','ConnectTimeout=10','-o','ConnectionAttempts=1',
           '-o','StrictHostKeyChecking=yes', args.host, 'bash -s']
    try:
        with log.open('wb') as stream:
            result = subprocess.run(cmd, input=COMMAND.encode(), stdout=stream,
                                    stderr=subprocess.STDOUT, env=environment(), timeout=45)
        code = result.returncode
    except subprocess.TimeoutExpired:
        code = 124
    (out/'preflight_transport.json').write_text(json.dumps({'exit_code':code,
        'scope':'read-only inventory; no overlay or workload change',
        'hardware_function_pass':False}, indent=2), encoding='utf-8')
    print(log.read_text(encoding='utf-8',errors='replace'))
    sys.exit(code)

if __name__ == '__main__':
    main()
