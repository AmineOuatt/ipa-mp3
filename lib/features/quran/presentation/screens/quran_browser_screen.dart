import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/download_service.dart';
import '../../../downloads/presentation/screens/youtube_download_screen.dart';
import 'surah_selection_screen.dart';

class QuranBrowserMode extends StatefulWidget {
  final String? initialReciterName;
  final String? initialSurahName;
  final String? initialSurahId;

  const QuranBrowserMode({
    super.key,
    this.initialReciterName,
    this.initialSurahName,
    this.initialSurahId,
  });

  @override
  State<QuranBrowserMode> createState() => _QuranBrowserModeState();
}

class _QuranBrowserModeState extends State<QuranBrowserMode> {
  // English UI items, Arabic search capable endpoints
  List<dynamic> _reciters = [];
  List<dynamic> _suwar = [];

  // Riwaya filter (e.g., Hafs, Warsh, Qalun)
  List<String> _riwayat = ['All'];
  String _selectedRiwaya = 'All';

  bool _isLoading = true;
  String _searchQuery = "";
  List<String> _favoriteReciterIds = [];
  bool _showFavoritesOnly = false;
  bool _handledInitialJump = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  String? _extractRiwaya(dynamic reciter) {
    if (reciter == null) return null;
    if (reciter['rewaya'] != null) return reciter['rewaya'].toString();
    if (reciter['moshaf'] is List && reciter['moshaf'].isNotEmpty) {
      final name = reciter['moshaf'][0]['name']?.toString() ?? '';
      final parts = name.split(' - ');
      if (parts.isNotEmpty) {
        return parts[0].trim();
      }
    }
    return null;
  }

