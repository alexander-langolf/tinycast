import { readdir, readFile, realpath, writeFile, unlink } from 'node:fs/promises';
import { join, sep } from 'node:path';
import type { ActionContext } from './context';
import { EventLog } from './events';

export type Arguments = { target?: string; fromLink?: boolean };
export type Action = { meta: { title: string; linkSafe: boolean }; run: (ctx: ActionContext, args: Arguments) => Promise<unknown> };
export const validName = (value: string) => /^[a-z][a-z0-9-]{0,63}$/.test(value);

export class ActionCatalog {
  private actions = new Map<string, Action>();
  private versions = new Map<string, string>();
  private pending?: Promise<void>;
  constructor(private root: string, private log: EventLog) {}
  get(name: string) { return this.actions.get(name); }
  list() { return [...this.actions].map(([name, a]) => ({ name, ...a.meta })).sort((a, b) => a.name.localeCompare(b.name)); }
  refresh(): Promise<void> {
    if (this.pending) return this.pending;
    this.pending = this.load().finally(() => { this.pending = undefined; });
    return this.pending;
  }
  private async load() {
    const directory = join(this.root, 'actions');
    const files = await readdir(directory);
    const names = new Set<string>();
    for (const file of files) {
      if (!file.endsWith('.ts') || !validName(file.slice(0, -3))) continue;
      const name = file.slice(0, -3); names.add(name);
      try {
        const path = join(directory, file);
        if (!(await realpath(path)).startsWith((await realpath(directory)) + sep)) throw Error('path');
        const bytes = await readFile(path);
        const version = Bun.hash(bytes).toString(16);
        if (this.versions.get(name) === version) continue;
        this.versions.set(name, version);
        // Bun 1.4.2 misses a second new module under a symlinked path such as /var, so use the real one.
        const revision = join(await realpath(directory), `.workflow-${crypto.randomUUID()}.ts`);
        let imported: any;
        try {
          await writeFile(revision, bytes, { mode: 0o600, flag: 'wx' });
          imported = await import(revision);
        } finally { await unlink(revision).catch(() => {}); }
        if (!imported.meta || typeof imported.meta.title !== 'string' || !imported.meta.title.trim() || imported.meta.title.length > 120 || typeof imported.meta.linkSafe !== 'boolean' || typeof imported.run !== 'function') throw Error('exports');
        this.actions.set(name, { meta: Object.freeze({ title: imported.meta.title, linkSafe: imported.meta.linkSafe }), run: imported.run });
        this.log.write(crypto.randomUUID(), 'policyReload', 'success', { count: this.actions.size });
      } catch { this.log.write(crypto.randomUUID(), 'policyReload', 'failed'); }
    }
    for (const name of this.actions.keys()) if (!names.has(name)) { this.actions.delete(name); this.versions.delete(name); }
  }
}
