# Security

## Permission model

Archiver requests exactly two normal-level, user-grant permissions:

- `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`
- `ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY`

They are requested at first launch. If the user declines, the app only sees
its private sandbox (`/sandbox` in the UI); `Download` and `Documents` mounts
are simply absent. The app declares no network permission.

The virtual filesystem maps fixed prefixes onto real directories:
`/sandbox`, `/download`, `/documents`. Paths are normalised and confined to a
mount; there is no way to address an arbitrary absolute path.

## Archive handling

- ZIP metadata is read with a bounded tail read (max 65,557 bytes) plus a
  ranged read of the central directory. Zip64 is rejected instead of guessed.
- Entry names containing `..` segments, leading `/`, backslashes or NUL bytes
  are dropped at parse time, so a crafted archive cannot escape the extraction
  directory.
- Extraction targets must resolve inside a mount; the app refuses to write
  outside one.
- "Extract selected" decompresses into the app's private cache first, copies
  the requested entries, then removes the temporary tree. This trades disk
  space for correctness: a large archive can temporarily need its full
  uncompressed size in the cache. There is no zip-bomb limit in v1.
- Encrypted ZIP entries are not detected; zlib reports an error and the app
  surfaces it as "Extract failed".

## In-archive mode

Archive entries are read-only. Delete, rename, move, copy and paste are
disabled while browsing an archive.

## Reporting

This is a hobby project without a security-response process. Open a GitHub
issue for non-sensitive reports; for anything sensitive, contact the
maintainer through the address on their GitHub profile.
