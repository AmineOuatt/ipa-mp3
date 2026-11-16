# Mp360 Upgrade Plan: Refactoring & Feature Expansion

## 1. Baseline Metrics (Phase 0)

Recorded on branch `feature/mp360-upgrade`:
- **Git Branch**: `feature/mp360-upgrade`
- **Flutter SDK**: `3.50.0` (Dart `3.14.0`)
- **`flutter pub get`**: Exit code `0`
- **`dart format --output=none --set-exit-if-changed .`**: Exit code `0` (Clean, 24 files formatted)
- **`flutter analyze`**:
  - Exit code `1`
  - **16 issues total** (0 errors, 0 warnings, 16 informational):
    - 8 `deprecated_member_use` infos on `package:flutter/material.dart` (Flutter 3.50 preview notices)
    - 1 `deprecated_member_use` info on `onReorder` in `audio_looper_screen.dart:2028`
    - 7 `avoid_print` infos in root scratch files (`test_*.dart`)
- **`flutter test`**:
  - Exit code `1` (1 test failed: `test/widget_test.dart` due to pre-existing `LateInitializationError: Field 'appPlayer' has not been initialized`)
- **`flutter build apk --debug`**:
  - Exit code `0` (`√ Built build\app\outputs\flutter-apk\app-debug.apk` in 33.7s)

---

## 2. Current Structure & Diagnosis

### 2.1 File Tree
```
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart            // Theme and UI color palette
│   │   ├── pref_keys.dart             // SharedPreferences key strings
│   │   └── audio_constants.dart       // Notification IDs and action keys
│   ├── theme/
│   │   └── app_theme.dart             // Centralized ThemeData definition
│   └── utils/
│       ├── duration_formatter.dart    // Reusable duration formatting utility
│       └── file_size_formatter.dart   // Byte size formatting utility
├── models/
│   ├── audio_group.dart               // AudioGroup playlist model + serialization
│   ├── loop_bookmark.dart             // LoopBookmark segment model + serialization
│   ├── models.dart                    // Barrel export
│   └── saved_audio_entry.dart         // SavedAudioEntry model + serialization
├── services/
│   ├── audio_handler.dart             // AppAudioHandler (audio_service) + global bindings
│   └── notification_service.dart      // Local notifications manager
├── features/
│   ├── player/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── audio_looper_screen.dart   // Main player screen (~2,100 lines)
│   │       │   └── segment_player_screen.dart // Dedicated segment repeater screen
│   │       └── widgets/
│   │           └── waveform_painter.dart      // Custom canvas waveform painter
│   └── quran/
│       └── presentation/
│           └── screens/
│               ├── quran_browser_screen.dart  // Reciter list & search screen
│               └── surah_selection_screen.dart// Surah browser & download screen
├── quran_browser.dart                 // Backward-compatible re-export file
└── main.dart                          // App bootstrap (52 lines)
```

### 2.2 Problems Found
1. **Oversized Screen File**: `lib/features/player/presentation/screens/audio_looper_screen.dart` is still ~2,100 lines and contains inline library panel bottom sheets, group creation dialogs, and large audio playback controls.
2. **Hardcoded User-Facing Strings**: All UI text is hardcoded in English across screens with zero localization infrastructure.
3. **Android Background Playback Defect (B1 Root Cause)**:
   - In `services/audio_handler.dart` and `main.dart`, `AudioService.init()` was conditionally called **ONLY for iOS** (`if (useIosMediaControls)` where `useIosMediaControls => !kIsWeb && Platform.isIOS`). On Android, `appAudioHandler` was set to `null` and a raw unmanaged `AudioPlayer()` was used.
   - `android/app/src/main/AndroidManifest.xml` lacked required foreground service permissions (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `POST_NOTIFICATIONS`) and lacked the `com.ryanheise.audioservice.AudioService` service declaration with `foregroundServiceType="mediaPlayback"`.
   - Without an Android foreground service, Android's Low Memory Killer (LMK) terminates the app within minutes when backgrounded or when the screen is locked.

---

## 3. Target Feature-First Architecture

