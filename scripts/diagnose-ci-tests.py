#!/usr/bin/env python3
"""One full offline run plus bounded startup-case isolation on the CI toolchain.

Never run locally. Only synthetic test output and allowlisted crash fields leave
the runner; no raw crash reports, environment dump, databases or app bundles.
"""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

STARTUP_CASES = (
    "nilDevelopmentSuiteReportsPreferenceConstructionWithoutFallback",
    "startupPreferenceFailureIsDistinctAndPreservesOriginalError",
    "startupRecoveryFailureStopsBeforePreferenceConstruction",
    "startupSuccessReportsNoFailure",
    "startupRecoveryFailuresReportExactStageAndReleaseStore",
    "startupReportsRealAdmissionErrorWithoutChangingItsType",
    "startupErrorSnapshotsExcludeUntrustedDescriptionsDomainsAndUnderlyingErrors",
)


def run_command(command, output):
    """Stream merged output without a shell; retain the observed child status."""
    with output.open("wb") as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        while chunk := process.stdout.read1(65536):
            log.write(chunk)
            log.flush()
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
        code = process.wait()
    text = output.read_text(errors="replace")
    return {
        "command": command, "pid": process.pid, "returnCode": code,
        "signal": signal.Signals(-code).name if code < 0 else None,
        "statusScope": "observed SwiftPM subprocess; test-child signal may require crash evidence",
        "startedTests": re.findall(r"Test (.+?) started\.", text),
        "completedRunSummaries": re.findall(r"Test run with [^\n]+", text),
    }


def crash_summary(path, started):
    if path.is_symlink() or path.stat().st_mtime < started or path.stat().st_size > 10_000_000:
        return None
    # Modern .ips files contain one metadata JSON object and one report object.
    content = path.read_text(errors="replace")
    decoder = json.JSONDecoder()
    first, end = decoder.raw_decode(content.lstrip())
    remaining = content.lstrip()[end:].lstrip()
    report = decoder.raw_decode(remaining)[0] if remaining else first
    if report.get("procName") != "CopyStoryPackageTests":
        return None
    threads = report.get("threads", [])
    fault = report.get("faultingThread")
    thread = threads[fault] if isinstance(fault, int) and 0 <= fault < len(threads) else {}
    frames = []
    images = report.get("usedImages", [])
    for frame in thread.get("frames", [])[:40]:
        index = frame.get("imageIndex")
        image = images[index] if isinstance(index, int) and 0 <= index < len(images) else {}
        frames.append({key: value for key, value in {
            "image": Path(image.get("path", "unknown")).name,
            "symbol": frame.get("symbol"), "imageOffset": frame.get("imageOffset"),
        }.items() if value is not None})
    # Deliberately exclude user paths, registers, memory, application-specific
    # messages, raw report metadata, arguments, environment and binary UUIDs.
    return {
        "pid": report.get("pid"), "procName": report["procName"],
        "exception": {key: report.get("exception", {}).get(key) for key in ("type", "signal")},
        "termination": {key: report.get("termination", {}).get(key) for key in ("namespace", "code", "indicator")},
        "faultingFrames": frames,
    }


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("CI-only diagnostic; no local tests were started.")
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    output = Path(os.environ["RUNNER_TEMP"]) / "copystory-ci-diagnostics"
    output.mkdir(exist_ok=False)
    os.environ.update(COPYSTORY_APP_STORE="1", COPYSTORY_SHIPPING_RECONSTRUCTION="1")
    started = time.time()
    records = []
    failed = False
    try:
        for name, command in (
            ("toolchain", ["swift", "--version"]),
            ("developer", ["xcode-select", "-p"]),
            ("test-help", ["swift", "test", "--help"]),
        ):
            record = run_command(command, output / (name + ".log"))
            records.append(record)
            failed |= record["returnCode"] != 0
        help_text = (output / "test-help.log").read_text()

        def diagnostics(name):
            args = ["--verbose"]
            if "--xunit-output" in help_text:
                args += ["--xunit-output", str(output / (name + ".xml"))]
            return args

        # Full original allowlist runs first, unchanged. Isolation never replaces
        # baseline coverage and cannot turn a baseline failure into success.
        commands = [("full-offline", ["scripts/test-development.sh", *diagnostics("full-offline")])]
        commands += [(case, ["swift", "test", "--skip-build", "--disable-xctest",
                            "--filter", case, *diagnostics(case)]) for case in STARTUP_CASES]
        for name, command in commands:
            print(f"\n::group::{name}", flush=True)
            record = run_command(command, output / (name + ".log"))
            record["label"] = name
            # A successful command with zero selected/completed tests is not a pass.
            record["completedTests"] = any(
                re.search(r"Test run with [1-9][0-9]* tests?", value)
                for value in record["completedRunSummaries"])
            records.append(record)
            failed |= record["returnCode"] != 0 or not record["completedTests"]
            print(json.dumps(record), flush=True)
            print("::endgroup::", flush=True)
    except BaseException:
        failed = True
        raise
    finally:
        crashes, errors = [], []
        # Give ReportCrash a bounded chance to finish; never poll/retry tests.
        time.sleep(5)
        reports = Path.home() / "Library" / "Logs" / "DiagnosticReports"
        for path in sorted(reports.glob("CopyStoryPackageTests*.ips")):
            try:
                summary = crash_summary(path, started)
                if summary:
                    crashes.append(summary)
            except (OSError, ValueError, TypeError, KeyError, IndexError):
                errors.append("A matching crash report could not be parsed; raw report excluded.")
        result = {"commands": records, "crashes": crashes, "crashCollectionNotes": errors,
                  "failed": failed, "rawCrashReportsIncluded": False}
        (output / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2), flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
