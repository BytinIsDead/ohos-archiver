/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * File browser and ZIP manager. The list follows the ZArchiver layout:
 * breadcrumbs on top, name/size/age columns, a persistent action bar and
 * an in-archive browsing mode.
 */

import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import { Logger } from '../common/Logger';
import { requestStorage } from '../common/Permissions';
import { FileEntry } from '../core/fs/FileEntry';
import {
  baseName,
  joinPath,
  parentPath,
  pathSegments,
  resolvePath
} from '../core/fs/PathUtil';
import {
  filterEntries,
  humanSize,
  relativeAge,
  sortEntries
} from '../core/fs/Format';
import {
  archiveRootParent,
  expandArchiveNames,
  listArchiveDirectory
} from '../core/zip/ZipReader';
import { Paths } from '../services/Paths';
import { Vfs } from '../services/Vfs';
import { ArchiveHandle, ArchiveService } from '../services/ArchiveService';

const TAG: string = 'Browser';
const BG: string = '#12161f';
const CARD: string = '#1a2130';
const BAR: string = '#161c28';
const TEXT: string = '#e6edf3';
const MUTED: string = '#8b98a9';
const ACCENT: string = '#f0b429';
const SELECTED_BG: string = '#2a3446';
const BORDER: string = '#232c3d';

class Crumb {
  label: string;
  path: string;

  constructor(label: string, path: string) {
    this.label = label;
    this.path = path;
  }
}

@Entry
@Component
struct Index {
  private vfs: Vfs | null = null;
  private archive: ArchiveHandle | null = null;
  private extractZipPath: string = '';

  @State cwd: string = '/';
  @State entries: Array<FileEntry> = [];
  @State query: string = '';
  @State sortKey: string = 'name';
  @State ascending: boolean = true;
  @State selecting: boolean = false;
  @State selected: Array<string> = [];
  @State status: string = '';
  @State busy: boolean = false;

  @State archivePath: string = '';
  @State archiveDir: string = '/';

  @State dialogMode: string = '';
  @State dialogTitle: string = '';
  @State dialogHint: string = '';
  @State dialogValue: string = '';

  @State clipboard: Array<string> = [];
  @State clipboardMode: string = '';

  aboutToAppear(): void {
    this.boot();
  }

  private async boot(): Promise<void> {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>(Paths.CONTEXT);
    if (context !== undefined) {
      await requestStorage(context);
    }
    this.vfs = new Vfs(Paths.filesDir());
    this.refresh();
    this.status = 'Pick a folder or open a ZIP archive';
  }

  private toast(message: string): void {
    try {
      promptAction.showToast({ message: message, duration: 2000 });
    } catch (err) {
      Logger.warn(TAG, 'toast failed');
    }
  }

  private refresh(): void {
    const vfs: Vfs | null = this.vfs;
    if (vfs === null) {
      return;
    }
    this.entries = vfs.list(this.cwd);
  }

  private navigate(path: string): void {
    this.cwd = path;
    this.query = '';
    this.selected = [];
    this.selecting = false;
    this.refresh();
  }

  private inArchive(): boolean {
    return this.archive !== null;
  }

  private visibleEntries(): Array<FileEntry> {
    const archive: ArchiveHandle | null = this.archive;
    const source: Array<FileEntry> = archive === null ? this.entries
      : listArchiveDirectory(archive.entries, this.archiveDir);
    const filtered: Array<FileEntry> = filterEntries(source, this.query);
    return sortEntries(filtered, this.sortKey, this.ascending, true);
  }

  private crumbs(): Array<Crumb> {
    const out: Array<Crumb> = [];
    if (this.archive !== null) {
      out.push(new Crumb(baseName(this.archivePath), '/'));
      let acc: string = '';
      const segments: Array<string> = pathSegments(this.archiveDir);
      for (let i = 0; i < segments.length; i++) {
        acc = acc + '/' + segments[i];
        out.push(new Crumb(segments[i], acc));
      }
      return out;
    }
    out.push(new Crumb('/', '/'));
    let acc: string = '';
    const segments: Array<string> = pathSegments(this.cwd);
    for (let i = 0; i < segments.length; i++) {
      acc = acc + '/' + segments[i];
      out.push(new Crumb(segments[i], acc));
    }
    return out;
  }

  private sortMark(key: string): string {
    if (this.sortKey !== key) {
      return '';
    }
    return this.ascending ? ' \u2191' : ' \u2193';
  }

