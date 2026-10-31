#!/usr/bin/env bash
# Runs a build command and keeps a copy of its output in ci-logs/ so that
# tool/ci_report.py can attach it to the commit if the job fails.
set -o pipefail
name="$1"; shift
mkdir -p ci-logs
"$@" 2>&1 | tee "ci-logs/${name}.log"
