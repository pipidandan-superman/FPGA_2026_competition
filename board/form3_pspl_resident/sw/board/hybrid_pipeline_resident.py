"""PS backbone/neck + PL heads + PS decode candidate pipeline.

Speed/display candidate (2026-11-03 pspl_v8n_gesture7_boardprep_run01 A/B/C):
runs the PL heads through the in-process pl_heads_runtime (init once, run per
frame -- no runpy re-execution, no per-frame feature/segment files), decodes
at a parameterized display confidence (default 0.40; the seven-gesture
judgment gate stays >= 0.55 in the harness), maps boxes back through the
correct inverse letterbox (x*2, (y-40)*2 for 640x480 -> 320x320; the old
[2.0,1.5,2.0,1.5] mapping was the NanoDet direct-resize geometry and
misplaced boxes vertically), and reports a pre-threshold top-1 baseline every
frame for the int8 sensitivity record.
"""
import hashlib
import json
import os
from pathlib import Path

import numpy as np

import head_decode as HD
import pl_heads_runtime as RT
from hybrid_client import request_hybrid

ROOT = Path(os.environ.get("PSPL_ROOT", str(Path(__file__).resolve().parents[2])))
DESCRIPTOR = ROOT / 'prog/descriptor_table.json'
LABELS = ['Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']
SEGMENTS = [
    ('reg8', (64, 40, 40)), ('reg16', (64, 20, 20)), ('reg32', (64, 10, 10)),
    ('cls8', (7, 40, 40)), ('cls16', (7, 20, 20)), ('cls32', (7, 10, 10)),
]
SEGMENT_BUF = {'reg8': 88, 'reg16': 94, 'reg32': 100, 'cls8': 91, 'cls16': 97, 'cls32': 103}
DISPLAY_CONF = float(os.environ.get('HEADS_DISPLAY_CONF', '0.50'))
SRC_W, SRC_H = 640, 480

# 2026-11-05 board verdict (user, live seven-gesture test): the merged_v65
# dataset's Left/Right ground truth is inverted vs viewer direction -- see
# 2026-10-23_mcontract_v8n_lr_retrain_run01 (visual-left images carry GT
# "Right", e.g. person-pointing-left; the lr mirror-swap augmentation
# faithfully preserved that convention). The lr_retrain README names the
# board per-gesture test as the final arbiter; that test says: pointing
# left must display "Left". Remap class ids 1<->2 at the decode exit so
# display strip, boxes, judgment progression and the top-1 baseline all
# speak viewer semantics. Candidate-only; frozen packages untouched.
LR_CLASS_REMAP = {1: 2, 2: 1}


def _scales():
    desc = json.loads(DESCRIPTOR.read_text())
    heads = next(e for e in desc['entries'] if e['op'] == 'heads')
    return {int(e['buf']): float(e['scale']) for e in heads['reg'] + heads['cls']}


def top1_baseline(segments, cls_scales):
    """Pre-threshold best class score over the three cls planes (int8
    sensitivity baseline; same dequant+sigmoid as the decoder)."""
    best_conf, best_cls, best_seg = 0.0, -1, None
    for name, shape in SEGMENTS:
        if not name.startswith('cls'):
            continue
        arr = np.frombuffer(segments[name], dtype=np.int8,
                            count=int(np.prod(shape))).reshape(shape)
        s = 1.0 / (1.0 + np.exp(-(arr.astype(np.float32)
                                  * np.float32(cls_scales[SEGMENT_BUF[name]]))))
        m = float(s.max())
        if m > best_conf:
            best_conf = m
            best_cls = int(np.unravel_index(int(s.argmax()), s.shape)[0])
            best_seg = name
    return dict(confidence=round(best_conf, 4),
                class_id=LR_CLASS_REMAP.get(best_cls, best_cls),
                segment=best_seg,
                label=LABELS[LR_CLASS_REMAP.get(best_cls, best_cls)] if best_cls >= 0 else None)


def decode_heads(blob, conf=DISPLAY_CONF):
    by_scale = _scales()
    regs, clss, rs, cs = {}, {}, {}, {}
    for name, shape in SEGMENTS:
        count = int(np.prod(shape))
        arr = np.frombuffer(blob[name], dtype=np.int8, count=count).reshape(shape).copy()
        if name.startswith('reg'):
            regs[name] = arr
            rs[name] = by_scale[SEGMENT_BUF[name]]
        else:
            clss[name] = arr
            cs[name] = by_scale[SEGMENT_BUF[name]]
    raw = HD.decode(regs, clss, rs, cs, conf=conf, iou=0.7, canvas=320)
    detections = []
    for d in raw:
        xy = HD.canvas_to_frame(np.array(d['xyxy'], np.float32), SRC_W, SRC_H)
        xy[0] = min(max(xy[0], 0.0), SRC_W - 1.0)
        xy[2] = min(max(xy[2], 0.0), SRC_W - 1.0)
        xy[1] = min(max(xy[1], 0.0), SRC_H - 1.0)
        xy[3] = min(max(xy[3], 0.0), SRC_H - 1.0)
        cid = LR_CLASS_REMAP.get(d['label'], d['label'])
        detections.append(dict(label=LABELS[cid], class_id=cid,
                               confidence=float(d['confidence']),
                               xyxy=[float(v) for v in xy]))
    return detections


def run_once(blob, conf=None):
    import time
    conf = DISPLAY_CONF if conf is None else conf
    started = time.perf_counter()
    raw_reference, features = request_hybrid(blob, port=5003)
    ps_feature_ms = (time.perf_counter() - started) * 1000.0
    segments, rt_stats = RT.run(features)
    if sum(map(len, segments.values())) != 149100:
        raise RuntimeError('Bad structural heads segment lengths')
    detections = decode_heads(segments, conf=conf)
    result = {
        'result': 'HYBRID_PS_PL_COMPLETE',
        'ps_backbone_neck_ms': ps_feature_ms,
        'pl_driver_ms': rt_stats['pl_driver_ms'],
        'pl_prep_ms': rt_stats['prep_ms'],
        'pl_replay_ms': rt_stats['replay_ms'],
        'pl_doorbell_wall_s': rt_stats['walls'],
        'pl_seg_ms': rt_stats['seg_ms'],
        'pl_recovered': rt_stats['recovered'],
        'pl_fsm_reload': rt_stats['fsm_reload'],
        'display_conf': conf,
        'raw_reference_shape': list(raw_reference.shape),
        'feature_sha256': [hashlib.sha256(f.tobytes()).hexdigest() for f in features],
        'top1_baseline': top1_baseline(segments, _scales()),
        'detections': detections,
    }
    (ROOT / 'hybrid_result.json').write_text(json.dumps(result, indent=2))
    return result
