import 'dart:convert';
import 'package:flutter/material.dart';
import 'desktop_web_styles.dart';
import 'desktop_web_script.dart';

class DesktopWebTemplate {
  static final icons = <String, int>{
    'note': Icons.description_outlined.codePoint,
    'mistake': Icons.edit_note_rounded.codePoint,
    'status': Icons.devices_rounded.codePoint,
    'lock': Icons.lock_outline_rounded.codePoint,
    'add': Icons.add_rounded.codePoint,
    'search': Icons.search_rounded.codePoint,
    'refresh': Icons.refresh_rounded.codePoint,
    'close': Icons.close_rounded.codePoint,
    'delete': Icons.delete_outline_rounded.codePoint,
    'pin': Icons.push_pin_outlined.codePoint,
    'archive': Icons.archive_outlined.codePoint,
    'check': Icons.check_rounded.codePoint,
    'edit': Icons.edit_outlined.codePoint,
    'connection': Icons.wifi_rounded.codePoint,
  };
  static String render({required String localIp, required int port, required String version}) {
    String icon(String name) => '<span class="mi" aria-hidden="true">&#' + icons[name].toString() + ';</span>';
    return '''<!DOCTYPE html>
<html lang="en" data-type="software">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="page-type" content="software"><meta name="site-kind" content="software">
<link rel="icon" type="image/png" href="/assets/prepdesk.png">
<meta name="theme-color" content="#f7f8fc"><meta name="description" content="Your Prepdesk notes and mistakes, connected to your phone.">
<title>Prepdesk Desktop Companion</title>
<style>${DesktopWebStyles.value}</style>
</head><body>
<a class="skip-link" href="#main-content">Skip to workspace</a>
<div class="app" id="app" inert>
<aside class="sidebar" aria-label="Workspace navigation">
  <div class="brand"><div class="brand-mark" aria-hidden="true"></div><div><div class="wordmark">Prepdesk</div><small>DESKTOP COMPANION</small></div></div>
  <nav class="nav" aria-label="Main navigation">
    <button type="button" data-tab="keep" aria-current="page">${icon('note')}<span>Keep notes</span><span id="note-count" class="count">0</span></button>
    <button type="button" data-tab="mistakes">${icon('mistake')}<span>Mistakes</span><span id="mistake-count" class="count">0</span></button>
    <button type="button" data-tab="status">${icon('status')}<span>Connection</span></button>
  </nav>
  <div class="sidebar-footer"><strong>Your phone. A bigger workspace.</strong>Keep Prepdesk open on the same Wi-Fi network.<br><br>Prepdesk v$version</div>
</aside>
<div class="workspace">
<header class="topbar"><span class="topbar-label">DESKTOP COMPANION</span><div class="topbar-actions"><span id="connection" class="connection">Checking connection</span><button class="btn" id="lock-button" type="button">${icon('lock')}<span>Lock</span></button></div></header>
<main id="main-content" tabindex="-1">
<div id="workspace-error" class="error-bar" role="alert" hidden></div>
<section class="panel" id="panel-keep" aria-labelledby="keep-title">
  <div class="page-head"><div><h1 id="keep-title">Keep notes</h1><p>Your notes and checklists, together. Protected notes stay on your phone.</p></div><button class="btn btn-primary" id="new-note" type="button">${icon('add')}New note</button></div>
  <div class="toolbar"><label class="search">${icon('search')}<span class="sr-only">Search notes</span><input id="note-search" type="search" placeholder="Search notes, checklists or tags"></label><div class="filters" aria-label="Note filters"><button class="filter" data-note-filter="all" aria-pressed="true">All notes</button><button class="filter" data-note-filter="pinned" aria-pressed="false">Pinned</button><button class="filter" data-note-filter="archive" aria-pressed="false">Archive</button></div></div>
  <div class="section-line"><span id="note-summary" aria-live="polite">Loading notes</span><button class="btn icon-button" type="button" id="refresh-notes" aria-label="Refresh notes" title="Refresh notes">${icon('refresh')}</button></div>
  <div class="notes-grid" id="notes-container"></div>
</section>
<section class="panel" id="panel-mistakes" aria-labelledby="mistake-title" hidden>
  <div class="page-head"><div><h1 id="mistake-title">Mistakes notebook</h1><p>Keep the question, the correction and what you learned in one place.</p></div><button class="btn btn-primary" id="new-mistake" type="button">${icon('add')}Log mistake</button></div>
  <div class="toolbar"><label class="search">${icon('search')}<span class="sr-only">Search mistakes</span><input id="mistake-search" type="search" placeholder="Search topics, answers or takeaways"></label><label class="sr-only" for="subject-filter">Subject</label><select id="subject-filter" class="select"><option value="">All subjects</option></select><label class="sr-only" for="status-filter">Status</label><select id="status-filter" class="select"><option value="">All statuses</option><option value="unresolved">Unresolved</option><option value="resolved">Resolved</option></select></div>
  <div class="section-line"><span id="mistake-summary" aria-live="polite">Loading mistakes</span><button class="btn icon-button" id="refresh-mistakes" type="button" aria-label="Refresh mistakes" title="Refresh mistakes">${icon('refresh')}</button></div>
  <div class="mistakes-list" id="mistakes-container"></div>
</section>
<section class="panel" id="panel-status" aria-labelledby="status-title" hidden>
  <div class="page-head"><div><h1 id="status-title">Connected to your phone.</h1><p>This workspace reads and saves directly to Prepdesk on your local network.</p></div><button class="btn" id="refresh-status" type="button">${icon('refresh')}Check connection</button></div>
  <div class="status-grid"><article class="status-card">${icon('connection')}<h2>Local connection</h2><p id="status-description">Checking your phone connection.</p><dl class="status-data"><dt>Phone address</dt><dd>$localIp:$port</dd><dt>App version</dt><dd>$version</dd><dt>Session</dt><dd id="session-status">Checking</dd></dl></article><article class="status-card">${icon('lock')}<h2>Your private workspace</h2><p>Pair using the six-digit code shown in your phone's Desktop Companion settings. Lock this workspace when you step away.</p><p>Protected Keep notes can only be opened and changed on your phone.</p><p>This connection is local HTTP. Use it on a trusted Wi-Fi network.</p></article></div>
</section>
</main></div></div>
<dialog id="pair-dialog" class="pair-dialog" aria-labelledby="pair-title">
<form id="pair-form" class="pair-content"><div class="pair-mark brand-mark" aria-hidden="true"></div><h1 id="pair-title">Open your study space</h1><p>Open Desktop Companion in Prepdesk on your phone, then enter the six-digit pairing code.</p><label class="sr-only" for="pair-pin">Six-digit pairing code</label><input id="pair-pin" type="password" inputmode="numeric" pattern="[0-9]{6}" minlength="6" maxlength="6" autocomplete="off" required placeholder="000000"><button class="btn btn-primary" type="submit">Connect to phone</button><p id="pair-error" class="form-error" role="alert"></p><small>Same Wi-Fi network. No cloud sign-in required.</small></form>
</dialog>
<dialog id="note-reader" aria-labelledby="reader-title">
<div class="dialog-head"><h2 id="reader-title">Note</h2><button class="btn icon-button" type="button" data-close="note-reader" aria-label="Close note">${icon('close')}</button></div>
<div id="reader-body" class="dialog-body note-reader-body"></div>
<div class="dialog-foot"><button id="reader-edit" class="btn btn-primary" type="button">${icon('edit')} Edit note</button></div>
</dialog>
<dialog id="note-dialog" aria-labelledby="note-dialog-title"><form id="note-form">
<div class="dialog-head"><div><h2 id="note-dialog-title">New note</h2><p>Make space for an idea.</p></div><button class="btn icon-button" type="button" data-close="note-dialog" aria-label="Close note">${icon('close')}</button></div>
<div class="dialog-body"><div class="field"><label for="note-title">Title</label><input id="note-title" maxlength="500" placeholder="Give your note a title"></div><div class="field"><label for="note-content">Note</label><textarea id="note-content" rows="8" placeholder="Start writing..."></textarea></div><div class="fields"><div class="field"><label for="note-tags">Tags, separated by commas</label><input id="note-tags" placeholder="Revision, formulas"></div><div class="field"><label for="note-color">Note color</label><select id="note-color"><option value="#FFFFFF">Paper</option><option value="#F28B82">Coral</option><option value="#FBBC04">Peach</option><option value="#FFF475">Sand</option><option value="#CCFF90">Mint</option><option value="#A7FFEB">Sage</option><option value="#CBF0F8">Fog</option><option value="#AECBFA">Storm</option><option value="#D7AEFB">Dusk</option><option value="#FDCFE8">Blossom</option><option value="#E6C9A8">Clay</option><option value="#E8EAED">Chalk</option></select></div></div><p id="note-form-error" class="form-error" role="alert"></p></div>
<div class="dialog-foot"><button class="btn" type="button" data-close="note-dialog">Cancel</button><button class="btn btn-primary" type="submit">Save note</button></div>
</form></dialog>
<dialog id="mistake-dialog" aria-labelledby="mistake-dialog-title"><form id="mistake-form">
<div class="dialog-head"><div><h2 id="mistake-dialog-title">Log a mistake</h2><p>A useful correction starts with what happened.</p></div><button class="btn icon-button" type="button" data-close="mistake-dialog" aria-label="Close mistake form">${icon('close')}</button></div>
<div class="dialog-body"><div class="fields"><div class="field"><label for="mistake-subject">Subject</label><input id="mistake-subject" list="subjects" required maxlength="200" placeholder="Linear Algebra"><datalist id="subjects"></datalist></div><div class="field"><label for="mistake-topic">Topic</label><input id="mistake-topic" required maxlength="500" placeholder="Eigenvalues"></div><div class="field"><label for="mistake-severity">Severity</label><select id="mistake-severity"><option>LOW</option><option selected>MEDIUM</option><option>HIGH</option></select></div><div class="field"><label for="mistake-quiz">Linked quiz</label><input id="mistake-quiz" placeholder="Optional quiz title"></div></div><div class="field"><label for="mistake-question">Question or source</label><textarea id="mistake-question" rows="3"></textarea></div><div class="fields"><div class="field"><label for="mistake-wrong">Your answer</label><textarea id="mistake-wrong" rows="3"></textarea></div><div class="field"><label for="mistake-correct">Correct answer</label><textarea id="mistake-correct" rows="3"></textarea></div></div><div class="field"><label for="mistake-reason">Why it went wrong</label><textarea id="mistake-reason" rows="2"></textarea></div><div class="field"><label for="mistake-takeaway">Key takeaway and formulas</label><textarea id="mistake-takeaway" rows="3"></textarea></div><p id="mistake-form-error" class="form-error" role="alert"></p></div>
<div class="dialog-foot"><button class="btn" type="button" data-close="mistake-dialog">Cancel</button><button class="btn btn-primary" type="submit">Save mistake</button></div></form></dialog>
<dialog id="confirm-dialog" aria-labelledby="confirm-title"><div class="dialog-head"><h2 id="confirm-title">Delete this record?</h2></div><div class="dialog-body"><p>This removes the record from your phone too. This cannot be undone.</p></div><form method="dialog" class="dialog-foot"><button class="btn" value="cancel">Cancel</button><button class="btn btn-danger" value="delete">Delete</button></form></dialog>
<div class="toast" id="toast" role="status" hidden></div>
<script>window.NYRO_ICONS = ${jsonEncode(icons)};</script><script>${DesktopWebScript.value}</script>
</body></html>''';
  }
}
