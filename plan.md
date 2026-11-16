# Architecture & Refactoring Plan: MP360 Audio Player

## 1. Baseline Metrics (Phase 0)

Recorded before modifying any project code:

- **Git Branch**: `refactor/structure-cleanup` (branched from clean `main`)
- **Flutter SDK**: `3.50.0` (Dart `3.14.0`)
- **`flutter pub get`**: Exit code `0` (clean dependency resolution)
- **`dart format --output=none --set-exit-if-changed .`**:
  - Exit code `1`
  - 4 files unformatted: `test_api.dart`, `test_arabic.dart`, `test_full_fetch.dart`, `test_merge.dart`
- **`flutter analyze`**:
  - Exit code `1`
  - **24 issues total** (0 errors, 5 warnings, 19 infos):
    - `lib/main.dart`: 4 warnings (`dead_code` at 619 & 641, `unused_element` `_showAudioSize` at 839, `unused_element` `_buildSegmentRangeBar` at 2639), 7 infos (`empty_statements`, `unnecessary_to_list_in_spreads`, `prefer_is_empty`, `deprecated_member_use`, `prefer_typing_uninitialized_variables`, `curly_braces_in_flow_control_structures`)
    - `lib/quran_browser.dart`: 1 warning (`unnecessary_question_mark` at 117), 3 infos (`deprecated_member_use`, `curly_braces_in_flow_control_structures`, `empty_catches`)
    - Root scratch files (`test_*.dart`): 7 infos (`avoid_print`)
- **`flutter test`**:
  - Exit code `1` (1 test failed: `test/widget_test.dart` due to `LateInitializationError: Field 'appPlayer' has not been initialized`)
- **`flutter build apk --debug`**:
  - Exit code `0` (`√ Built build\app\outputs\flutter-apk\app-debug.apk`)

---

## 2. Current Structure & Analysis

### 2.1 File Tree
```
lib/
├── main.dart             (3,285 lines - Monolith: Models, AudioHandler, NotificationService, AudioLooperScreen, _WaveformPainter, SegmentPlayerScreen)
└── quran_browser.dart    (667 lines   - Monolith: QuranBrowserMode, SurahSelectionScreen, API handling, Download logic)
```

### 2.2 Problems Found

1. **Monolithic & Oversized Files**:
   - `lib/main.dart` is **3,285 lines** containing 11 distinct classes, data models, audio service integration, local notification management, custom painters, and 2 full screens with hundreds of lines of inline bottom sheets and dialogs.
   - `lib/quran_browser.dart` is **667 lines** mixing network API requests, download progress tracking, and UI dialogs.

2. **Mixed Responsibilities**:
   - `main.dart` handles:
     - App bootstrap (`main()`, `runApp()`)
     - Data models (`LoopBookmark`, `SavedAudioEntry`, `AudioGroup`) with JSON serialization
     - Background audio handling (`AppAudioHandler` with `audio_service`)
     - Notification management (`NotificationService` with `flutter_local_notifications`)
     - Persistent storage (direct `SharedPreferences` reads/writes for library and groups)
     - Audio file operations & picker integration (`file_picker`)
     - Custom UI painting (`_WaveformPainter`)
     - Main player screen (`AudioLooperScreen`)
     - Segment looping player screen (`SegmentPlayerScreen`)

3. **Duplicated Code**:
   - `_formatDuration(Duration d)` is implemented identically in both `_AudioLooperScreenState` (`lib/main.dart:1972`) and `_SegmentPlayerScreenState` (`lib/main.dart:2869`).
   - Redundant JSON parsing and fallback error-handling logic scattered across state methods.

4. **Dead Code & Unused Declarations**:
   - Unused private method `_showAudioSize()` in `lib/main.dart:839`.
   - Unused private widget `_buildSegmentRangeBar()` in `lib/main.dart:2639`.
   - Stray empty statements creating dead code branches in `lib/main.dart:619` and `641` (`};`).
   - Unused nullable typing `dynamic?` in `lib/quran_browser.dart:117`.

