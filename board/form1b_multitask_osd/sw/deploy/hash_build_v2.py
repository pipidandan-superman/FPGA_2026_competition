import hashlib, os, datetime

RUNS = r"E:\competition\4_metrics\logs\2026-11-02_multitask_osd_debug_run01\project_multitask\multitask_osd.runs"

for m in ("display_test_task_coco_osd_0_0", "display_test_task_pose_osd_0_0"):
    p = os.path.join(RUNS, m + "_synth_1", m + ".dcp")
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()[:8]
    t = datetime.datetime.fromtimestamp(os.path.getmtime(p)).strftime("%H:%M:%S")
    print(m, "dcp_sha=", h, "mtime=", t)

b = os.path.join(RUNS, "impl_1", "display_test_wrapper.bit")
print("bit_sha256=", hashlib.sha256(open(b, "rb").read()).hexdigest())
print("bit_size=", os.path.getsize(b),
      "bit_mtime=", datetime.datetime.fromtimestamp(os.path.getmtime(b)).strftime("%H:%M:%S"))
