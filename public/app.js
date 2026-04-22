const notesEl = document.getElementById('notes');
const form = document.getElementById('add');
const input = document.getElementById('text');

async function load() {
  const res = await fetch('/api/notes');
  const notes = await res.json();
  render(notes);
}

function render(notes) {
  notesEl.innerHTML = '';
  if (notes.length === 0) {
    const li = document.createElement('li');
    li.className = 'empty';
    li.textContent = 'no notes yet';
    notesEl.appendChild(li);
    return;
  }
  for (const note of notes) {
    const li = document.createElement('li');
    const left = document.createElement('div');
    left.innerHTML = `<div>${escapeHtml(note.text)}</div><div class="meta">${new Date(note.createdAt).toLocaleString()}</div>`;
    const btn = document.createElement('button');
    btn.className = 'delete';
    btn.textContent = 'delete';
    btn.onclick = () => remove(note.id);
    li.appendChild(left);
    li.appendChild(btn);
    notesEl.appendChild(li);
  }
}

async function add(text) {
  const res = await fetch('/api/notes', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });
  if (!res.ok) {
    alert('failed to add note');
    return;
  }
  await load();
}

async function remove(id) {
  await fetch(`/api/notes/${id}`, { method: 'DELETE' });
  await load();
}

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

form.addEventListener('submit', (e) => {
  e.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  add(text);
});

load();