5. **Inconsistent Naming & Code Standards**:
   - Private classes defined alongside public ones in the same file.
   - Missing explicit type annotations on variables (`late var _positionSubscription` in `lib/main.dart:2785`).
   - Missing curly braces on control flow (`if (tempStart < Duration.zero) tempStart = Duration.zero;` at `lib/main.dart:3224`).

6. **Magic Numbers & Hardcoded Strings**:
   - Color constants (`0xFF121212`, `0xFF1DB954`, `0xFF181818`, `0xFF282828`) hardcoded across UI components.
   - SharedPreferences keys (`saved_audios_v2`, `audio_groups_v1`, `last_audio_path`) hardcoded in multiple methods.
   - Notification IDs, channel IDs (`audio_playback`), and action identifiers (`play_pause`, `next_segment`, `prev_segment`, `stop`) scattered without centralized constants.

7. **Missing `const` and Style Issues**:
   - Hundreds of un-optimized widget constructors and `EdgeInsets` instances lacking `const`.

---

## 3. Target Structure (Feature-First & Modular)

Adapted strictly to what the app contains without unnecessary abstraction layers:

```
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart            // Theme and UI color palette
│   │   ├── pref_keys.dart             // SharedPreferences key strings
│   │   └── audio_constants.dart       // Notification IDs, action keys, defaults
│   ├── theme/
│   │   └── app_theme.dart             // Centralized ThemeData definition
│   └── utils/
│       ├── duration_formatter.dart    // Reusable duration formatting utility
│       └── file_size_formatter.dart   // Byte size formatting utility
│
├── models/
│   ├── loop_bookmark.dart             // A-B loop segment model + serialization
│   ├── saved_audio_entry.dart         // Saved audio library item model + serialization
│   └── audio_group.dart               // Playlist group model + serialization
│
├── services/
│   ├── audio_handler.dart             // AppAudioHandler (audio_service implementation)
│   └── notification_service.dart      // Local notifications manager
│
├── features/
│   ├── player/
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── audio_looper_screen.dart   // Main player screen
│   │   │   │   └── segment_player_screen.dart // Segment/loop repeater player screen
│   │   │   └── widgets/
│   │   │       ├── waveform_painter.dart      // Custom waveform canvas painter
│   │   │       └── edit_segment_sheet.dart    // Bottom sheet for editing segment start/end
│   ├── library/
│   │   └── presentation/
│   │       └── widgets/
│   │           ├── library_panel.dart         // Saved audios & groups bottom sheet
│   │           └── group_dialogs.dart         // Create/rename/delete/move group dialogs
│   └── quran/
│       └── presentation/
│           └── screens/
│               ├── quran_browser_screen.dart  // Reciter list & search screen
│               └── surah_selection_screen.dart// Surah browser & download screen
│
└── main.dart                          // App bootstrap, global player binding, AudioRepeaterApp
```

---

## 4. Step-by-Step Execution Plan

Each step is independent, behavior-preserving, verifiable, and committed individually.

### Step 1: Formatting & Cleaning Dead Code
- **Files Affected**: `lib/main.dart`, `lib/quran_browser.dart`
- **Changes**:
  - Remove stray semicolons `};` causing dead code warnings at `lib/main.dart:619, 641`.
  - Remove unused private method `_showAudioSize` (`lib/main.dart:839`).
  - Remove unused private method `_buildSegmentRangeBar` (`lib/main.dart:2639`).
  - Fix `dynamic?` to `dynamic` in `lib/quran_browser.dart:117`.
  - Fix single-line control flow braces at `lib/main.dart:3224` and `lib/quran_browser.dart:154`.
  - Run `dart format .` on all files.
- **Risk Level**: Very Low (eliminates compiler warnings; removes uninvoked code).
- **Verification**: `flutter analyze` warning count drops; app builds.

