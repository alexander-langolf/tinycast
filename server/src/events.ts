import { appendFileSync, chmodSync, existsSync, mkdirSync, renameSync, statSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

export class EventLog {
  constructor(private directory?: string, private record?: (line: string) => void) {}
  write(correlationID: string, step: 'start' | 'end' | 'error' | 'policyReload', outcome: 'started' | 'success' | 'failed' | 'cancelled', fields: { length?: number; count?: number } = {}, durationMS = 0) {
    const safe: Record<string, string> = {};
    for (const key of ['length', 'count'] as const) {
      const value = fields[key];
      if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) safe[key] = String(value);
    }
    const line = JSON.stringify({ time: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), level: outcome === 'failed' ? 'error' : 'info', category: 'workflows', operation: 'workflow', correlationID, step, durationMS: Math.max(0, durationMS), outcome, fields: safe });
    this.record?.(line);
    if (!this.directory) return;
    try {
      mkdirSync(this.directory, { recursive: true, mode: 0o700 });
      chmodSync(this.directory, 0o700);
      const file = join(this.directory, 'server.jsonl');
      if (existsSync(file) && statSync(file).size + Buffer.byteLength(line) > 5 * 1024 * 1024) {
        const oldest = join(this.directory, 'server.3.jsonl');
        if (existsSync(oldest)) unlinkSync(oldest);
        for (let n = 2; n >= 1; n--) {
          const source = join(this.directory, `server.${n}.jsonl`);
          if (existsSync(source)) renameSync(source, join(this.directory, `server.${n + 1}.jsonl`));
        }
        renameSync(file, join(this.directory, 'server.1.jsonl'));
      }
      appendFileSync(file, line + '\n', { mode: 0o600 }); chmodSync(file, 0o600);
    } catch { /* Diagnostics failures must not print request data or credentials. */ }
  }
}
