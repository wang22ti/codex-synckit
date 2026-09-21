import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { DatabaseSync } from 'node:sqlite';

const source = fs.readFileSync(path.join(import.meta.dirname, '..', 'Repair-CodexThreadCatalog.mjs'), 'utf8');
// Exercise the production reconciler without invoking unrelated rollout imports.
const start = source.indexOf('function reconcileSidebarSections(');
const end = source.indexOf('\nasync function main()', start);
const context = vm.createContext({ fs, path, process, console });
vm.runInContext(source.slice(start, end), context);
const reconcile = context.reconcileSidebarSections;
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-sidebar-native-'));
const dbPath = path.join(work, 'state.sqlite');
const statePath = path.join(work, 'state.json');
const db = new DatabaseSync(dbPath);
const section = '11111111-1111-4111-8111-111111111111';
const field = 'sidebar-custom-sections-v3';
try {
  db.exec('CREATE TABLE thread_sections(id TEXT PRIMARY KEY,name TEXT NOT NULL); CREATE TABLE threads(id TEXT PRIMARY KEY,thread_section_id TEXT,section_position INTEGER,section_entered_at_ms INTEGER,is_pinned INTEGER DEFAULT 0);');
  db.exec("INSERT INTO threads(id) VALUES ('task-one'),('task-two'); INSERT INTO thread_sections VALUES ('unrelated','Unrelated');");
  const write = name => fs.writeFileSync(statePath, JSON.stringify({
    'device-only': 'preserve', 'electron-persisted-atom-state': { [field]: { account: {
      sections: [{ id: section, name, itemKeys: ['codex:project:p1', 'codex:thread:local:task-two', 'codex:thread:local:task-one'] }],
      collapsedSectionIds: [section], sectionOrder: ['custom:' + section] } } }
  }));
  write('Materials');
  let result = reconcile(db, dbPath, statePath);
  assert.equal(result.sidebar_sections_count, 1);
  assert.equal(db.prepare('SELECT name FROM thread_sections WHERE id=?').get(section).name, 'Materials');
  assert.equal(db.prepare("SELECT thread_section_id FROM threads WHERE id='task-one'").get().thread_section_id, section);
  assert.equal(db.prepare("SELECT section_position FROM threads WHERE id='task-two'").get().section_position, 1000000);
  assert.equal(JSON.parse(fs.readFileSync(statePath))['device-only'], 'preserve');
  assert.equal(reconcile(db, dbPath, statePath).sidebar_section_statements, 0);
  write('Renamed');
  reconcile(db, dbPath, statePath);
  assert.equal(db.prepare('SELECT name FROM thread_sections WHERE id=?').get(section).name, 'Renamed');
  fs.writeFileSync(statePath, JSON.stringify({ 'codexkit-sidebar-retired-local-sections': [section], 'electron-persisted-atom-state': { [field]: { account: { sections: [], sectionOrder: [], collapsedSectionIds: [] } } } }));
  reconcile(db, dbPath, statePath);
  assert.equal(db.prepare('SELECT * FROM thread_sections WHERE id=?').get(section), undefined);
  assert.equal(db.prepare("SELECT thread_section_id FROM threads WHERE id='task-one'").get().thread_section_id, null);
  assert.equal(db.prepare('SELECT count(*) n FROM threads').get().n, 2);
  assert.equal(db.prepare("SELECT name FROM thread_sections WHERE id='unrelated'").get().name, 'Unrelated');
  assert.ok(fs.readdirSync(path.join(work, 'sidebar-section-backups')).length >= 1);
  console.log('Sidebar native import, ordering, rename, deletion, backup, and idempotency tests passed');
} finally { db.close(); fs.rmSync(work, { recursive: true, force: true }); }
