#!/usr/bin/env python3
"""Check publishable Git files for accidental private artifacts and common secrets.

This is a defense in depth check, not a comprehensive credential detector.
It reports file names/categories only, never matching secret values.
"""
from pathlib import Path
import hashlib
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
files = subprocess.check_output(
    ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
).decode().split("\0")
patterns = {
    "private key": rb"-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----",
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "cloud credential": rb"\bAKIA[A-Z0-9]{16}\b",
    "personal absolute path": rb"/(?:Users|home)/[A-Za-z0-9_.-]+/",
}
private_suffixes = {".p12", ".p8", ".pem", ".key", ".sqlite", ".sqlite3", ".db", ".image"}
failures = []
for name in sorted(set(files) - {""}):
    path = root / name
    if path.is_symlink():
        failures.append((name, "source symlink requires manual review"))
        continue
    if not path.is_file():
        continue
    if path.suffix.lower() in private_suffixes or path.name.startswith(".env"):
        failures.append((name, "private artifact type"))
    data = path.read_bytes()
    reviewed_icon = (name == "Resources/CopyStory.icns" and hashlib.sha256(data).hexdigest() ==
                     "5d6ade6524c91186139a14fed89d7685fc1a7d2724ef96de82e6babc0a12c61c")
    if b"\x00" in data and not reviewed_icon:
        failures.append((name, "unexpected binary artifact"))
    for category, pattern in patterns.items():
        if re.search(pattern, data):
            failures.append((name, category))
for name, category in failures:
    print(f"{name}: {category}", file=sys.stderr)
if failures:
    sys.exit(1)
print("Publishable source hygiene checks passed.")
