import json
import time
import numpy as np
import hybrid_pipeline_resident as pipeline

blob = np.load('/home/xilinx/PSPL_YOLOV8N_RESIDENT/live_input.npy').astype(np.float32)
results = []
for index in range(3):
    started = time.perf_counter()
    result = pipeline.run_once(blob)
    result['frame_index'] = index
    result['total_pipeline_ms'] = (time.perf_counter() - started) * 1000.0
    results.append(result)
    print('STEADY_FRAME', index, 'total_ms', result['total_pipeline_ms'],
          'ps_feature_ms', result['ps_backbone_neck_ms'],
          'detections', json.dumps(result['detections']), flush=True)
with open('/home/xilinx/PSPL_YOLOV8N_RESIDENT/evidence/hybrid_steady_results.json', 'w') as out:
    json.dump(results, out, indent=2)
print('STEADY_THREE_FRAME_COMPLETE')
