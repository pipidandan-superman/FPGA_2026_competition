import hashlib
import json
import os
import runpy
import time
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np
from pynq import MMIO

from camera import Camera, log
import head_decode as HD

ROOT = Path(__file__).resolve().parents[2]
CONTROL = ROOT / 'continuous'
CONTROL.mkdir(parents=True, exist_ok=True)
PHASE = CONTROL / 'phase'
BIT = ROOT / 'net3_pl_hp_rebalance.bit'
RUNNER = Path(__file__).resolve().with_name('p_d1_live_run_continuous.py')
DESCRIPTOR = ROOT / 'descriptor_table.json'
LIVE_INPUT = ROOT / 'live_input.npy'
LIVE_HEADS = ROOT / 'live_heads.bin'
FRAME_BYTES = 640 * 480 * 3
LABELS = ['Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']
SEGMENTS = [
    ('reg8', (64, 40, 40)), ('reg16', (64, 20, 20)), ('reg32', (64, 10, 10)),
    ('cls8', (7, 40, 40)), ('cls16', (7, 20, 20)), ('cls32', (7, 10, 10)),
]

cam = Camera(BIT, {
    '.bit': 'c1015749f5f6b190fae483cddaeb4dc1d18c300ba752a7cf3a6bd927893957b8',
    '.hwh': '7b0d7c315af715acc11dd08152b36b9106a03958108f80faa9fca07b61ca1873',
})
box = MMIO(cam.overlay.ip_dict['pix_frame_display_0']['phys_addr'], 0x10000)
text = MMIO(cam.overlay.ip_dict['t1_text_osd_0']['phys_addr'], 0x10000)
soft_reset = MMIO(cam.overlay.ip_dict['inf_reset_gpio']['phys_addr'], 0x10000)
soft_reset.write(0, 1)
if box.read(0) != 0x47424F58:
    raise RuntimeError('GBOX ID mismatch %#x' % box.read(0))
if text.read(0) != 0x544C424C:
    raise RuntimeError('TLBL ID mismatch %#x' % text.read(0))
box.write(0x18, 0)
text.write(0x0C, 440)
text.write(0x10, 16)
text.write(0x14, 0x00FF00)
text.write(0x18, 0x000000)
text.write(0x08, 16)  # net_id=0, state=7 (None), score hidden

DESC = json.loads(DESCRIPTOR.read_text())
HEADS_DESC = next(e for e in DESC['entries'] if e['op'] == 'heads')
SCALE_BY_BUF = {int(e['buf']): float(e['scale']) for e in HEADS_DESC['reg'] + HEADS_DESC['cls']}
SEGMENT_BUF = {'reg8': 88, 'reg16': 94, 'reg32': 100, 'cls8': 91, 'cls16': 97, 'cls32': 103}


def phase():
    try:
        return PHASE.read_text().strip()
    except FileNotFoundError:
        return 'run'


def check_vdma():
    status = dict(mm2s_cr=hex(cam.read(0)), mm2s_sr=hex(cam.read(4)),
                  s2mm_cr=hex(cam.read(0x30)), s2mm_sr=hex(cam.read(0x34)),
                  slots=cam.slots())
    if (cam.read(4) | cam.read(0x34)) & 0x8FF0 or not (cam.read(0) & 1 and cam.read(0x30) & 1):
        raise RuntimeError('VDMA_RUNTIME_ERROR ' + json.dumps(status))
    return status


def decode_heads(blob):
    regs, clss, reg_scales, cls_scales = {}, {}, {}, {}
    offset = 0
    for name, shape in SEGMENTS:
        count = int(np.prod(shape))
        arr = np.frombuffer(blob, dtype=np.int8, count=count, offset=offset).reshape(shape).copy()
        offset += count
        if name.startswith('reg'):
            regs[name] = arr
            reg_scales[name] = SCALE_BY_BUF[SEGMENT_BUF[name]]
        else:
            clss[name] = arr
            cls_scales[name] = SCALE_BY_BUF[SEGMENT_BUF[name]]
    raw = HD.decode(regs, clss, reg_scales, cls_scales, conf=0.55, iou=0.7, canvas=320)
    detections = []
    for d in raw:
        xy = np.array(d['xyxy'], np.float32) * np.array([2.0, 1.5, 2.0, 1.5], np.float32)
        detections.append(dict(label=LABELS[d['label']], class_id=d['label'],
                               confidence=float(d['confidence']), xyxy=[float(v) for v in xy]))
    return detections


def quality_filter(detections):
    accepted = []
    for d in detections:
        x1, y1, x2, y2 = d['xyxy']
        area = max(0.0, x2 - x1) * max(0.0, y2 - y1) / float(640 * 480)
        if area > 0.90:
            log('DETECTION_REJECT_FULL_FRAME', label=d['label'],
                confidence=d['confidence'], area_ratio=round(area, 4))
            continue
        accepted.append(d)
    return accepted


