"""Fetch a completed board_transport run and hash all returned evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from board_preflight import environment

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
record=json.loads((args.output/'transport.json').read_text())
target=args.output/'board_artifacts'
if target.exists():raise SystemExit('Evidence already fetched; use existing files')
subprocess.run(['scp','-o','ConnectTimeout=10','-o','StrictHostKeyChecking=yes','-r',
    record['host']+':'+record['remote'],str(target.resolve())],env=environment(),
    check=True,timeout=90,stdin=subprocess.DEVNULL)
manifest=[dict(path=p.relative_to(target).as_posix(),size=p.stat().st_size,
               sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(target.rglob('*')) if p.is_file()]
(args.output/'fetched_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('FETCHED_FILES',len(manifest))
