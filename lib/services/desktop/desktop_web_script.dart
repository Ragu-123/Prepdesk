class DesktopWebScript {
  static const value = r'''
'use strict';
const $ = id => document.getElementById(id);
const state = { notes: [], mistakes: [], noteFilter: 'all', editingNote: null, token: sessionStorage.getItem('nyro_token') || localStorage.getItem('nyro_token') || '', authenticated: false };
localStorage.removeItem('nyro_token');
if (state.token) sessionStorage.setItem('nyro_token', state.token);
const truth = value => value === true || value === 1;
const resolved = record => ['RESOLVED', 'COMPLETED', 'DONE'].includes(String(record.status || '').toUpperCase());
const text = value => value == null ? '' : String(value);
function node(tag, className, value) { const item = document.createElement(tag); if (className) item.className = className; if (value != null) item.textContent = value; return item; }
function icon(name) { const item = node('span', 'mi', String.fromCodePoint(window.NYRO_ICONS[name] || window.NYRO_ICONS.note)); item.setAttribute('aria-hidden', 'true'); return item; }
function action(label, symbol, callback, style = 'btn icon-button') { const button = node('button', style); button.type = 'button'; button.title = label; button.setAttribute('aria-label', label); if (symbol) button.append(icon(symbol)); if (!symbol || !style.includes('icon-button')) button.append(node('span', '', label)); button.addEventListener('click', callback); return button; }
function jsonList(value) { if (Array.isArray(value)) return value; try { const parsed = JSON.parse(value || '[]'); return Array.isArray(parsed) ? parsed : []; } catch (_) { return []; } }
let toastTimer;
function toast(message) { $('toast').textContent = message; $('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').hidden = true, 4500); }
function report(error) { $('workspace-error').textContent = error.message || 'Unable to reach your phone. Check the connection and retry.'; $('workspace-error').hidden = false; }
function connected(value) { $('connection').textContent = value ? 'Phone connected' : 'Connection interrupted'; $('connection').classList.toggle('offline', !value); $('session-status').textContent = value ? 'Paired' : 'Not connected'; $('status-description').textContent = value ? 'Your phone is reachable. Changes save directly to NYRO Tasks.' : 'Keep NYRO open and check that both devices are on the same Wi-Fi network.'; }
async function api(path, options = {}) {
  const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(path, { ...options, signal: controller.signal, headers: { 'Content-Type': 'application/json', ...(state.token ? { Authorization: 'Bearer ' + state.token } : {}), ...options.headers } });
    const data = await response.json().catch(() => ({}));
    if (response.status === 401) { lockLocal(); throw new Error('Your session expired. Pair with your phone again.'); }
    if (!response.ok) throw new Error(data.error || 'The change could not be saved. Please retry.');
    connected(true); return data;
  } catch (error) { if (error.name === 'AbortError') throw new Error('Your phone did not respond. Check the Wi-Fi connection and retry.'); throw error; }
  finally { clearTimeout(timer); }
}
function lockLocal() {
  state.authenticated = false; state.token = ''; state.notes = []; state.mistakes = []; state.editingNote = null;
  sessionStorage.removeItem('nyro_token'); $('app').inert = true;
  document.querySelectorAll('dialog[open]').forEach(dialog => dialog.close());
  $('notes-container').replaceChildren(); $('mistakes-container').replaceChildren();
  $('note-form').reset(); $('mistake-form').reset(); $('pair-pin').value = '';
  if (!$('pair-dialog').open) $('pair-dialog').showModal();
  $('pair-pin').focus(); connected(false);
}
async function lockStudio() { try { await api('/api/auth/logout', { method: 'POST' }); } catch (_) {} finally { lockLocal(); } }
async function loadWorkspace() { $('app').inert = false; $('pair-dialog').close(); state.authenticated = true; $('workspace-error').hidden = true; await Promise.allSettled([loadNotes(), loadMistakes(), loadSubjects()]); }
async function checkSession() {
  if (!state.token) { lockLocal(); return; }
  try { const data = await api('/api/auth/status'); if (data.authenticated) { if (!state.authenticated) await loadWorkspace(); } else lockLocal(); }
  catch (_) { connected(false); if (!state.authenticated) lockLocal(); }
}
$('pair-dialog').addEventListener('cancel', event => event.preventDefault());
$('pair-form').addEventListener('submit', async event => {
  event.preventDefault(); const button = event.submitter || event.currentTarget.querySelector('button[type=submit]'); button.disabled = true; $('pair-error').textContent = '';
  try {
    const data = await api('/api/auth/verify', { method: 'POST', body: JSON.stringify({ pin: $('pair-pin').value }) });
    if (!data.success || !data.token) throw new Error(data.error || 'That code was not accepted. Check the code on your phone.');
    state.token = data.token; sessionStorage.setItem('nyro_token', state.token); $('pair-pin').value = ''; await loadWorkspace();
  } catch (error) { $('pair-error').textContent = error.message; }
  finally { button.disabled = false; }
});
$('pair-pin').addEventListener('input', event => event.target.value = event.target.value.replace(/[^0-9]/g, '').slice(0, 6));
$('lock-button').addEventListener('click', lockStudio);
document.querySelectorAll('[data-tab]').forEach(button => button.addEventListener('click', () => {
  const target = button.dataset.tab;
  document.querySelectorAll('.panel').forEach(panel => panel.hidden = panel.id !== 'panel-' + target);
  document.querySelectorAll('[data-tab]').forEach(item => item === button ? item.setAttribute('aria-current', 'page') : item.removeAttribute('aria-current'));
  if (target === 'status') checkSession();
}));
document.querySelectorAll('[data-close]').forEach(button => button.addEventListener('click', () => $(button.dataset.close).close()));
function empty(container, heading, description, symbol, onCreate) {
  const item = node('div', 'empty'); item.append(icon(symbol), node('h2', '', heading), node('p', '', description));
  if (onCreate) item.append(action('Create one', 'add', onCreate, 'btn btn-tonal'));
  container.append(item);
}
async function loadNotes() {
  try { const data = await api('/api/notes?archived=true'); state.notes = (data.notes || []).filter(note => !truth(note.is_locked)); renderNotes(); $('workspace-error').hidden = true; }
  catch (error) { report(error); }
}
function renderNotes() {
  const query = $('note-search').value.toLowerCase().trim();
  const notes = state.notes.filter(note => {
    const archived = truth(note.is_archived);
    return (state.noteFilter === 'archive' ? archived : !archived) && (state.noteFilter !== 'pinned' || truth(note.is_pinned)) &&
      [note.title, note.content, note.tags_json, note.todo_items_json].some(value => text(value).toLowerCase().includes(query));
  }).sort((a, b) => Number(truth(b.is_pinned)) - Number(truth(a.is_pinned)) || Number(b.updated_at) - Number(a.updated_at));
  $('note-count').textContent = state.notes.filter(note => !truth(note.is_archived)).length;
  $('note-summary').textContent = notes.length + (notes.length === 1 ? ' note' : ' notes') + (state.noteFilter === 'archive' ? ' in archive' : ' in your workspace');
  const container = $('notes-container'); container.replaceChildren();
  if (!notes.length) { empty(container, query ? 'No matching notes' : 'A fresh page awaits.', query ? 'Try another word or change the filter.' : 'Save a thought, a formula or a useful checklist.', 'note', query ? null : () => openNote()); return; }
  notes.forEach(note => {
    const card = node('article', 'note' + (truth(note.is_code) ? ' is-code' : ''));
    if (/^#[0-9a-fA-F]{6}$/.test(note.color || '')) card.style.backgroundColor = note.color;
    const open = node('button', 'note-open'); open.type = 'button'; open.addEventListener('click', () => openNote(note));
    open.append(node('h2', '', note.title || 'Untitled note'));
    if (note.content) open.append(node('div', 'note-body', note.content));
    if (truth(note.is_todo_list)) {
      const list = node('div', 'note-body');
      jsonList(note.todo_items_json).forEach(item => { const row = node('div'); row.append(icon(item.checked ? 'check' : 'note'), node('span', '', ' ' + text(item.text))); list.append(row); }); open.append(list);
    }
    const tags = node('div', 'note-meta'); jsonList(note.tags_json).forEach(tag => tags.append(node('span', 'tag', tag))); open.append(tags);
    const controls = node('div', 'card-actions');
    const updated = Number(note.updated_at); controls.append(node('span', 'note-date', Number.isFinite(updated) && updated > 0 ? new Date(updated).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : ''));
    controls.append(action((truth(note.is_pinned) ? 'Unpin: ' : 'Pin: ') + (note.title || 'Untitled note'), 'pin', event => mutateNote(note, { is_pinned: !truth(note.is_pinned) }, event.currentTarget)),
      action((truth(note.is_archived) ? 'Restore: ' : 'Archive: ') + (note.title || 'Untitled note'), 'archive', event => mutateNote(note, { is_archived: !truth(note.is_archived) }, event.currentTarget)),
      action('Delete: ' + (note.title || 'Untitled note'), 'delete', () => deleteRecord('note', note.id)));
    card.append(open, controls); container.append(card);
  });
}
async function mutateNote(note, changes, button) {
  button.disabled = true;
  try { await api('/api/notes/' + encodeURIComponent(note.id), { method: 'PATCH', body: JSON.stringify(changes) }); await loadNotes(); toast('Note updated'); }
  catch (error) { report(error); }
  finally { button.disabled = false; }
}
function openNote(note = null) {
  state.editingNote = note; $('note-form').reset(); $('note-form-error').textContent = '';
  $('note-dialog-title').textContent = note ? 'Edit note' : 'New note';
  $('note-title').value = note ? text(note.title) : ''; $('note-content').value = note ? text(note.content) : '';
  $('note-tags').value = note ? jsonList(note.tags_json).join(', ') : '';
  $('note-color').value = note && /^#[0-9a-fA-F]{6}$/.test(note.color) ? note.color.toUpperCase() : '#FFFFFF';
  $('note-dialog').showModal(); $('note-title').focus();
}
$('note-form').addEventListener('submit', async event => {
  event.preventDefault(); const button = event.submitter || event.currentTarget.querySelector('button[type=submit]'); button.disabled = true; $('note-form-error').textContent = '';
  const payload = { title: $('note-title').value.trim(), content: $('note-content').value.trim(), tags: $('note-tags').value.split(',').map(tag => tag.trim()).filter(Boolean), color: $('note-color').value };
  if (!payload.title && !payload.content && !state.editingNote) { $('note-form-error').textContent = 'Add a title or a note before saving.'; button.disabled = false; return; }
  try {
    await api(state.editingNote ? '/api/notes/' + encodeURIComponent(state.editingNote.id) : '/api/notes', { method: state.editingNote ? 'PATCH' : 'POST', body: JSON.stringify(payload) });
    $('note-dialog').close(); await loadNotes(); toast('Note saved to your phone');
  } catch (error) { $('note-form-error').textContent = error.message; }
  finally { button.disabled = false; }
});
document.querySelectorAll('[data-note-filter]').forEach(button => button.addEventListener('click', () => { state.noteFilter = button.dataset.noteFilter; document.querySelectorAll('[data-note-filter]').forEach(item => item.setAttribute('aria-pressed', String(item === button))); renderNotes(); }));
$('note-search').addEventListener('input', renderNotes); $('new-note').addEventListener('click', () => openNote()); $('refresh-notes').addEventListener('click', loadNotes);
async function loadSubjects() {
  try { const data = await api('/api/subjects'); $('subjects').replaceChildren(); const select = $('subject-filter'); const previous = select.value; select.replaceChildren(new Option('All subjects', '')); (data.subjects || []).forEach(subject => { $('subjects').append(new Option(subject, subject)); select.append(new Option(subject, subject)); }); select.value = previous; }
  catch (error) { report(error); }
}
async function loadMistakes() {
  try { const data = await api('/api/mistakes'); state.mistakes = data.mistakes || data.records || []; renderMistakes(); }
  catch (error) { report(error); }
}
function detail(title, value, className = '') { const item = node('div', 'detail ' + className); item.append(node('span', 'detail-label', title), node('div', '', value || 'Not added')); return item; }
function renderMistakes() {
  const query = $('mistake-search').value.toLowerCase().trim(); const subject = $('subject-filter').value; const status = $('status-filter').value;
  const records = state.mistakes.filter(record => (!subject || record.subject === subject) && (!status || resolved(record) === (status === 'resolved')) &&
    [record.topic, record.subject, record.question_text, record.wrong_answer, record.correct_answer, record.mistake_reason, record.reason, record.key_takeaway, record.takeaway, record.quiz_title].some(value => text(value).toLowerCase().includes(query)));
  $('mistake-count').textContent = state.mistakes.filter(record => !resolved(record)).length;
  $('mistake-summary').textContent = records.length + (records.length === 1 ? ' record' : ' records') + ' / ' + state.mistakes.filter(record => !resolved(record)).length + ' unresolved';
  const container = $('mistakes-container'); container.replaceChildren();
  if (!records.length) { empty(container, state.mistakes.length ? 'No matching mistakes' : 'Every correction is progress.', state.mistakes.length ? 'Try another search or clear the filters.' : 'Log a question and the lesson you want to remember.', 'mistake', state.mistakes.length ? null : openMistake); return; }
  records.forEach(record => {
    const card = node('article', 'mistake'); const head = node('div', 'mistake-head'); const heading = node('div'); const pills = node('div', 'pills');
    const severity = ['LOW', 'MEDIUM', 'HIGH'].includes(text(record.severity).toUpperCase()) ? text(record.severity).toUpperCase() : 'MEDIUM';
    pills.append(node('span', 'pill', record.subject || 'General'), node('span', 'pill ' + severity.toLowerCase(), severity));
    if (record.quiz_title) pills.append(node('span', 'pill', record.quiz_title));
    heading.append(pills, node('h2', '', record.topic || 'Study mistake')); head.append(heading, node('span', 'pill' + (resolved(record) ? ' resolved' : ''), resolved(record) ? 'Resolved' : 'Unresolved')); card.append(head);
    if (record.question_text) card.append(detail('QUESTION / SOURCE', record.question_text));
    const answers = node('div', 'answers'); answers.append(detail('YOUR ANSWER', record.wrong_answer, 'wrong'), detail('CORRECT ANSWER', record.correct_answer, 'correct')); card.append(answers);
    card.append(detail('WHY IT WENT WRONG', record.mistake_reason || record.reason, 'reason'), detail('KEY TAKEAWAY & FORMULAS', record.key_takeaway || record.takeaway, 'takeaway'));
    const foot = node('div', 'mistake-foot');
    foot.append(action(resolved(record) ? 'Mark unresolved' : 'Mark resolved', 'check', async event => {
      const button = event.currentTarget; button.disabled = true;
      try { await api('/api/mistakes/' + encodeURIComponent(record.id) + '/resolve', { method: 'PATCH', body: JSON.stringify({ resolved: !resolved(record) }) }); await loadMistakes(); toast('Mistake updated'); }
      catch (error) { report(error); } finally { button.disabled = false; }
    }, 'btn btn-tonal'), action('Delete record', 'delete', () => deleteRecord('mistake', record.id), 'btn btn-danger'));
    card.append(foot); container.append(card);
  });
}
function openMistake() { $('mistake-form').reset(); $('mistake-form-error').textContent = ''; $('mistake-dialog').showModal(); $('mistake-subject').focus(); }
$('mistake-form').addEventListener('submit', async event => {
  event.preventDefault(); const button = event.submitter || event.currentTarget.querySelector('button[type=submit]'); button.disabled = true; $('mistake-form-error').textContent = '';
  const fields = { subject: 'subject', topic: 'topic', severity: 'severity', quiz_title: 'quiz', question_text: 'question', wrong_answer: 'wrong', correct_answer: 'correct', mistake_reason: 'reason', key_takeaway: 'takeaway' }; const payload = {};
  Object.entries(fields).forEach(([key, field]) => payload[key] = $('mistake-' + field).value.trim());
  try { await api('/api/mistakes', { method: 'POST', body: JSON.stringify(payload) }); $('mistake-dialog').close(); await Promise.all([loadMistakes(), loadSubjects()]); toast('Mistake saved to your phone'); }
  catch (error) { $('mistake-form-error').textContent = error.message; } finally { button.disabled = false; }
});
$('new-mistake').addEventListener('click', openMistake); $('refresh-mistakes').addEventListener('click', loadMistakes); $('refresh-status').addEventListener('click', checkSession);
['mistake-search', 'subject-filter', 'status-filter'].forEach(id => $(id).addEventListener(id === 'mistake-search' ? 'input' : 'change', renderMistakes));
function confirmDelete() { return new Promise(resolve => { const dialog = $('confirm-dialog'); dialog.returnValue = 'cancel'; dialog.addEventListener('close', () => resolve(dialog.returnValue === 'delete'), { once: true }); dialog.showModal(); }); }
async function deleteRecord(type, id) {
  if (!await confirmDelete()) return;
  try { await api('/api/' + (type === 'note' ? 'notes/' : 'mistakes/') + encodeURIComponent(id), { method: 'DELETE' }); await (type === 'note' ? loadNotes() : loadMistakes()); toast(type === 'note' ? 'Note deleted' : 'Mistake deleted'); }
  catch (error) { report(error); }
}
setInterval(() => { if (state.authenticated && !document.hidden) checkSession(); }, 60000);
checkSession();
''';
}
