import { describe, it, expect, beforeEach } from 'vitest';
import { readFileSync } from 'fs';
import request from 'supertest';
import { createApp } from '../server.js';

let app;
beforeEach(() => {
  app = createApp();
});

describe('POST /api/notes', () => {
  it('creates a note with the given text', async () => {
    const res = await request(app).post('/api/notes').send({ text: 'hello' });
    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({ id: expect.any(Number), text: 'hello' });
  });

  it('rejects empty text', async () => {
    const res = await request(app).post('/api/notes').send({ text: '' });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/notes', () => {
  it('returns an empty list when no notes exist', async () => {
    const res = await request(app).get('/api/notes');
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  it('returns created notes', async () => {
    await request(app).post('/api/notes').send({ text: 'one' });
    await request(app).post('/api/notes').send({ text: 'two' });
    const res = await request(app).get('/api/notes');
    expect(res.body.map((n) => n.text)).toEqual(['one', 'two']);
  });
});

describe('frontend empty state', () => {
  it('shows friendly copy when notes list is empty', () => {
    const src = readFileSync(new URL('../public/app.js', import.meta.url), 'utf8');
    expect(src).toContain('no notes yet — add your first one! ✨');
  });
});

describe('DELETE /api/notes/:id', () => {
  it('removes an existing note', async () => {
    const created = await request(app).post('/api/notes').send({ text: 'zap' });
    const id = created.body.id;
    const del = await request(app).delete(`/api/notes/${id}`);
    expect(del.status).toBe(200);
    const list = await request(app).get('/api/notes');
    expect(list.body).toEqual([]);
  });
});
