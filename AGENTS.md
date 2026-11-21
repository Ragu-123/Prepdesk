# AGENTS.md — NYRO Tasks Project Guide & Handoff for AI Agents

> **Audience**: AI Coding Agents (Codex, Antigravity, Claude, DeepCoder, etc.) working on the **NYRO Tasks** Android application.
> **Purpose**: Single source of truth containing hard constraints, architecture guidelines, navigation hierarchy, database migration rules, and the exact step-by-step GitHub Actions build procedure to ensure zero errors and seamless upgrades.

---

## 1. Critical Rules & Inviolable Constraints

1. **Zero Emojis Everywhere**:
   - Strictly **0 emojis** in all Dart code, HTML, CSS, JavaScript, JSON, and strings.
   - Use Material 3 / Google font icons (`Icons.*`) exclusively for icons, badges, and visual status indicators.
   - Every agent MUST run a zero-emoji scanner before committing.

2. **No Local Flutter / Gradle Builds**:
   - The local environment is a Windows host without a working Flutter SDK or Android build toolchain installed in PATH.
   - **DO NOT** run `flutter build`, `flutter run`, `flutter analyze`, or `./gradlew assembleRelease` locally. They will fail.
   - **All APK builds and compiler checks occur exclusively via GitHub Actions CI**.
   - Local validation is performed via AST bracket/parenthesis/quote balance checker scripts, Node.js syntax verification for embedded web scripts, and symbol regex checks.

3. **Active Repository & Working Directory**:
   - Root project folder: `c:\Users\SEC\Downloads\gate2027\tasksapp\android\Tasks`.
   - Git remote: `gh-origin` -> `https://github.com/Ragu-123/nyro-tasks.git`.
   - `master` is protected. Use `pre-prod` for all changes and open pull requests from `pre-prod` into `master`.
   - Keep these two branches in the repository. Use version tags for releases.
   - **Never touch or navigate to `slip-app`** — `Tasks` is the only active application repository.

4. **Modular Architecture — Never Bloat Monolithic Files**:
   - Never place all features or handlers into a single file. Keep UI widgets, data models, REST handlers, and services cleanly decomposed into their designated modular directories.

---

## 2. Architecture & Modular Directory Map

```
Tasks/
├── android/                         # Native Android Gradle configuration & manifests
│   └── app/src/main/AndroidManifest.xml  # Includes USE_FULL_SCREEN_INTENT, Bluetooth permissions
├── lib/
│   ├── data/
│   │   ├── database_service.dart    # SQLite persistence, schema creation, defensive migrations
│   │   └── keep_note_model.dart     # KeepNote, ChecklistItem, KeepNoteColors (12 pastel tones)
│   ├── pages/
│   │   ├── alerts/
│   │   │   └── alerts_page.dart     # Reminders coordinator page (renamed from Alarms & Routines)
│   │   ├── bitchat/
│   │   │   └── bitchat_main_page.dart  # BitChat mesh interface with runtime Bluetooth permission check
│   │   ├── home/
│   │   │   └── home_page.dart       # Main coordinator: bottom navigation, center FAB modal, drawer
│   │   ├── keep/                    # Google Keep modular architecture
│   │   │   ├── keep_page.dart       # 2-column masonry grid, pinned vs others, archive, vault lock mask
│   │   │   ├── note_editor_sheet.dart  # Modal editor with static close (left), static save (right), scrollable tools
│   │   │   └── widgets/             # Modular Keep widgets
│   │   │       ├── keep_empty_state.dart
│   │   │       ├── keep_search_bar.dart
│   │   │       ├── note_card.dart
│   │   │       ├── note_checklist_editor.dart
│   │   │       ├── note_color_picker.dart
│   │   │       └── note_tags_editor.dart
│   │   ├── settings/
│   │   │   └── settings_page.dart   # App settings: In-App Updates, Keep Vault, Reminders & Routine
│   │   └── tabs/                    # Primary 4 bottom navigation tabs (Today, Timetable, Revisit, Quizzes)
│   ├── services/
│   │   ├── app_update_service.dart  # In-app GitHub release checker and currentAppVersion
│   │   ├── desktop_log_server_service.dart # Router delegating requests to desktop handlers
│   │   ├── desktop/                 # Modular Desktop Companion Studio
│   │   │   ├── desktop_auth_handler.dart     # 6-digit PIN auth, session heartbeat, token revocation
│   │   │   ├── desktop_mistakes_handler.dart # Full REST /api/mistakes & /api/subjects CRUD
│   │   │   ├── desktop_notes_handler.dart    # REST /api/notes CRUD
│   │   │   └── desktop_web_template.dart     # Web portal HTML/CSS/JS with Keep tab & full mistake cards
│   │   ├── notification_service.dart# Scheduled notifications, heads-up snooze actions, route payloads
│   │   ├── vault_service.dart       # Master PIN + local_auth biometrics (fingerprint/face) for Keep
│   │   └── bitchat/                 # Bluetooth LE and Nostr relay networking
│   └── widgets/
│       ├── full_screen_alarm_dialog.dart     # Ringing alarm screen overlay with Snooze / Dismiss
│       ├── notifications_history_sheet.dart  # In-app notifications history sheet
│       ├── add_mistake_modal_sheet.dart      # Mobile mistake logging modal
│       └── top_banner_notification.dart      # In-app heads-up notification banners
└── pubspec.yaml                     # Dependencies and app semantic version (X.Y.Z+BUILD)
```

