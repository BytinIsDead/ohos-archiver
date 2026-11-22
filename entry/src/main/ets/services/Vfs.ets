/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Virtual filesystem exposed to the browser: '/' lists the named mounts,
 * each mount maps a stable virtual prefix onto a real directory.
 */

import fs from '@ohos.file.fs';
import environment from '@ohos.file.environment';
import { FileEntry } from '../core/fs/FileEntry';
import { baseName, normalizePath, parentPath } from '../core/fs/PathUtil';
import { Logger } from '../common/Logger';

const TAG: string = 'Vfs';

export class Mount {
  path: string;
  root: string;
  label: string;

  constructor(path: string, root: string, label: string) {
    this.path = path;
    this.root = root;
    this.label = label;
  }
}

function mountEntry(mount: Mount): FileEntry {
  return new FileEntry(mount.label, mount.path, true, false, 0, 0,
    0o040755, 0, 0, '', '', 'mount');
}

export class Vfs {
  private sandbox: string;
  private mounts: Array<Mount> = [];

  constructor(sandbox: string) {
    this.sandbox = sandbox;
    this.initMounts();
  }

  private initMounts(): void {
    this.mounts.push(new Mount('/sandbox', this.sandbox, 'Sandbox'));
    try {
      this.mounts.push(new Mount('/download',
        environment.getUserDownloadDir(), 'Download'));
    } catch (err) {
      Logger.warn(TAG, 'Download unavailable (permission not granted)');
    }
    try {
      this.mounts.push(new Mount('/documents',
        environment.getUserDocumentDir(), 'Documents'));
    } catch (err) {
      Logger.warn(TAG, 'Documents unavailable (permission not granted)');
    }
  }

  mountPaths(): Array<string> {
    const out: Array<string> = [];
    for (let i = 0; i < this.mounts.length; i++) {
      out.push(this.mounts[i].path);
    }
    return out;
  }

  mountFor(vpath: string): Mount | null {
    const path: string = normalizePath(vpath);
    let best: Mount | null = null;
    for (let i = 0; i < this.mounts.length; i++) {
      const mount: Mount = this.mounts[i];
      if (path === mount.path || path.startsWith(mount.path + '/')) {
        if (best === null || mount.path.length > best.path.length) {
          best = mount;
        }
      }
    }
    return best;
  }

  real(vpath: string): string {
    const path: string = normalizePath(vpath);
    const mount: Mount | null = this.mountFor(path);
    if (mount === null) {
      return '';
    }
    if (path === mount.path) {
      return mount.root;
    }
    return mount.root + path.substring(mount.path.length);
  }

  exists(vpath: string): boolean {
    const real: string = this.real(vpath);
    if (real === '') {
      return false;
    }
    try {
      return fs.accessSync(real);
    } catch (err) {
      return false;
    }
  }

  isDir(vpath: string): boolean {
    if (normalizePath(vpath) === '/') {
      return true;
    }
    const real: string = this.real(vpath);
    if (real === '') {
      return false;
    }
    try {
      return fs.statSync(real).isDirectory();
    } catch (err) {
      return false;
    }
  }

  private entryFor(childPath: string, real: string, name: string,
                   origin: string): FileEntry {
    let isDir: boolean = false;
    let isLink: boolean = false;
    let size: number = 0;
    let mtime: number = 0;
    let mode: number = 0;
    let uid: number = 0;
    let gid: number = 0;
    try {
      const stat: fs.Stat = fs.statSync(real);
      isDir = stat.isDirectory();
      isLink = stat.isSymbolicLink();
      size = isDir ? 0 : stat.size;
      mtime = stat.mtime;
      mode = stat.mode;
      uid = stat.uid;
      gid = stat.gid;
    } catch (err) {
      Logger.warn(TAG, `stat failed: ${real}`);
    }
    return new FileEntry(name, childPath, isDir, isLink, size, mtime,
      mode, uid, gid, '', '', origin);
  }

