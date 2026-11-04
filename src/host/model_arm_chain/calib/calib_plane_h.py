# Side-view plane homography calibration: pixel (u,v) -> arm-base (X,Y mm)
# on the desk working plane. Companion to sideview_layout_checklist.md.
#
# Why homography still works from the side: every target sits on ONE plane
# (desk / light mat), and plane->plane mapping is a 3x3 homography for ANY
# camera pose. Side view only makes accuracy non-uniform (near field good,
# far field bad) -> operating zone in the near half of the frame, camera
# elevation >=45deg (checklist section A).
#
# Conventions (side-view specific, do not relax):
#  - VERTICAL-TOUCH: at every point the gripper touches the plane VERTICALLY
#    (alpha=-90). A vertical tip offset moves only Z, so FK (X,Y) equals the
#    ground contact point regardless of gripper length. |alpha+90| beyond
#    ALPHA_TOL_DEG -> warn, require explicit confirm.
#  - TIP-ON-PLANE: side view couples height error h into lateral drift
#    ~h/tan(elevation). Settle the tip ON the plane before clicking.
#  - Detection-time convention (runtime, not this script): feed the bottom-
#    edge MIDPOINT of the YOLO box into H, never the box center.
#
# Frame sources:
#  --camera N        local webcam (plumbing dry-runs)
#  --frame-dir PATH  per-point files point_XX.png (board-window canon: save a
#                    PNG on the board via the v1.4 camera path, scp to PC,
#                    drop into the dir; scene must hold still while polling)
#  --stub-frame      synthetic grid, no camera at all (flow test today)
# TODO(board-window): live board grabber (PYNQ VDMA -> PNG stream) replaces
#   --frame-dir polling when the cam_hdmi_pc_ble BD is back on the bench.
#
# Verdicts: CALIB_COLLECT_PASS / CALIB_H_PASS / CALIB_VALIDATION_PASS /
#           SELFCHK_PASS (report.json + points.csv + homography.json).
import argparse
import asyncio
import csv
import json
import math
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kms_math import kms_fk  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from arm_link import ArmLink, verdict_line  # noqa: E402

EVIDENCE_ROOT = Path("E:/competition/4_metrics/logs").resolve()
TARGET_MAC = "98:EA:A0:21:01:3A"      # WeBotPi 013a in arm socket (B0 canon)
H_OUT_DEFAULT = Path(__file__).resolve().parent / "homography.json"
ALPHA_TOL_DEG = 10.0                  # vertical-touch convention tolerance
RESID_PX_GATE = 2.0                   # CALIB_H_PASS reprojection gate
VAL_ERR_MM_GATE = 10.0                # CALIB_VALIDATION_PASS per-point gate
VAL_FAR_MIN = 1                       # validation must include >=1 far point
CSV_FIELDS = ["idx", "u", "v", "x_mm", "y_mm", "z_mm", "alpha_deg",
              "pwm0", "pwm1", "pwm2", "pwm3", "far"]


# --------------------------------------------------------------------------
# frame sources
# --------------------------------------------------------------------------
class CameraFrames:
    def __init__(self, index):
        self.cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)

    def get(self, _idx):
        ok, frame = self.cap.read()
        if not ok:
            raise RuntimeError("camera grab failed")
        return frame


class FrameDirFrames:
    """Polls for point_XX.png per calibration point (board-window canon)."""

    def __init__(self, directory, timeout_s=180.0):
        self.dir = Path(directory)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.timeout_s = timeout_s

    def get(self, idx):
        want = self.dir / ("point_%02d.png" % idx)
        print("[frame-dir] put %s (board: v1.4 camera path save PNG -> scp)"
              % want, flush=True)
        t0 = time.time()
        while time.time() - t0 < self.timeout_s:
            if want.exists():
                img = cv2.imread(str(want))
                if img is not None:
                    return img
            time.sleep(0.5)
        raise TimeoutError("no frame within %ss: %s" % (self.timeout_s, want))


class StubFrames:
    """Synthetic light mat + grid; lets the whole click flow run today."""

    def __init__(self):
        img = np.full((480, 640, 3), 235, np.uint8)
        for i in range(0, 640, 80):
            cv2.line(img, (i, 0), (i, 479), (200, 200, 200), 1)
        for j in range(0, 480, 80):
            cv2.line(img, (0, j), (639, j), (200, 200, 200), 1)
        cv2.putText(img, "STUB FRAME (plumbing only)", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 200), 2)
        self.img = img

    def get(self, _idx):
        return self.img.copy()


def build_frames(args):
    if args.stub_frame:
        return StubFrames()
    if args.frame_dir:
        return FrameDirFrames(args.frame_dir)
    return CameraFrames(args.camera)


