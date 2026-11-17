# NYRO Tasks v1.0.18

This release refreshes the light interface and Desktop Companion Studio, fixes multi-checkpoint reminders, and replaces notification-only alarms with native Android ringing alarms.

## What changed

- Floating, rounded navigation inspired by the music app reference, Material icons, bundled typography, tonal controls, and short transitions that respect reduced motion.
- Native alarm-clock scheduling, looping alarm audio, vibration, a lock-screen alarm activity, Snooze 5/10 minutes, Dismiss, a two-minute ringing timeout, and reboot restoration. The alarm editor's test control schedules an actual ringing alarm two seconds ahead.
- Task names appear as notification titles, with expanded text and clear actions. In-app notifications use larger, bolder headings. Protected note contents remain hidden.
- Grant buttons disappear after access is enabled. Permission status refreshes when returning from Android settings. Startup does not request permissions.
- A one-time reminder remains active while future checkpoints exist. Checking off an occurrence advances to the next checkpoint; it completes only after the last occurrence.
- Routine setting changes reschedule notifications immediately, using the saved morning and evening times.
- PIN changes and removal require the current PIN. PIN removal is blocked while protected notes exist. Missing credentials cannot be replaced by opening a protected note.
- Salted PBKDF2 PIN verification with failed-attempt throttling and device-backed credential storage. Legacy PINs migrate after successful PIN authentication.
- Biometrics start only after tapping the biometric icon. Protected editors lock after backgrounding and block screen capture while open.
- Desktop pairing, navigation, search, note editing/pinning/archiving, mistake forms, status filters, and error feedback share the app's visual system. Fonts and Material icons are served by the phone, without external font requests.
- Desktop APIs reject attempts to overwrite or delete protected notes and exclude their contents from listings. Cloud export sanitization excludes vault credentials and protected notes; existing protected notes are preserved during database restore.

The Hub upload service and its bridge/fallback transfer paths are unchanged. BitChat is unchanged.

## Alarm setup

Enable Notifications, Precise timing, and Full-screen alarms in Settings > Reminders & Routine Alerts. These are separate Android access controls. Once granted, the Enable actions disappear. Choose alarm mode for reminders that should ring; banner mode remains a normal notification.

Use the alarm editor's ringing test, then verify a saved alarm while the screen is locked. Snooze should stop audio immediately and ring again after the selected interval. Device alarm volume, Do Not Disturb, and manufacturer behavior still require device verification.

## Validation and release

All Flutter and Gradle work runs in GitHub Actions. No local Flutter SDK is installed or used. The workflow validates Dart, regression tests, and embedded desktop JavaScript, then builds the GitHub APK and Play-distribution AAB. Only a successful version-tag run publishes the release. Branch pushes alone do not start duplicate builds; workflow dispatch remains available.

Regression coverage includes automatic and manual multi-checkpoint completion, native alarm delegation, credential migration, missing-credential denial, protected-note export filtering, desktop API protection, and permission-panel layout/state. Desktop browser interaction checks use synthetic fixtures and cover note creation/editing/search/pinning/archive/delete and mistake creation/filtering/resolution/delete. These checks do not establish end-to-end behavior on every Android device or the user's live LAN.

The desktop design check found and prompted fixes for heading order and keyboard focus contrast. Its remaining landing-page checks concern hero sections, decorative moments, marketing imagery, equal-height marketing rows, and full-page container rules; those do not describe this functional sidebar workspace. Its open findings are documented in `DESKTOP_DESIGN_REVIEW.md`, rather than reported as a clean gate pass.

## Before Google Play submission

The Play AAB targets API 36, removes APK-install permission, and routes update checks to Google Play. It is a submission candidate, not a guarantee of Play approval or removal of a Play Protect warning.

Review Play Console's full-screen intent and foreground-service declarations, privacy policy, Data safety form, and required testing. The existing repository signing identity is preserved for GitHub upgrade compatibility; a dedicated Play upload key and Play App Signing should be configured before store release because signing material exists in repository history.

The vault changes harden app access and credential storage. Note rows still use the app's SQLite database; this release does not claim PIN-derived content encryption or end-to-end encrypted backups. Protected notes stay local and are excluded from cloud exports.

For an incorrect harmful-app classification, use Google's [app verification appeal](https://support.google.com/googleplay/android-developer/answer/2992033). Uploading a backup to a particular provider does not, by itself, establish the cause of a warning. Google publishes [target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878) and [Play Protect developer guidance](https://developers.google.com/android/play-protect/warning-dev-guidance).