---

## 3. Subsystem Implementation Details

### A. Google Keep Notes Module ("KeepLocal")
1. **Visual Style**:
   - Light Google Keep aesthetic with 12 Google Keep pastel tones (`KeepNoteColors.palette`) and dark mode counterparts.
   - Cards styled with continuous squircle curves (`BorderRadius.circular(16)`), subtle borders, checklist preview, tag pills, pin icon, and reminder chip.
2. **Editor Layout (`note_editor_sheet.dart`)**:
   - **Static Left Close Button**: Non-scrolling `IconButton(Icons.close_rounded)`.
   - **Static Right Save Button**: Non-scrolling `ElevatedButton` ("Save") so it is never pushed off-screen.
   - **Scrollable Middle Tools**: `Expanded` wrapping `SingleChildScrollView(scrollDirection: Axis.horizontal, physics: BouncingScrollPhysics())` housing:
     - Reminder button (`Icons.alarm_add_rounded`)
     - Protect/Lock button (`Icons.lock_outline_rounded`)
     - Checklist toggle (`Icons.check_box_outlined`)
     - Monospace code mode (`Icons.code_rounded`)
     - Pin to top (`Icons.push_pin_outlined`)
     - Archive note (`Icons.archive_outlined`)
     - Delete note (`Icons.delete_outline_rounded`)
3. **Note Reminders**:
   - Notes support date/time reminder scheduling with repeat options.
   - Active reminders render a pill badge on note cards (`Icons.alarm_on_rounded`).
   - Reminders page features a dedicated Keep section showing note reminders with direct navigation.
4. **Keep Vault & Security (`vault_service.dart`)**:
   - Master Vault PIN (4 or 6 digits) + device biometrics (`local_auth` fingerprint/face).
   - Locked cards mask title/body behind a lock badge until authenticated.
   - Card context menu operations (`Protect Note`, `Archive`, `Delete`) require authentication before execution.
   - Top AppBar gear icon in `keep_page.dart` navigates directly to Keep Settings.

### B. Reminders & Routines Module
1. **Terminology**: Renamed from "Alarms & Routines" to **"Reminders"** everywhere in user-facing UI and navigation.
2. **Alert Trigger Modes**:
   - **Notification Banner**: Heads-up banner with quick **Snooze (5m / 10m)** and **Dismiss** actions.
   - **Full-Screen Alarm**: High-priority ringing overlay (`FullScreenAlarmDialog`) with wake-screen capabilities enabled by `USE_FULL_SCREEN_INTENT`.
3. **Multi-Day Checkpoints**:
   - In `alerts_page.dart`, `_addCheckpoint` allows picking any date (`showDatePicker`) and time (`showTimePicker`), supporting multiple reminder checkpoints across days for a single task.
4. **"Once" vs Recurring**:
   - Explicit "Once" option ensures reminders trigger once and auto-complete without repeating weekly.
   - Selecting day pills (`S M T W T F S`) sets recurring weekly notifications.
5. **Separation from Daily Routines**:
   - Morning Brief / Afternoon Session / Evening Review daily routine toggles belong **exclusively in Settings -> Reminders & Routine Alerts**, NOT duplicated in the Reminders coordinator list.

### C. Desktop Companion Studio & Server
1. **Modular Routing**:
   - `DesktopLogServerService` only acts as a thin HTTP router on port `8080` (or configured port).
   - Routes `/api/auth/*` -> `DesktopAuthHandler`
   - Routes `/api/notes/*` -> `DesktopNotesHandler`
   - Routes `/api/mistakes/*` and `/api/subjects` -> `DesktopMistakesHandler`
   - Serves web dashboard via `DesktopWebTemplate.render()`
2. **Mistakes Studio Mobile Parity**:
   - Displays complete cards matching the phone experience:
     - Topic, Subject badge, Severity badge (`LOW`: green, `MEDIUM`: amber, `HIGH`: red), linked Quiz badge.
     - Question / Source text box.
     - Side-by-side Wrong Answer (red tinted box) and Correct Answer (green tinted box).
     - Why It Went Wrong (`mistake_reason`).
     - Key Takeaway & Formulas (`key_takeaway`).
     - Status toggle (`RESOLVED` / `UNRESOLVED`) and Delete button.
   - Includes a **"+ Log Mistake"** desktop modal form submitting via `POST /api/mistakes`.
   - Handler supports fallbacks: `mistake_reason` || `reason`, `key_takeaway` || `takeaway`, `question_text`, `wrong_answer`, `correct_answer`, `quiz_title`, `severity`.

