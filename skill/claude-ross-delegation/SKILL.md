---
name: claude-ross-delegation
description: Delegate bounded, independent work to the local Claude Code client and coordinate AMD ROSS Vivado MCP operations in E:\competition. Use when a task benefits from parallel analysis, AMD documentation search, Vivado session work, long-running report inspection, or otherwise useful idle Claude capacity. Do not use for unbounded busywork or concurrent mutation of the same project or Vivado session.
---

# Claude Code and ROSS Delegation

Use Claude Code as a worker controlled by the primary agent. The primary agent owns task decomposition, permissions, workspace isolation, evidence review, and final acceptance.

## Claude invocation authorization and MCP fallback

Claude Code may be started, resumed, messaged, or delegated to only when the user explicitly asks to call Claude, Claude Code, or Claude delegation in the current instruction. A task merely mentioning Vivado, MCP, ROSS, or parallel work does not authorize a Claude invocation.

When the user has explicitly authorized Claude and Claude is unavailable, rejected, rate-limited, unauthenticated, or otherwise unable to execute, continue the authorized Vivado work through the connected Vivado MCP directly. Use the structured Vivado MCP operations (`vivado_list_sessions`, `vivado_start`, `vivado_connect`, `vivado_execute`, `vivado_status`, `vivado_log_messages`, and related lifecycle tools) rather than stopping solely because the Claude client failed. Preserve the Claude error and the direct-MCP evidence separately. Do not silently substitute raw shell Vivado/XSim commands.

If Claude was not explicitly authorized, do not use Claude as a fallback or for background monitoring; use direct MCP when available, or report the missing direct MCP capability.

Before using this skill in E:\competition, apply:

- E:\competition\.codex\skills\project-workspace-policy\SKILL.md
- E:\competition\.codex\skills\daily-engineering-log\SKILL.md
- E:\competition\6_skill\vivado-ai-workflow\SKILL.md for every Vivado operation

## Why Claude became callable

Do not equate an installed VSIX with a usable agent bridge. Four conditions are required:

1. Claude Code is installed and authenticated.
2. vivado-mcp and any needed documentation MCP servers are registered with Claude.
3. The MCP servers report Connected and the Vivado path resolves.
4. The Claude invocation has permission to call the required MCP tools.

On Windows, `claude mcp get vivado-mcp` must also show a `PATH` containing both the Vivado `bin` directory and `bin\unwrapped\win64.o`. A Connected status with only `VIVADO_PATH` is insufficient for XSim child-process launches and can produce `ERROR: [Common 17-180] Spawn failed`.

The earlier Codex tool surface exposed no vivado-named tools, so direct Vivado MCP calls from that client were unavailable. After VS Code and Claude Code had been opened and used, their extension host and user-scope MCP configuration launched the ROSS stdio bridge. Opening VS Code helped activate the client, but it was not sufficient by itself; registration, a valid Vivado path, connection health, and tool permission were also required.

## Verified local baseline

These facts were observed on 2026-10-11 and are drift-prone. Recheck before live work:

- VS Code: 1.105.1. Core ROSS features work; the bundled Skills view needs VS Code 1.114 or later.
- Claude Code: 2.1.296.
- ROSS/Vivado MCP server: 2026.9.1.
- Vivado: F:\vivado2025\2025.2\Vivado\bin\vivado.bat.
- Claude user MCP configuration contains vivado-mcp and amd-doc-search.
- Evidence: E:\competition\4_metrics\logs\2026-10-11_vivado-ai-workflow_run01.

The extension bundles an MCP server while Claude also has a standalone user-scope server. Prefer one deployment for future live work. Never stop existing servers or sessions merely to remove duplication without checking ownership and active work.

## Delegation policy

Prefer delegating when all of these are true:

- The subtask is useful, bounded, and independently verifiable.
- Its inputs, allowed paths, forbidden actions, and acceptance marker are explicit.
- It does not contend with the primary agent or another worker for the same mutable project, Vivado session, output directory, port, or hardware.
- Claude has the relevant tools or domain context.
- Delegation saves wall-clock time or provides a meaningful second check.

When Claude is idle, select the next qualified item from the current user-authorized work queue. Do not invent work merely to keep Claude busy.

Good delegation candidates include:

- Read-only Vivado session, log, timing, utilization, and warning inspection.
- AMD documentation search.
- Independent RTL or report review.
- A simulation or analysis run in its own evidence directory and session.
- Long-running status monitoring with a clear terminal marker.
- Independent comparison or second-pass validation.

Do not delegate:

- Concurrent writes to the same project or Vivado session.
- Changes to E:\competition\2_fpga without current explicit user authorization.
- Board programming, deployment, destructive cleanup, branch integration, or external publication without the required authorization.
- Tasks whose overhead exceeds doing them directly.
- Open-ended prompts without a stop condition.

## Preflight