  list(vpath: string): Array<FileEntry> {
    const path: string = normalizePath(vpath);
    if (path === '/') {
      const roots: Array<FileEntry> = [];
      for (let i = 0; i < this.mounts.length; i++) {
        roots.push(mountEntry(this.mounts[i]));
      }
      return roots;
    }
    const real: string = this.real(path);
    if (real === '') {
      return [];
    }
    let names: Array<string> = [];
    try {
      names = fs.listFileSync(real);
    } catch (err) {
      Logger.warn(TAG, `list failed: ${real}`);
      return [];
    }
    const out: Array<FileEntry> = [];
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      const childPath: string = path === '/' ? '/' + name : path + '/' + name;
      out.push(this.entryFor(childPath, real + '/' + name, name, 'local'));
    }
    return out;
  }

  mkdir(vpath: string): void {
    const real: string = this.real(vpath);
    if (real === '' || fs.accessSync(real)) {
      return;
    }
    fs.mkdirSync(real);
  }

  removeRecursive(vpath: string): void {
    const real: string = this.real(vpath);
    if (real === '' || normalizePath(vpath) === '/' ||
        this.isMountRoot(vpath)) {
      return;
    }
    this.removeTree(real);
  }

  private removeTree(real: string): void {
    if (fs.statSync(real).isDirectory()) {
      const names: Array<string> = fs.listFileSync(real);
      for (let i = 0; i < names.length; i++) {
        this.removeTree(real + '/' + names[i]);
      }
      fs.rmdirSync(real);
    } else {
      fs.unlinkSync(real);
    }
  }

  isMountRoot(vpath: string): boolean {
    const path: string = normalizePath(vpath);
    for (let i = 0; i < this.mounts.length; i++) {
      if (this.mounts[i].path === path) {
        return true;
      }
    }
    return false;
  }

  /** First unused "name", "name (1)", "name (2)" inside destDir. */
  private uniqueTarget(destDirV: string, name: string): FileEntry {
    const existsName = (candidate: string): boolean =>
      this.exists(destDirV === '/' ? '/' + candidate : destDirV + '/' + candidate);
    if (!existsName(name)) {
      return new FileEntry(name, '', false, false, 0, 0, 0, 0, 0, '', '', 'local');
    }
    let stem: string = name;
    let ext: string = '';
    const dot: number = name.lastIndexOf('.');
    if (dot > 0) {
      stem = name.substring(0, dot);
      ext = name.substring(dot);
    }
    let n: number = 1;
    while (n < 1000) {
      const candidate: string = `${stem} (${n})${ext}`;
      if (!existsName(candidate)) {
        return new FileEntry(candidate, '', false, false, 0, 0, 0, 0, 0,
          '', '', 'local');
      }
      n++;
    }
    return new FileEntry(`${stem}-${Date.now()}${ext}`, '', false, false,
      0, 0, 0, 0, 0, '', '', 'local');
  }

  copyRecursive(realSrc: string, realDst: string): void {
    const stat: fs.Stat = fs.statSync(realSrc);
    if (stat.isDirectory()) {
      if (!fs.accessSync(realDst)) {
        fs.mkdirSync(realDst);
      }
      const names: Array<string> = fs.listFileSync(realSrc);
      for (let i = 0; i < names.length; i++) {
        this.copyRecursive(realSrc + '/' + names[i], realDst + '/' + names[i]);
      }
    } else {
      fs.copyFileSync(realSrc, realDst);
    }
  }

  /** Copies a path into destDir, picking a non-clashing name. */
  copyInto(srcV: string, destDirV: string): string {
    const srcReal: string = this.real(srcV);
    const destDirReal: string = this.real(destDirV);
    if (srcReal === '' || destDirReal === '') {
      return '';
    }
    if (!this.isDir(destDirV)) {
      return '';
    }
    const target: FileEntry = this.uniqueTarget(destDirV, baseName(srcV));
    const destReal: string = destDirReal + '/' + target.name;
    this.copyRecursive(srcReal, destReal);
    return target.name;
  }

  moveInto(srcV: string, destDirV: string): string {
    const srcReal: string = this.real(srcV);
    const destDirReal: string = this.real(destDirV);
    if (srcReal === '' || destDirReal === '') {
      return '';
    }
    if (normalizePath(srcV) === '/' || this.isMountRoot(srcV) ||
        normalizePath(parentPath(srcV)) === normalizePath(destDirV)) {
      return '';
    }
    const target: FileEntry = this.uniqueTarget(destDirV, baseName(srcV));
    const destReal: string = destDirReal + '/' + target.name;
    try {
      fs.renameSync(srcReal, destReal);
    } catch (err) {
      this.copyRecursive(srcReal, destReal);
      this.removeTree(srcReal);
    }
    return target.name;
  }

  rename(vpath: string, newName: string): string {
    const name: string = newName.trim();
    if (name === '' || name.indexOf('/') >= 0 || normalizePath(vpath) === '/' ||
        this.isMountRoot(vpath)) {
      return '';
    }
    const parent: string = parentPath(vpath);
    const target: FileEntry = this.uniqueTarget(parent, name);
    const srcReal: string = this.real(vpath);
    const destReal: string = this.real(parent) + '/' + target.name;
    fs.renameSync(srcReal, destReal);
    return target.name;
  }

  isZip(vpath: string): boolean {
    return baseName(vpath).toLowerCase().endsWith('.zip');
  }
}