```
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart
│   │   ├── pref_keys.dart
│   │   └── audio_constants.dart
│   ├── theme/
│   │   └── app_theme.dart
│   ├── utils/
│   │   ├── duration_formatter.dart
│   │   └── file_size_formatter.dart
│   └── l10n/
│       ├── app_en.arb
│       ├── app_ar.arb
│       └── l10n.dart
├── models/
│   ├── audio_group.dart
│   ├── loop_bookmark.dart
│   ├── saved_audio_entry.dart
│   ├── download_task.dart             // Download task model for B4, B5, B6
│   └── models.dart
├── services/
│   ├── audio_handler.dart             // Full Android & iOS AudioService
│   ├── notification_service.dart
│   ├── download_service.dart          // YouTube & playlist download orchestrator
│   └── widget_service.dart            // Home screen widget updater
├── features/
│   ├── player/
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── audio_looper_screen.dart
│   │   │   │   └── segment_player_screen.dart
│   │   │   └── widgets/
│   │   │       ├── waveform_painter.dart
│   │   │       └── player_controls.dart
│   ├── library/
│   │   └── presentation/
│   │       └── widgets/
│   │           ├── library_panel.dart
│   │           └── group_dialogs.dart
│   ├── quran/
│   │   └── presentation/
│   │       └── screens/
│   │           ├── quran_browser_screen.dart
│   │           └── surah_selection_screen.dart
│   ├── downloads/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   └── youtube_download_screen.dart
│   │       └── widgets/
│   │           └── download_progress_sheet.dart
│   ├── settings/
│   │   └── presentation/
│   │       └── screens/
│   │           └── settings_screen.dart
│   └── about/
│       └── presentation/
│           └── screens/
│               └── about_screen.dart
├── shared/
│   └── widgets/
│       └── app_text_field.dart
├── quran_browser.dart
└── main.dart
```

---

## 4. Dependencies Justification Table (Phase B)

| Dependency | Purpose / Why Needed | Maintenance Status |
| :--- | :--- | :--- |
| `flutter_localizations` (SDK) | Official Flutter localization support for English & Arabic ARB | Official Flutter SDK |
| `intl: ^0.19.0` | Number/date formatting, RTL bidirectionality, and ARB message lookup | Active (Dart official) |
| `package_info_plus: ^8.1.2` | Read real app version & build number for the About screen | Active (fluttercommunity) |
| `home_widget: ^0.7.0` | Bridge Flutter audio state to Android AppWidgetProvider | Active |
| `youtube_explode_dart: ^2.2.1` | Fetch YouTube video/playlist metadata and stream audio without external binaries | Active |

---

## 5. Ordered Execution Plan

### PHASE A - Refactor (No Behavior Changes)

#### A1. Format, Remove Unused Imports & Dead Code
- **Goal**: Ensure zero dead imports, clean formatting across all Dart files.
- **Files**: All `lib/` files.
- **Verification**: `dart format --output=none --set-exit-if-changed .` passes; `flutter analyze` clean.

#### A2. Naming Conventions & Import Organization
- **Goal**: Organize imports alphabetically and group by Dart, packages, and local modules.
- **Files**: `lib/main.dart`, `lib/services/*.dart`, `lib/features/**/*.dart`.
- **Verification**: `flutter analyze` clean.

#### A3. Extract Constants, Strings & Theme Values
- **Goal**: Consolidate remaining hardcoded color literals and dimension metrics into `AppColors`.
- **Files**: `lib/features/player/presentation/screens/audio_looper_screen.dart`, `lib/core/constants/app_colors.dart`.
- **Verification**: `flutter analyze` clean; UI colors unchanged.

#### A4. Split Large Files & Widgets
- **Goal**: Extract `library_panel.dart` and `group_dialogs.dart` from `audio_looper_screen.dart` to bring file size below 1,000 lines.
- **Files**:
  - Create: `lib/features/library/presentation/widgets/library_panel.dart`
  - Create: `lib/features/library/presentation/widgets/group_dialogs.dart`
  - Update: `lib/features/player/presentation/screens/audio_looper_screen.dart`
- **Verification**: `flutter analyze` clean; open library sheet and dialogs; verify playlists and folder grouping work identically.

#### A5. Move Files into Target Feature Structure
- **Goal**: Establish the `features/library`, `features/settings`, and `shared/` directories.
- **Files**: Reorganize shared files and update imports.
- **Verification**: `flutter analyze` 0 warnings; `flutter build apk --debug` succeeds.

---

### PHASE B - Features (One Step Per Feature, Atomic Commits)

