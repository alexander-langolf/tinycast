import { quickAction } from '../src/quick-action';
import type { ActionContext } from '../src/context';
import type { Arguments } from '../src/catalog';
export const meta = { title: 'Fix Grammar', linkSafe: true };
export async function run(ctx: ActionContext, args: Arguments) { return quickAction(ctx, args, 'fix-grammar', 'Fix Grammar', 'Fixing Grammar…'); }
