#!/usr/bin/env bash
# Text/Git audit only. Never runs Flutter, Dart, Gradle or application tests.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/cast_phase2_round5_static_audit.py "$@"
