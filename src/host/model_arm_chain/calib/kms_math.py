# Vendored pure-math excerpt from 3_host/pai/scripts/b_layer/b_teleop_record.py
# (v3 $KMS path, 2026-10-06) — kinematics_analysis() / kinematics_move() alpha
# scan / kms_fk(), ported from MyArm32 x_kinematics.c + x_main.c
# ($KMS:x,y,z,time! drives the same solve on the STM32 board).
# Copied here so calib runs standalone: no teleop imports, no BLE, no cv2.
#
# Units: Cartesian mm in the ARM BASE frame (x=right, y=forward, z=up);
# angles deg; servos 000-003 pwm counts.
# Link geometry (setup_kinematics(111,105,86,175)): L0 base height, L1 upper
# arm, L2 forearm, L3 wrist segment; alpha = wrist pitch.
import math

KMS_L0, KMS_L1, KMS_L2, KMS_L3 = 111.0, 105.0, 86.0, 175.0  # mm
KMS_Y_MIN = -80.0              # kinematics_move() hard reject (x_main.c)
KMS_HOME = (0.0, 200.0, 150.0)  # reachable working pose


def kms_analysis(x, y, z, alpha_deg):
    """Verbatim port of kinematics_analysis() (x_kinematics.c:37).
    Returns (0, (angles, pwms)) on success or (errcode, None) like the C."""
    l0, l1, l2, l3 = KMS_L0, KMS_L1, KMS_L2, KMS_L3
    if x == 0:
        theta6 = 0.0
    elif x > 0 and y < 0:
        theta6 = 180.0 + math.degrees(math.atan(x / y))
    else:
        theta6 = math.degrees(math.atan(x / y))
        if y < 0:
            theta6 -= 180.0
    yr = math.hypot(x, y) - l3 * math.cos(math.radians(alpha_deg))
    zr = z - l0 - l3 * math.sin(math.radians(alpha_deg))
    if zr < -l0:
        return 1, None
    d = math.hypot(yr, zr)
    if d < 1e-6 or d > (l1 + l2):
        return 2, None
    ccc = math.acos(yr / d)
    bbb = (yr * yr + zr * zr + l1 * l1 - l2 * l2) / (2 * l1 * d)
    if not -1.0 <= bbb <= 1.0:
        return 5, None
    zf = -1.0 if zr < 0 else 1.0
    theta5 = math.degrees(ccc * zf + math.acos(bbb))
    if not 0.0 <= theta5 <= 180.0:
        return 6, None
    aaa = -(yr * yr + zr * zr - l1 * l1 - l2 * l2) / (2 * l1 * l2)
    if not -1.0 <= aaa <= 1.0:
        return 3, None
    theta4 = 180.0 - math.degrees(math.acos(aaa))
    if not -135.0 <= theta4 <= 135.0:
        return 4, None
    theta3 = alpha_deg - theta5 + theta4
    if not -90.0 <= theta3 <= 90.0:
        return 7, None
    ang = (theta6, theta5 - 90.0, theta4, theta3)
    pwm = tuple(int(1500 + s * 2000.0 * a / 270.0)
                for s, a in zip((-1, 1, 1, 1), ang))
    return 0, (ang, pwm)


def kms_solve(x, y, z):
    """Port of kinematics_move()'s Alpha scan: keep the most negative
    feasible alpha. Returns (alpha, (ang, pwm)) or None."""
    if y < KMS_Y_MIN:
        return None
    best = None
    for alpha in range(0, -136, -1):
        err, res = kms_analysis(x, y, z, alpha)
        if err == 0:
            best = (float(alpha), res)
    return best


def kms_fk(pwms):
    """Servo pwms (000..003) -> (x, y, z, alpha): arm-base-frame wrist+tip
    point. Inverse of kms_analysis()'s servo mapping + 2-link geometry."""
    th6 = (1500 - pwms[0]) * 270.0 / 2000.0
    th5 = (pwms[1] - 1500) * 270.0 / 2000.0 + 90.0
    th4 = (pwms[2] - 1500) * 270.0 / 2000.0
    th3 = (pwms[3] - 1500) * 270.0 / 2000.0
    alpha = th3 + th5 - th4
    rad = math.radians
    w_y = KMS_L1 * math.cos(rad(th5)) + KMS_L2 * math.cos(rad(th5 - th4))
    w_z = KMS_L1 * math.sin(rad(th5)) + KMS_L2 * math.sin(rad(th5 - th4))
    r = w_y + KMS_L3 * math.cos(rad(alpha))
    z = w_z + KMS_L0 + KMS_L3 * math.sin(rad(alpha))
    return (r * math.sin(rad(th6)), r * math.cos(rad(th6)), z, alpha)