  Future<void> _fetchData() async {
    final prefs = await SharedPreferences.getInstance();
    _favoriteReciterIds = prefs.getStringList('favorite_reciters') ?? [];

    setState(() => _isLoading = true);

    try {
      // Endpoints configured with ar to allow Arabic search data returned,
      final suwarResponse = await http.get(
        Uri.parse('https://mp3quran.net/api/v3/suwar?language=ar'),
      );
      final recitersResponse = await http.get(
        Uri.parse('https://mp3quran.net/api/v3/reciters?language=ar'),
      );

      if (suwarResponse.statusCode == 200 &&
          recitersResponse.statusCode == 200) {
        final reciters = jsonDecode(recitersResponse.body)['reciters'];
        final riwayaSet = <String>{};
        for (final r in reciters) {
          final riwaya = _extractRiwaya(r);
          if (riwaya != null && riwaya.trim().isNotEmpty) {
            riwayaSet.add(riwaya);
          }
        }
        setState(() {
          _suwar = jsonDecode(suwarResponse.body)['suwar'];
          _reciters = reciters;
          _riwayat = ['All', ...riwayaSet.toList()..sort()];
          _isLoading = false;
        });

        _openInitialSourceIfNeeded();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openInitialSourceIfNeeded() {
    if (_handledInitialJump) return;
    _handledInitialJump = true;

    final initialReciter = widget.initialReciterName;
    if (initialReciter == null || initialReciter.trim().isEmpty) return;

    final normalizedNeedle = initialReciter.toLowerCase().trim();
    dynamic matched;

    for (final reciter in _reciters) {
      final name = (reciter['name'] ?? '').toString().toLowerCase().trim();
      if (name == normalizedNeedle) {
        matched = reciter;
        break;
      }
    }

    matched ??= _reciters.cast<dynamic>().firstWhere(
      (reciter) => (reciter?['name'] ?? '').toString().toLowerCase().contains(
        normalizedNeedle,
      ),
      orElse: () => null,
    );

    if (matched == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openReciter(
        matched,
        initialSurahName: widget.initialSurahName,
        initialSurahId: widget.initialSurahId,
      );
    });
  }

  Future<void> _toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteReciterIds.contains(id)) {
        _favoriteReciterIds.remove(id);
      } else {
        _favoriteReciterIds.add(id);
      }
    });
    await prefs.setStringList('favorite_reciters', _favoriteReciterIds);
  }

  void _openReciter(
    dynamic reciter, {
    String? initialSurahName,
    String? initialSurahId,
  }) async {
    if (reciter['moshaf'] == null || (reciter['moshaf'] as List).isEmpty) {
      return;
    }

    // Automatically select the first moshaf
    final moshaf = reciter['moshaf'][0];

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SurahSelectionScreen(
          reciterName: reciter['name'],
          moshaf: moshaf,
          suwarList: _suwar,
          initialSurahName: initialSurahName,
          initialSurahId: initialSurahId,
        ),
      ),
    );

    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  void _downloadFullReciterFolder(dynamic reciter) {
    if (reciter['moshaf'] == null || (reciter['moshaf'] as List).isEmpty) {
      return;
    }
    final moshaf = reciter['moshaf'][0];
    final availableSurahs = moshaf['surah_list'].toString().split(',');
    final allSuwar = _suwar
        .where((s) => availableSurahs.contains(s['id'].toString()))
        .toList();
    final reciterName = reciter['name'].toString();
    final folderController = TextEditingController(text: reciterName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text(
          'Download Full Folder of Suwar',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download all ${allSuwar.length} suwar by $reciterName into a dedicated folder in your library.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: folderController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Folder Name / Reciter',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'DOWNLOAD ALL',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              final folder = folderController.text.trim();
              if (folder.isNotEmpty) {
                DownloadService.instance.enqueueQuranReciterDownload(
                  reciterName: reciterName,
                  serverUrl: moshaf['server'].toString(),
                  suwarToDownload: allSuwar,
                  customFolderName: folder,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Queued ${allSuwar.length} suwar into folder "$folder"',
                    ),
                    backgroundColor: AppColors.primary,
                    action: SnackBarAction(
                      label: 'VIEW QUEUE',
                      textColor: Colors.black,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const YoutubeDownloadScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> filtered = _reciters.where((r) {
      final name = r['name'].toString().toLowerCase();
      final id = r['id'].toString();
      final riwaya = _extractRiwaya(r)?.toLowerCase() ?? '';
      bool matchesSearch = name.contains(_searchQuery.toLowerCase());
      bool matchesFav = !_showFavoritesOnly || _favoriteReciterIds.contains(id);
      bool matchesRiwaya =
          _selectedRiwaya == 'All' || riwaya == _selectedRiwaya.toLowerCase();
      return matchesSearch && matchesFav && matchesRiwaya;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Audio Library",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
      ),
      body: Container(
        color: AppColors.background,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: TextField(
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: Colors.black54,
                                ),
                                hintText: 'Search reciters...',
                                hintStyle: TextStyle(color: Colors.black54),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: _showFavoritesOnly
                                ? AppColors.primary
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              _showFavoritesOnly
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _showFavoritesOnly
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                _showFavoritesOnly = !_showFavoritesOnly;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Riwaya filter dropdown
                  if (_riwayat.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              dropdownColor: const Color(0xFF1E1E1E),
                              value: _selectedRiwaya,
                              iconEnabledColor: Colors.white70,
                              style: const TextStyle(color: Colors.white),
                              items: _riwayat
                                  .map(
                                    (r) => DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(r),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _selectedRiwaya = val;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      itemBuilder: (context, index) {
                        final r = filtered[index];
                        final id = r['id'].toString();
                        final isFav = _favoriteReciterIds.contains(id);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.surfaceElevated,
                            radius: 25,
                            child: Icon(
                              Icons.person_outline,
                              color: Colors.white70,
                            ),
                          ),
                          title: Text(
                            r['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            "Reciter",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.download_for_offline_outlined,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                tooltip: "Download All Suwar",
                                onPressed: () => _downloadFullReciterFolder(r),
                              ),
                              IconButton(
                                icon: Icon(
                                  isFav
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFav
                                      ? AppColors.primary
                                      : Colors.white54,
                                ),
                                onPressed: () => _toggleFavorite(id),
                              ),
                            ],
                          ),
                          onTap: () => _openReciter(r),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
