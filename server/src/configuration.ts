import { readFile, readdir, realpath } from 'node:fs/promises';
import { join, sep } from 'node:path';
import { EventLog } from './events';

export type Policy = {
  'quick-actions': Record<'rewrite' | 'fix-grammar', { preview: boolean }>;
  lyra: { schemaVersion: number; selection: { minWords: number; maxCharacters: number }; fix: { minWords: number; maxCharacters: number; pauseMs: number; punctuationEndsPause: boolean }; modes: { name: string; prompt: string }[]; routing: Record<string, string> };
};
export type Snapshot = { prompts: Record<string, string>; policy: Policy };
const object = (x: unknown): x is Record<string, any> => !!x && typeof x === 'object' && !Array.isArray(x);
const keys = (x: Record<string, unknown>, allowed: string[]) => Object.keys(x).sort().join(',') === allowed.sort().join(',');
const integer = (x: unknown, low: number, high: number) => typeof x === 'number' && Number.isInteger(x) && x >= low && x <= high;
function limits(x: any) { return object(x) && integer(x.minWords, 1, 10000) && integer(x.maxCharacters, 1, 100000) && x.minWords <= x.maxCharacters; }
function validate(policy: Policy, prompts: Record<string, string>) {
  const quick = policy['quick-actions'], lyra = policy.lyra;
  if (!object(quick) || !keys(quick, ['rewrite', 'fix-grammar']) || !Object.values(quick).every(x => object(x) && keys(x, ['preview']) && typeof x.preview === 'boolean')) throw Error('quick-actions');
  if (!object(lyra) || !keys(lyra, ['schemaVersion', 'fix', 'selection', 'modes', 'routing']) || lyra.schemaVersion !== 1 || !limits(lyra.selection) || !keys(lyra.selection, ['minWords', 'maxCharacters']) || !limits(lyra.fix) || !keys(lyra.fix, ['minWords', 'maxCharacters', 'pauseMs', 'punctuationEndsPause']) || !integer(lyra.fix.pauseMs, 0, 60000) || typeof lyra.fix.punctuationEndsPause !== 'boolean') throw Error('lyra');
  if (!Array.isArray(lyra.modes) || lyra.modes.length < 1 || lyra.modes.length > 16 || !object(lyra.routing)) throw Error('modes');
  const names = new Set<string>();
  for (const mode of lyra.modes) {
    if (!object(mode) || !keys(mode, ['name', 'prompt']) || typeof mode.name !== 'string' || !/^[a-z][a-z0-9-]{0,63}$/.test(mode.name) || names.has(mode.name) || typeof mode.prompt !== 'string' || !/^prompts\/[a-zA-Z0-9_-]+\.txt$/.test(mode.prompt) || !prompts[mode.prompt.slice(8, -4)]) throw Error('mode');
    names.add(mode.name);
    const route = lyra.routing[mode.name];
    if (typeof route !== 'string' || !route.trim() || route.length > 256) throw Error('route');
  }
  if (!keys(lyra.routing, [...names])) throw Error('routing');
  for (const name of ['rewrite', 'fix-grammar']) if (!prompts[name]) throw Error('prompt');
}
export class Configuration {
  private current?: Snapshot;
  private pending?: Promise<void>;
  private fingerprint?: string;
  constructor(private root: string, private log: EventLog) {}
  snapshot(): Snapshot { if (!this.current) throw Error('configuration'); return this.current; }
  refresh(): Promise<void> {
    if (this.pending) return this.pending;
    this.pending = this.load().finally(() => { this.pending = undefined; }); return this.pending;
  }
  private async load() {
    try {
      const prompts: Record<string, string> = {}, contents: Record<string, string> = {};
      const names = (await readdir(join(this.root, 'prompts'))).filter(n => /^[a-zA-Z0-9_-]+\.txt$/.test(n));
      async function read(root: string, name: string) {
        const path = join(root, name);
        if (!(await realpath(path)).startsWith((await realpath(root)) + sep)) throw Error('path');
        const data = await readFile(path);
        if (data.byteLength > 262144) throw Error('size');
        return new TextDecoder('utf-8', { fatal: true }).decode(data);
      }
      for (const name of [...names.map(n => 'prompts/' + n), 'policy/lyra.json', 'policy/quick-actions.json'].sort()) contents[name] = await read(this.root, name);
      const fingerprint = Bun.hash(JSON.stringify(contents)).toString(16);
      if (fingerprint === this.fingerprint) return;
      this.fingerprint = fingerprint;
      for (const name of names) { const text = contents['prompts/' + name]!; if (!text.trim()) throw Error('prompt'); prompts[name.slice(0, -4)] = text; }
      const policy: Policy = { lyra: JSON.parse(contents['policy/lyra.json']!), 'quick-actions': JSON.parse(contents['policy/quick-actions.json']!) };
      validate(policy, prompts);
      for (const [name, content] of Object.entries(contents)) if (await read(this.root, name) !== content) { this.fingerprint = undefined; throw Error('changed'); }
      this.current = deepFreeze({ prompts, policy }); this.log.write(crypto.randomUUID(), 'policyReload', 'success');
    } catch { this.log.write(crypto.randomUUID(), 'policyReload', 'failed'); }
  }
}
function deepFreeze<T>(value: T): T { if (value && typeof value === 'object') { Object.freeze(value); for (const child of Object.values(value)) deepFreeze(child); } return value; }
