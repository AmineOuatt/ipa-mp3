import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/player/presentation/screens/audio_looper_screen.dart';
import 'services/audio_handler.dart';
import 'services/notification_service.dart';

export 'services/audio_handler.dart' show appPlayer, appAudioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final player = AudioPlayer();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      appAudioHandler = await AudioService.init(
        builder: () => AppAudioHandler(player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.mp3.channel.audio',
          androidNotificationChannelName: 'MP360 Playback',
          androidNotificationChannelDescription:
              'MP360 Audio Player Background Controls',
          androidNotificationIcon: 'mipmap/ic_launcher',
          fastForwardInterval: Duration(seconds: 5),
          rewindInterval: Duration(seconds: 5),
          androidStopForegroundOnPause: false,
          androidNotificationOngoing: false,
          androidResumeOnClick: true,
        ),
      );
      appPlayer = appAudioHandler!.player;
    } catch (e) {
      debugPrint('AudioService init failed: $e');
      appAudioHandler = null;
      appPlayer = player;
    }
  } else {
    appAudioHandler = null;
    appPlayer = player;
  }

  try {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await NotificationService().init();
    }
  } catch (e) {
    debugPrint('Notification init skipped: $e');
  }

  runApp(const AudioRepeaterApp());
}

class AudioRepeaterApp extends StatefulWidget {
  const AudioRepeaterApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    final state = context.findAncestorStateOfType<_AudioRepeaterAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<AudioRepeaterApp> createState() => _AudioRepeaterAppState();
}

class _AudioRepeaterAppState extends State<AudioRepeaterApp> {
  Locale _locale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('app_language_code') ?? 'en';
    if (mounted) {
      setState(() => _locale = Locale(langCode));
    }
  }

  void setLocale(Locale newLocale) {
    setState(() => _locale = newLocale);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP360',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AudioLooperScreen(),
    );
  }
}
