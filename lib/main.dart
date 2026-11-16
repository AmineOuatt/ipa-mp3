import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'core/theme/app_theme.dart';
import 'features/player/presentation/screens/audio_looper_screen.dart';
import 'services/audio_handler.dart';
import 'services/notification_service.dart';

export 'services/audio_handler.dart' show appPlayer, appAudioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (useIosMediaControls) {
    final player = AudioPlayer();
    appAudioHandler = await AudioService.init(
      builder: () => AppAudioHandler(player),
    );
    appPlayer = appAudioHandler!.player;
  } else {
    appAudioHandler = null;
    appPlayer = AudioPlayer();
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

class AudioRepeaterApp extends StatelessWidget {
  const AudioRepeaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP360',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AudioLooperScreen(),
    );
  }
}
