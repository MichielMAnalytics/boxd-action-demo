import express from 'express';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

export function createApp() {
  const app = express();
  app.use(express.json());
  app.use(express.static(join(__dirname, 'public')));

  // In-memory note store. Resets on restart; fine for a demo.
  const notes = [];
  let nextId = 1;

  app.get('/api/notes', (_req, res) => {
    res.json(notes);
  });

  app.post('/api/notes', (req, res) => {
    const { text } = req.body ?? {};
    if (typeof text !== 'string' || text.trim() === '') {
      return res.status(400).json({ error: 'text is required' });
    }
    const note = { id: nextId++, text: text.trim(), createdAt: new Date().toISOString() };
    notes.push(note);
    res.status(201).json(note);
  });

  // BUG: returns 200 and empty body even when the id doesn't exist.
  // Should return 404 when no matching note is found.
  app.delete('/api/notes/:id', (req, res) => {
    const id = Number(req.params.id);
    const idx = notes.findIndex((n) => n.id === id);
    if (idx !== -1) notes.splice(idx, 1);
    res.status(200).end();
  });

  return app;
}

// Only start a server when this file is run directly (not imported from tests).
const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const port = Number(process.env.PORT ?? 3000);
  createApp().listen(port, () => {
    console.log(`notes server listening on http://localhost:${port}`);
  });
}
