import type { ActionContext } from './context';
import type { Arguments } from './catalog';
export async function quickAction(ctx: ActionContext, args: Arguments, name: 'rewrite' | 'fix-grammar', title: string, progress: string) {
  const selection = await ctx.selectionRead(args.target);
  await ctx.hudShow(progress);
  const result = await ctx.modelComplete({ connection: 'quickActions', instructions: ctx.prompt(name), text: 'Text:\n' + selection.text });
  ctx.signal.throwIfAborted();
  if (args.fromLink || ctx.policy['quick-actions'][name].preview) return ctx.uiPreview({ handle: selection.handle, title, original: selection.text, text: result.text, showsDiff: true });
  const applied = await ctx.textReplace(selection.handle, result.text);
  if (applied.applied) await ctx.hudShow(title + ' applied');
  return applied;
}
