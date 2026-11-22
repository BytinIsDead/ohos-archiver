/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Pure ZIP central-directory reader. Only browsing metadata is parsed here;
 * decompression is delegated to @ohos.zlib by the service layer. Zip64 is
 * rejected explicitly rather than guessed at.
 */

import { FileEntry } from '../fs/FileEntry';

const SIG_EOCD: number = 0x06054b50;
const SIG_CENTRAL: number = 0x02014b50;
const EOCD_MIN: number = 22;
const EOCD_MAX_COMMENT: number = 65535;
const ZIP64_MARK: number = 0xFFFFFFFF;

export class EocdInfo {
  cdOffset: number;
  cdSize: number;
  entryCount: number;
  comment: string;

  constructor(cdOffset: number, cdSize: number, entryCount: number,
              comment: string) {
    this.cdOffset = cdOffset;
    this.cdSize = cdSize;
    this.entryCount = entryCount;
    this.comment = comment;
  }
}

export class ZipEntryInfo {
  name: string;
  isDir: boolean;
  compressedSize: number;
  size: number;
  crc32: number;
  method: number;
  dosTime: number;
  dosDate: number;
  localHeaderOffset: number;

  constructor(name: string, isDir: boolean, compressedSize: number,
              size: number, crc32: number, method: number, dosTime: number,
              dosDate: number, localHeaderOffset: number) {
    this.name = name;
    this.isDir = isDir;
    this.compressedSize = compressedSize;
    this.size = size;
    this.crc32 = crc32;
    this.method = method;
    this.dosTime = dosTime;
    this.dosDate = dosDate;
    this.localHeaderOffset = localHeaderOffset;
  }

  /** DOS date/time converted to Unix seconds (local time). */
  mtimeSeconds(): number {
    const year: number = 1980 + ((this.dosDate >> 9) & 0x7f);
    const month: number = ((this.dosDate >> 5) & 0x0f) - 1;
    const day: number = this.dosDate & 0x1f;
    const hour: number = (this.dosTime >> 11) & 0x1f;
    const minute: number = (this.dosTime >> 5) & 0x3f;
    const second: number = (this.dosTime & 0x1f) * 2;
    return Math.floor(new Date(year, month, day, hour, minute, second)
      .getTime() / 1000);
  }
}

function u16(data: Uint8Array, at: number): number {
  return data[at] | (data[at + 1] << 8);
}

function u32(data: Uint8Array, at: number): number {
  return (data[at] | (data[at + 1] << 8) | (data[at + 2] << 16) |
    (data[at + 3] << 24)) >>> 0;
}

/** UTF-8 decode with a per-byte fallback for legacy (CP437-ish) names. */
export function decodeZipName(data: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < data.length) {
    const b: number = data[i];
    if (b < 0x80) {
      out += String.fromCharCode(b);
      i++;
      continue;
    }
    let need: number = 0;
    let code: number = 0;
    if ((b & 0xe0) === 0xc0) {
      need = 1;
      code = b & 0x1f;
    } else if ((b & 0xf0) === 0xe0) {
      need = 2;
      code = b & 0x0f;
    } else if ((b & 0xf8) === 0xf0) {
      need = 3;
      code = b & 0x07;
    } else {
      out += String.fromCharCode(b);
      i++;
      continue;
    }
    if (i + need >= data.length) {
      out += String.fromCharCode(b);
      i++;
      continue;
    }
    let valid: boolean = true;
    for (let k = 1; k <= need; k++) {
      const cc: number = data[i + k];
      if ((cc & 0xc0) !== 0x80) {
        valid = false;
        break;
      }
      code = (code << 6) | (cc & 0x3f);
    }
    if (!valid) {
      out += String.fromCharCode(b);
      i++;
      continue;
    }
    if (code < 0x10000) {
      out += String.fromCharCode(code);
    } else {
      const v: number = code - 0x10000;
      out += String.fromCharCode(0xd800 + (v >> 10),
        0xdc00 + (v & 0x3ff));
    }
    i += need + 1;
  }
  return out;
}

function decodeUtf8(data: Uint8Array): string {
  return decodeZipName(data);
}

/**
 * Finds the End Of Central Directory record in the tail of the file.
 * `tailOffset` is the file offset of byte 0 of `tail`.
 */
export function findEocd(tail: Uint8Array, tailOffset: number,
                         fileSize: number): EocdInfo | null {
  if (tail.length < EOCD_MIN) {
    return null;
  }
  for (let i = tail.length - EOCD_MIN; i >= 0; i--) {
    if (u32(tail, i) !== SIG_EOCD) {
      continue;
    }
    const commentLen: number = u16(tail, i + 20);
    if (i + EOCD_MIN + commentLen !== tail.length) {
      continue;
    }
    const disk: number = u16(tail, i + 4);
    const cdDisk: number = u16(tail, i + 6);
    const countDisk: number = u16(tail, i + 8);
    const count: number = u16(tail, i + 10);
    const cdSize: number = u32(tail, i + 12);
    const cdOffset: number = u32(tail, i + 16);
    if (disk !== 0 || cdDisk !== 0 || countDisk !== count) {
      return null;
    }
    if (count === 0xffff || cdSize === ZIP64_MARK || cdOffset === ZIP64_MARK) {
      throw new Error('Zip64 archives are not supported');
    }
    if (cdOffset + cdSize > fileSize) {
      return null;
    }
    const comment: string =
      decodeUtf8(tail.subarray(i + EOCD_MIN, i + EOCD_MIN + commentLen));
    return new EocdInfo(cdOffset, cdSize, count, comment);
  }
  return null;
}

