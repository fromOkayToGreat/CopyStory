#!/usr/bin/env python3
"""Validate monotonically increasing builds against every public stable feed."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from release_policy import REPOSITORY, ROOT, feed, info, require

try:
    allow_first = sys.argv[1:] == ["--first-release"]
    require(not sys.argv[1:] or allow_first, "Only --first-release is accepted")
    pages = json.loads(subprocess.check_output(["gh", "api", f"repos/{REPOSITORY}/releases", "--paginate", "--slurp"]))
    releases = [r for page in pages for r in page if not r["draft"] and not r["prerelease"]]
    require(bool(releases) != allow_first, "Use --first-release only when no public stable releases exist")
    highest = 0
    with tempfile.TemporaryDirectory(prefix="release-history-", dir=ROOT / ".build") as tmp:
        for index, release in enumerate(releases):
            require(any(asset["name"] == "appcast.xml" for asset in release["assets"]),
                    "Existing stable release is missing its signed appcast; review history manually")
            directory = Path(tmp) / str(index)
            subprocess.run(["gh", "release", "download", release["tag_name"], "--repo", REPOSITORY,
                            "--pattern", "appcast.xml", "--dir", str(directory)], check=True)
            highest = max(highest, feed(directory / "appcast.xml"))
    require(int(info()["CFBundleVersion"]) > highest, "Build is not newer than all published stable releases")
    print(f"Release history verified; previous highest build: {highest}")
except (ValueError, OSError, subprocess.CalledProcessError) as error:
    sys.exit(f"Release history check failed: {error}")
