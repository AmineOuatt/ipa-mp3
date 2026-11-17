import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class WidgetService {
  static const String _widgetProviderName = 'Mp3AppWidgetProvider';

  static Future<void> updateWidget({
    required String title,
    required String artist,
    required bool isPlaying,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await HomeWidget.saveWidgetData<String>('title', title);
      await HomeWidget.saveWidgetData<String>('artist', artist);
      await HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying);
      await HomeWidget.updateWidget(
        name: _widgetProviderName,
        androidName: _widgetProviderName,
      );
    } catch (e) {
      debugPrint('Failed to update home screen widget: $e');
    }
  }

  static Future<void> clearWidget() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await HomeWidget.saveWidgetData<String>('title', 'MP360');
      await HomeWidget.saveWidgetData<String>('artist', 'No Audio Playing');
      await HomeWidget.saveWidgetData<bool>('isPlaying', false);
      await HomeWidget.updateWidget(
        name: _widgetProviderName,
        androidName: _widgetProviderName,
      );
    } catch (e) {
      debugPrint('Failed to clear home screen widget: $e');
    }
  }
}

