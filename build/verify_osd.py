"""Vivado 2025.2 XSim smoke, OSD positives and historical negative control."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--vivado-home',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();out=a.output.resolve();vh=a.vivado_home.resolve()
    if out.is_relative_to(ROOT) or out.exists():p.error('Use a new output directory outside package')
    if not (vh/'settings64.bat').is_file():p.error('Vivado settings64.bat missing')
    out.mkdir(parents=True)
    rtl=ROOT/'src/form1b_multitask_osd/rtl';tb=ROOT/'sim/form1b_multitask_osd/tb'
    cases=[('smoke','tb_simulator_smoke',[],None),
           ('coco','tb_task_coco_osd',[rtl/'axi_lite_slave.v',rtl/'task_coco_osd.v',tb/'tb_task_coco_osd.v'],'COCO_OSD_ALL_PASS'),
           ('pose','tb_task_pose_osd',[rtl/'axi_lite_slave.v',rtl/'task_pose_osd.v',tb/'tb_task_pose_osd.v'],'POSE_OSD_ALL_PASS'),
           ('negative_pose','tb_task_pose_osd',[rtl/'axi_lite_slave.v',ROOT/'sim/form1b_multitask_osd/sim_v3/negctl_task_pose_osd_old.v',tb/'tb_task_pose_osd.v'],'POSE_FONT_PIXEL_FAIL')]
    ledger=[]
    for name,top,sources,marker in cases:
        run=out/name;run.mkdir()
        if name=='smoke':
            sources=[ROOT/'sim/form1b_multitask_osd/tb/tb_simulator_smoke.sv'];marker='SIMULATOR_SMOKE_PASS'
        for source in sources+list(rtl.glob('*.hex')):
            shutil.copyfile(source,run/source.name)
            ledger.append(dict(case=name,path=source.relative_to(ROOT).as_posix(),sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
        (out/'input_manifest.json').write_text(json.dumps(ledger,indent=2))
        (run/'run.tcl').write_text('run all\nquit\n')
        commands=['@echo off','if not defined PROCESSOR_ARCHITECTURE set PROCESSOR_ARCHITECTURE=AMD64',
                  'call "'+str(vh/'settings64.bat')+'"','if errorlevel 1 exit /b 2',
                  'cd /d "'+str(run)+'"',
                  'call "'+str(vh/'bin/xvlog.bat')+'" --sv '+' '.join('"'+s.name+'"' for s in sources)+' > compile.log 2>&1',
                  'if errorlevel 1 exit /b 3',
                  'call "'+str(vh/'bin/xelab.bat')+'" work.'+top+' -s test_snapshot > elaborate.log 2>&1',
                  'if errorlevel 1 exit /b 4',
                  'call "'+str(vh/'bin/xsim.bat')+'" test_snapshot --tclbatch run.tcl > simulation.log 2>&1',
                  'exit /b %errorlevel%']
        (run/'run.cmd').write_text('\n'.join(commands)+'\n')
        result=subprocess.run(['cmd.exe','/d','/c',str(run/'run.cmd')],capture_output=True,text=True,timeout=300)
        (run/'launcher.txt').write_text(result.stdout+result.stderr)
        text=(run/'simulation.log').read_text(errors='replace') if (run/'simulation.log').exists() else ''
        if 'xsim v2025.2' not in text:raise RuntimeError('Unexpected or missing simulator version')
        if name=='negative_pose':
            passed=('Fatal:' in text and marker in text and 'POSE_OSD_ALL_PASS' not in text)
        else:passed=(result.returncode==0 and marker in text and 'Fatal:' not in text and 'ERROR:' not in text)
        record=dict(case=name,exit_code=result.returncode,marker=marker,passed=passed)
        (run/'result.json').write_text(json.dumps(record,indent=2));print(json.dumps(record),flush=True)
        if not passed:raise RuntimeError('Simulation gate failed: '+name)
    (out/'input_manifest.json').write_text(json.dumps(ledger,indent=2))
    (out/'result.json').write_text(json.dumps(dict(marker='OSD_REGRESSION_PASS',cases=4),indent=2))
    print('OSD_REGRESSION_PASS')
if __name__=='__main__':main()
