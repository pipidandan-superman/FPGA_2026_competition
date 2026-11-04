# Replaceable policy head for the model+arm chain (Option 1, PC-only).
# PolicyHead.act(observation) -> Action | None
#   observation: {"t": capture ts, "detections": [{label, conf, xyxy}],
#                 "yolo_ms": ..., "frame_id": ...}
#   Action: {"kind": "wave", "sid": int, "delta": int, "t_ms": int}
#           (loop resolves start pos via PRAD, moves +delta, then returns;
#            kept deliberately small/safe while the head is a stand-in)
# Swap point: when the pi0 fine-tuned ckpt lands (C2, teammate), implement
# PiPolicy against the pi0 serve endpoint and pass --policy pi.
import time


class PolicyHead:
    name = "base"

    def act(self, obs):
        raise NotImplementedError

    def note_executed(self, action, result):
        """feedback hook so cooldowns/state advance only on real execution"""


class ScriptPolicy(PolicyHead):
    """Stand-in head: trigger class debounced over N frames -> safe wave action."""

    name = "script"

    def __init__(self, trigger_class="bottle", debounce=5, conf=0.5,
                 cooldown_s=15.0, sid=1, delta=80, t_ms=500):
        self.trigger_class = trigger_class
        self.debounce = debounce
        self.conf = conf
        self.cooldown_s = cooldown_s
        self.sid = sid
        self.delta = delta
        self.t_ms = t_ms
        self._hits = 0
        self._last_fire = 0.0
        self.fired = 0

    def act(self, obs):
        now = time.time()
        if now - self._last_fire < self.cooldown_s:
            return None
        hit = any(d["label"] == self.trigger_class and d["conf"] >= self.conf
                  for d in obs["detections"])
        self._hits = self._hits + 1 if hit else 0
        if self._hits >= self.debounce:
            self._last_fire = now
            self._hits = 0
            return {"kind": "wave", "sid": self.sid, "delta": self.delta,
                    "t_ms": self.t_ms}
        return None

    def note_executed(self, action, result):
        self.fired += 1


class PiPolicy(PolicyHead):
    """pi0 adapter stub. NOT usable until the fine-tuned ckpt exists (C2 line,
    training with teammate). Interface target: openpi serve_policy HTTP endpoint
    (A2 service, p50 215ms). Input contract: single camera image + state vector
    (32-dim myarm2 state); output: 32-dim action chunk -> mapped to servo frames
    via the same motion-rule guardrails as ScriptPolicy."""

    name = "pi0"

    def __init__(self, *a, **kw):
        raise RuntimeError(
            "PiPolicy unavailable: pi0 fine-tuned ckpt not ready (C2 pending). "
            "Use --policy script until the teammate delivers the checkpoint."
        )


def build_policy(name, **kw):
    if name == "script":
        return ScriptPolicy(**kw)
    if name == "pi0":
        return PiPolicy()
    raise ValueError("unknown policy %r" % name)
