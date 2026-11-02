import type { Policy, Snapshot } from './configuration';
import { EventLog } from './events';

export type Selection = { text: string; source: string; bundleID: string; handle: string };
export interface ActionContext {
  signal: AbortSignal;
  policy: Policy;
  prompt(name: string): string;
  log(fields: { length?: number; count?: number }): void;
  selectionRead(target?: string): Promise<Selection>;
  modelComplete(args: { connection: string; instructions: string; text: string; maxTokens?: number }): Promise<{ text: string }>;
  textReplace(handle: string, text: string): Promise<{ applied: boolean }>;
  uiPreview(args: { handle: string; title: string; original: string; text: string; showsDiff: boolean }): Promise<{ choice: 'replace' | 'copy' | 'dismissed' }>;
  uiMarker(handle: string, text: string): Promise<{ choice: 'applied' | 'dismissed' }>;
  hudShow(text: string): Promise<void>;
}
export function context(options: { port: number; token: string; correlationID: string; signal: AbortSignal; snapshot: Snapshot; log: EventLog; fetch?: typeof fetch }): ActionContext {
  const send = options.fetch ?? fetch;
  async function primitive<T>(name: string, args: unknown, signal = options.signal): Promise<T> {
    signal.throwIfAborted();
    const response = await send(`http://127.0.0.1:${options.port}/mcp`, {
      method: 'POST', signal: AbortSignal.any([signal, AbortSignal.timeout(110000)]), redirect: 'error',
      headers: { Authorization: `Bearer ${options.token}`, 'Content-Type': 'application/json', Accept: 'application/json', 'MCP-Protocol-Version': '2025-03-26', 'X-Tinycast-Correlation': options.correlationID },
      body: JSON.stringify({ jsonrpc: '2.0', id: crypto.randomUUID(), method: 'tools/call', params: { name, arguments: args } }),
    });
    if (!response.ok) throw Error('primitive request failed');
    const body = await response.json() as any;
    if (body.error || !body.result || body.result.isError) throw Error('primitive refused');
    return body.result.structuredContent ?? JSON.parse(body.result.content[0].text);
  }
  async function interaction<T>(name: string, args: unknown): Promise<T> {
    const { id } = await primitive<{ id: string }>(name, args);
    try {
      while (true) {
        const result = await primitive<{ pending: boolean; choice?: string }>('ui_result', { id });
        if (!result.pending) return { choice: result.choice } as T;
        await Bun.sleep(250); options.signal.throwIfAborted();
      }
    } finally {
      // A disconnected action must not leave a panel capable of applying its abandoned result.
      try { await primitive('ui_result', { id, cancel: true }, AbortSignal.timeout(3000)); } catch {}
    }
  }
  return {
    signal: options.signal, policy: options.snapshot.policy,
    prompt(name) { if (!/^[a-zA-Z0-9_-]+$/.test(name) || !options.snapshot.prompts[name]) throw Error('prompt'); return options.snapshot.prompts[name]; },
    log(fields) { options.log.write(options.correlationID, 'end', 'success', fields); },
    selectionRead: target => primitive('selection_read', target ? { target } : {}),
    modelComplete: args => primitive('model_complete', args),
    textReplace: (handle, text) => primitive('text_replace', { handle, text }),
    uiPreview: args => interaction('ui_preview', args),
    uiMarker: (handle, text) => interaction('ui_marker', { handle, text }),
    hudShow: async text => { await primitive('hud_show', { text }); },
  };
}
