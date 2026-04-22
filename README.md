# boxd-action-demo

A tiny fullstack notes app used to smoke-test the
[boxd fix-on-issue GitHub Action](.github/actions/fix-on-issue/README.md).

## Stack

- **Backend**: Express (ESM), in-memory store. See `server.js`.
- **Frontend**: Vanilla HTML/JS served from `public/`.
- **Tests**: vitest + supertest in `tests/`.

## Run locally

```bash
npm install
npm start        # http://localhost:3000
npm test         # vitest
```

## The deliberate bug

`DELETE /api/notes/:id` returns `200` even when the id doesn't exist.
It should return `404` when no matching note is found. File this as an
issue, label it `claude-fix`, and watch the action open a PR.
