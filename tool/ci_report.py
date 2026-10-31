"""Attach failure output to the commit as a check run (readable via the API).

GitHub's raw job logs live on a separate download host; a check run's text is
served by api.github.com, so whoever is fixing the build can read it.
"""
import json
import os
import pathlib
import re
import sys
import urllib.request

job = sys.argv[1] if len(sys.argv) > 1 else "build"
logs = sorted(pathlib.Path("ci-logs").glob("*.log"))
parts = []
for p in logs:
    lines = p.read_text(errors="replace").splitlines()
    hits = [l for l in lines if re.search(
        r"error|warning [•-]|info [•-]|What went wrong|FAILURE|Exception|\.dart:\d+|\.(kt|swift|m|gradle|kts):\d+",
        l, re.I)]
    parts.append(f"===== {p.name}: matching lines =====\n" + "\n".join(hits[:400]))
    parts.append(f"===== {p.name}: last 150 lines =====\n" + "\n".join(lines[-150:]))
text = "\n\n".join(parts) or "No ci-logs captured; the failure happened in a setup step."
if len(text) > 64000:
    text = text[:30000] + "\n...[trimmed]...\n" + text[-33000:]

body = {
    "name": f"{job} failure log",
    "head_sha": os.environ["GITHUB_SHA"],
    "status": "completed",
    "conclusion": "failure",
    "output": {"title": f"{job} failed", "summary": f"Captured output from {len(logs)} step(s).", "text": text},
}
req = urllib.request.Request(
    f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/check-runs",
    data=json.dumps(body).encode(),
    method="POST",
    headers={
        "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
        "Accept": "application/vnd.github+json",
    },
)
try:
    urllib.request.urlopen(req, timeout=30)
    print("Posted failure log check run")
except Exception as e:  # never mask the real failure
    print(f"Could not post failure log: {e}")