### Step 2: Extract Core Constants & Utilities
- **Files Affected**:
  - Create: `lib/core/constants/app_colors.dart`, `lib/core/constants/pref_keys.dart`, `lib/core/constants/audio_constants.dart`
  - Create: `lib/core/utils/duration_formatter.dart`, `lib/core/utils/file_size_formatter.dart`
  - Create: `lib/core/theme/app_theme.dart`
  - Update: `lib/main.dart`
- **Changes**:
  - Extract reusable duration formatting (`formatDuration`) and byte size formatting (`formatFileSize`).
  - Extract theme definition into `AppTheme`.
  - Reference utilities in `lib/main.dart`.
- **Risk Level**: Low (pure extraction of static helpers).
- **Verification**: `flutter analyze` passes; duration display in UI remains identical.

### Step 3: Extract Data Models
- **Files Affected**:
  - Create: `lib/models/loop_bookmark.dart`, `lib/models/saved_audio_entry.dart`, `lib/models/audio_group.dart`
  - Update: `lib/main.dart`
- **Changes**:
  - Move `LoopBookmark`, `SavedAudioEntry`, and `AudioGroup` into standalone files under `lib/models/`.
  - Export models and import into `lib/main.dart`.
  - Keep all constructors, getters (`start`, `end`, `duration`), `toJson()`, `fromJson()` identical.
- **Risk Level**: Low (identical class definitions and serialization).
- **Verification**: `flutter analyze` clean; JSON persistence remains 100% compatible.

### Step 4: Extract Audio & Notification Services
- **Files Affected**:
  - Create: `lib/services/audio_handler.dart`, `lib/services/notification_service.dart`
  - Update: `lib/main.dart`
- **Changes**:
  - Move `AppAudioHandler` into `lib/services/audio_handler.dart`.
  - Move `NotificationService` into `lib/services/notification_service.dart`.
  - Keep global references (`appAudioHandler`, `appPlayer`) accessible as before.
- **Risk Level**: Low-Medium (background audio and notifications).
- **Verification**: `flutter analyze` clean; `flutter build apk --debug` succeeds; notification and background service callbacks intact.

### Step 5: Extract Quran Browser Feature Screens
- **Files Affected**:
  - Create: `lib/features/quran/presentation/screens/quran_browser_screen.dart`
  - Create: `lib/features/quran/presentation/screens/surah_selection_screen.dart`
  - Update/Replace: `lib/quran_browser.dart` (can re-export or update imports)
- **Changes**:
  - Separate `QuranBrowserMode` and `SurahSelectionScreen` into dedicated feature files.
  - Keep widget parameters, API endpoints, download logic, and result contract identical.
- **Risk Level**: Low (isolated feature screen).
- **Verification**: `flutter analyze` clean; Quran navigation triggers and returns correctly.

### Step 6: Extract Waveform Painter & Segment Player
- **Files Affected**:
  - Create: `lib/features/player/presentation/widgets/waveform_painter.dart`
  - Create: `lib/features/player/presentation/screens/segment_player_screen.dart`
  - Create: `lib/features/player/presentation/widgets/edit_segment_sheet.dart`
  - Update: `lib/main.dart`
- **Changes**:
  - Move `_WaveformPainter` (made public `WaveformPainter` or package-private) to `waveform_painter.dart`.
  - Move `SegmentPlayerScreen` and `_SegmentPlayerScreenState` into `segment_player_screen.dart`.
  - Move the 180-line `_showEditSegmentSheet` to `edit_segment_sheet.dart`.
  - Add explicit types to `_positionSubscription` and `_stateSubscription`.
- **Risk Level**: Low-Medium (segment player state and navigation).
- **Verification**: `flutter analyze` clean; segment player opens and loops seamlessly.

### Step 7: Extract Library Dialogs & Panel Widgets
- **Files Affected**:
  - Create: `lib/features/library/presentation/widgets/library_panel.dart`
  - Create: `lib/features/library/presentation/widgets/group_dialogs.dart`
  - Update: `lib/main.dart`
- **Changes**:
  - Extract `_openLibraryPanel` bottom sheet and group management dialogs (`_createNewGroup`, `_renameGroup`, etc.) into dedicated widgets/functions.
  - Maintain exact state callbacks and setState operations.
