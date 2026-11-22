# Building

## Requirements

- DevEco Studio 6.1.1 or newer, or the HarmonyOS commandline-tools package
  containing `hvigor`, `ohpm` and the API 24 SDK.
- Node 24 only for the plain-Node core tests.

Set `DEVECO_STUDIO_HOME` if the toolchain is not at the default location.

## Local build

```sh
scripts/build_hap.bat        # Windows
DEVECO_STUDIO_HOME=/path scripts/build_hap.sh
```

The scripts run `ohpm install` and then:

```sh
hvigorw --mode module -p module=entry@default -p product=default assembleHap
```

Output: `entry/build/default/outputs/default/entry-default-unsigned.hap`,
copied to `out/`. The HAP is unsigned; install it with a signing profile of
your own. There is no native code and no CMake step.

## Checks

```sh
python3 scripts/check_mpl_headers.py
python3 scripts/check_configs.py
cd tests && npm test
```

- `check_mpl_headers.py` enforces the SPDX identifier and Exhibit A notice on
  every first-party source file.
- `check_configs.py` validates strict-JSON resources, consistent
  `modelVersion`, SDK strings, bundle name, PNG icons, the page declared by
  `main_pages`, the permission set (exactly the two storage permissions, no
  INTERNET), and the absence of runtime dependencies.
- `tests` copies `entry/src/main/ets/core/**` to `tests/.build` and runs
  `node --test` with native type stripping.

## CI

`.github/workflows/ci.yml` runs the three checks, then downloads a public
HarmonyOS commandline-tools zip (revision-pinned), builds the unsigned HAP and
uploads it as an artifact. No secrets or repository variables are required;
`HOS_TOOLS_URL` may override the download URL.

## Status

The HAP compiles with hvigor (API 24) and the 19 core tests pass. It has not
been installed on a device or emulator, and the storage-permission flow has
not been exercised on hardware.
