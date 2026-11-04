---
name: zynq-pynq-overlay-workflow
description: Develop, deploy, and validate Zynq PYNQ overlays on an existing Linux SD image, including PS compatibility, AXI control, BD reset wiring, staged board diagnosis, and safe restoration. Use for BIT/HWH replacement and PS-PL integration; not for arbitrary SD-image rebuilding or bare-metal-only workflows.
---

# Zynq PYNQ Overlay Workflow

An SD image boots the PS; a compatible overlay can replace PL while Linux runs. A successful bitstream download does not prove AXI responsiveness, application correctness, or restoration of the previous workload.

Workspace adaptation: in `E:\competition`, apply its project-workspace-policy and daily-engineering-log skills; evidence belongs in `4_metrics/logs/<run>` and daily records in `7_logs/YYYY-MM-DD`. Other workspaces retain their own approved paths.

## Establish scope and compatibility

- Obtain authority for each hardware-changing phase. A question about deployment does not authorize downloading, stopping services, rebooting, or changing boot files. Preserve the user's selected board, project, and stage gates.
- Follow the current workspace's path/log/frozen-baseline rules. Snapshot the exact source, BD/XCI/XDC, matched BIT/HWH/XSA, hashes, and runtime configuration before changing a proven design. Keep each failed run immutable; use new run names.
- Separate PS boot configuration (DDR, crystal/PLL assumptions, MIO, Ethernet/SD/UART, memory map) from PL topology and fabric clocks. Loading a BIT does not rerun the new XSA's complete FSBL initialization. Review FSBL/device tree/kernel driver changes if those foundations differ. New PS-PL interfaces require comparison with the running PS configuration; do not assume a successful BIT download establishes PS-side compatibility.
- Audit kernel-bound PL devices, interrupts, DMA ownership, and userspace mappings before replacing hardware. HWH metadata is not a substitute for a Linux device tree. Quiesce every actual owner, not just a conveniently named service.
- For an EES-331 task, read [references/ees331.md](references/ees331.md). Treat it as a board profile, not universal parameters.

## Verify hardware beyond pure RTL

- Exercise AXI independent AW/W arrival, backpressure stability, delayed backends, WSTRB, access errors, reset, and command snapshot/sequence/ACK semantics with self-checking simulation. Do not inject intentionally invalid MMIO accesses on Linux merely to duplicate SLVERR coverage.
- Check the generated BD and HWH: every reset input's polarity **and connected inactive level**, clock lock input, debug reset, clock association, address aperture, and interconnect clock conversion. Unused active-low reset inputs must be high. Checking only the primary reset misses auxiliary-reset faults.
- Include official-IP/BD integration evidence. Reproduce the faulty connection in a controlled test when useful, then prove correct reset assertion, release, and an actual CSR response. Pure RTL PASS and Vivado `validate_bd_design` do not establish integration correctness.
- Build with the project's approved Vivado launcher. Require implementation, timing/DRC, address/clock/reset reports, no unresolved black boxes, matched BIT/HWH, and XSA consistency. Regenerate dependent IP and synthesis runs after BD changes.
- Gate board downloads on the generated hardware contract, not only file names or prior build PASS. Reject known-faulty artifacts even if their old manifest is internally consistent.

## Stage board operations

1. Confirm actual SSH/console login, runtime, boot ID, original workload, and physical/streaming baseline. Board wall-clock dates can be stale; use boot IDs and monotonic event timestamps. When preflighting a startup service that is expected to die, wait for its TERMINAL state (failed/inactive, process gone) — a wait loop that breaks on `active` races the service's own failure window and misreads a live owner as vacuous.
2. Transfer matched artifacts and software into a new independent directory; verify hashes after transfer. Resolve physical addresses from the matching HWH, and peripheral register models from the IP's own generated metadata (XCI memory maps, generated headers) rather than recollection — silicon-observed reset values then double as a configuration audit. Compile architecture-specific MMIO/barrier helpers on the target and retain their hashes.
3. Announce the interruption. Acquire ownership, stop the original application, and verify DMA has halted and buffers are released. If that cannot be established, stop before reconfiguration. Process exit or absence of a device client does not prove DMA stopped. For DMA-capable hardware require a register-level halt check even after the application exits. For a design with no DMA, record the matched hardware contract that establishes this exception.
   **Post-reboot / post-power-cycle first load is a hard-gate window, not a convenience.** After any board restart, assume the original service has autostarted and its DMA is live until proven otherwise — never assume the "old profile" (service self-exits, lock auto-released ⇒ safe to download) holds. EES-331 regime change (2026-10-02 re-cable, M13-proven): the camera service streams persistently and its VDMA keeps DMA-ing on HP ports with no owning process after the zocl lock auto-releases; downloading any overlay in that state reconfigures fabric mid-AXI = whole-PS silent death (zero ARP, no sentinel). Mandatory three-gate sequence before the first download after a restart, in scripts not from memory: (a) `systemctl stop` the original service (stop only, never disable), (b) process-level confirmation the owner is gone, (c) **register-level** DMA-halt proof — resolve the VDMA base from the matching HWH and read MM2S_DMACR/S2MM_DMACR (offsets 0x00/0x30) RS bits through /dev/mem; both RS=0. Abort the load if any gate fails. Reusable gate helper + relaunch flow: `4_metrics/logs/2026-10-20_t1_text_osd_run01/deploy/vdma_halt_check.py` and `relaunch_chain_c2_v4.sh`. Cost of skipping, evidenced 2026-10-21: two whole-PS silent deaths, each ~40 s after a post-reboot chain relaunch.