- **Risk Level**: Low-Medium (library state and callbacks).
- **Verification**: `flutter analyze` clean; open library panel, group creation, search, and playlist items function identically.

### Step 8: Move Main Player Screen to Feature Folder & Clean Up `main.dart`
- **Files Affected**:
  - Create: `lib/features/player/presentation/screens/audio_looper_screen.dart`
  - Update: `lib/main.dart`
- **Changes**:
  - Move `AudioLooperScreen` to its feature folder.
  - Keep `lib/main.dart` minimal (only initialization, global player config, and `AudioRepeaterApp`).
- **Risk Level**: Low.
- **Verification**: `flutter analyze` clean; app launches into `AudioLooperScreen`.

### Step 9: Lint Polish & Final Const Optimization
- **Files Affected**: All files in `lib/`
- **Changes**:
  - Add missing `const` constructors where applicable.
  - Remove unused imports.
  - Run `dart format .` across entire repository.
- **Risk Level**: Very Low (static improvements only).
- **Verification**: `flutter analyze` passes with 0 warnings in `lib/`.

---

## 5. Verification Checklist

1. **Static Analysis**: `flutter analyze` has 0 errors and zero new warnings compared to baseline.
2. **Formatting**: `dart format --output=none --set-exit-if-changed .` passes cleanly on all `lib/` files.
3. **App Build**: `flutter build apk --debug` succeeds without errors.
4. **Manual Smoke Test Suite**:
   - [ ] **Audio Playback**: Load local file or online stream -> Play / Pause / Seek.
   - [ ] **Playback Speed**: Toggle speeds (0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2.0x).
   - [ ] **A-B Looping**: Set Point A, Set Point B -> audio loops between A and B accurately.
   - [ ] **Segment Management**: Save segment -> segment appears in list -> edit label -> delete segment.
   - [ ] **Segment Player**: Tap segment -> opens Segment Player -> plays sequence / loops segment -> edit segment start/end.
   - [ ] **Library & Groups**: Open library panel -> create new group -> move track to group -> expand/collapse group.
   - [ ] **Quran Browser**: Open online browser -> search reciter (Arabic & English) -> select Surah -> stream or download.
   - [ ] **Persistence**: Restart app -> library items and bookmarks persist correctly.
   - [ ] **Notifications & Background**: Background playback continues -> notification controls respond.

---

## 6. Rollback Strategy

- All work is isolated on git branch `refactor/structure-cleanup`.
- Exactly **one git commit per step**.
- If any step fails verification or introduces a regression, it will be reverted cleanly with `git revert HEAD` or reset before proceeding.

---

## 7. Observed Issues (Not Fixed - Preserved per Constraints)

1. **`test/widget_test.dart` Failure**:
   - `test/widget_test.dart` pumps `AudioRepeaterApp` without initializing `appPlayer`, which is a `late final AudioPlayer` created inside `main()`. This throws `LateInitializationError: Field 'appPlayer' has not been initialized.` at test runtime.
   - Preserved without fixing as per strict non-regression / no logic rewrite rule.
2. **Root Scratch Scripts**:
   - `test_api.dart`, `test_arabic.dart`, `test_full_fetch.dart`, `test_merge.dart` reside directly in root, contain `avoid_print` lint warnings, and are not hooked into `flutter test`.
   - Left untouched outside `lib/`.
3. **Deprecated Flutter API Usage**:
   - `onReorder` in `lib/main.dart:2468` is deprecated in Flutter 3.41+ in favor of `onReorderItem`.
   - Left intact to avoid touching reorder behavior.
4. **Untyped API Maps in `quran_browser.dart`**:
   - The online browser uses `dynamic` maps instead of strict data classes. Preserved as-is to guarantee zero behavioral divergence.
5. **Direct File System Operations in UI Thread**:
   - `File(entry.path).existsSync()` and `File(path).lengthSync()` called synchronously on the UI thread in state methods. Preserved as-is.

