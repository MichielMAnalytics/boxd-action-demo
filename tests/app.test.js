import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const appJs = readFileSync(resolve(__dirname, '../public/app.js'), 'utf8');

describe('empty-state copy in app.js', () => {
  it('shows friendly empty-state text', () => {
    expect(appJs).toContain('no notes yet — add your first one! ✨');
  });
});
