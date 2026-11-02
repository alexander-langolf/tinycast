import { afterEach, expect, test } from 'bun:test';
import { mkdtemp, mkdir, writeFile, rm, cp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ActionCatalog } from '../src/catalog';
import { Configuration } from '../src/configuration';
import { createHandler } from '../src/http';
import { EventLog } from '../src/events';

const roots: string[] = [];
afterEach(async () => { for (const root of roots.splice(0)) await rm(root, { recursive: true, force: true }); });
async function fixture() {
  const root = await mkdtemp(join(tmpdir(), 'tinycast-workflows-')); roots.push(root);
  await mkdir(join(root, 'actions'));
  await cp(join(import.meta.dir, '../prompts'), join(root, 'prompts'), { recursive: true });
  await cp(join(import.meta.dir, '../policy'), join(root, 'policy'), { recursive: true });
  const events: string[] = [];
  const log = new EventLog(undefined, line => events.push(line));
  const catalog = new ActionCatalog(root, log);
  const config = new Configuration(root, log);
  return { root, events, log, catalog, config };
}
const action = (value: number) => `export const meta = {title:'Test',linkSafe:true}; export async function run(){return {value:${value}}}`;
test('changed actions reload; syntax and export failures retain last valid; new actions load', async () => {
  const { root, catalog } = await fixture(); const file = join(root, 'actions/test.ts');
  await writeFile(file, action(1)); await catalog.refresh();
  const old = catalog.get('test')!;
  expect(await old.run({} as any, {})).toEqual({ value: 1 });
  await writeFile(file, action(2)); await catalog.refresh();
  expect(await catalog.get('test')!.run({} as any, {})).toEqual({ value: 2 });
  expect(await old.run({} as any, {})).toEqual({ value: 1 });
  await writeFile(file, 'export const broken = {'); await catalog.refresh();
  expect(await catalog.get('test')!.run({} as any, {})).toEqual({ value: 2 });
  await writeFile(file, 'export const meta = { title: "bad", linkSafe: "yes" }; export const run = 2;'); await catalog.refresh();
  expect(await catalog.get('test')!.run({} as any, {})).toEqual({ value: 2 });
  await writeFile(join(root, 'actions/other.ts'), action(3)); await catalog.refresh();
  expect(catalog.list()).toHaveLength(2);
});
test('prompts and policies reload and reject malformed edits without losing valid values', async () => {
  const { root, config } = await fixture(); await config.refresh();
  const original = config.snapshot();
  await writeFile(join(root, 'prompts/rewrite.txt'), 'New exact prompt'); await config.refresh();
  expect(config.snapshot().prompts.rewrite).toBe('New exact prompt');
  expect(original.prompts.rewrite).not.toBe('New exact prompt');
  await writeFile(join(root, 'prompts/rewrite.txt'), ''); await config.refresh();
  expect(config.snapshot().prompts.rewrite).toBe('New exact prompt');
  await writeFile(join(root, 'prompts/rewrite.txt'), 'New exact prompt');
  await writeFile(join(root, 'policy/quick-actions.json'), JSON.stringify({ rewrite: { preview: false }, 'fix-grammar': { preview: true } })); await config.refresh();
  expect(config.snapshot().policy['quick-actions'].rewrite.preview).toBe(false);
  await writeFile(join(root, 'policy/quick-actions.json'), '{'); await config.refresh();
  expect(config.snapshot().policy['quick-actions'].rewrite.preview).toBe(false);
});
test('auth, routes, correlation and event privacy', async () => {
  const f = await fixture(); await writeFile(join(f.root, 'actions/test.ts'), action(1));
  const handler = createHandler({ ...f, token: 'secret', tinycastPort: 43321, tinycastToken: 'native' });
  const request = (path: string, init: RequestInit = {}) => new Request('http://127.0.0.1:43322' + path, init);
  expect((await handler(request('/health'))).status).toBe(401);
  const headers = { Authorization: 'Bearer secret' };
  expect((await handler(request('/health', { headers }))).status).toBe(200);
  expect((await (await handler(request('/actions', { headers }))).json()).actions[0].name).toBe('test');
  const id = crypto.randomUUID();
  const response = await handler(request('/actions/test', { method: 'POST', headers: { ...headers, 'X-Tinycast-Correlation': id }, body: '{}' }));
  expect(response.headers.get('X-Tinycast-Correlation')).toBe(id);
  expect(await response.json()).toEqual({ value: 1 });
  expect((await handler(request('/actions/test', { method: 'POST', headers, body: '{' }))).status).toBe(400);
  await writeFile(join(f.root, 'actions/test.ts'), `export const meta={title:'Test',linkSafe:true}; export async function run(){throw Error('PRIVATE-TEXT')}`);
  expect((await handler(request('/actions/test', { method: 'POST', headers, body: '{}' }))).status).toBe(500);
  expect(f.events.join('')).not.toContain('PRIVATE-TEXT');
  for (const line of f.events) { const e = JSON.parse(line); expect(e.correlationID).toBeDefined(); expect(e.step).toBeDefined(); }
});