# --------------------------------------------------------------------------
# operator picking + arm side
# --------------------------------------------------------------------------
def pick_uv(frame, title):
    """Show frame, operator left-clicks the tip contact point.
    SPACE/ENTER=confirm, R=re-pick, Q=abort."""
    state = {"uv": None}

    def _on_mouse(event, x, y, _flags, _param):
        if event == cv2.EVENT_LBUTTONDOWN:
            state["uv"] = (x, y)

    cv2.namedWindow(title, cv2.WINDOW_NORMAL)
    cv2.setMouseCallback(title, _on_mouse)
    picked = None
    try:
        while True:
            disp = frame.copy()
            if state["uv"]:
                cv2.drawMarker(disp, state["uv"], (0, 0, 255),
                               cv2.MARKER_CROSS, 24, 2)
                cv2.putText(disp, "u=%d v=%d" % state["uv"],
                            (state["uv"][0] + 12, state["uv"][1] - 8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 200), 1)
            cv2.putText(disp, "click tip contact | SPACE=ok R=repick Q=quit",
                        (10, disp.shape[0] - 12), cv2.FONT_HERSHEY_SIMPLEX,
                        0.5, (0, 0, 0), 1)
            cv2.imshow(title, disp)
            key = cv2.waitKey(60) & 0xFF
            if key in (13, 32) and state["uv"]:
                picked = state["uv"]
                break
            if key == ord("r"):
                state["uv"] = None
            if key == ord("q"):
                raise SystemExit("aborted by operator")
    finally:
        cv2.destroyAllWindows()
    return picked


