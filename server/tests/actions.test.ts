import { describe, expect, test } from 'bun:test';
import { run as rewrite } from '../actions/rewrite';
import { run as fixGrammar } from '../actions/fix-grammar';
import { run as lyra } from '../actions/lyra-fix-selection';
import type { ActionContext } from '../src/context';

function fixture(preview = true, text = 'This are three words') {
  const calls: [string, unknown][] = [];
  const ctx = {
    signal: new AbortController().signal,
    policy: { 'quick-actions': { rewrite: { preview }, 'fix-grammar': { preview } }, lyra: {
      selection: { minWords: 3, maxCharacters: 1000 }, routing: { fix: 'local' },
      modes: [{ name: 'fix', prompt: 'prompts/fix.txt' }],
    } },
    prompt: (name: string) => `prompt:${name}`,
    log: () => {},
    selectionRead: async (target?: string) => { calls.push(['read', target]); return { text, source: 'accessibility', bundleID: 'test.app', handle: 'h' }; },
    hudShow: async (text: string) => { calls.push(['hud', text]); },
    modelComplete: async (args: unknown) => { calls.push(['model', args]); return { text: 'These are three words' }; },
    textReplace: async (handle: string, text: string) => { calls.push(['replace', { handle, text }]); return { applied: true }; },
    uiPreview: async (args: unknown) => { calls.push(['preview', args]); return { choice: 'dismissed' }; },
    uiMarker: async (handle: string, text: string) => { calls.push(['marker', { handle, text }]); return { choice: 'applied' }; },
  } as unknown as ActionContext;
  return { ctx, calls };
}

describe('workflow actions', () => {
  test('rewrite reads the target, exact prompt and delimiter, then previews', async () => {
    const { ctx, calls } = fixture();
    await rewrite(ctx, { target: 'test.app' });
    expect(calls.map(c => c[0])).toEqual(['read', 'hud', 'model', 'preview']);
    expect(calls[0][1]).toBe('test.app');
    expect(calls[2][1]).toEqual({ connection: 'quickActions', instructions: 'prompt:rewrite', text: 'Text:\nThis are three words' });
  });
  test('fix grammar applies only under direct-call policy', async () => {
    const { ctx, calls } = fixture(false);
    await fixGrammar(ctx, {});
    expect(calls.map(c => c[0])).toEqual(['read', 'hud', 'model', 'replace', 'hud']);
    expect((calls[2][1] as any).instructions).toBe('prompt:fix-grammar');
  });
  test('link source always requires preview', async () => {
    const { ctx, calls } = fixture(false);
    await fixGrammar(ctx, { fromLink: true });
    expect(calls.some(c => c[0] === 'preview')).toBe(true);
    expect(calls.some(c => c[0] === 'replace')).toBe(false);
  });
  test('lyra enforces limits and wraps the selection', async () => {
    const { ctx, calls } = fixture();
    await lyra(ctx, {});
    expect(calls.map(c => c[0])).toEqual(['read', 'model', 'marker']);
    expect(calls[1][1]).toEqual({ connection: 'lyra', instructions: 'prompt:fix', text: '<input>\nThis are three words\n</input>', maxTokens: 2048 });
    const short = fixture(true, 'two words');
    expect(await lyra(short.ctx, {})).toEqual({ outcome: 'limits' });
    expect(short.calls.length).toBe(1);
    const long = fixture(true, 'one two ' + 'x'.repeat(1000));
    expect(await lyra(long.ctx, {})).toEqual({ outcome: 'limits' });
  });
  test('refused writes never claim applied', async () => {
    const { ctx, calls } = fixture(false);
    ctx.textReplace = async () => ({ applied: false });
    expect(await rewrite(ctx, {})).toEqual({ applied: false });
    expect(calls.filter(c => c[0] === 'hud')).toHaveLength(1);
  });
  test('model failure stops the workflow before UI or writes', async () => {
    const { ctx, calls } = fixture();
    ctx.modelComplete = async () => { throw Error('private selection'); };
    await expect(rewrite(ctx, {})).rejects.toThrow();
    expect(calls.map(c => c[0])).toEqual(['read', 'hud']);
  });
});