  private toggleSort(key: string): void {
    if (this.sortKey === key) {
      this.ascending = !this.ascending;
    } else {
      this.sortKey = key;
      this.ascending = true;
    }
  }

  private isSelected(path: string): boolean {
    return this.selected.indexOf(path) >= 0;
  }

  private selectedEntries(): Array<FileEntry> {
    const visible: Array<FileEntry> = this.visibleEntries();
    const out: Array<FileEntry> = [];
    for (let i = 0; i < visible.length; i++) {
      if (this.isSelected(visible[i].path)) {
        out.push(visible[i]);
      }
    }
    return out;
  }

  private toggleSelected(entry: FileEntry): void {
    const copy: Array<string> = this.selected.slice();
    const index: number = copy.indexOf(entry.path);
    if (index >= 0) {
      copy.splice(index, 1);
    } else {
      copy.push(entry.path);
    }
    this.selected = copy;
  }

  private selectAll(): void {
    const visible: Array<FileEntry> = this.visibleEntries();
    const copy: Array<string> = this.selected.slice();
    for (let i = 0; i < visible.length; i++) {
      if (copy.indexOf(visible[i].path) < 0) {
        copy.push(visible[i].path);
      }
    }
    this.selected = copy;
    if (copy.length === 0) {
      this.toast('Nothing to select');
    }
  }

  private clearSelection(): void {
    this.selected = [];
    this.selecting = false;
  }

  private onRowTap(entry: FileEntry): void {
    if (this.selecting) {
      this.toggleSelected(entry);
      return;
    }
    this.openEntry(entry);
  }

  private openEntry(entry: FileEntry): void {
    if (this.inArchive()) {
      if (entry.isDir) {
        this.archiveDir = entry.path;
        this.query = '';
      } else {
        this.toast('Extract the archive to open files');
      }
      return;
    }
    if (entry.isDir) {
      this.navigate(entry.path);
      return;
    }
    const vfs: Vfs | null = this.vfs;
    if (vfs !== null && vfs.isZip(entry.path)) {
      this.openArchive(entry.path);
    } else {
      this.toast('No viewer for this file');
    }
  }

  private goUp(): void {
    if (this.inArchive()) {
      if (this.archiveDir === '/') {
        this.closeArchive();
      } else {
        this.archiveDir = archiveRootParent(this.archiveDir);
        this.query = '';
      }
      return;
    }
    if (this.cwd === '/') {
      this.toast('Already at the mount root');
      return;
    }
    this.navigate(parentPath(this.cwd));
  }

  private async openArchive(path: string): Promise<void> {
    const vfs: Vfs | null = this.vfs;
    if (vfs === null) {
      return;
    }
    this.busy = true;
    this.status = 'Reading archive…';
    try {
      const handle: ArchiveHandle =
        await ArchiveService.open(vfs.real(path));
      this.archive = handle;
      this.archivePath = path;
      this.archiveDir = '/';
      this.query = '';
      this.selected = [];
      this.selecting = false;
      this.status = `${handle.entries.length} entries`;
    } catch (err) {
      this.toast((err as Error).message);
      this.status = 'Not a readable ZIP archive';
    } finally {
      this.busy = false;
    }
  }

  private async reloadArchive(): Promise<void> {
    const path: string = this.archivePath;
    if (path.length > 0) {
      await this.openArchive(path);
    }
  }

  private closeArchive(): void {
    this.archive = null;
    this.archivePath = '';
    this.archiveDir = '/';
    this.selected = [];
    this.selecting = false;
    this.query = '';
    this.refresh();
    this.status = `Back in ${this.cwd}`;
  }

  private ensureVdir(path: string): void {
    const vfs: Vfs | null = this.vfs;
    if (vfs === null) {
      return;
    }
    const segments: Array<string> = pathSegments(path);
    let acc: string = '';
    for (let i = 0; i < segments.length; i++) {
      acc = acc + '/' + segments[i];
      vfs.mkdir(acc);
    }
  }

  private promptCreateFolder(): void {
    this.dialogMode = 'mkdir';
    this.dialogTitle = 'New folder';
    this.dialogHint = 'Name';
    this.dialogValue = '';
  }

  private promptZip(): void {
    if (this.inArchive()) {
      this.toast('Leave the archive first');
      return;
    }
    if (this.selected.length === 0) {
      this.toast('Select files to compress');
      return;
    }
    this.dialogMode = 'zip';
    this.dialogTitle = 'Create ZIP';
    this.dialogHint = 'Archive name';
    this.dialogValue = 'archive.zip';
  }