#### B1. Fix Android Background Playback Being Killed
- **Root Cause**:
  1. `AudioService.init()` was called exclusively on iOS in `main.dart`; on Android, `appAudioHandler` was null and only a raw `AudioPlayer` was used without an Android foreground service.
  2. `AndroidManifest.xml` lacked `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `POST_NOTIFICATIONS` permissions.
  3. `AndroidManifest.xml` lacked the `com.ryanheise.audioservice.AudioService` service declaration and `MediaButtonReceiver`.
- **Changes**:
  1. Update `lib/main.dart` to initialize `AudioService.init(builder: () => AppAudioHandler(player))` uniformly on both Android and iOS.
  2. Configure `AudioSession` for music playback, audio focus handling, and becoming-noisy events (pause on headphone unplug).
  3. Update `android/app/src/main/AndroidManifest.xml` with required service declarations and permissions.
  4. Ensure `AppAudioHandler` broadcasts continuous playback state and media items so Android holds a persistent media notification.
  5. Add an optional helper prompt in settings guiding the user to disable Android battery optimization.
- **Verification**: Run `flutter build apk --debug`; verify persistent media notification on Android; test background audio continues playing with screen off.

#### B2. Arabic/English Language Switch + About Button
- **Changes**:
  1. Add `flutter_localizations` and `intl` to `pubspec.yaml`, create `l10n.yaml`.
  2. Create `lib/core/l10n/app_en.arb` and `lib/core/l10n/app_ar.arb` with all strings.
  3. Wire dynamic `Locale` switching in `AudioRepeaterApp` backed by `SharedPreferences` (persists across launches, changes instantly without restart).
  4. Implement full RTL awareness (`Directionality.of(context)`).
  5. Add Settings / Language dialog and an About screen showing app name, version (`package_info_plus`), description, developer contact, and license info.
- **Verification**: Toggle between English and Arabic; verify UI flips RTL properly with correct Arabic typography and strings; open About screen.

#### B3. Android Home Screen Widget
- **Changes**:
  1. Add `home_widget` dependency.
  2. Create native Android AppWidget layout (`res/layout/widget_layout.xml`), widget provider info (`res/xml/widget_info.xml`), and Kotlin `AppWidgetProvider`.
  3. Register widget receiver in `AndroidManifest.xml`.
  4. Create `WidgetService` in Flutter that updates widget title, reciter/artist, and play/pause icon on playback state changes.
  5. Connect widget button click actions (play/pause, next, prev) to `AppAudioHandler`.
- **Verification**: Add widget to Android emulator home screen; verify track info updates and buttons control playback.

#### B4. Download Audio from YouTube URL Inside the App
- **Changes**:
  1. Add `youtube_explode_dart` dependency.
  2. Create `lib/features/downloads/presentation/screens/youtube_download_screen.dart`.
  3. Provide URL text field with clipboard paste button, URL validation, and metadata preview (title, author, duration, thumbnail).
  4. Fetch audio-only stream (prefer highest bitrate m4a/webm), stream download to app documents folder, and insert entry into `_library` with proper naming and group.
  5. Handle network errors, age-restricted videos, and invalid URLs gracefully with snackbars and retry actions.
- **Verification**: Paste YouTube link; verify video preview loads; download audio; verify track appears in library and plays smoothly.

#### B5. Download Entire Playlist as a New Folder
- **Changes**:
  1. Add playlist URL parsing and metadata extraction via `youtube_explode_dart`.
  2. Dialog allowing user to name the target folder (defaults to playlist title, sanitized of illegal filename characters).
  3. Queue all playlist tracks, skip existing files, and download with concurrency throttle (2-3 simultaneous downloads).
  4. Create `AudioGroup` in `SharedPreferences` for the folder and assign all downloaded tracks to `groupId`.
  5. Provide summary report upon completion (X succeeded, Y failed with retry button).
- **Verification**: Provide YouTube playlist URL; verify folder creation; check sequential/parallel downloads and folder appearance in library.

#### B6. Download Progress UI
- **Changes**:
  1. Implement `DownloadTask` model and `DownloadService` with reactive progress streams.
  2. Build in-app progress bottom sheet / panel displaying active downloads, per-track percent bar, overall playlist count (e.g., 3/15), and cancel/pause buttons.
  3. Show Android ongoing notification with download progress bar for background downloads.
  4. Maintain progress state in `DownloadService` singleton so it survives orientation changes and screen navigation.
- **Verification**: Start multi-track download; verify progress bar updates smoothly in app and in Android notification; rotate screen and navigate away; verify completion.

---

## 6. Verification Checklist & Rollback Strategy

### Verification per Step:
1. `dart format --output=none --set-exit-if-changed .` passes.
2. `flutter analyze` produces 0 errors and 0 new warnings.
3. `flutter test` baseline status preserved.
4. `flutter build apk --debug` succeeds.

### Rollback Strategy:
- Each sub-step has its own atomic git commit.
- If any check fails or introduces regressions, run `git revert HEAD` or reset to the previous commit.

---

## 7. Observed Issues (Preserved per Constraints)
1. **`test/widget_test.dart` Failure**: Fails because `appPlayer` is initialized in async `main()` rather than being injected into `AudioRepeaterApp`. Preserved without unrequested test rewrite.
2. **Scratch Scripts in Root**: `test_api.dart`, `test_arabic.dart`, `test_full_fetch.dart`, `test_merge.dart` contain `avoid_print` warnings. Left untouched.
3. **Deprecated `onReorder`**: `ReorderableListView` in `audio_looper_screen.dart` uses `onReorder`.