### D. Side Navigation Drawer Structure
In `lib/pages/home/home_page.dart`, `_buildSideNavigationDrawer()` must strictly maintain this ordering:
1. **Keep** (`_openKeepPage()`)
2. **Cloud Sync** (`_showCloudSyncModal()`)
3. **Reminders** (`_showAlertsSheet()`, formerly Alerts & Routines)
4. **Jump to Date** (`_pickDate()`)
5. **BitChat P2P Mesh** (`_openBitchatPage()`)
   - Direct hairline divider: `const Divider(height: 1, thickness: 1, color: googleHairline)`
6. **Notifications** (`_showNotificationsHistorySheet()`, clean title without subtitle)
   - Equal vertical spacing: `EdgeInsets.symmetric(horizontal: 10, vertical: 8)`
7. **Settings** (`_openSettingsPage()`, clean title without subtitle)

In `settings_page.dart`, the categories must be ordered:
1. **Desktop Companion Studio**
2. **In-App Updates**
3. **Keep Vault & Note Security** (placed directly under In-App Updates)
4. **Reminders & Routine Alerts**

---

## 4. Database Schema & Migration Guidelines

- File: `lib/data/database_service.dart`.
- **Database Version**: Incremented when schema tables change.
- **Rules**:
  1. Separate initial table creation `_createAllTables(db)` from incremental migrations `_runMigrations(db)`.
  2. Always use `PRAGMA table_info(table_name)` to verify whether a column exists before running `ALTER TABLE ... ADD COLUMN ...`.
  3. Never put non-migrated column references inside `INSERT OR IGNORE` initial bootstrap statements on existing databases.
  4. Keep defensive queries in all service calls (e.g., fallback if `repeat_days` or `reminder_at` columns are temporarily missing).

---

## 5. Step-by-Step GitHub Actions Release Procedure

Build and publish only APKs and their SHA-256 checksums. Skip the Google Play bundle.

When asked to update the app, fix bugs, or build a new version:

### Step 1: Code Changes & AST Verification
- Implement all requested changes adhering to the zero-emoji rule and modular architecture.
- Run local PowerShell verification script to verify 0 bracket/parenthesis/quote balance errors across all modified Dart files:

```powershell
$files = Get-ChildItem -Recurse lib/*.dart | Select-Object -ExpandProperty FullName
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f)
    $curly = 0; $paren = 0; $bracket = 0
    # verify balance
}
```

- Run zero-emoji scanner across all modified files:
```powershell
$emojiRegex = '[\uD83C-\uDBFF\uDC00-\uDFFF\u2600-\u26FF\u2700-\u27BF]'
```

### Step 2: Version Bump
- Increment version in `Tasks/pubspec.yaml`:
  ```yaml
  version: 1.0.18+19   # Bump semver and build number
  ```
- Increment version in `Tasks/lib/services/app_update_service.dart`:
  ```dart
  static const String currentVersion = '1.0.18';
  ```

### Step 3: Prepare and Verify the Pull Request

Fetch `gh-origin` and fast-forward `pre-prod` to `gh-origin/master` before starting work. Commit the intended changes on `pre-prod`.

```powershell
git push gh-origin pre-prod
gh pr create --repo Ragu-123/nyro-tasks --base master --head pre-prod
gh workflow run build_apk.yml --repo Ragu-123/nyro-tasks --ref pre-prod
```

Wait for the workflow to succeed for the exact pull request commit before merging. Merge into `master` through the pull request and confirm the merged source matches the tested source.

### Step 4: Tag the Merged Release

Set `$releaseTag` to the agreed version tag, `$mergedCommit` to the merge commit, and `$testedRunId` to the successful pre-prod build ID. The tag workflow verifies that the tagged tree matches the build, then publishes the checked artifacts from that run.

```powershell
git fetch gh-origin
git tag -a $releaseTag $mergedCommit -m "Prepdesk $releaseTag" -m "Build-Run: $testedRunId"
git push gh-origin "refs/tags/$releaseTag"
```

### Step 5: Verify Publication

Use the tagged run's ID as `$runId`.

```powershell
gh run watch $runId --repo Ragu-123/nyro-tasks --exit-status
```

Confirm GitHub published the files and checksums. Fast-forward `pre-prod` to the merged `master` and keep it for the next change.

### Step 6: Download & Mirror Release APK
- Download the generated `app-release.apk` from the GitHub Release into both:
  1. `c:\Users\SEC\Downloads\nyro-tasks-vX.Y.Z.apk`
  2. `c:\Users\SEC\Downloads\gate2027\tasksapp\android\app-release.apk`
- Output the direct clickable markdown links to the user.

---

## 6. Anti-Patterns & Common Traps (What NOT to Do)

1. **DO NOT** attempt to run `flutter build` on the Windows host.
2. **DO NOT** add emojis to buttons, tabs, toasts, or log statements.
3. **DO NOT** remove the static positioning of the Close and Save buttons in `note_editor_sheet.dart`.
4. **DO NOT** put Morning Brief / Afternoon Session / Evening Review cards back into `alerts_page.dart`.
5. **DO NOT** alter the side drawer item order without explicit user confirmation.
6. **DO NOT** hardcode fixed 4-dot inputs for vault PINs if 6-digit PINs are supported.
7. **DO NOT** forget `<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>` when modifying alarm notification channels.
