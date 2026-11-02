import { watch } from 'node:fs';
import { resolve, join } from 'node:path';
import { ActionCatalog } from './catalog';
import { Configuration } from './configuration';
import { EventLog } from './events';
import { createHandler } from './http';

const root = resolve(import.meta.dir, '..');
const token = process.env.TINYCAST_SERVER_TOKEN, tinycastToken = process.env.TINYCAST_TOKEN;
function port(value: string | undefined, fallback: number) { const n = Number(value ?? fallback); if (!Number.isInteger(n) || n < 1 || n > 65535) throw Error('Invalid port'); return n; }
if (!token || !tinycastToken) throw Error('Workflow credentials are required');
const log = new EventLog(process.env.TINYCAST_DIAGNOSTICS_DIRECTORY);
const catalog = new ActionCatalog(root, log), config = new Configuration(root, log);
await Promise.all([catalog.refresh(), config.refresh()]); config.snapshot();
const controller = new AbortController();
let settle: ReturnType<typeof setTimeout> | undefined;
const watchers = ['actions', 'prompts', 'policy'].map(name => watch(join(root, name), () => {
  clearTimeout(settle); settle = setTimeout(() => { void Promise.all([catalog.refresh(), config.refresh()]).catch(() => log.write(crypto.randomUUID(), 'policyReload', 'failed')); }, 100);
}));
const server = Bun.serve({ hostname: '127.0.0.1', port: port(process.env.TINYCAST_SERVER_PORT, 43322), idleTimeout: 0,
  fetch: createHandler({ catalog, config, log, token, tinycastToken, tinycastPort: port(process.env.TINYCAST_PORT, 43321), signal: controller.signal }),
  error: () => Response.json({ error: 'Workflow failed' }, { status: 500 }),
});
function stop() { controller.abort(); clearTimeout(settle); for (const watcher of watchers) watcher.close(); server.stop(true); }
process.once('SIGTERM', stop); process.once('SIGINT', stop);
