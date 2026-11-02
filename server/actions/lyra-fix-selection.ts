import type { ActionContext } from '../src/context';
import type { Arguments } from '../src/catalog';
export const meta = { title: 'Fix selection with Lyra', linkSafe: true };
export async function run(ctx: ActionContext, args: Arguments) {
  const selection = await ctx.selectionRead(args.target);
  const policy = ctx.policy.lyra;
  if ([...selection.text].length > policy.selection.maxCharacters || selection.text.trim().split(/\s+/u).filter(Boolean).length < policy.selection.minWords) return { outcome: 'limits' };
  const mode = policy.modes.find(m => m.name === 'fix');
  if (!mode) return { outcome: 'disabled' };
  const route = policy.routing.fix;
  const result = await ctx.modelComplete({ connection: route === 'local' ? 'lyra' : route!, instructions: ctx.prompt(mode.prompt.slice(8, -4)), text: '<input>\n' + selection.text + '\n</input>', maxTokens: 2048 });
  ctx.signal.throwIfAborted();
  if (selection.text.trim() === result.text.trim()) return { outcome: 'unchanged' };
  return ctx.uiMarker(selection.handle, result.text);
}