4. On a new or previously failed design, separate metadata parsing, download-only, liveness, identity read, and functional commands into explicit checkpoints. For a design with no addressable PL slave (e.g. PS-only), identity is the artifact hashes plus the HWH contract plus kernel-side download evidence (fresh FPGA-manager/zocl log entry per reload), not a CSR read. Preserve a known restoration route. Do not repeat a known bad MMIO read to diagnose a bus hang.
5. Run deterministic functional tests with sequence/result/count checks, timeout handling, reset/reload coverage, and stage-specific criteria. A software timeout cannot necessarily interrupt a CPU load stalled on AXI; prevent invalid/held-reset access through structural gates first.
6. Restore the previous overlay/workload and verify actual new frames or equivalent output. `systemctl active` alone is not recovery. Physical HDMI observation and packet/CRC evidence are distinct requirements.

Gate reload success on observed data movement, not download completion: a bitstream can download with the FPGA manager reporting `operating` while the design's external devices (sensors, codecs) never resume, because hot reload loses boot-time implicit settling such as camera SCCB configuration. Insert an explicit timed settle before first use, then wait a bounded first-frame/first-transaction window with periodic slot/status reports and fail closed on timeout. For the EES-331 camera overlay, follow the proven per-board sequence in [references/ees331.md](references/ees331.md).

Use PYNQ's paired HWH clock divisors, then verify their meaning against the board's real reference clock/PLL state. Some Zynq PYNQ releases assume a 50 MHz reference clock; do not treat their reported MHz as a measurement on a 33.333 MHz board or change a system PLL to fix a display-only discrepancy.

## Evidence, failure, and handoff

- Stream stdout and stderr into durable host logs during execution; do not buffer until process exit. Flush board events, and use fsync at important checkpoints where power-loss retention matters — fsync applies to durable log files only; character devices and pipes reject fsync (EINVAL). Retain partial/truncated evidence rather than manufacturing a complete result.
- After timeout or lost communication, command execution is uncertain: do not auto-resubmit. Inspect existing events, current boot/service state, serial output, and safe metadata. Do not infer root cause solely from black HDMI or an extinguished PL LED when the new overlay intentionally omits them.
- If no safe control channel remains, stop and request the smallest required user action. After reboot, recover old logs before retrying. Distinguish recovery success from test success.
- Packet receivers joining a live stream should explicitly synchronize at a frame boundary and record startup discards; never silently forgive CRC/loss after synchronization or overwrite the initial failed observation.
- Report separately: RTL PASS, official-IP/BD PASS, build PASS, board function PASS, workload-restoration PASS, and main-project coexistence PASS. Independent PASS is not integration PASS; unimplemented BRAM/DMA/business features remain unaccepted.
- Publish only authorized, reviewed sources, reproducible entries and selected evidence. Project integration is not permission to merge a protected Git branch. Shutdown requires separate explicit authority and saved work; never force-close unrelated unsaved applications.

## Delivered executable verification

Use `scripts/verify_baseline_reload.py` only for the EES-331 camera baseline
whose BIT/HWH/application hashes are pinned in that script. It refuses other
artifacts and unexpected owners. Invoke from the package root after obtaining
board-test authority:

```text
python build/board_preflight.py --output <fresh-evidence-directory>
python build/board_transport.py --script skill/zynq-pynq-overlay-workflow/scripts/verify_baseline_reload.py --output <another-fresh-evidence-directory> --sudo --timeout 300
python build/fetch_board_evidence.py --output <the-same-board-test-directory>
```

The host needs Python 3.10+ and OpenSSH. Verify the board host key before use;
the scripts enforce strict host-key checking. Provide credentials through
`BOARD_PW` or `EES331_SSH_PASSWORD`, never in command arguments or log files.
`board_transport.py` uploads a reviewed script and executes it; review the
script and preserve the user's authorized scope on every invocation.

The baseline test copies the installed artifacts into a fresh directory,
uses a 10-second sensor settle and bounded first-frame window, verifies both
DMA run/halted status bits, records real stream progress, and restores the
original service. Fetch all evidence; host transport success is not a test
result. A timeout leaves remote state uncertain: inspect it before retrying.

Verified evidence: `2026-11-03_amd_overlay_skill_run04` recorded 41 frames in
8.0276 seconds, read/write slot transitions 240/239, stopped DMA and freed
buffers, then restored increasing service frame counts 11→21 on the same
boot ID. The user confirmed normal moving HDMI output after restoration.
This establishes baseline reload/restoration only. Competition BIT/HWH,
inference accuracy, seven gestures and application coexistence require their
own acceptance runs.
