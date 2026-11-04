#!/usr/bin/env bash
# Portable upload-only entrypoint. Loading hardware is a separate gated step.
set -euo pipefail
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
exec "${PYTHON:-python}" "$PACKAGE_ROOT/build/stage_submission.py" --form form2_pl_continuous "$@"
