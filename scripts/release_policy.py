#!/usr/bin/env python3
"""Fail-closed metadata, package and staged release validation. No credentials."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import posixpath
import re
import stat
import subprocess
import sys
import unicodedata
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "fromOkayToGreat/CopyStory"
FEED = f"https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def info(path=ROOT / "Config/Info.plist"):
    with Path(path).open("rb") as handle:
        p = plistlib.load(handle)
    require(p.get("CFBundleIdentifier") == "com.copystory.app", "Unexpected bundle identifier")
    require(re.fullmatch(r"[1-9][0-9]*", p.get("CFBundleVersion", "")), "Build must be a positive integer")
    require(int(p["CFBundleVersion"]) <= 2**64 - 1, "Build must fit UInt64")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", p.get("CFBundleShortVersionString", "")), "Invalid release version")
    require(p.get("SUFeedURL") == FEED, "Feed URL does not match this repository")
    require(len(base64.b64decode(p.get("SUPublicEDKey", ""), validate=True)) == 32, "Missing/invalid update public key")
    require(p.get("LSMinimumSystemVersion") == "26.0", "Unexpected minimum OS")
    for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
        require(p.get(key) is True, f"{key} must be true")
    for key in ("SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUEnableSystemProfiling", "SUEnableJavaScript"):
        require(p.get(key) is False, f"{key} must default to false")
    require(type(p.get("SUSignedFeedFailureExpirationInterval")) is int and p["SUSignedFeedFailureExpirationInterval"] == 0,
            "Signed feed failures must never expire")
    return p


def output(*args):
    return subprocess.check_output(args, stderr=subprocess.STDOUT, text=True)


def bundle(app, public=False):
    app = Path(app).resolve(strict=True)
    p = info(app / "Contents/Info.plist")
    development = p.get("CopyStoryDevelopmentBuild") is True
    expected = dict(info())
    if development:
        expected["CopyStoryDevelopmentBuild"] = True
    require(p == expected, "Packaged plist differs from reviewed configuration")
    require(not (public and development), "Public app cannot be a development build")
    executable = app / "Contents/MacOS/CopyStory"
    require(set(output("lipo", "-archs", str(executable)).split()) == {"arm64", "x86_64"}, "App must be universal")
    require("@rpath/Sparkle.framework/Versions/B/Sparkle" in output("otool", "-arch", "all", "-L", str(executable)), "Missing Sparkle link")
    load_commands = output("otool", "-arch", "all", "-l", str(executable))
    require("@executable_path/../Frameworks" in load_commands, "Missing Frameworks rpath")
    require(re.findall(r"^\s+minos (\S+)$", load_commands, re.MULTILINE) == ["26.0", "26.0"],
            "Both executable slices must target macOS 26")
    for path in app.rglob("*"):
        if path.is_symlink():
            require(path.resolve().is_relative_to(app), f"Symlink escapes app: {path.name}")
        require(path.name not in {"Source", ".git", ".DS_Store"}, "Unintended source or metadata in bundle")
        require(path.suffix.lower() not in {".sqlite", ".sqlite3", ".db", ".p12", ".p8", ".pem", ".key"}, "Private data/key in bundle")
    for name in ("CopyStory-LICENSE", "Sparkle-LICENSE"):
        require((app / "Contents/Resources/Licenses" / name).is_file(), f"Missing {name}")
    binary = executable.read_bytes()
    require(b"/Users/" not in binary and b"/home/" not in binary, "Personal build paths remain in executable")
    fw = app / "Contents/Frameworks/Sparkle.framework"
    require(plistlib.loads((fw / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"] == "2.10.0", "Unexpected Sparkle version")
    components = [fw / "Versions/B/XPCServices/Downloader.xpc", fw / "Versions/B/XPCServices/Installer.xpc",
                  fw / "Versions/B/Autoupdate", fw / "Versions/B/Updater.app", fw, app]
    teams = set()
    for component in components:
        details = output("codesign", "-dvv", str(component))
        require("runtime" in details, f"Hardened runtime missing: {component.name}")
        result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(component)], capture_output=True, check=True)
        entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
        for key in ("com.apple.security.cs.disable-library-validation", "com.apple.security.get-task-allow",
                    "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"):
            if key == "com.apple.security.cs.disable-library-validation" and development and component == app:
                require("Signature=adhoc" in details and entitlements.get(key) is True,
                        "Development exception requires explicit ad-hoc signature and entitlement")
            else:
                require(not entitlements.get(key), f"Unsafe entitlement {key}")
        if public:
            require("Authority=Developer ID Application:" in details, "Public app requires Developer ID Application")
            require("Timestamp=" in details, "Public app requires secure timestamp")
            team = re.search(r"^TeamIdentifier=(.+)$", details, re.MULTILINE)
            require(team and team[1] != "not set", "Missing signing team")
            teams.add(team[1])
    require(not public or len(teams) == 1, "Nested components must share the Developer ID team")
    return p


def verify_signature(path, signature=None):
    cmd = ["swift", str(ROOT / "scripts/verify-update.swift"), info()["SUPublicEDKey"], str(path)]
    if signature is not None:
        cmd.append(signature)
    subprocess.run(cmd, check=True)


def feed(path, expected_build=None, stage=None):
    path = Path(path)
    verify_signature(path)
    data = path.read_bytes()
    require(b"<!DOCTYPE" not in data and b"<!ENTITY" not in data, "Feed cannot contain declarations")
    items = ET.fromstring(data).findall("./channel/item")
    require(items, "Feed has no updates")
    builds = []
    for item in items:
        value = item.findtext(SPARKLE + "version", "")
        require(re.fullmatch(r"[1-9][0-9]*", value), "Feed build must be a positive integer")
        require(int(value) <= 2**64 - 1, "Feed build must fit UInt64")
        builds.append(int(value))
    if expected_build is not None:
        require(max(builds) == int(expected_build), "Feed version differs from release")
    if stage:
        require(len(items) == 1, "Staged release must contain one full update")
        p = info()
        item = items[0]
        require(item.findtext(SPARKLE + "shortVersionString") == p["CFBundleShortVersionString"], "Feed version mismatch")
        require(item.findtext(SPARKLE + "minimumSystemVersion") == "26.0", "Feed OS mismatch")
        enclosures = item.findall("enclosure")
        require(len(enclosures) == 1, "Expected one full archive")
        enclosure = enclosures[0]
        name = f"CopyStory-{p['CFBundleShortVersionString']}.zip"
        require(enclosure.get("url") == f"https://github.com/{REPOSITORY}/releases/download/v{p['CFBundleShortVersionString']}/{name}", "Unexpected release URL")
        archive = Path(stage) / name
        require(int(enclosure.get("length", "0")) == archive.stat().st_size, "Archive length mismatch")
        signature = enclosure.get(SPARKLE + "edSignature", "")
        require(len(base64.b64decode(signature, validate=True)) == 64, "Missing archive signature")
        verify_signature(archive, signature)
    return max(builds)


def hashes(stage):
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(stage).iterdir()) if p.is_file() and p.name != "release-manifest.json"}


def validate_archive(path):
    # ditto archives store canonical files only: no members beneath symlink
    # aliases. Enforce that property to rule out chained symlink traversal.
    def identity(name):
        # Common APFS volumes compare names without case and normalize Unicode.
        return unicodedata.normalize("NFC", name).casefold()

    with zipfile.ZipFile(path) as archive:
        entries, symlinks = {}, set()
        for member in archive.infolist():
            name = member.filename.rstrip("/")
            require(name and not name.startswith("/") and "\\" not in name and
                    all(part not in ("", ".", "..") for part in name.split("/")), "Unsafe archive entry")
            require(name.split("/")[0] in ("CopyStory.app", "__MACOSX"), "Unexpected archive root")
            require(identity(name) not in entries, "Duplicate archive entry")
            entries[identity(name)] = member
            mode = member.external_attr >> 16
            require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), "Special archive file")
            if stat.S_ISLNK(mode):
                require(name.startswith("CopyStory.app/Contents/Frameworks/Sparkle.framework/"), "Unexpected archive symlink")
                target = archive.read(member).decode("utf-8")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                require(not target.startswith("/") and "\\" not in target and
                        resolved.startswith("CopyStory.app/Contents/Frameworks/Sparkle.framework/"), "Archive symlink escapes framework")
                symlinks.add(identity(name))
        require("copystory.app" in entries and entries["copystory.app"].is_dir(), "Missing app root directory")
        for name in entries:
            parents = name.split("/")[:-1]
            require(all("/".join(parents[:index]) not in symlinks for index in range(1, len(parents) + 1)),
                    "Archive entry descends through a symlink")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["config", "bundle", "feed", "stage", "manifest", "archive"])
    parser.add_argument("path", nargs="?")
    parser.add_argument("--public", action="store_true")
    parser.add_argument("--development", action="store_true")
    args = parser.parse_args()
    p = info()
    if args.action == "config":
        print(json.dumps(p, indent=2))
    elif args.action == "bundle":
        bundle(args.path, args.public)
    elif args.action == "feed":
        print(feed(args.path))
    elif args.action == "archive":
        validate_archive(args.path)
    else:
        stage = Path(args.path).resolve(strict=True)
        feed(stage / "appcast.xml", p["CFBundleVersion"], stage)
        allowed = {f"CopyStory-{p['CFBundleShortVersionString']}.zip", "appcast.xml", "SHA256SUMS", "release-manifest.json"}
        require({f.name for f in stage.iterdir()} <= allowed, "Unexpected staged files")
        require((stage / "SHA256SUMS").is_file(), "Missing checksums")
        names = [f"CopyStory-{p['CFBundleShortVersionString']}.zip", "appcast.xml"]
        expected_checksums = "".join(f"{hashlib.sha256((stage / name).read_bytes()).hexdigest()}  {name}\n" for name in names)
        require((stage / "SHA256SUMS").read_text() == expected_checksums, "Checksums must cover exactly the archive and signed feed")
        manifest = {"schema": 1, "version": p["CFBundleShortVersionString"], "build": int(p["CFBundleVersion"]),
                    "commit": output("git", "-C", str(ROOT), "rev-parse", "HEAD").strip(), "files": hashes(stage)}
        if args.action == "manifest":
            (stage / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        else:
            require(json.loads((stage / "release-manifest.json").read_text()) == manifest, "Staged assets or source commit changed")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError, KeyError) as error:
        sys.exit(f"Release validation failed: {error}")
