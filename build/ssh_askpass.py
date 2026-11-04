"""OpenSSH helper: credentials are provided only in the process environment."""
import os
import sys

password = os.environ.get('EES331_SSH_PASSWORD') or os.environ.get('BOARD_PW')
if not password:
    sys.exit(1)
sys.stdout.write(password + '\n')