def update_overlay(detections):
    if not detections:
        box.write(0x18, 0)
        text.write(0x08, 16)
        return
    top = max(detections, key=lambda d: d['confidence'])
    x1, y1, x2, y2 = top['xyxy']
    l = max(0, min(639, int(round(x1))))
    r = max(0, min(639, int(round(x2))))
    t = max(0, min(479, int(round(y1))))
    b = max(0, min(479, int(round(y2))))
    if r - l < 4:
        r = min(639, l + 4)
    if b - t < 4:
        b = min(479, t + 4)
    box.write(0x18, 0)
    box.write(0x08, l)
    box.write(0x0C, r)
    box.write(0x10, t)
    box.write(0x14, b)
    box.write(0x18, 1)
    label = 8 + int(top['class_id']) + 1  # net_id=1 (V8), state=class_id
    digit = min(9, max(1, int(top['confidence'] * 10)))
    text.write(0x08, label | (digit << 5))


def save_result(seq, started, input_sha, blob, detections, rc):
    result = dict(result='CONTINUOUS_PL_DECODE_COMPLETE', frame_seq=seq,
                  timestamp=datetime.now(timezone.utc).isoformat(),
                  inference_ms=round((time.monotonic() - started) * 1000, 3),
                  inference_rc=rc, input_sha256=input_sha,
                  preprocessing='plfront_bgr_mean_std_normalize_rne_zp0',
                  heads_sha256=hashlib.sha256(blob).hexdigest(),
                  top=detections[0] if detections else None,
                  detections=detections)
    tmp = ROOT / 'live_result.json.tmp'
    tmp.write_text(json.dumps(result, indent=2, ensure_ascii=False))
    tmp.replace(ROOT / 'live_result.json')
    with (CONTROL / 'results.jsonl').open('a') as history:
        history.write(json.dumps(result, ensure_ascii=False) + '\n')
    return result


seq = 0
try:
    cam.start()
    log('CONTINUOUS_GESTURE_READY', detail='Overlay loaded once; service runs until phase=stop')
    while phase() != 'stop':
        soft_reset.write(0, 0)
        time.sleep(0.05)
        soft_reset.write(0, 1)
        time.sleep(0.05)
        log('INFERENCE_SOFT_RESET_PULSE', next_frame=seq + 1)
        frame = None
        for _ in range(200):
            frame = cam.snapshot()
            if frame is not None:
                break
            time.sleep(0.005)
        if frame is None:
            raise RuntimeError('No stable real camera frame')
        frame_bgr = np.frombuffer(frame, dtype=np.uint8).reshape(480, 640, 3)
        canvas = cv2.resize(frame_bgr, (320, 320), interpolation=cv2.INTER_LINEAR)
        bgr = canvas.astype(np.float32).transpose(2, 0, 1)[None]
        mean_milli = np.array([103530, 116280, 123675], np.float32).reshape(1, 3, 1, 1)
        std_milli = np.array([57375, 57120, 58395], np.float32).reshape(1, 3, 1, 1)
        normalized = (bgr * 1000.0 - mean_milli) / std_milli
        x = np.clip(np.rint(normalized / np.float32(0.020787402400820273)), -128, 127).astype(np.int8)
        np.save(LIVE_INPUT, x)
        input_sha = hashlib.sha256(x.tobytes()).hexdigest()
        os.environ['LIVE_INPUT'] = str(LIVE_INPUT)
        os.environ['LIVE_HEADS_OUT'] = str(LIVE_HEADS)
        os.environ['LIVE_ARENA_INPUT_OUT'] = str(ROOT / 'live_arena_input.bin')
        started = time.monotonic()
        rc = 99
        try:
            runpy.run_path(str(RUNNER), run_name='__main__')
        except SystemExit as exc:
            rc = int(exc.code or 0)
        if rc != 0:
            seq += 1
            blob = LIVE_HEADS.read_bytes() if LIVE_HEADS.exists() else b''
            save_result(seq, started, input_sha, blob, [], rc)
            update_overlay([])
            log('CONTINUOUS_FRAME_ERROR_RECOVER', frame_seq=seq, inference_rc=rc,
                action='keep_hdmi_running_and_soft_reset_next_frame')
            continue
        blob = LIVE_HEADS.read_bytes()
        if len(blob) != 149100:
            raise RuntimeError('Bad live heads length %d' % len(blob))
        detections = quality_filter(decode_heads(blob))
        detections.sort(key=lambda d: d['confidence'], reverse=True)
        seq += 1
        result = save_result(seq, started, input_sha, blob, detections, rc)
        update_overlay(detections)
        annotated = frame_bgr.copy()
        for d in detections:
            x1, y1, x2, y2 = [int(round(v)) for v in d['xyxy']]
            cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(annotated, '%s %.2f' % (d['label'], d['confidence']),
                        (max(0, x1), max(20, y1 - 6)), cv2.FONT_HERSHEY_SIMPLEX,
                        0.55, (0, 255, 0), 2, cv2.LINE_AA)
        cv2.imwrite(str(ROOT / 'live_annotated.jpg'), annotated)
        log('CONTINUOUS_GESTURE_RESULT', frame_seq=seq,
            inference_ms=result['inference_ms'], detections=len(detections), top=result['top'],
            vdma=check_vdma())
    log('CONTINUOUS_GESTURE_USER_STOP', frames=seq)
except Exception as exc:
    log('CONTINUOUS_GESTURE_FAIL', frames=seq, error=str(exc))
    raise
finally:
    box.write(0x18, 0)
    text.write(0x08, 0)
    cam.close()
    log('CONTINUOUS_GESTURE_STOPPED', frames=seq)
