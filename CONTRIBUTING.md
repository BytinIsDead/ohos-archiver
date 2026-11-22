# Contributing

## Ground rules

- Clean-room code only. Do not paste in code or assets from other file
  managers, and do not add third-party runtime binaries.
- Every first-party source file starts with the MPL Exhibit A notice and
  `SPDX-License-Identifier: MPL-2.0-no-copyleft-exception`.
- Keep `core/` free of HarmonyOS imports so it stays testable on plain Node.

## Before sending a change

```sh
python3 scripts/check_mpl_headers.py
python3 scripts/check_configs.py
cd tests && npm test
scripts/build_hap.bat        # or .sh
```

Add or update tests under `tests/core` for anything in `core/`.
`ArchiveService` and `Vfs` depend on system APIs and are exercised manually.

## Style

- ArkTS: explicit types, no `any`, `Array<T>` generics, small classes rather
  than object literals.
- UI strings are user-facing English; code identifiers are English.
- Prefer the existing colour constants in `pages/Index.ets` over new hex
  values.
