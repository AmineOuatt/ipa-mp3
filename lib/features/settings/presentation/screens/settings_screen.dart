import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../main.dart';
import '../../../about/presentation/screens/about_screen.dart';
import '../../../downloads/presentation/screens/youtube_download_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currentLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  Future<void> _loadCurrentLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('app_language_code') ?? 'en';
    if (mounted) {
      setState(() => _currentLanguage = lang);
    }
  }

  Future<void> _setLanguage(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language_code', langCode);
    setState(() => _currentLanguage = langCode);
    if (mounted) {
      AudioRepeaterApp.setLocale(context, Locale(langCode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n?.settings ?? 'Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader(l10n?.language ?? 'Language'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text(
                    'English',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'English',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  value: 'en',
                  groupValue: _currentLanguage,
                  activeColor: AppColors.primaryGreen,
                  onChanged: (val) {
                    if (val != null) _setLanguage(val);
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                RadioListTile<String>(
                  title: const Text(
                    'العربية',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Arabic',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  value: 'ar',
                  groupValue: _currentLanguage,
                  activeColor: AppColors.primaryGreen,
                  onChanged: (val) {
                    if (val != null) _setLanguage(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader(
            l10n?.batteryOptimization ?? 'Battery Optimization',
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.batteryOptimizationDesc ??
                      'Ensure continuous background playback by disabling battery optimization for MP360.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n?.batteryOptimizationDesc ??
                              'Running with foreground service and wake lock active.',
                        ),
                        backgroundColor: AppColors.surfaceElevated,
                      ),
                    );
                  },
                  icon: const Icon(Icons.battery_charging_full, size: 18),
                  label: Text(
                    l10n?.openBatterySettings ?? 'Battery Optimization Info',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader('Downloads'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.cloud_download_rounded,
                color: AppColors.primaryGreen,
              ),
              title: Text(
                l10n?.youtubeDownload ?? 'YouTube Audio Download',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                l10n?.downloadPlaylist ?? 'Download tracks and full playlists',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const YoutubeDownloadScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader(l10n?.about ?? 'About'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.info_outline,
                color: AppColors.primaryGreen,
              ),
              title: Text(
                l10n?.aboutTitle ?? 'About MP360',
                style: const TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.primaryGreen,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
