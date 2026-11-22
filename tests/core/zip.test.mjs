/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  ZipEntryInfo, decodeZipName, findEocd, isSafeName,
  parseCentralDirectory, listArchiveDirectory, expandArchiveNames,
  archiveRootParent
} from '../.build/core/zip/ZipReader.ts';

function u16(buf, at, value) {
  buf[at] = value & 0xff;
  buf[at + 1] = (value >> 8) & 0xff;
}

function u32(buf, at, value) {
  buf[at] = value & 0xff;
  buf[at + 1] = (value >> 8) & 0xff;
  buf[at + 2] = (value >> 16) & 0xff;
  buf[at + 3] = (value >> 24) & 0xff;
}

function dosStamp(year, month, day, hour, minute, second) {
  return {
    date: ((year - 1980) << 9) | (month << 5) | day,
    time: (hour << 11) | (minute << 5) | Math.floor(second / 2)
  };
}

function centralEntry(name, opts = {}) {
  const nameBytes = Buffer.from(name, 'utf8');
  const extra = opts.extra ?? 0;
  const comment = opts.comment ?? '';
  const buf = Buffer.alloc(46 + nameBytes.length + extra + comment.length);
  const stamp = opts.stamp ?? dosStamp(2026, 1, 2, 3, 4, 6);
  u32(buf, 0, 0x02014b50);
  u16(buf, 4, 20);
  u16(buf, 6, 20);
  u16(buf, 8, opts.flags ?? 0x800);
  u16(buf, 10, opts.method ?? 8);
  u16(buf, 12, stamp.time);
  u16(buf, 14, stamp.date);
  u32(buf, 16, 0);
  u32(buf, 20, opts.compressedSize ?? 10);
  u32(buf, 24, opts.size ?? 100);
  u16(buf, 28, nameBytes.length);
  u16(buf, 30, extra);
  u16(buf, 32, comment.length);
  u16(buf, 34, 0);
  u16(buf, 36, 0);
  u32(buf, 38, opts.attrs ?? 0);
  u32(buf, 42, opts.localOffset ?? 0);
  nameBytes.copy(buf, 46);
  if (comment.length > 0) {
    Buffer.from(comment, 'utf8').copy(buf, 46 + nameBytes.length + extra);
  }
  return buf;
}

function eocdBytes(count, cdSize, cdOffset, comment = '') {
  const commentBytes = Buffer.from(comment, 'utf8');
  const buf = Buffer.alloc(22 + commentBytes.length);
  u32(buf, 0, 0x06054b50);
  u16(buf, 4, 0);
  u16(buf, 6, 0);
  u16(buf, 8, count);
  u16(buf, 10, count);
  u32(buf, 12, cdSize);
  u32(buf, 16, cdOffset);
  u16(buf, 20, commentBytes.length);
  commentBytes.copy(buf, 22);
  return buf;
}

function buildZip(entryBuffers, comment = '') {
  const cd = Buffer.concat(entryBuffers);
  const cdOffset = 12;
  const eocd = eocdBytes(entryBuffers.length, cd.length, cdOffset, comment);
  return {
    bytes: Buffer.concat([Buffer.alloc(cdOffset), cd, eocd]),
    cdOffset,
    cdSize: cd.length
  };
}

test('findEocd locates the record and decodes the comment', () => {
  const zip = buildZip([centralEntry('a.txt')], 'hello');
  const tail = new Uint8Array(zip.bytes);
  const info = findEocd(tail, 0, zip.bytes.length);
  assert.ok(info);
  assert.equal(info.cdOffset, zip.cdOffset);
  assert.equal(info.cdSize, zip.cdSize);
  assert.equal(info.entryCount, 1);
  assert.equal(info.comment, 'hello');
});

test('findEocd tolerates prefixed tails and rejects truncated input', () => {
  const zip = buildZip([centralEntry('a.txt')]);
  const prefixed = Buffer.concat([Buffer.from('noise'), zip.bytes]);
  const tail = new Uint8Array(prefixed);
  const offset = prefixed.length - zip.bytes.length;
  const info = findEocd(tail, offset, prefixed.length);
  assert.ok(info);
  assert.equal(info.cdOffset, zip.cdOffset);
  assert.equal(findEocd(new Uint8Array(10), 0, 100), null);
});

test('Zip64 markers are rejected explicitly', () => {
  const cd = centralEntry('big.bin', { compressedSize: 0xffffffff });
  assert.throws(() => parseCentralDirectory(new Uint8Array(cd)), /Zip64/);
  const zip64Eocd = eocdBytes(0xffff, 0, 0);
  assert.throws(() => findEocd(new Uint8Array(zip64Eocd), 0,
    zip64Eocd.length), /Zip64/);
});

