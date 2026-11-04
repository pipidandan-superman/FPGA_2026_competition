"""Generate or verify complete SHA-256 manifests for the submission package."""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORMS = ('accelerator_ac1', 'form1a_ble_bridge_j5', 'form1a_pl_preprocess',
         'form1b_multitask_osd', 'form2_pl_continuous', 'form3_pspl_resident')
SKIP_PARTS = {'.git', '__pycache__', '.Xil', '.vivado-ai'}
SKIP_SUFFIXES = {'.pyc', '.jou', '.pb'}


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(block)
    return sha.hexdigest()


def files_under(base, manifest_name):
    result = []
    for path in sorted(base.rglob('*')):
        if not path.is_file() or path == base / manifest_name:
            continue
        relative = path.relative_to(base)
        if any(part in SKIP_PARTS for part in relative.parts) or path.suffix in SKIP_SUFFIXES:
            continue
        result.append(path)
    return result


def write_manifest(base):
    target = base / 'sha256_manifest.txt'
    files = files_under(base, target.name)
    text = ''.join(f'{digest(path)}  {path.relative_to(base).as_posix()}\n' for path in files)
    target.write_text(text, encoding='utf-8', newline='\n')
    print(f'MANIFEST_WRITTEN {target} files={len(files)}')
    return len(files)


def verify_manifest(base):
    target = base / 'sha256_manifest.txt'
    expected = {}
    for line in target.read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        sha, relative = line.split('  ', 1)
        if relative in expected:
            raise RuntimeError(f'Duplicate manifest path: {relative}')
        expected[relative] = sha
    actual_files = files_under(base, target.name)
    actual = {path.relative_to(base).as_posix(): path for path in actual_files}
    if set(expected) != set(actual):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise RuntimeError(f'Manifest coverage mismatch missing={missing[:5]} extra={extra[:5]}')
    for relative, path in actual.items():
        if digest(path) != expected[relative]:
            raise RuntimeError(f'Hash mismatch: {relative}')
    print(f'MANIFEST_VERIFY_PASS {base} files={len(actual)}')
    return len(actual)


def verify_binary_manifest():
    target = ROOT / 'binary_sha256.txt'
    count = 0
    for line in target.read_text(encoding='utf-8-sig').splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        expected, relative = line.split(None, 1)
        path = (ROOT / relative.strip()).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise RuntimeError(f'Missing binary entry: {relative}')
        if digest(path) != expected.lower():
            raise RuntimeError(f'Binary hash mismatch: {relative}')
        count += 1
    print(f'BINARY_MANIFEST_VERIFY_PASS files={count}')
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('generate', 'verify'))
    args = parser.parse_args()
    if args.action == 'generate':
        total = 0
        for form in FORMS:
            total += write_manifest(ROOT / 'board' / form)
        total += write_manifest(ROOT)
        print(f'PACKAGE_MANIFEST_GENERATED files={total}')
    verify_binary_manifest()
    for form in FORMS:
        verify_manifest(ROOT / 'board' / form)
    verify_manifest(ROOT)
    print('PACKAGE_MANIFEST_VERIFY_PASS')


if __name__ == '__main__':
    main()