  private promptRename(): void {
    if (this.inArchive()) {
      this.toast('Archive entries are read-only');
      return;
    }
    const sel: Array<FileEntry> = this.selectedEntries();
    if (sel.length !== 1) {
      this.toast('Select exactly one item');
      return;
    }
    this.dialogMode = 'rename';
    this.dialogTitle = 'Rename';
    this.dialogHint = 'New name';
    this.dialogValue = sel[0].name;
  }

  private promptDelete(): void {
    if (this.inArchive()) {
      this.toast('Archive entries are read-only');
      return;
    }
    if (this.selected.length === 0) {
      this.toast('Select items to delete');
      return;
    }
    this.dialogMode = 'delete';
    this.dialogTitle = 'Delete';
    this.dialogHint = `Delete ${this.selected.length} item(s)? ` +
      'This cannot be undone.';
    this.dialogValue = '';
  }

  private promptExtract(): void {
    const vfs: Vfs | null = this.vfs;
    if (vfs === null) {
      return;
    }
    this.extractZipPath = '';
    if (this.inArchive()) {
      const sel: Array<FileEntry> = this.selectedEntries();
      const stem: string = this.zipStem(baseName(this.archivePath));
      this.dialogValue = joinPath(parentPath(this.archivePath), stem);
      this.dialogTitle = sel.length > 0
        ? `Extract ${sel.length} selected` : 'Extract archive';
    } else {
      const sel: Array<FileEntry> = this.selectedEntries();
      let zipPath: string = '';
      if (sel.length === 1 && !sel[0].isDir && vfs.isZip(sel[0].path)) {
        zipPath = sel[0].path;
      }
      if (zipPath.length === 0) {
        this.toast('Select a ZIP file first');
        return;
      }
      this.extractZipPath = zipPath;
      this.dialogValue =
        joinPath(parentPath(zipPath), this.zipStem(baseName(zipPath)));
      this.dialogTitle = 'Extract archive';
    }
    this.dialogMode = 'extract';
    this.dialogHint = 'Destination folder';
  }

  private zipStem(name: string): string {
    const lower: string = name.toLowerCase();
    return lower.endsWith('.zip') ? name.substring(0, name.length - 4)
      : name;
  }

  private copySelection(move: boolean): void {
    if (this.inArchive()) {
      this.toast('Archive entries are read-only');
      return;
    }
    if (this.selected.length === 0) {
      return;
    }
    this.clipboard = this.selected.slice();
    this.clipboardMode = move ? 'move' : 'copy';
    this.status = `${move ? 'Cut' : 'Copied'} ${this.selected.length} item(s)`;
    this.clearSelection();
  }

  private paste(): void {
    const vfs: Vfs | null = this.vfs;
    if (vfs === null || this.inArchive()) {
      return;
    }
    if (this.clipboard.length === 0) {
      return;
    }
    this.busy = true;
    try {
      let done: number = 0;
      for (let i = 0; i < this.clipboard.length; i++) {
        const source: string = this.clipboard[i];
        if (!vfs.exists(source)) {
          continue;
        }
        const name: string = this.clipboardMode === 'move'
          ? vfs.moveInto(source, this.cwd)
          : vfs.copyInto(source, this.cwd);
        if (name.length > 0) {
          done++;
        }
      }
      this.status = `Pasted ${done} item(s) into ${this.cwd}`;
      this.toast(this.status);
      this.clipboard = [];
      this.clipboardMode = '';
      this.refresh();
    } catch (err) {
      this.toast(`Paste failed: ${(err as Error).message}`);
    } finally {
      this.busy = false;
    }
  }

