#!/usr/bin/env bash
# Retired broad process-name launcher; no hardware side effects.
set -euo pipefail
printf '%s\n' 'This historical launcher is retired. Use build/board_transport.py with build/verify_form3.py after staging; see build/README.md.' >&2
exit 2
