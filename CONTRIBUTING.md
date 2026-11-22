# Contributing

## Ground rules

- Clean-room code only. Do not paste in code or assets from other file
  managers, and do not add third-party runtime binaries.
- Every first-party source file starts with the MPL Exhibit A notice and
  `SPDX-License-Identifier: MPL-2.0-no-copyleft-exception`.
- Keep `core/` free of HarmonyOS imports so it stays testable on plain Node.

## AI-assisted contributions

AI tools are allowed, with conditions:

- **You own the change.** Read, understand and be able to explain every line
  you submit. You are responsible for its correctness, licensing and security.
- **Verify APIs, flags and paths** against the installed SDK or upstream
  documentation. Generated code that merely looks plausible is not evidence.
- **Disclose AI assistance** in the PR description (tool and extent). Using AI
  is fine; submitting unreviewed output is not.
- **Do not paste secrets, keys, tokens, account data, proprietary or
  decompiled code, or third-party assets** into AI tools.
- AI output follows the same clean-room, license-header and testing rules as
  hand-written code.

## Testing before every commit (required)

A runtime change that has not been tested on real hardware or an emulator must
not be committed.

Before committing any code, resource or configuration change:

1. Build the HAP (`scripts/build_hap.bat` / `.sh`) and fix every error.
2. Install and run it on a **real HarmonyOS device or an emulator**.
3. Exercise the feature you changed, including at least one failure or edge
   path, and smoke-test the core flows (open a mount, browse, extract, ZIP).
4. Include the device/emulator model, API version, steps and result in the PR
   description. "It compiles" and "CI passed" are not testing.

Documentation-only commits are exempt from device testing but still must pass
the header and config checks. If you cannot test, **do not commit** — ask a
maintainer or another contributor to test first.

Useful device checklist:

- first launch with storage granted and with storage denied;
- browse `/sandbox`, `/download`, `/documents`;
- create a ZIP from a multi-selection and open it;
- extract all, then extract a single selected file;
- copy, move, rename, delete, new folder;
- open a corrupt file and confirm the error is reported, not a crash.

## Strict commit rules

- `main` must build and pass all checks at every commit. Never push a broken
  commit with the intention of fixing it later.
- One logical change per commit. Do not mix refactors, features and fixes, and
  do not include unrelated formatting or drive-by edits.
- Never bypass hooks or CI: no `--no-verify`, no skipped tests, no disabled
  checks. Fix the root cause.
- Commit no build output, dependencies, caches, secrets, keys, tokens,
  third-party binaries or game assets.
- Never force-push or rewrite history on `main`. If a commit is wrong, revert
  it with a new commit; do not layer hacks on top.
- Stage files by name and review `git diff --staged` plus `git status` before
  committing.
- Preserve license headers and notices. Changes to licensing, permissions or
  the build configuration require maintainer agreement.
- Update tests and documentation in the same commit as the behaviour change.
- When unsure, stop and open an issue instead of guessing.

## Before sending a change

```sh
python3 scripts/check_mpl_headers.py
python3 scripts/check_configs.py
cd tests && npm test
scripts/build_hap.bat        # or .sh
```

Add or update tests under `tests/core` for anything in `core/`.
`ArchiveService` and `Vfs` depend on system APIs and are exercised on a device
or emulator.

## Style

- ArkTS: explicit types, no `any`, `Array<T>` generics, small classes rather
  than object literals.
- UI strings are user-facing English; code identifiers are English.
- Prefer the existing colour constants in `pages/Index.ets` over new hex
  values.