test('parseCentralDirectory extracts metadata and skips unsafe paths', () => {
  const zip = buildZip([
    centralEntry('src/'),
    centralEntry('src/main.txt', { size: 42, compressedSize: 20, localOffset: 8 }),
    centralEntry('../evil.sh'),
    centralEntry('Ünïcode/naïve.txt', { size: 7, compressedSize: 7, method: 0 })
  ]);
  const cd = zip.bytes.subarray(zip.cdOffset, zip.cdOffset + zip.cdSize);
  const entries = parseCentralDirectory(new Uint8Array(cd));
  assert.equal(entries.length, 3);
  assert.equal(entries[0].name, 'src/');
  assert.equal(entries[0].isDir, true);
  assert.equal(entries[1].name, 'src/main.txt');
  assert.equal(entries[1].size, 42);
  assert.equal(entries[1].compressedSize, 20);
  assert.equal(entries[1].localHeaderOffset, 8);
  assert.equal(entries[2].name, 'Ünïcode/naïve.txt');
  assert.ok(entries[1].mtimeSeconds() > 0);
});

test('parseCentralDirectory throws on a truncated directory', () => {
  const cd = centralEntry('a.txt', { extra: 4 });
  assert.throws(() => parseCentralDirectory(new Uint8Array(cd.subarray(0, 50))),
    /Truncated/);
});

test('listArchiveDirectory builds folder and file rows per level', () => {
  const zip = buildZip([
    centralEntry('src/'),
    centralEntry('src/main.txt', { size: 42 }),
    centralEntry('src/lib/util.js', { size: 9 }),
    centralEntry('README.md', { size: 5 })
  ]);
  const entries = parseCentralDirectory(
    new Uint8Array(zip.bytes.subarray(zip.cdOffset,
      zip.cdOffset + zip.cdSize)));

  const root = listArchiveDirectory(entries, '/');
  assert.deepEqual(root.map(e => e.name), ['src', 'README.md']);
  assert.equal(root[0].isDir, true);
  assert.equal(root[0].path, '/src');
  assert.equal(root[1].size, 5);

  const src = listArchiveDirectory(entries, '/src');
  assert.deepEqual(src.map(e => e.name), ['lib', 'main.txt']);
  assert.equal(src[0].path, '/src/lib');

  const lib = listArchiveDirectory(entries, '/src/lib');
  assert.deepEqual(lib.map(e => e.name), ['util.js']);
});

test('expandArchiveNames pulls in a selected folder and dedupes', () => {
  const entries = [
    new ZipEntryInfo('src/', true, 0, 0, 0, 0, 0, 0, 0),
    new ZipEntryInfo('src/a.txt', false, 1, 1, 0, 0, 0, 0, 0),
    new ZipEntryInfo('src/lib/b.txt', false, 1, 1, 0, 0, 0, 0, 0),
    new ZipEntryInfo('other.txt', false, 1, 1, 0, 0, 0, 0, 0)
  ];
  assert.deepEqual(expandArchiveNames(entries, ['src/', 'src/a.txt']),
    ['src/', 'src/a.txt', 'src/lib/b.txt']);
  assert.deepEqual(expandArchiveNames(entries, ['other.txt']), ['other.txt']);
  assert.deepEqual(expandArchiveNames(entries, ['src']),
    ['src/', 'src/a.txt', 'src/lib/b.txt']);
});

test('decodeZipName handles UTF-8 and legacy high bytes', () => {
  assert.equal(decodeZipName(new Uint8Array([0x2f, 0x61])), '/a');
  assert.equal(decodeZipName(new Uint8Array(
    [0xc3, 0x9c, 0x6e, 0x69])), 'Üni');
  assert.equal(decodeZipName(new Uint8Array([0x41, 0xe9])), 'Aé');
  assert.equal(decodeZipName(new Uint8Array([0x41, 0xc3])), 'AÃ');
});

test('isSafeName blocks traversal and absolute paths', () => {
  assert.equal(isSafeName('a/b.txt'), true);
  assert.equal(isSafeName('a/../b.txt'), false);
  assert.equal(isSafeName('/etc/passwd'), false);
  assert.equal(isSafeName('a\\b.txt'), false);
  assert.equal(isSafeName(''), false);
});

test('archiveRootParent walks back to the archive root', () => {
  assert.equal(archiveRootParent('/a/b'), '/a');
  assert.equal(archiveRootParent('/a'), '/');
  assert.equal(archiveRootParent('/'), '/');
});