  private async confirmDialog(): Promise<void> {
    const mode: string = this.dialogMode;
    const value: string = this.dialogValue.trim();
    this.dialogMode = '';
    const vfs: Vfs | null = this.vfs;
    if (vfs === null) {
      return;
    }
    if (mode === 'delete') {
      try {
        for (let i = 0; i < this.selected.length; i++) {
          vfs.removeRecursive(this.selected[i]);
        }
        this.status = `Deleted ${this.selected.length} item(s)`;
        this.clearSelection();
        this.refresh();
      } catch (err) {
        this.toast(`Delete failed: ${(err as Error).message}`);
      }
      return;
    }
    if (value.length === 0) {
      this.toast('Name cannot be empty');
      return;
    }
    if (mode === 'mkdir' && value.indexOf('/') >= 0) {
      this.toast('Name cannot contain /');
      return;
    }
    if (mode === 'mkdir') {
      try {
        vfs.mkdir(joinPath(this.cwd, value));
        this.status = `Created ${value}`;
        this.refresh();
      } catch (err) {
        this.toast(`Create failed: ${(err as Error).message}`);
      }
      return;
    }
    if (mode === 'rename') {
      if (value.indexOf('/') >= 0) {
        this.toast('Name cannot contain /');
        return;
      }
      try {
        const source: string = this.selected[0];
        const name: string = vfs.rename(source, value);
        this.status = name.length > 0 ? `Renamed to ${name}` : 'Rename failed';
        this.clearSelection();
        this.refresh();
      } catch (err) {
        this.toast(`Rename failed: ${(err as Error).message}`);
      }
      return;
    }
    if (mode === 'zip') {
      await this.createZip(value);
      return;
    }
    if (mode === 'extract') {
      await this.runExtract(value);
    }
  }

  private async createZip(name: string): Promise<void> {
    const vfs: Vfs | null = this.vfs;
    if (vfs === null) {
      return;
    }
    if (name.indexOf('/') >= 0) {
      this.toast('Name cannot contain /');
      return;
    }
    const zipName: string = name.toLowerCase().endsWith('.zip')
      ? name : name + '.zip';
    let dest: string = joinPath(this.cwd, zipName);
    let counter: number = 1;
    while (vfs.exists(dest)) {
      const stem: string = zipName.substring(0, zipName.length - 4);
      dest = joinPath(this.cwd, `${stem} (${counter}).zip`);
      counter++;
    }
    const sel: Array<FileEntry> = this.selectedEntries();
    const sources: Array<string> = [];
    for (let i = 0; i < sel.length; i++) {
      sources.push(vfs.real(sel[i].path));
    }
    this.busy = true;
    this.status = 'Creating archive…';
    try {
      await ArchiveService.createZip(sources, vfs.real(dest));
      this.status = `Created ${baseName(dest)}`;
      this.toast(this.status);
      this.clearSelection();
      this.refresh();
    } catch (err) {
      this.toast(`ZIP failed: ${(err as Error).message}`);
      this.status = 'ZIP creation failed';
    } finally {
      this.busy = false;
    }
  }

  private async runExtract(destInput: string): Promise<void> {
    const vfs: Vfs | null = this.vfs;
    if (vfs === null) {
      return;
    }
    const destV: string = resolvePath('/', destInput);
    const destReal: string = vfs.real(destV);
    if (destV === '/' || destReal === '') {
      this.toast('Choose a folder inside a mount');
      return;
    }
    this.busy = true;
    this.status = 'Extracting…';
    try {
      this.ensureVdir(destV);
      if (this.archive !== null) {
        const handle: ArchiveHandle = this.archive;
        const sel: Array<FileEntry> = this.selectedEntries();
        if (sel.length > 0) {
          const names: Array<string> = [];
          for (let i = 0; i < sel.length; i++) {
            names.push(sel[i].path.substring(1) +
              (sel[i].isDir ? '/' : ''));
          }
          const expanded: Array<string> =
            expandArchiveNames(handle.entries, names);
          await ArchiveService.extractSelected(handle.realPath, destReal,
            expanded, Paths.cacheDir());
          this.status = `Extracted ${sel.length} item(s) to ${destV}`;
        } else {
          await ArchiveService.extractAll(handle.realPath, destReal);
          this.status = `Extracted archive to ${destV}`;
        }
        this.clearSelection();
      } else {
        const handle: ArchiveHandle =
          await ArchiveService.open(vfs.real(this.extractZipPath));
        await ArchiveService.extractAll(handle.realPath, destReal);
        this.status = `Extracted ${baseName(this.extractZipPath)} to ${destV}`;
        this.refresh();
      }
      this.toast(this.status);
    } catch (err) {
      this.toast(`Extract failed: ${(err as Error).message}`);
      this.status = 'Extract failed';
    } finally {
      this.busy = false;
    }
  }

