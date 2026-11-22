# OHOS Archiver

A file browser and ZIP manager for HarmonyOS, split out of
[ohos-terminal](https://github.com/BytinIsDead/ohos-terminal). Built with
ArkTS on the stage model, target API 24 ("6.1.1(24)").

The layout follows ZArchiver: breadcrumbs on top, `Name / Size / Age` columns,
a persistent action bar, and in-archive browsing before extraction.

## Features

- Browse the application sandbox plus the public **Download** and
  **Documents** folders (when the storage permissions are granted).
- Open and inspect a ZIP's directory tree without extracting it.
- Extract the whole archive, or only the selected files/folders, to a
  destination folder you choose.
- Create ZIP archives from a multi-selection.
- Multi-select with copy, move, rename and delete.
- Name filter, sortable columns (name/size/age, both directions).

## Not supported (v1)

- Archive formats other than ZIP (no 7z, RAR, TAR).
- Zip64 archives, encrypted archives, and multi-volume archives.
- Editing entries inside an archive; archives are read-only in the browser.
- Previewing file contents.

The HAP is unsigned and has **not** been run on a physical device or emulator
yet; see [docs/BUILD.md](docs/BUILD.md) for what is verified in CI.

## Permissions

`ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` and
`ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY` are normal-level,
user-grant permissions. They are requested at first launch. Declining them is
harmless: the app simply shows only the private sandbox mount. No network
permission is requested.

## Build

Requires DevEco Studio 6.1.1+ (or the HarmonyOS commandline-tools package with
the API 24 SDK).

```sh
scripts/build_hap.bat   # Windows
scripts/build_hap.sh    # Linux/macOS
```

The unsigned HAP lands in `out/`.

Core logic tests run on plain Node 24, with no SDK needed:

```sh
cd tests
npm test
```

## Layout

```
entry/src/main/ets/
  common/       Logger, runtime storage permission request
  core/fs/      FileEntry, path helpers, formatting/sorting
  core/zip/     Pure ZIP central-directory reader and archive listing
  services/     Vfs mounts, ArchiveService (zlib + ranged reads)
  pages/Index   Browser UI
```

## License

MPL-2.0 with the Exhibit B "Incompatible With Secondary Licenses" notice;
SPDX identifier `MPL-2.0-no-copyleft-exception`. Every first-party source file
carries the Exhibit A notice. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