export function isSafeName(name: string): boolean {
  if (name.length === 0 || name.startsWith('/') ||
      name.indexOf('\\') >= 0 || name.indexOf('\u0000') >= 0) {
    return false;
  }
  const parts: Array<string> = name.split('/');
  for (let i = 0; i < parts.length; i++) {
    if (parts[i] === '..') {
      return false;
    }
  }
  return true;
}

export function parseCentralDirectory(cd: Uint8Array): Array<ZipEntryInfo> {
  const out: Array<ZipEntryInfo> = [];
  let at: number = 0;
  while (at + 46 <= cd.length) {
    if (u32(cd, at) !== SIG_CENTRAL) {
      break;
    }
    const flags: number = u16(cd, at + 8);
    const method: number = u16(cd, at + 10);
    const dosTime: number = u16(cd, at + 12);
    const dosDate: number = u16(cd, at + 14);
    const crc32: number = u32(cd, at + 16);
    const compressedSize: number = u32(cd, at + 20);
    const size: number = u32(cd, at + 24);
    const nameLen: number = u16(cd, at + 28);
    const extraLen: number = u16(cd, at + 30);
    const commentLen: number = u16(cd, at + 32);
    const localOffset: number = u32(cd, at + 42);
    const next: number = at + 46 + nameLen + extraLen + commentLen;
    if (next > cd.length) {
      throw new Error('Truncated ZIP central directory');
    }
    if (compressedSize === ZIP64_MARK || size === ZIP64_MARK ||
        localOffset === ZIP64_MARK) {
      throw new Error('Zip64 archives are not supported');
    }
    const nameBytes: Uint8Array = cd.subarray(at + 46, at + 46 + nameLen);
    const name: string = (flags & 0x800) !== 0
      ? decodeUtf8(nameBytes)
      : decodeZipName(nameBytes);
    if (isSafeName(name)) {
      const isDir: boolean = name.endsWith('/');
      out.push(new ZipEntryInfo(name, isDir, compressedSize, size, crc32,
        method, dosTime, dosDate, localOffset));
    }
    at = next;
  }
  return out;
}

function virtualPath(dir: string, name: string): string {
  return dir === '/' ? '/' + name : dir + '/' + name;
}

/**
 * One directory level of an archive. `dir` is an in-archive path such as
 * '/', '/src' or '/src/lib'.
 */
export function listArchiveDirectory(entries: Array<ZipEntryInfo>,
                                     dir: string): Array<FileEntry> {
  const normalized: string = dir === '' ? '/' : dir;
  const prefix: string = normalized === '/' ? '' :
    (normalized.endsWith('/') ? normalized.substring(1)
      : normalized.substring(1) + '/');
  const folders: Array<FileEntry> = [];
  const files: Array<FileEntry> = [];
  for (let i = 0; i < entries.length; i++) {
    const info: ZipEntryInfo = entries[i];
    if (prefix.length > 0 && !info.name.startsWith(prefix)) {
      continue;
    }
    const rest: string = prefix.length > 0 ? info.name.substring(prefix.length)
      : info.name;
    if (rest.length === 0) {
      continue;
    }
    const slash: number = rest.indexOf('/');
    if (slash >= 0) {
      const folderName: string = rest.substring(0, slash);
      if (folderName.length === 0) {
        continue;
      }
      let known: boolean = false;
      for (let f = 0; f < folders.length; f++) {
        if (folders[f].name === folderName) {
          known = true;
          const stamp: number = info.mtimeSeconds();
          if (stamp > folders[f].mtime) {
            folders[f].mtime = stamp;
          }
          break;
        }
      }
      if (!known) {
        folders.push(new FileEntry(folderName,
          virtualPath(normalized, folderName), true, false, 0,
          info.mtimeSeconds(), 0o040755, 0, 0, '', '', 'zip'));
      }
      continue;
    }
    files.push(new FileEntry(rest, virtualPath(normalized, rest), false,
      false, info.size, info.mtimeSeconds(), 0o100644, 0, 0, '', '', 'zip'));
  }
  return folders.concat(files);
}

/**
 * Expands selected archive-relative names so a selected folder brings all of
 * its descendants. Names passed back to @ohos.zlib keep their zip spelling.
 */
export function expandArchiveNames(entries: Array<ZipEntryInfo>,
                                   selected: Array<string>):
    Array<string> {
  const out: Array<string> = [];
  for (let s = 0; s < selected.length; s++) {
    const name: string = selected[s];
    const folderPrefix: string = name.endsWith('/') ? name : name + '/';
    let isFolder: boolean = name.endsWith('/');
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].name === name || entries[i].name === folderPrefix) {
        isFolder = true;
        break;
      }
    }
    for (let i = 0; i < entries.length; i++) {
      const candidate: string = entries[i].name;
      if (candidate === name ||
          (isFolder && candidate.startsWith(folderPrefix))) {
        if (out.indexOf(candidate) < 0) {
          out.push(candidate);
        }
      }
    }
  }
  return out;
}

export function archiveRootParent(dir: string): string {
  const normalized: string = dir === '' ? '/' : dir;
  if (normalized === '/') {
    return '/';
  }
  const index: number = normalized.lastIndexOf('/');
  return index <= 0 ? '/' : normalized.substring(0, index);
}
