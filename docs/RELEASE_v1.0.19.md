# NYRO Tasks 1.0.19

This release batches the Today dashboard, subject-based traps, note readers, desktop privacy invalidation, and adaptive notification branding into one tag workflow.

## Data and behavior

The dashboard reads the existing daily pacing, lecture, revisit, and quiz queries. It introduces no schema change. Traps match normalized subject phrases against a quiz's subject, module, syllabus, and title; legacy records without a subject retain exact normalized title matching. Counts and modal lists share that matcher.

Keep's reader refreshes the note before display and editing. Protected content shares screenshot-protection ownership across nested reader/editor surfaces. Biometrics remain explicitly activated by their icon.

The desktop excludes protected notes and tags, checks protection inside write/delete transactions, and marks responses no-store. A privacy revision invalidates in-flight list responses and paired sessions. A streaming privacy event clears visible browser notes, reader/editor contents, and credentials. A three-second heartbeat provides a fallback; hiding the tab clears note contents, and returning validates the session before fetching fresh notes. Existing browser tabs must reload after an upgrade to receive this JavaScript. Previously copied data cannot be erased remotely. Note bodies remain local SQLite data, with the existing security and storage limits described in the prior release documentation.

Adaptive colors use a stable six-color palette. The app follows the selected subject or study date; notifications follow their task title. The desktop follows the phone's active accent. The preference persists in app configuration and native preferences so alarm delivery after reboot respects the switch. Existing reminder, note, and daily schedules are refreshed after a change. The icon silhouette is the same clipboard mark as the launcher, exported without its opaque background; the large icon uses the launcher bitmap. Android owns the surrounding notification template.

## Verification

Local checks: zero-emoji scanning, Dart lexical delimiter checks, embedded desktop JavaScript syntax/control references, XML parsing, and git whitespace checks. No local Flutter SDK or Gradle build is used.

GitHub Actions performs Flutter analysis, regression tests, UI preview capture, the GitHub APK build, and the Play AAB build. New tests cover cross-quiz trap retrieval, legacy locks, stale desktop writes/deletes, streaming session revocation, note readers, nested screenshot protection, DB-backed Today metrics, pinned sections, notification branding, and adaptive colors. A narrow-screen large-text layout test covers the dashboard summary.

Device checks remain necessary for OEM lock-screen styling, alarm wake/sound delivery, Android full-screen access, and biometrics. Google Play/Play Protect decisions cannot be guaranteed by passing CI.

Hub upload implementation, transfer endpoints, and BitChat are outside this change.