1. Read the applicable project and domain skills.
2. Resolve a unique evidence directory:

       E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN

3. Check Claude MCP health from the intended working directory:

       claude mcp list

   Require vivado-mcp to report Connected before a Vivado task. Require amd-doc-search to report Connected before relying on AMD document search.

4. Check existing sessions before starting a new one. Reuse only when project ownership, working directory, and state are compatible.
5. Confirm no other worker is mutating the same project or session.
6. If Claude reports an unrecognized configured model such as glm-5, use an explicit supported model for that invocation. Do not rewrite user model settings unless asked.

## Dispatch modes

### Planning or review only

Use non-mutating planning when the task needs decomposition, review, or a second opinion. Plan mode does not prove MCP execution.

       claude -p --model sonnet --permission-mode plan --no-session-persistence "<bounded prompt>"

### Read-only MCP verification

Prefer an interactive approval surface. For non-interactive verification, allow only the named read-only MCP tools. Do not grant edit or execute tools.

Typical read-only Vivado tools:

- vivado_client_info
- vivado_list_sessions
- vivado_status
- vivado_log_messages
- vivado_history

If the CLI requires permission bypass because no approval UI exists, use it only after current user authorization and combine it with an exact allowed-tools whitelist. Permission bypass is never a default for mutation.

### Bounded execution

For simulation, synthesis, implementation, or generated outputs:

- Use a dedicated working/evidence directory.
- Name the permitted MCP tools.
- State whether a new session may be created.
- State exact files that may change.
- State explicit forbidden actions.
- Require a machine-readable terminal marker.
- Preserve raw logs and return paths plus hashes.
- Do not accept an agent summary without inspecting raw evidence.

### Background work

Use Claude background sessions for genuinely long, independent tasks:

       claude --bg "<bounded prompt>"
       claude agents
       claude logs <id-or-name>
       claude attach <id-or-name>
       claude stop <id-or-name>

Record the returned session identifier in the evidence directory. Monitor at meaningful intervals; do not busy-poll.

## Command reference

```powershell
claude --version
claude doctor
claude mcp list
claude mcp get <name>
claude -p --model sonnet --permission-mode plan --no-session-persistence "<prompt>"
claude --bg --name <name> "<bounded prompt>"
claude agents
claude logs <id-or-name>
claude attach <id-or-name>
claude stop <id-or-name>
claude rm <id>
claude --resume <id>
claude -c
```

For non-interactive calls, prefer plan mode, no session persistence, an explicit model, and a narrow `--allowed-tools` list. Use `--output-format json` for machine-readable output. `--dangerously-skip-permissions` is never a default.

## Prompt contract

Every delegated prompt should identify:

- Objective.
- Inputs and working directory.
- Allowed tools and allowed writes.
- Forbidden paths and forbidden actions.
- Whether an existing Vivado session may be reused.
- Acceptance criteria and terminal markers.
- Evidence directory.
- Required final report: commands, exit status, changed files, evidence paths, hashes, unresolved risks.

For Vivado work, explicitly prohibit direct shell invocation of vivado, xvlog, xelab, and xsim. Those operations must use the structured ROSS/Vivado MCP tools, either directly by Codex or through Claude when Claude invocation is explicitly authorized.

## Concurrency rules

- One mutable project per worker.
- One owner per Vivado session.
- Never run GUI and batch writers against the same XPR.
- Never give two workers the same run directory.
- Read-only report review may run in parallel when the files are stable.
- Board and physical I/O operations are serialized.

The primary agent may keep Claude occupied with independent queued work while continuing its own task, but must not let parallelism weaken evidence, permissions, or project ownership.

## Acceptance levels

Keep these levels separate:

- CLIENT_READY: Claude CLI runs.
- MCP_CONNECTED: server health reports Connected.
- READ_ONLY_PASS: a named read-only MCP tool returns current data.
- FLOW_PASS: the requested simulation/build flow reaches its explicit marker with raw evidence.
- BOARD_PASS: separately obtained hardware evidence meets board acceptance.

Never promote an earlier level to a later one.

## Stop conditions

Stop the delegated task and preserve evidence when:

- MCP health is not Connected.
- The required tool is missing or denied.
- Claude attempts an out-of-scope write or asks for broader permissions.
- Another worker owns the target project/session.
- A run directory collision is detected.
- Vivado reports a command already running, stale ownership, or project lock.
- Required terminal evidence is absent.

## Closeout

1. Review Claude output and raw artifacts.
2. Compare changed files against the allowed scope.
3. Record PASS, FAIL, BLOCKED, or UNVERIFIED without inflating the result.
4. Link raw evidence from E:\competition\7_logs\YYYY-MM-DD\03_validation_summary.md.
5. Run the project skill-path audit:

       powershell -ExecutionPolicy Bypass -File E:\competition\4_metrics\scripts\audit_project_skill_paths.ps1
