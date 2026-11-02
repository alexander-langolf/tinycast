import { timingSafeEqual } from 'node:crypto';
import { ActionCatalog, validName } from './catalog';
import { Configuration } from './configuration';
import { context } from './context';
import { EventLog } from './events';

export function createHandler(options: { catalog: ActionCatalog; config: Configuration; log: EventLog; token: string; tinycastPort: number; tinycastToken: string; signal?: AbortSignal }) {
  let active = false;
  return async (request: Request): Promise<Response> => {
    const json = (value: unknown, status = 200, headers: Record<string, string> = {}) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store', ...headers } });
    const bearer = Buffer.from(request.headers.get('Authorization') ?? ''), expected = Buffer.from('Bearer ' + options.token);
    if (bearer.length !== expected.length || !timingSafeEqual(bearer, expected)) return json({ error: 'Unauthorized' }, 401);
    if (request.headers.has('Origin')) return json({ error: 'Browser requests are refused' }, 403);
    const url = new URL(request.url);
    try { await Promise.all([options.catalog.refresh(), options.config.refresh()]); } catch { return json({ error: 'Configuration unavailable' }, 503); }
    if (request.method === 'GET' && url.pathname === '/health') return json({ status: 'ok', actionCount: options.catalog.list().length });
    if (request.method === 'GET' && url.pathname === '/actions') return json({ actions: options.catalog.list() });
    if (request.method !== 'POST' || !url.pathname.startsWith('/actions/')) return json({ error: 'Not found' }, 404);
    const name = url.pathname.slice('/actions/'.length);
    const action = validName(name) ? options.catalog.get(name) : undefined;
    if (!action) return json({ error: 'Unknown action' }, 404);
    const fromLink = request.headers.get('X-Tinycast-Source') === 'link';
    if (fromLink && !action.meta.linkSafe) return json({ error: 'Action is not link-safe' }, 403);
    if (active) return json({ error: 'Another workflow is active' }, 409);
    let args: { target?: string; fromLink: boolean };
    try {
      const reader = request.body?.getReader(); let bytes = 0, parts: Uint8Array[] = [];
      if (reader) { while (true) { const part = await reader.read(); if (part.done) break; bytes += part.value.byteLength; if (bytes > 262144) { await reader.cancel(); return json({ error: 'Body too large' }, 413); } parts.push(part.value); } }
      const body = Buffer.concat(parts).toString('utf8'); const value = body ? JSON.parse(body) : {};
      if (!value || Array.isArray(value) || typeof value !== 'object' || Object.keys(value).some(k => k !== 'target') || (value.target !== undefined && (typeof value.target !== 'string' || !/^[a-zA-Z0-9.-]{1,256}$/.test(value.target)))) return json({ error: 'Invalid arguments' }, 400);
      args = { ...value, fromLink };
    } catch { return json({ error: 'Invalid JSON' }, 400); }
    const supplied = request.headers.get('X-Tinycast-Correlation') ?? '';
    const id = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(supplied) ? supplied : crypto.randomUUID();
    const headers = { 'X-Tinycast-Correlation': id };
    const signal = options.signal ? AbortSignal.any([request.signal, options.signal]) : request.signal;
    active = true; const started = performance.now(); options.log.write(id, 'start', 'started');
    try {
      const ctx = context({ port: options.tinycastPort, token: options.tinycastToken, correlationID: id, signal, snapshot: options.config.snapshot(), log: options.log });
      const result = await action.run(ctx, args);
      signal.throwIfAborted(); options.log.write(id, 'end', 'success', {}, performance.now() - started);
      return json(result ?? {}, 200, headers);
    } catch {
      options.log.write(id, 'error', signal.aborted ? 'cancelled' : 'failed', {}, performance.now() - started);
      return json({ error: 'Workflow failed' }, 500, headers);
    } finally { active = false; }
  };
}
