#!/usr/bin/env python3
"""Validate all inputs before synchronizing the generated version settings."""
import argparse
import plistlib
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
version = Path("VERSION").read_text().strip()
build = Path("BUILD_NUMBER").read_text().strip()
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
    raise SystemExit("Invalid VERSION")
if not re.fullmatch(r"[1-9][0-9]*", build):
    raise SystemExit("Invalid BUILD_NUMBER")

updates = {}
project = Path("project.yml")
text = project.read_text()
for key, value in [("MARKETING_VERSION", version), ("CURRENT_PROJECT_VERSION", build)]:
    text, count = re.subn(r'(^\s*' + key + r': )"[^"\n]*"',
                          lambda m: m[1] + '"' + value + '"', text, flags=re.M)
    if count != 1:
        raise SystemExit(f"Expected one {key} in project.yml, got {count}")
updates[project] = text.encode()
for name in ["App", "PreviewExt", "ThumbExt"]:
    path = Path(f"Packaging/{name}-Info.plist")
    data = plistlib.loads(path.read_bytes())
    for key in ["CFBundleShortVersionString", "CFBundleVersion"]:
        if key not in data:
            raise SystemExit(f"Missing {key} in {path}")
    # Preserve formatting and all unrelated properties.
    text = path.read_text()
    for key, value in [("CFBundleShortVersionString", version), ("CFBundleVersion", build)]:
        text, count = re.subn(r'(<key>' + key + r'</key>\s*<string>)[^<]*(</string>)',
                             lambda m: m[1] + value + m[2], text)
        if count != 1:
            raise SystemExit(f"Expected one {key} in {path}")
    updates[path] = text.encode()
changed = [str(p) for p, contents in updates.items() if p.read_bytes() != contents]
if args.check:
    if changed:
        raise SystemExit("Version drift: " + ", ".join(changed) + "; run ./scripts/sync-version.sh")
else:
    for path, contents in updates.items():
        path.write_bytes(contents)
print(f"Version {version}, build {build}: {'checked' if args.check else 'synchronized'}")
