class DesktopWebScript {
  static const value = r'''
'use strict';
const $ = id => document.getElementById(id);
const state = { notes: [], mistakes: [], files: [], fileSharingEnabled: false, noteFilter: 'all', fileFilter: 'all', editingNote: null, token: sessionStorage.getItem('nyro_token') || localStorage.getItem('nyro_token') || '', authenticated: false, activeUploadXhrs: [], activeUploadIds: [], uploading: false };
localStorage.removeItem('nyro_token');
if (state.token) sessionStorage.setItem('nyro_token', state.token);
const truth = value => value === true || value === 1;
const resolved = record => ['RESOLVED', 'COMPLETED', 'DONE'].includes(String(record.status || '').toUpperCase());
const text = value => value == null ? '' : String(value);
function node(tag, className, value) { const item = document.createElement(tag); if (className) item.className = className; if (value != null) item.textContent = value; return item; }
function icon(name) { const item = node('span', 'mi', String.fromCodePoint(window.NYRO_ICONS[name] || window.NYRO_ICONS.note)); item.setAttribute('aria-hidden', 'true'); return item; }
function action(label, symbol, callback, style = 'btn icon-button') { const button = node('button', style); button.type = 'button'; button.title = label; button.setAttribute('aria-label', label); if (symbol) button.append(icon(symbol)); if (!symbol || !style.includes('icon-button')) button.append(node('span', '', label)); button.addEventListener('click', callback); return button; }
function jsonList(value) { if (Array.isArray(value)) return value; try { const parsed = JSON.parse(value || '[]'); return Array.isArray(parsed) ? parsed : []; } catch (_) { return []; } }
let sessionStream;
let privacyRevision;
let toastTimer;
function toast(message) { $('toast').textContent = message; $('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').hidden = true, 4500); }
function report(error) { $('workspace-error').textContent = error.message || 'Unable to reach your phone. Check the connection and retry.'; $('workspace-error').hidden = false; }
function connected(value) { $('connection').textContent = value ? 'Phone connected' : 'Connection interrupted'; $('connection').classList.toggle('offline', !value); $('session-status').textContent = value ? 'Paired' : 'Not connected'; $('status-description').textContent = value ? 'Your phone is reachable. Changes save directly to Prepdesk.' : 'Keep Prepdesk open and check that both devices are on the same Wi-Fi network.'; }
function applyAppearance(accent) {
  if (!/^#[0-9a-fA-F]{6}$/.test(accent || '')) return;
  const style = document.documentElement.style;
  style.setProperty('--primary', accent);
  style.setProperty('--primary-hover', 'color-mix(in srgb, ' + accent + ' 85%, black)');
  style.setProperty('--tonal', 'color-mix(in srgb, ' + accent + ' 15%, white)');
  style.setProperty('--canvas', 'color-mix(in srgb, ' + accent + ' 3%, white)');
}
function applyFileSharingState(enabled) {
  state.fileSharingEnabled = Boolean(enabled);
  $('files-disabled-banner').hidden = state.fileSharingEnabled;
  $('file-dropzone').hidden = !state.fileSharingEnabled;
  $('pick-upload').disabled = !state.fileSharingEnabled;
  $('file-sharing-status').textContent = state.fileSharingEnabled ? 'Enabled (Phone <-> PC)' : 'Turned off on phone';
}
async function api(path, options = {}) {
  const requestToken = state.token;
  const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(path, { ...options, signal: controller.signal, headers: { 'Content-Type': 'application/json', ...(state.token ? { Authorization: 'Bearer ' + state.token } : {}), ...options.headers } });
    const data = await response.json().catch(() => ({}));
    if (response.status === 401) { lockLocal(); throw new Error('Your session expired. Pair with your phone again.'); }
    if (requestToken !== state.token && path !== '/api/auth/verify') throw new Error('Session changed. Pair again.');
    if (!response.ok) throw new Error(data.error || 'The change could not be saved. Please retry.');
    connected(true); return data;
  } catch (error) { if (error.name === 'AbortError') throw new Error('Your phone did not respond. Check the Wi-Fi connection and retry.'); throw error; }
  finally { clearTimeout(timer); }
}
function lockLocal() {
  abortActiveUploads();
  if (sessionStream) { sessionStream.abort(); sessionStream = null; }
  privacyRevision = undefined;
  state.authenticated = false; state.token = ''; state.notes = []; state.mistakes = []; state.files = []; state.editingNote = null;
  sessionStorage.removeItem('nyro_token'); $('app').inert = true;
  document.querySelectorAll('dialog[open]').forEach(dialog => dialog.close());
  $('notes-container').replaceChildren(); $('mistakes-container').replaceChildren(); $('files-container').replaceChildren();
  $('note-form').reset(); $('mistake-form').reset(); $('pair-pin').value = '';
  $('reader-title').textContent = 'Note'; $('reader-body').replaceChildren();
  $('preview-body').replaceChildren();
  if (!$('pair-dialog').open) $('pair-dialog').showModal();
  $('pair-pin').focus(); connected(false);
}
async function lockStudio() { try { await api('/api/auth/logout', { method: 'POST' }); } catch (_) {} finally { lockLocal(); } }
async function watchPrivacy() {
  if (sessionStream) sessionStream.abort();
  const controller = new AbortController(); sessionStream = controller;
  try {
    const response = await fetch('/api/session/events', { headers: { Authorization: 'Bearer ' + state.token }, signal: controller.signal, cache: 'no-store' });
    if (response.status === 401) { lockLocal(); return; }
    if (!response.ok || !response.body) return;
    const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = '';
    while (!controller.signal.aborted) {
      const chunk = await reader.read(); if (chunk.done) break;
      buffer += decoder.decode(chunk.value, { stream: true });
      const frames = buffer.split(/\r?\n\r?\n/); buffer = frames.pop();
      for (const frame of frames) {
        if (frame.includes('event: privacy')) { lockLocal(); return; }
        if (frame.includes('event: files')) {
          try {
            const dataLine = frame.split(/\r?\n/).find(line => line.startsWith('data:'));
            if (dataLine) {
              const info = JSON.parse(dataLine.slice(5).trim());
              applyFileSharingState(info.file_sharing_enabled);
              if (info.file_sharing_enabled) loadFiles();
              else { state.files = []; renderFiles(); }
            }
          } catch (_) {}
        }
      }
    }
  } catch (_) { /* Heartbeat also checks revocation if streaming is interrupted. */ }
}
async function loadWorkspace() {
  $('app').inert = false; $('pair-dialog').close(); state.authenticated = true; watchPrivacy(); $('workspace-error').hidden = true;
  await Promise.allSettled([loadNotes(), loadMistakes(), loadSubjects(), state.fileSharingEnabled ? loadFiles() : Promise.resolve()]);
}
async function checkSession() {
  if (!state.token) { lockLocal(); return; }
  try { const data = await api('/api/auth/status'); if (data.authenticated) {
    if (privacyRevision !== undefined && data.privacy_revision !== privacyRevision) { lockLocal(); return; }
    privacyRevision = data.privacy_revision; applyAppearance(data.accent); applyFileSharingState(data.file_sharing_enabled);
    if (!state.authenticated) await loadWorkspace();
  } else lockLocal(); }
  catch (_) { lockLocal(); }
}
$('pair-dialog').addEventListener('cancel', event => event.preventDefault());
$('pair-form').addEventListener('submit', async event => {
  event.preventDefault(); const button = event.submitter || event.currentTarget.querySelector('button[type=submit]'); button.disabled = true; $('pair-error').textContent = '';
  try {
    const data = await api('/api/auth/verify', { method: 'POST', body: JSON.stringify({ pin: $('pair-pin').value }) });
    if (!data.success || !data.token) throw new Error(data.error || 'That code was not accepted. Check the code on your phone.');
    state.token = data.token; sessionStorage.setItem('nyro_token', state.token); $('pair-pin').value = '';
    const status = await api('/api/auth/status').catch(() => ({}));
    applyAppearance(status.accent); applyFileSharingState(status.file_sharing_enabled);
    await loadWorkspace();
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
  if (target === 'files' && state.fileSharingEnabled) loadFiles();
}));
document.querySelectorAll('[data-close]').forEach(button => button.addEventListener('click', () => {
  const targetId = button.dataset.close;
  if (targetId === 'file-preview-dialog') $('preview-body').replaceChildren();
  $(targetId).close();
}));
$('preview-close').addEventListener('click', () => $('preview-body').replaceChildren());
function empty(container, heading, description, symbol, onCreate) {
  const item = node('div', 'empty'); item.append(icon(symbol), node('h2', '', heading), node('p', '', description));
  if (onCreate) item.append(action('Create one', 'add', onCreate, 'btn btn-tonal'));
  container.append(item);
}
async function loadNotes() {
  try { const data = await api('/api/notes?archived=true'); if (document.hidden || !state.authenticated) return; state.notes = (data.notes || []).filter(note => !truth(note.is_locked)); renderNotes(); $('workspace-error').hidden = true; }
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
    const open = node('button', 'note-open'); open.type = 'button'; open.addEventListener('click', () => readNote(note));
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
function readNote(note) {
  state.editingNote = note;
  $('reader-title').textContent = note.title || 'Untitled note';
  const body = $('reader-body'); body.replaceChildren();
  body.append(node('div', truth(note.is_code) ? 'reader-text reader-code' : 'reader-text', note.content));
  if (truth(note.is_todo_list)) jsonList(note.todo_items_json).forEach(item => {
    const row = node('p', 'reader-check'); row.append(icon(item.checked ? 'check' : 'note'), node('span', '', item.text)); body.append(row);
  });
  const tags = node('div', 'note-meta'); jsonList(note.tags_json).forEach(tag => tags.append(node('span', 'tag', tag))); body.append(tags);
  $('note-reader').showModal(); $('reader-edit').focus();
}
$('reader-edit').addEventListener('click', () => {
  const note = state.editingNote;
  $('note-reader').close(); $('reader-title').textContent = 'Note'; $('reader-body').replaceChildren();
  if (note && state.authenticated) openNote(note);
});
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

// --- Bidirectional Ultra-Fast File Sharing ---
function fileKindIcon(file) {
  const mime = String(file.mime_type || '').toLowerCase();
  const ext = String(file.extension || '').toLowerCase();
  if (ext === 'pdf' || mime.includes('pdf')) return 'pdf';
  if (mime.startsWith('video/') || ['mp4', 'mkv', 'webm', 'mov', 'avi'].includes(ext)) return 'video';
  if (mime.startsWith('audio/') || ['mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac'].includes(ext)) return 'audio';
  if (mime.startsWith('image/') || ['png', 'jpg', 'jpeg', 'webp', 'gif'].includes(ext)) return 'image';
  return 'file';
}
function isPreviewable(file) {
  const kind = fileKindIcon(file);
  return ['pdf', 'video', 'audio', 'image'].includes(kind);
}
async function loadFiles() {
  if (!state.fileSharingEnabled) { state.files = []; renderFiles(); return; }
  try { const data = await api('/api/files'); state.files = data.files || []; renderFiles(); }
  catch (error) { if (String(error.message || '').includes('turned off')) applyFileSharingState(false); else report(error); }
}
function renderFiles() {
  const query = $('file-search').value.toLowerCase().trim();
  const files = state.files.filter(f => {
    if (state.fileFilter === 'phone' && f.source !== 'phone') return false;
    if (state.fileFilter === 'pc' && f.source !== 'pc') return false;
    if (state.fileFilter === 'media' && !isPreviewable(f)) return false;
    return [f.name, f.extension, f.mime_type, f.uploaded_by].some(v => text(v).toLowerCase().includes(query));
  });
  $('file-count').textContent = state.files.length;
  $('file-summary').textContent = !state.fileSharingEnabled ? 'File sharing disabled on phone' : (files.length + (files.length === 1 ? ' file' : ' files') + ' ready to open or download');
  const container = $('files-container'); container.replaceChildren();
  if (!state.fileSharingEnabled) return;
  if (!files.length) { empty(container, query ? 'No matching files' : 'Share any file with your phone', query ? 'Try another filename or clear the filter.' : 'Drop PDF, MP4, MKV, MP3, WAV or any file above, or share from your phone settings.', 'folder', null); return; }
  files.forEach(file => {
    const row = node('article', 'file-row');
    const iconBox = node('div', 'file-icon'); iconBox.append(icon(fileKindIcon(file)));
    const info = node('div', 'file-info');
    info.append(node('div', 'file-title', file.name));
    const meta = node('div', 'file-meta');
    meta.append(node('span', 'pill', (file.extension || 'FILE').toUpperCase()), node('span', '', file.size_display || ''), node('span', 'pill', file.source === 'phone' ? 'From phone' : 'Sent from PC'));
    if (file.created_at) meta.append(node('span', '', new Date(file.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })));
    info.append(meta);
    const acts = node('div', 'file-actions');
    if (isPreviewable(file)) acts.append(action('Preview', 'play', () => openFilePreview(file), 'btn btn-tonal'));
    acts.append(action('Download', 'download', () => downloadSharedFile(file), 'btn'), action('Delete', 'delete', () => deleteRecord('file', file.id)));
    row.append(iconBox, info, acts);
    container.append(row);
  });
}
async function downloadSharedFile(file) {
  try {
    const res = await api('/api/files/ticket', { method: 'POST', body: JSON.stringify({ id: file.id }) });
    const a = document.createElement('a');
    a.href = '/api/files/download/' + encodeURIComponent(file.id) + '?ticket=' + encodeURIComponent(res.ticket);
    a.download = file.name;
    document.body.append(a); a.click(); a.remove();
  } catch (error) { report(error); }
}
async function openFilePreview(file) {
  try {
    const res = await api('/api/files/ticket', { method: 'POST', body: JSON.stringify({ id: file.id }) });
    const url = '/api/files/download/' + encodeURIComponent(file.id) + '?ticket=' + encodeURIComponent(res.ticket) + '&preview=1';
    $('preview-title').textContent = file.name;
    $('preview-download').href = '/api/files/download/' + encodeURIComponent(file.id) + '?ticket=' + encodeURIComponent(res.ticket);
    $('preview-download').download = file.name;
    const body = $('preview-body'); body.replaceChildren();
    const kind = fileKindIcon(file);
    if (kind === 'video') { const v = document.createElement('video'); v.controls = true; v.autoplay = true; v.playsInline = true; v.src = url; body.append(v); }
    else if (kind === 'audio') { const a = document.createElement('audio'); a.controls = true; a.autoplay = true; a.src = url; body.append(a); }
    else if (kind === 'image') { const i = document.createElement('img'); i.src = url; i.alt = file.name; body.append(i); }
    else { const frame = document.createElement('iframe'); frame.src = url; frame.title = file.name; body.append(frame); }
    $('file-preview-dialog').showModal();
  } catch (error) { report(error); }
}
function updateUploadProgress(name, sentBytes, totalBytes, startedAt) {
  const pct = totalBytes > 0 ? Math.min(100, Math.round((sentBytes / totalBytes) * 100)) : 0;
  const elapsedSec = Math.max(0.1, (Date.now() - startedAt) / 1000);
  const mbps = (sentBytes / (1024 * 1024)) / elapsedSec;
  $('upload-progress-wrap').hidden = false;
  $('upload-status-name').textContent = name;
  $('upload-status-meta').textContent = pct + '% • ' + mbps.toFixed(1) + ' MB/s';
  $('upload-progress-bar').style.width = pct + '%';
}
function abortActiveUploads() {
  state.activeUploadXhrs.forEach(xhr => { try { xhr.abort(); } catch (_) {} });
  state.activeUploadXhrs = [];
  state.activeUploadIds.forEach(id => { api('/api/files/upload/abort', { method: 'POST', body: JSON.stringify({ upload_id: id }) }).catch(() => {}); });
  state.activeUploadIds = [];
  state.uploading = false;
  $('upload-progress-wrap').hidden = true;
}
function uploadSingleXhr(url, method, blob, extraHeaders, onBytes) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    state.activeUploadXhrs.push(xhr);
    let lastLoaded = 0;
    xhr.open(method, url, true);
    if (state.token) xhr.setRequestHeader('Authorization', 'Bearer ' + state.token);
    Object.entries(extraHeaders || {}).forEach(([k, v]) => xhr.setRequestHeader(k, v));
    xhr.upload.onprogress = evt => { if (evt.lengthComputable) { const delta = Math.max(0, evt.loaded - lastLoaded); lastLoaded = evt.loaded; onBytes(delta); } };
    xhr.onload = () => {
      state.activeUploadXhrs = state.activeUploadXhrs.filter(x => x !== xhr);
      if (xhr.status >= 200 && xhr.status < 300) resolve(JSON.parse(xhr.responseText || '{}'));
      else { let err = 'Upload failed'; try { err = JSON.parse(xhr.responseText).error || err; } catch (_) {} reject(new Error(err)); }
    };
    xhr.onerror = () => { state.activeUploadXhrs = state.activeUploadXhrs.filter(x => x !== xhr); reject(new Error('Network interruption during upload')); };
    xhr.onabort = () => { state.activeUploadXhrs = state.activeUploadXhrs.filter(x => x !== xhr); reject(new Error('Upload cancelled')); };
    xhr.send(blob);
  });
}
async function sendFilesToPhone(fileList) {
  if (!state.fileSharingEnabled) { toast('Enable File Sharing on your phone first.'); return; }
  const files = Array.from(fileList || []).filter(f => f && f.size >= 0);
  if (!files.length || state.uploading) return;
  state.uploading = true;
  const DIRECT_LIMIT = 8 * 1024 * 1024;
  const CHUNK_SIZE = 4 * 1024 * 1024;
  const PARALLEL = 3;
  try {
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const startedAt = Date.now();
      let sentBytes = 0;
      const label = (files.length > 1 ? '(' + (i + 1) + '/' + files.length + ') ' : '') + file.name;
      updateUploadProgress(label, 0, file.size, startedAt);
      if (file.size <= DIRECT_LIMIT) {
        await uploadSingleXhr('/api/files/upload', 'POST', file, { 'X-File-Name': encodeURIComponent(file.name), 'Content-Type': 'application/octet-stream' }, delta => { sentBytes += delta; updateUploadProgress(label, sentBytes, file.size, startedAt); });
      } else {
        const init = await api('/api/files/upload/init', { method: 'POST', body: JSON.stringify({ name: file.name, size: file.size }) });
        const uploadId = init.upload_id;
        state.activeUploadIds.push(uploadId);
        const offsets = [];
        for (let off = 0; off < file.size; off += CHUNK_SIZE) offsets.push(off);
        let cursor = 0;
        const worker = async () => {
          while (cursor < offsets.length) {
            const off = offsets[cursor++];
            const slice = file.slice(off, Math.min(file.size, off + CHUNK_SIZE));
            await uploadSingleXhr('/api/files/upload/chunk?upload_id=' + encodeURIComponent(uploadId) + '&offset=' + off, 'PUT', slice, { 'Content-Type': 'application/octet-stream' }, delta => { sentBytes += delta; updateUploadProgress(label, sentBytes, file.size, startedAt); });
          }
        };
        await Promise.all(Array.from({ length: Math.min(PARALLEL, offsets.length) }, worker));
        await api('/api/files/upload/complete', { method: 'POST', body: JSON.stringify({ upload_id: uploadId }) });
        state.activeUploadIds = state.activeUploadIds.filter(id => id !== uploadId);
      }
      toast('Sent ' + file.name + ' to phone');
    }
    await loadFiles();
  } catch (error) { if (error.message !== 'Upload cancelled') report(error); }
  finally { state.uploading = false; $('upload-progress-wrap').hidden = true; $('file-input').value = ''; }
}
$('pick-upload').addEventListener('click', () => $('file-input').click());
$('file-dropzone').addEventListener('click', () => $('file-input').click());
$('file-dropzone').addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); $('file-input').click(); } });
$('file-input').addEventListener('change', e => sendFilesToPhone(e.target.files));
['dragenter', 'dragover'].forEach(ev => $('file-dropzone').addEventListener(ev, e => { e.preventDefault(); $('file-dropzone').classList.add('is-dragging'); }));
['dragleave', 'drop'].forEach(ev => $('file-dropzone').addEventListener(ev, e => { e.preventDefault(); $('file-dropzone').classList.remove('is-dragging'); }));
$('file-dropzone').addEventListener('drop', e => sendFilesToPhone(e.dataTransfer && e.dataTransfer.files));
$('abort-uploads').addEventListener('click', abortActiveUploads);
$('refresh-files').addEventListener('click', loadFiles);
$('file-search').addEventListener('input', renderFiles);
document.querySelectorAll('[data-file-filter]').forEach(button => button.addEventListener('click', () => { state.fileFilter = button.dataset.fileFilter; document.querySelectorAll('[data-file-filter]').forEach(item => item.setAttribute('aria-pressed', String(item === button))); renderFiles(); }));
function confirmDelete() { return new Promise(resolve => { const dialog = $('confirm-dialog'); dialog.returnValue = 'cancel'; dialog.addEventListener('close', () => resolve(dialog.returnValue === 'delete'), { once: true }); dialog.showModal(); }); }
async function deleteRecord(type, id) {
  if (!await confirmDelete()) return;
  const endpoint = type === 'note' ? 'notes/' : (type === 'file' ? 'files/' : 'mistakes/');
  try { await api('/api/' + endpoint + encodeURIComponent(id), { method: 'DELETE' }); await (type === 'note' ? loadNotes() : (type === 'file' ? loadFiles() : loadMistakes())); toast(type === 'note' ? 'Note deleted' : (type === 'file' ? 'File removed' : 'Mistake deleted')); }
  catch (error) { report(error); }
}
setInterval(() => { if (state.authenticated && !document.hidden) checkSession(); }, 3000);
document.addEventListener('visibilitychange', async () => {
  if (document.hidden) {
    state.notes = []; state.editingNote = null; $('notes-container').replaceChildren();
    $('note-form').reset(); $('note-dialog').close(); $('note-reader').close();
    $('reader-title').textContent = 'Note'; $('reader-body').replaceChildren(); $('app').inert = true;
  } else if (state.token) {
    await checkSession();
    if (state.authenticated) { await Promise.allSettled([loadNotes(), state.fileSharingEnabled ? loadFiles() : Promise.resolve()]); $('app').inert = false; }
  }
});
checkSession();
''';
}