  @Builder
  row(entry: FileEntry) {
    Row() {
      if (this.selecting) {
        Text(this.isSelected(entry.path) ? '\u2713' : '')
          .width(26)
          .fontSize(16)
          .fontColor(ACCENT)
          .textAlign(TextAlign.Center)
      }
      Text(entry.isDir ? '\u25A0' : '\u00B7')
        .width(18)
        .fontSize(entry.isDir ? 11 : 18)
        .fontColor(entry.isDir ? ACCENT : MUTED)
        .textAlign(TextAlign.Center)
      Text(entry.isDir ? entry.name + '/' : entry.name)
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(entry.isDir ? ACCENT : TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(entry.isDir ? '\u2014' : humanSize(entry.size))
        .width(72)
        .fontSize(12)
        .fontColor(MUTED)
        .textAlign(TextAlign.End)
      Text(entry.mtime > 0 ? relativeAge(entry.mtime) : '')
        .width(46)
        .fontSize(12)
        .fontColor(MUTED)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(52)
    .padding({ left: 10, right: 12 })
    .backgroundColor(this.isSelected(entry.path) ? SELECTED_BG : CARD)
    .border({ width: { bottom: 1 }, color: BORDER })
    .onClick(() => this.onRowTap(entry))
  }

  @Builder
  barButton(label: string, enabled: boolean, action: () => void) {
    Button(label)
      .height(33)
      .fontSize(12)
      .fontColor(enabled ? TEXT : '#5c6779')
      .backgroundColor('#232c3d')
      .borderRadius(8)
      .margin({ right: 8 })
      .enabled(enabled)
      .onClick(action)
  }

  @Builder
  promptOverlay() {
    Column() {
      Column() {
        Text(this.dialogTitle)
          .fontSize(17)
          .fontColor(TEXT)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })
        if (this.dialogMode === 'delete') {
          Text(this.dialogHint)
            .fontSize(14)
            .fontColor(MUTED)
        } else {
          Text(this.dialogHint)
            .fontSize(12)
            .fontColor(MUTED)
            .margin({ bottom: 6 })
          TextInput({ text: this.dialogValue, placeholder: this.dialogHint })
            .height(42)
            .fontSize(14)
            .fontColor(TEXT)
            .backgroundColor('#12161f')
            .borderRadius(8)
            .onChange((value: string) => {
              this.dialogValue = value;
            })
        }
        Row() {
          Button('Cancel')
            .layoutWeight(1)
            .height(38)
            .fontColor(TEXT)
            .backgroundColor('#232c3d')
            .onClick(() => {
              this.dialogMode = '';
            })
          Button(this.dialogMode === 'delete' ? 'Delete' : 'OK')
            .layoutWeight(1)
            .height(38)
            .margin({ left: 10 })
            .fontColor(this.dialogMode === 'delete' ? '#ffffff' : '#12161f')
            .backgroundColor(this.dialogMode === 'delete' ? '#e5534b' : ACCENT)
            .onClick(() => {
              this.confirmDialog();
            })
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .padding(20)
      .backgroundColor('#1d2433')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#99000000')
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Button('\u2191')
            .width(36)
            .height(36)
            .fontSize(18)
            .fontColor(TEXT)
            .backgroundColor('#232c3d')
            .borderRadius(8)
            .onClick(() => this.goUp())
          Scroll() {
            Row() {
              ForEach(this.crumbs(), (crumb: Crumb) => {
                Text(crumb.label)
                  .fontSize(13)
                  .fontColor(crumb.path === (this.inArchive()
                    ? this.archiveDir : this.cwd) ? ACCENT : TEXT)
                  .maxLines(1)
                  .margin({ right: 4, left: 4 })
                  .onClick(() => {
                    if (this.inArchive()) {
                      this.archiveDir = crumb.path;
                      this.query = '';
                    } else {
                      this.navigate(crumb.path);
                    }
                  })
                Text('\u203A')
                  .fontSize(13)
                  .fontColor(MUTED)
                  .margin({ right: 2 })
              }, (crumb: Crumb) => crumb.path)
            }
            .height(36)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .margin({ left: 8, right: 4 })
          if (this.selecting) {
            Button('All')
              .height(32)
              .fontSize(12)
              .fontColor(TEXT)
              .backgroundColor('#232c3d')
              .borderRadius(8)
              .margin({ right: 6 })
              .onClick(() => this.selectAll())
            Button('Done')
              .height(32)
              .fontSize(12)
              .fontColor(ACCENT)
              .backgroundColor('#232c3d')
              .borderRadius(8)
              .onClick(() => this.clearSelection())
          } else {
            Button('\u27F3')
              .width(36)
              .height(36)
              .fontSize(16)
              .fontColor(TEXT)
              .backgroundColor('#232c3d')
              .borderRadius(8)
              .margin({ right: 6 })
              .onClick(() => {
                if (this.inArchive()) {
                  this.reloadArchive();
                } else {
                  this.refresh();
                }
              })
            if (this.inArchive()) {
              Button('\u00D7')
                .width(36)
                .height(36)
                .fontSize(18)
                .fontColor(TEXT)
                .backgroundColor('#232c3d')
                .borderRadius(8)
                .onClick(() => this.closeArchive())
            }
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 6 })

        Row() {
          TextInput({ text: this.query, placeholder: 'Filter\u2026' })
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .fontColor(TEXT)
            .placeholderColor(MUTED)
            .backgroundColor(CARD)
            .borderRadius(8)
            .onChange((value: string) => {
              this.query = value;
            })
          if (this.query.length > 0) {
            Button('\u00D7')
              .width(32)
              .height(32)
              .fontSize(14)
              .fontColor(MUTED)
              .backgroundColor('#00000000')
              .margin({ left: 6 })
              .onClick(() => {
                this.query = '';
              })
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })

        Row() {
          Text('Name' + this.sortMark('name'))
            .layoutWeight(1)
            .fontSize(12)
            .fontColor(this.sortKey === 'name' ? ACCENT : MUTED)
            .onClick(() => this.toggleSort('name'))
          Text('Size' + this.sortMark('size'))
            .width(72)
            .fontSize(12)
            .fontColor(this.sortKey === 'size' ? ACCENT : MUTED)
            .textAlign(TextAlign.End)
            .onClick(() => this.toggleSort('size'))
          Text('Age' + this.sortMark('time'))
            .width(46)
            .fontSize(12)
            .fontColor(this.sortKey === 'time' ? ACCENT : MUTED)
            .textAlign(TextAlign.End)
            .onClick(() => this.toggleSort('time'))
        }
        .width('100%')
        .padding({ left: this.selecting ? 64 : 38, right: 12, bottom: 6 })
        .backgroundColor(BAR)
        .border({ width: { top: 1, bottom: 1 }, color: BORDER })

        if (this.visibleEntries().length === 0) {
          Column() {
            Text(this.inArchive() ? 'Empty folder in archive' : 'Empty folder')
              .fontSize(14)
              .fontColor(MUTED)
            if (!this.inArchive() && this.cwd === '/' && this.entries.length < 3) {
              Text('Grant storage access to see Download and Documents')
                .fontSize(12)
                .fontColor(MUTED)
                .margin({ top: 8 })
                .textAlign(TextAlign.Center)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.visibleEntries(), (entry: FileEntry) => {
              ListItem() {
                this.row(entry)
              }
            }, (entry: FileEntry) => entry.origin + '|' + entry.path)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }

        Text(this.selected.length > 0
          ? `${this.selected.length} selected \u00B7 ${this.status}`
          : this.status)
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .fontSize(11)
          .fontColor(MUTED)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .backgroundColor(BAR)

        Scroll() {
          Row() {
            if (this.selected.length > 0) {
              this.barButton('Copy', !this.inArchive(), () => this.copySelection(false))
              this.barButton('Move', !this.inArchive(), () => this.copySelection(true))
              this.barButton('Rename', !this.inArchive(), () => this.promptRename())
              this.barButton('Delete', !this.inArchive(), () => this.promptDelete())
              this.barButton('ZIP', !this.inArchive(), () => this.promptZip())
              this.barButton('Extract', true, () => this.promptExtract())
              this.barButton('Clear', true, () => this.clearSelection())
            } else {
              this.barButton('Folder+', !this.inArchive(), () => this.promptCreateFolder())
              this.barButton('Paste', this.clipboard.length > 0 && !this.inArchive(),
                () => this.paste())
              this.barButton('ZIP', !this.inArchive(), () => this.promptZip())
              this.barButton('Extract', true, () => this.promptExtract())
              this.barButton('Select', true, () => {
                this.selecting = true;
              })
            }
          }
          .padding({ left: 10, right: 4, top: 8, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .backgroundColor(BAR)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)

      if (this.busy) {
        Column() {
          Column() {
            LoadingProgress()
              .width(42)
              .height(42)
              .color(ACCENT)
            Text('Working\u2026')
              .fontSize(13)
              .fontColor(TEXT)
              .margin({ top: 8 })
          }
          .padding(20)
          .backgroundColor('#1d2433')
          .borderRadius(14)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
      }

      if (this.dialogMode !== '') {
        this.promptOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
