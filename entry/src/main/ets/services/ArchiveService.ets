/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * ZIP access: metadata comes from a ranged read of the central directory,
 * extraction and creation use the system zlib archive helpers.
 */

import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import {
  EocdInfo,
  ZipEntryInfo,
  findEocd,
  parseCentralDirectory
} from '../core/zip/ZipReader';
import { Logger } from '../common/Logger';

const TAG: string = 'ArchiveService';
const EOCD_WINDOW: number = 22 + 65535;

export class ArchiveHandle {
  realPath: string;
  entries: Array<ZipEntryInfo>;
  comment: string;

  constructor(realPath: string, entries: Array<ZipEntryInfo>,
              comment: string) {
    this.realPath = realPath;
    this.entries = entries;
    this.comment = comment;
  }
}

function ensureDir(real: string): void {
  if (fs.accessSync(real)) {
    return;
  }
  try {
    fs.mkdirSync(real, true);
  } catch (err) {
    if (!fs.accessSync(real)) {
      throw err as Error;
    }
  }
}

function removeTree(real: string): void {
  if (!fs.accessSync(real)) {
    return;
  }
  if (fs.statSync(real).isDirectory()) {
    const names: Array<string> = fs.listFileSync(real);
    for (let i = 0; i < names.length; i++) {
      removeTree(real + '/' + names[i]);
    }
    fs.rmdirSync(real);
  } else {
    fs.unlinkSync(real);
  }
}

function copyTree(src: string, dst: string): void {
  if (fs.statSync(src).isDirectory()) {
    ensureDir(dst);
    const names: Array<string> = fs.listFileSync(src);
    for (let i = 0; i < names.length; i++) {
      copyTree(src + '/' + names[i], dst + '/' + names[i]);
    }
  } else {
    fs.copyFileSync(src, dst);
  }
}

export class ArchiveService {
  static async open(archiveReal: string): Promise<ArchiveHandle> {
    const stat: fs.Stat = fs.statSync(archiveReal);
    if (!stat.isFile()) {
      throw new Error('Not a file');
    }
    const fileSize: number = stat.size;
    if (fileSize < 22) {
      throw new Error('Not a ZIP archive');
    }
    const tailLen: number = Math.min(fileSize, EOCD_WINDOW);
    const file: fs.File = fs.openSync(archiveReal, fs.OpenMode.READ_ONLY);
    const fd: number = file.fd;
    try {
      const tailBuf: ArrayBuffer = new ArrayBuffer(tailLen);
      fs.lseek(fd, fileSize - tailLen, fs.WhenceType.SEEK_SET);
      const tailRead: number = fs.readSync(fd, tailBuf);
      const eocd: EocdInfo | null =
        findEocd(new Uint8Array(tailBuf, 0, tailRead), fileSize - tailLen,
          fileSize);
      if (eocd === null) {
        throw new Error('Not a ZIP archive');
      }
      let entries: Array<ZipEntryInfo> = [];
      if (eocd.cdSize > 0) {
        const cdBuf: ArrayBuffer = new ArrayBuffer(eocd.cdSize);
        fs.lseek(fd, eocd.cdOffset, fs.WhenceType.SEEK_SET);
        const cdRead: number = fs.readSync(fd, cdBuf);
        if (cdRead !== eocd.cdSize) {
          throw new Error('Truncated ZIP central directory');
        }
        entries = parseCentralDirectory(new Uint8Array(cdBuf));
        if (entries.length === 0 && eocd.entryCount > 0) {
          throw new Error('Unreadable ZIP central directory');
        }
      }
      return new ArchiveHandle(archiveReal, entries, eocd.comment);
    } finally {
      fs.closeSync(file);
    }
  }

  static async extractAll(archiveReal: string, destReal: string):
      Promise<void> {
    ensureDir(destReal);
    await zlib.decompressFile(archiveReal, destReal);
  }

  /**
   * Extracts to a private temp dir, then copies only the requested entries.
   * `names` are archive-relative, folders end with '/'.
   */
  static async extractSelected(archiveReal: string, destReal: string,
                               names: Array<string>, cacheReal: string):
      Promise<void> {
    if (names.length === 0) {
      return;
    }
    ensureDir(destReal);
    const temp: string = `${cacheReal}/unzip-${Date.now()}`;
    ensureDir(temp);
    try {
      await zlib.decompressFile(archiveReal, temp);
      for (let i = 0; i < names.length; i++) {
        let rel: string = names[i];
        if (rel.endsWith('/')) {
          rel = rel.substring(0, rel.length - 1);
        }
        if (rel.length === 0) {
          continue;
        }
        const src: string = `${temp}/${rel}`;
        if (!fs.accessSync(src)) {
          continue;
        }
        const parentIndex: number = rel.lastIndexOf('/');
        if (parentIndex > 0) {
          ensureDir(`${destReal}/${rel.substring(0, parentIndex)}`);
        }
        copyTree(src, `${destReal}/${rel}`);
      }
    } finally {
      try {
        removeTree(temp);
      } catch (err) {
        Logger.warn(TAG, 'temp cleanup failed');
      }
    }
  }

  static async createZip(sourcesReal: Array<string>, destReal: string):
      Promise<void> {
    if (sourcesReal.length === 0) {
      throw new Error('Nothing to compress');
    }
    const options: zlib.Options = {
      level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
    };
    if (sourcesReal.length === 1) {
      await zlib.compressFile(sourcesReal[0], destReal, options);
    } else {
      await zlib.compressFiles(sourcesReal, destReal, options);
    }
  }
}
