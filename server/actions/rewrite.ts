import { quickAction } from '../src/quick-action';
import type { ActionContext } from '../src/context';
import type { Arguments } from '../src/catalog';
export const meta = { title: 'Rewrite', linkSafe: true };
export async function run(ctx: ActionContext, args: Arguments) { return quickAction(ctx, args, 'rewrite', 'Rewrite', 'Rewriting…'); }
