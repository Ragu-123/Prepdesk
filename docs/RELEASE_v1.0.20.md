# NYRO Tasks 1.0.20

## Appearance

Adaptive colors now lives in Settings > Appearance. The category page shows the current accent and explains when it changes. The settings category order begins with Desktop Companion Studio, In-App Updates, Keep Vault, and Reminders; Appearance and Cloud Sync follow.

A new foreground session chooses randomly from six readable accents, excluding the previous accent. This happens at a cold launch and when returning after the app was paused or hidden. Inactive-only transitions, such as some transient system overlays, do not rotate it. Regular initialization reloads, navigation, subject filters, and widget rebuilds keep the session color. Turning adaptive colors off restores fixed blue and prevents further rotation.

One light theme builder supplies both adaptive and fixed modes. Buttons, input focus, selection handles, progress indicators, navigation, dialogs, calendars, switches and chips share its color scheme. Theme-aware UI roles replace fixed blue accents across Home quick-add forms, reminders, schedules, quizzes, revisits, Keep controls, filters, settings, banners and vault prompts. Date/time pickers inherit the complete scheme instead of creating a separate default scheme. Error, success, severity, and user-selected Keep note colors retain their meanings.

Notifications follow the same session accent. Native alarm preferences persist the accent for background/reboot delivery; the native ringing screen also uses it. Existing scheduled reminder, note and routine notifications refresh without history duplication or permission prompts when the session accent changes. Desktop controls and hover surfaces follow the phone's accent through the existing session heartbeat.

Task checkboxes retain their circular style with a 48 dp touch target, checked semantics, and reduced-motion support. App bar typography uses the bundled font explicitly.

The reminder editor's additional-reminder row wraps its label and uses a full-size text button so narrow screens do not overflow.

## Verification

Local checks are lexical Dart delimiter/quote checks, zero-emoji scanning, XML parsing, desktop JavaScript syntax and control references, shared theme-role guards, and git whitespace checks. Flutter remains CI-only.

CI performs analysis, the existing privacy/reminder/trap regressions, new appearance grouping and session persistence tests, non-repeating color selection tests, contrast checks for all palettes, live reminder/calendar color checks, schedule quick-add checks, generated UI previews, APK and Play AAB builds. Physical-device notification templates and lifecycle behavior still require device verification.

Hub transfer implementation and BitChat are unchanged. Existing security behavior is preserved; vault changes in this release are visual styling only. This release does not claim Google Play or Play Protect approval.