async def read_fk(link, args, idx):
    """PRAD 000-003 -> FK wrist point (x,y,z,alpha). --no-arm: manual entry."""
    if args.no_arm:
        if args.stub_auto_xy:
            xs = [-120.0, -60.0, 0.0, 60.0, 120.0]
            ys = [140.0, 180.0, 220.0]
            x = xs[idx % len(xs)]
            y = ys[(idx // len(xs)) % len(ys)]
            print("[no-arm] synthetic XY (%.0f, %.0f)" % (x, y), flush=True)
            return {"x": x, "y": y, "z": 0.0, "alpha": -90.0,
                    "pwms": [1500, 1500, 1500, 1500]}
        raw = input("[no-arm] enter arm-frame x y (mm): ").split()
        return {"x": float(raw[0]), "y": float(raw[1]), "z": 0.0,
                "alpha": -900.0, "pwms": [0, 0, 0, 0]} if len(raw) == 2 \
            else (_ for _ in ()).throw(ValueError("need 'x y'"))
    pwms = []
    for sid in range(4):
        rb = await link.read_pos(sid, timeout=2.0, retries=3)
        if rb is None:
            raise RuntimeError("PRAD %03d dead (link? servo power?)" % sid)
        pwms.append(rb["pos"])
    x, y, z, alpha = kms_fk(pwms)
    return {"x": x, "y": y, "z": z, "alpha": alpha, "pwms": pwms}


async def collect_points(link, frames, args, n_points, run_dir, tag):
    rows = []
    for i in range(n_points):
        print("\n[%s %d/%d] jog arm: tip ON plane, gripper VERTICAL%s"
              % (tag, i + 1, n_points,
                 ", then drop frame" if args.frame_dir else ""), flush=True)
        input("    arm settled -> press ENTER...")
        fk = await read_fk(link, args, i)
        frame = frames.get(i)
        u, v = pick_uv(frame, "%s point %d/%d" % (tag, i + 1, n_points))
        warn = ""
        if abs(fk["alpha"] + 90.0) > ALPHA_TOL_DEG:
            warn = ("    !! alpha=%.1f (vertical-touch convention wants -90): "
                    "confirm this point is usable [y/N]: " % fk["alpha"])
            if input(warn).strip().lower() != "y":
                print("    point discarded, redo", flush=True)
                continue
        rows.append({"idx": len(rows), "u": u, "v": v,
                     "x_mm": round(fk["x"], 2), "y_mm": round(fk["y"], 2),
                     "z_mm": round(fk["z"], 2),
                     "alpha_deg": round(fk["alpha"], 1),
                     "pwm0": fk["pwms"][0], "pwm1": fk["pwms"][1],
                     "pwm2": fk["pwms"][2], "pwm3": fk["pwms"][3],
                     "far": 0})
        print("    ok idx=%d uv=(%d,%d) XY=(%.1f,%.1f)mm%s"
              % (rows[-1]["idx"], u, v, fk["x"], fk["y"], warn), flush=True)
        _append_csv(run_dir / "points.csv", rows[-1])
    return rows


def _append_csv(path, row):
    exists = path.exists()
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        if not exists:
            w.writeheader()
        w.writerow(row)


def solve_h(rows):
    uv = np.float32([[r["u"], r["v"]] for r in rows])
    xy = np.float32([[r["x_mm"], r["y_mm"]] for r in rows])
    h, mask = cv2.findHomography(uv, xy, cv2.RANSAC, 3.0)
    if h is None:
        raise RuntimeError("findHomography failed")
    proj = cv2.perspectiveTransform(uv.reshape(-1, 1, 2), h).reshape(-1, 2)
    resid = np.linalg.norm(proj - xy, axis=1)
    return h, resid, (mask.ravel() > 0).tolist() if mask is not None else None


def save_h(h, run_dir, args, rows, resid_median):
    inv = np.linalg.inv(h)
    doc = {
        "src": "pixel_uv", "dst": "arm_xy_mm",
        "homography": h.tolist(), "homography_inv": inv.tolist(),
        "points": len(rows),
        "resid_px_median": round(float(resid_median), 3),
        "frame_source": ("stub" if args.stub_frame else
                         ("frame-dir:%s" % args.frame_dir if args.frame_dir
                          else "camera:%d" % args.camera)),
        "conventions": {
            "vertical_touch_alpha_deg": -90.0,
            "alpha_tol_deg": ALPHA_TOL_DEG,
            "tip_on_plane": True,
            "detection_feed_point": "yolo_box_bottom_midpoint",
        },
    }
    out = Path(args.h_out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                   encoding="utf-8")
    (run_dir / "homography.json").write_text(
        json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


# --------------------------------------------------------------------------
# entry points
# --------------------------------------------------------------------------
def write_json(path, value):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2),
                   encoding="utf-8")
    tmp.replace(path)


def default_run_dir():
    today = time.strftime("%Y-%m-%d")
    n = 1
    while (EVIDENCE_ROOT / ("%s_model_arm_calib_run%02d" % (today, n))).exists():
        n += 1
    return EVIDENCE_ROOT / ("%s_model_arm_calib_run%02d" % (today, n))


async def arm_connect(args):
    if args.no_arm:
        return None
    link = ArmLink(args.target_mac)
    mtu = await link.connect(timeout=12.0)
    print(verdict_line("ARM_LINK_PASS", mtu=mtu), flush=True)
    return link


def load_h(path):
    return np.float32(json.loads(Path(path).read_text(encoding="utf-8"))
                      ["homography"])


def project(h, u, v):
    p = h @ np.float32([u, v, 1.0])
    return float(p[0] / p[2]), float(p[1] / p[2])


async def cmd_collect(args):
    run_dir = Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    frames = build_frames(args)
    link = await arm_connect(args)
    try:
        rows = await collect_points(link, frames, args,
                                    args.points, run_dir, "collect")
    finally:
        if link:
            await link.disconnect()
    if len(rows) < 4:
        print(verdict_line("CALIB_COLLECT_FAIL", points=len(rows)),
              flush=True)
        return 1
    print(verdict_line("CALIB_COLLECT_PASS", points=len(rows)), flush=True)
    h, resid, _inl = solve_h(rows)
    resid_med = float(np.median(resid))
    gate = resid_med < RESID_PX_GATE
    print(verdict_line("CALIB_H_" + ("PASS" if gate else "FAIL"),
                       resid_px_median=round(resid_med, 3),
                       resid_px_max=round(float(resid.max()), 3)), flush=True)
    out = save_h(h, run_dir, args, rows, resid_med)
    write_json(run_dir / "report.json",
               {"points": len(rows), "resid_px": resid.round(3).tolist(),
                "resid_px_median": round(resid_med, 3),
                "h_out": str(out)})
    print("[h] written to %s" % out, flush=True)
    return 0 if gate else 1


async def cmd_validate(args):
    run_dir = Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    h = load_h(args.h)
    frames = build_frames(args)
    link = await arm_connect(args)
    try:
        rows = await collect_points(link, frames, args,
                                    args.val_points, run_dir, "validate")
    finally:
        if link:
            await link.disconnect()
    far_idx = {int(x) - 1 for x in args.far.split(",") if x.strip()} \
        if args.far else set()
    for r in rows:
        r["far"] = 1 if r["idx"] in far_idx else 0
        _append_csv(run_dir / "validate_points.csv", r)
    errs = []
    for r in rows:
        px, py = project(h, r["u"], r["v"])
        err = math.hypot(px - r["x_mm"], py - r["y_mm"])
        errs.append({"idx": r["idx"], "err_mm": round(err, 2),
                     "far": r["far"]})
        print("    idx=%d err=%.1fmm%s" % (r["idx"], err,
                                           " (far)" if r["far"] else ""),
              flush=True)
    n_far = sum(e["far"] for e in errs)
    worst = max(e["err_mm"] for e in errs) if errs else float("inf")
    ok = (len(rows) >= args.val_points and n_far >= VAL_FAR_MIN
          and worst < args.max_err_mm)
    write_json(run_dir / "validate_report.json",
               {"errors": errs, "far_points": n_far, "worst_mm": worst,
                "gate_mm": args.max_err_mm})
    print(verdict_line(
        "CALIB_VALIDATION_" + ("PASS" if ok else "FAIL"),
        points=len(rows), far_points=n_far, worst_mm=round(worst, 2),
        gate_mm=args.max_err_mm), flush=True)
    if not ok and n_far < VAL_FAR_MIN:
        print("    note: >=1 far-field point MANDATORY (checklist C); "
              "re-run with --far <1-based indices>", flush=True)
    return 0 if ok else 1


async def cmd_selfcheck(args):
    """30s power-up ritual: click the reference object, compare vs its known
    arm coords; SELFCHK_PASS before every demo (v2 doc field law)."""
    run_dir = Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    h = load_h(args.h)
    frames = build_frames(args)
    link = await arm_connect(args)
    try:
        rows = await collect_points(link, frames, args, 1, run_dir,
                                    "selfcheck")
    finally:
        if link:
            await link.disconnect()
    r = rows[0]
    px, py = project(h, r["u"], r["v"])
    err = math.hypot(px - r["x_mm"], py - r["y_mm"])
    ok = err < args.max_err_mm
    write_json(run_dir / "selfcheck_report.json",
               {"err_mm": round(err, 2), "gate_mm": args.max_err_mm,
                "note": "drift beyond gate -> relative pose moved: "
                        "RECALIBRATE (checklist D)"})
    print(verdict_line("SELFCHK_" + ("PASS" if ok else "FAIL"),
                       err_mm=round(err, 2), gate_mm=args.max_err_mm),
          flush=True)
    return 0 if ok else 1


def cmd_solve(args):
    rows = list(csv.DictReader(open(args.points_csv, encoding="utf-8")))
    for r in rows:
        for k in ("u", "v", "x_mm", "y_mm"):
            r[k] = float(r[k])
    h, resid, inl = solve_h(rows)
    resid_med = float(np.median(resid))
    print(verdict_line("CALIB_H_" + ("PASS" if resid_med < RESID_PX_GATE
                                     else "FAIL"),
                       points=len(rows), resid_px_median=round(resid_med, 3),
                       ransac_inliers=sum(inl) if inl else None), flush=True)
    print(np.array2string(h, precision=6, suppress_small=True))
    return 0


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--run-dir", default=None,
                   help="evidence dir (default: new *_model_arm_calib_runNN)")
    p.add_argument("--h-out", default=str(H_OUT_DEFAULT))
    p.add_argument("--h", default=str(H_OUT_DEFAULT), help="homography.json")
    p.add_argument("--target-mac", default=TARGET_MAC)
    p.add_argument("--no-arm", action="store_true", help="manual x,y entry")
    p.add_argument("--stub-auto-xy", action="store_true",
                   help="with --no-arm: deterministic synthetic XY grid")
    src = p.add_mutually_exclusive_group()
    src.add_argument("--camera", type=int, default=None)
    src.add_argument("--frame-dir", default=None)
    src.add_argument("--stub-frame", action="store_true")
    sub = p.add_subparsers(dest="cmd", required=True)

    pc = sub.add_parser("collect", help="N points -> solve H -> homography.json")
    pc.add_argument("--points", type=int, default=12)

    pv = sub.add_parser("validate", help="M fresh points -> error gate")
    pv.add_argument("--val-points", type=int, default=5)
    pv.add_argument("--max-err-mm", type=float, default=VAL_ERR_MM_GATE)
    pv.add_argument("--far", default="",
                    help="1-based indices of far-field points, e.g. '2,5'")

    ps = sub.add_parser("selfcheck", help="30s power-up ritual, 1 point")
    ps.add_argument("--max-err-mm", type=float, default=VAL_ERR_MM_GATE)

    pl = sub.add_parser("solve", help="offline re-solve from points.csv")
    pl.add_argument("--points-csv", required=True)
    return p.parse_args()


async def _main_async(args):
    if args.run_dir is None:
        args.run_dir = str(default_run_dir())
    if args.cmd == "collect":
        return await cmd_collect(args)
    if args.cmd == "validate":
        return await cmd_validate(args)
    if args.cmd == "selfcheck":
        return await cmd_selfcheck(args)
    raise ValueError(args.cmd)


def main():
    args = parse_args()
    if args.cmd == "solve":
        raise SystemExit(cmd_solve(args))
    raise SystemExit(asyncio.run(_main_async(args)))


if __name__ == "__main__":
    main()
