# MP360 Enhancement & Feature Report

## 1. Code & Architecture Enhancements

### 1.1 Structural Refactoring (Feature-First)
- **Monolith Decomposition**: Decomposed the original ~3,300-line monolithic `lib/main.dart` into a modular, feature-first architecture (`core/`, `models/`, `services/`, `features/player/`, `features/library/`, `features/quran/`, `features/downloads/`, `features/settings/`, `features/about/`).
- **File Size Reduction**:
  - `lib/main.dart`: Reduced from **3,285 lines** to **106 lines** (pure app bootstrap and dynamic locale management).
  - `lib/features/player/presentation/screens/audio_looper_screen.dart`: Reduced from ~2,200 lines to **1,060 lines** by extracting `library_panel.dart`, `group_dialogs.dart`, `waveform_painter.dart`, and `segment_player_screen.dart`.
- **Domain Modeling**: Extracted type-safe models (`AudioGroup`, `LoopBookmark`, `SavedAudioEntry`, `DownloadTask`) with clear JSON serialization and state helpers.
- **Service Layer**: Dedicated singletons for background audio (`AppAudioHandler`), notifications (`NotificationService`), home widget sync (`WidgetService`), and downloads (`DownloadService`).
- **Code Cleanliness**: Eliminated dead code, unused imports, stray semicolons, and magic color constants (centralized in `AppColors`).

---

## 2. Features Added & Enhancements

