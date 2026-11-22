#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Configuration rules whose violations break hvigor or change the app's
permission posture.

  1. resources/**/*.json are STRICT JSON (restool rejects comments)
  2. no '#' comments in .json5 files
  3. modelVersion is consistent across oh-package and hvigor configs
  4. HarmonyOS SDK strings keep the "(api)" suffix and target >= compatible
  5. AppScope/app.json5 declares buildVersion and the archiver bundle name
  6. app icons are real PNG files
  7. the module requests exactly the two storage permissions (no network)
  8. the entry page named by main_pages exists
  9. no third-party runtime dependencies
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", ".hvigor", ".build", "node_modules", "oh_modules",
             "build", "out"}
errors: list[str] = []

EXPECTED_PERMISSIONS = {
    "ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY",
    "ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY",
}


def fail(msg: str) -> None:
    errors.append(msg)


def read(rel: str) -> str:
    path = ROOT / rel
    return path.read_text(encoding="utf-8") if path.exists() else ""


# 1. strict JSON resources
resource_files = sorted(
    list(ROOT.glob("AppScope/resources/**/*.json"))
    + list(ROOT.glob("entry/src/main/resources/**/*.json"))
)
for path in resource_files:
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{path.relative_to(ROOT)}: not strict JSON "
             f"({exc.msg} at line {exc.lineno})")

# 2. '#' comments in json5
for path in sorted(ROOT.rglob("*.json5")):
    if set(path.relative_to(ROOT).parts) & SKIP_DIRS:
        continue
    for lineno, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("#"):
            fail(f"{path.relative_to(ROOT)}:{lineno}: '#' comment "
                 "(JSON5 allows only //)")


# 3. modelVersion consistency
def model_version(rel: str) -> str | None:
    match = re.search(r'"modelVersion":\s*"([^"]+)"', read(rel))
    return match.group(1) if match else None


versions = {
    "oh-package.json5": model_version("oh-package.json5"),
    "hvigor/hvigor-config.json5": model_version("hvigor/hvigor-config.json5"),
}
declared = {name: version for name, version in versions.items() if version}
if not declared:
    fail("no modelVersion found in oh-package.json5 or hvigor config")
elif len(set(declared.values())) > 1:
    fail(f"modelVersion mismatch across configs: {declared}")
else:
    print(f"modelVersion: {next(iter(declared.values()))} (consistent)")

# 4. SDK version strings
build_profile = read("build-profile.json5")
sdk: dict[str, int] = {}
for key in ("compatibleSdkVersion", "targetSdkVersion"):
    match = re.search(rf'"{key}":\s*"([^"]+)"', build_profile)
    if not match:
        fail(f"build-profile.json5: {key} missing")
        continue
    value = match.group(1)
    parsed = re.fullmatch(r"(\d+\.\d+\.\d+)\((\d+)\)", value)
    if not parsed:
        fail(f'build-profile.json5: {key}="{value}" lacks the "(api)" suffix')
        continue
    sdk[key] = int(parsed.group(2))
if len(sdk) == 2 and sdk["targetSdkVersion"] < sdk["compatibleSdkVersion"]:
    fail("build-profile.json5: targetSdkVersion < compatibleSdkVersion")

# 5. app identity
app_json = read("AppScope/app.json5")
if '"buildVersion"' not in app_json:
    fail("AppScope/app.json5: missing required 'buildVersion'")
if '"org.mc4hos.archiver"' not in app_json:
    fail("AppScope/app.json5: bundleName must be org.mc4hos.archiver")

# 6. PNG app icons
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
for media in (ROOT / "AppScope/resources/base/media",
              ROOT / "entry/src/main/resources/base/media"):
    icon = media / "app_icon.png"
    if not icon.exists():
        fail(f"{icon.relative_to(ROOT)}: missing")
    elif not icon.read_bytes().startswith(PNG_MAGIC):
        fail(f"{icon.relative_to(ROOT)}: not a PNG file")

# 7. permission posture: exactly the storage pair, nothing network-wide
module_json = read("entry/src/main/module.json5")
requested = set(re.findall(r'"name":\s*"(ohos\.permission\.[A-Z_]+)"',
                           module_json))
if requested != EXPECTED_PERMISSIONS:
    fail("entry/src/main/module.json5: expected exactly "
         f"{sorted(EXPECTED_PERMISSIONS)}, found {sorted(requested)}")
if "INTERNET" in module_json:
    fail("entry/src/main/module.json5: archiver must not request INTERNET")

# 8. page declared by main_pages exists
pages_match = re.search(r'"pages":\s*"\$profile:([^"]+)"', module_json)
if not pages_match:
    fail("entry/src/main/module.json5: missing $profile main_pages")
else:
    profile = ROOT / "entry/src/main/resources/base/profile" / \
        f"{pages_match.group(1)}.json"
    if not profile.exists():
        fail(f"{profile.relative_to(ROOT)}: missing")
    else:
        try:
            pages = json.loads(profile.read_text(encoding="utf-8")).get(
                "src", [])
        except json.JSONDecodeError:
            pages = []
        if not pages:
            fail(f"{profile.relative_to(ROOT)}: no pages listed")
        for page in pages:
            if not (ROOT / "entry/src/main/ets" / f"{page}.ets").exists():
                fail(f"entry/src/main/ets/{page}.ets: page missing")

# 9. no third-party runtime dependencies
entry_pkg = read("entry/oh-package.json5")
deps_match = re.search(r'"dependencies"\s*:\s*\{([^}]*)\}', entry_pkg,
                       re.S)
if deps_match and deps_match.group(1).strip():
    fail("entry/oh-package.json5: unexpected runtime dependencies")

if errors:
    print(f"FAIL: {len(errors)} config rule violation(s):")
    for error in errors:
        print("  -", error)
    sys.exit(1)

print(f"OK: {len(resource_files)} strict-JSON resources valid; all rules pass")
