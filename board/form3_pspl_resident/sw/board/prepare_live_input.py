from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
S_INPUT = 0.020787402400820273
raw = bytes.fromhex(' '.join(
    line.strip() for line in (ROOT / 'gold/x_image.hex').read_text().splitlines()
    if line.strip() and not line.strip().startswith(';')))
if len(raw) != 307200:
    raise RuntimeError(f'x_image size mismatch: {len(raw)}')
q = np.frombuffer(raw, dtype=np.int8).reshape(1, 3, 320, 320)
blob = (q.astype(np.float32) * S_INPUT).astype(np.float32)
np.save(ROOT / 'live_input.npy', blob)
print('PREPARE_LIVE_INPUT_PASS', blob.shape, blob.dtype)