1. **B1: Android Persistent Background Playback**
   - **Root Cause Fixed**: Previously, `AudioService` was only initialized on iOS. On Android, the app lacked foreground service declarations, `WAKE_LOCK`, and media permissions, causing Android's Low Memory Killer (LMK) to terminate audio within minutes when the screen turned off.
   - **Enhancement**: Added `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `POST_NOTIFICATIONS` in `AndroidManifest.xml`. Converted `MainActivity` to `AudioServiceActivity`. Added audio focus handling and `becomingNoisy` listeners (auto-pause on headphone disconnect).

2. **B2: Arabic/English Localization & About Screen**
   - Built with official Flutter `l10n` (`intl` + ARB files: `app_en.arb`, `app_ar.arb`).
   - Dynamic in-app language switch in Settings applied instantly without app restart, persisted via `SharedPreferences`.
   - Full RTL (Right-to-Left) layout and typography support for Arabic.
   - Localized `AboutScreen` displaying dynamic version info via `package_info_plus`, app description, developer info, and source links.

3. **B3: Android Home Screen Widget**
   - Built native Android AppWidget (`res/layout/widget_layout.xml`, `res/xml/widget_info.xml`) and Kotlin `Mp3AppWidgetProvider`.
   - Real-time synchronization via `home_widget` and `WidgetService`.
   - Hardware/Media controls: Play/Pause, Next, and Previous buttons send broadcast intents directly to `audio_service`, controlling the real audio player even when the app is minimized.

4. **B4: In-App YouTube Audio Downloader (Hardened & Resilient)**
   - **Root Cause Diagnosed**:
     - YouTube implemented strict bot/PO-token gating on `googlevideo.com` CDN adaptive audio streams (itags 140, 251), returning 403 or stalling connections indefinitely.
     - `youtube_explode_dart` swallowed stream connection errors (`onError: (_) => null`), leaving the download loop waiting forever at 0 / Total MB with no error surfaced.
     - Default watch page fetching (`requireWatchPage: true`) hit YouTube's IP rate limiter (`RequestLimitExceededException`).
   - **Fix Implemented**:
     - **Multi-Client Manifest Fallback**: Requests streams with `requireWatchPage: false` using `YoutubeApiClient.androidVr` and `ios` with fallback to default client.
     - **Multi-Candidate Stream Fallback**: Tests candidate streams in priority order (Audio-only MP4 -> Audio-only WebM -> Muxed MP4 tag 18 which bypasses CDN bot-token checks).
     - **15-Second Chunk Timeout**: Detects 0-byte stalls within 15 seconds, aborts unresponsive streams, and seamlessly transitions to the next stream candidate.
     - **Atomic Part Files**: Writes to `<file>.part` and renames to final destination only on successful completion; cleans up `.part` files on failure or cancellation.
     - **Informative Error Reporting & Retry**: Surfaces clean user-facing error messages on the task tile and enables one-tap Retry.

5. **B5: YouTube Playlist Download as Folder**
   - Detects playlist URLs, fetches all tracks, and prompts for a custom folder/sheikh name (with filename sanitization).
   - Throttles parallel downloads (2 concurrent tasks) to avoid network throttling.
   - Automatically creates an `AudioGroup` in the library and assigns downloaded tracks to that group.

6. **B6: Reactive Download Progress UI & Background Notifications**
   - Reactive singleton `DownloadService` stream: state survives screen rotation and navigation.
   - In-app progress indicators with percentage, downloaded/total size, and cancel/retry per track.
   - Ongoing Android status bar notification displaying real-time progress for background downloads.

7. **B7: Direct Full Quran Reciter/Imam Folder Download**
   - When selecting any imam/reciter, download all available suwar directly into a dedicated library folder.
   - Available directly from `SurahSelectionScreen` (top action button) and from `QuranBrowserScreen` (reciter tile download icon).
   - Prompts for folder name (defaults to reciter name, editable), queues all tracks, and registers in Audio Library.

8. **B8: Single Surah Download Queue Integration**
   - Clicking download on an individual Surah now routes through `DownloadService.enqueueSingleSurahDownload`.
   - Appears immediately in the global Download Queue (`YoutubeDownloadScreen`) and displays ongoing status bar progress notification.
   - Interactive circular progress indicator right on the surah tile, transitioning to "Use Audio (Offline)" upon completion.

9. **B9: Samsung Galaxy & Xiaomi Redmi Widget & Notification Fix + Custom Flutter Player Bar**
   - **Root Cause Diagnosed**:
     - `androidStopForegroundOnPause: true` allowed MIUI/One UI aggressive battery savers to terminate the background media service and discard the notification on pause.
     - `SavedAudioEntry` lacked `operator ==` and `hashCode`, causing `_library.indexOf(_currentEntry!)` to return `-1`, breaking track switching ("swap between audios").
     - `Mp3AppWidgetProvider` only emitted `ACTION_DOWN` without `ACTION_UP` via package-level broadcast, which Samsung Knox and Xiaomi MIUI drop.
   - **Solutions Implemented**:
     - Configured `androidStopForegroundOnPause: false` and `androidNotificationOngoing: false` so playback services remain resilient on Samsung & Redmi.
     - Implemented `SavedAudioEntry` equality by `path` and cyclical next/previous audio swapping.
     - Updated Android Home Screen Widget (`Mp3AppWidgetProvider`) with explicit component targeting, complete key clicks (`ACTION_DOWN` + `ACTION_UP`), and 6 full controls: Previous, -5s Rewind, Play/Pause, +5s Fast Forward, Next, and Stop.
     - Built **`CustomAudioNotificationBar`**: a high-end Flutter notification-style mini-player widget embedded persistently across screens with real-time waveform icon, progress slider, Stop, -5s rewind, Play/Pause, +5s forward, and track swapping (Prev/Next).

---

## 3. Build & Verification Status

| Item | Details | Status |
| :--- | :--- | :--- |
| **Dart Format** | 36 files formatted cleanly | Passed |
| **Flutter Analyze** | 0 errors, 0 warnings | Clean |
| **Flutter Test** | All widget & unit tests passing | Passed |
| **Release APK** | `build/app/outputs/flutter-apk/app-release.apk` (57.4 MB) | Built & Verified |

---

## 4. Releases & Download Links

### 🚀 Release v4.3 (Latest)
- **Release Page**: [GitHub Release v4.3](https://github.com/AmineOuatt/ipa-mp3/releases/tag/v4.3)
- **Android APK**: [Download MP360-v4.3.apk (60.1 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.3/MP360-v4.3.apk)
- **iOS IPA**: [Download MP360-v4.3.ipa (9.55 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.3/MP360-v4.3.ipa)

### 📦 Release v4.2
- **Release Page**: [GitHub Release v4.2](https://github.com/AmineOuatt/ipa-mp3/releases/tag/v4.2)
- **Android APK**: [Download MP360-v4.2.apk (60.1 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.2/MP360-v4.2.apk)
- **iOS IPA**: [Download MP360-v4.2.ipa (9.55 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.2/MP360-v4.2.ipa)

### 📦 Release v4.1
- **Release Page**: [GitHub Release v4.1](https://github.com/AmineOuatt/ipa-mp3/releases/tag/v4.1)
- **Android APK**: [Download MP360-v4.1.apk (60.1 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.1/MP360-v4.1.apk)
- **iOS IPA**: [Download MP360-v4.1.ipa (9.55 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.1/MP360-v4.1.ipa)

### 📦 Release v4.0
- **Release Page**: [GitHub Release v4.0](https://github.com/AmineOuatt/ipa-mp3/releases/tag/v4.0)
- **Android APK**: [Download MP360-v4.0.apk (60.1 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.0/MP360-v4.0.apk)
- **iOS IPA**: [Download MP360-v4.0.ipa (9.55 MB)](https://github.com/AmineOuatt/ipa-mp3/releases/download/v4.0/MP360-v4.0.ipa)
