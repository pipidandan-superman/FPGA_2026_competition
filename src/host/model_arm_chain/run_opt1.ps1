param([Parameter(ValueFromRemainingArguments=$true)][string[]]$PassArgs)
$ErrorActionPreference = 'Stop'
$venv = 'E:/competition/4_metrics/logs/2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $venv)) { throw "venv missing: $venv" }
& $venv 'E:/competition/3_host/model_arm_chain/opt1_loop.py' @PassArgs
exit $LASTEXITCODE
