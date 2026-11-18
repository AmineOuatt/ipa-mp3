import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../models/audio_group.dart';
import '../../../../models/saved_audio_entry.dart';

class LibraryPanel extends StatefulWidget {
  final List<SavedAudioEntry> library;
  final List<AudioGroup> audioGroups;
  final SavedAudioEntry? currentEntry;
  final ValueChanged<SavedAudioEntry> onSelectAudio;
  final VoidCallback onCreateGroup;
  final ValueChanged<AudioGroup> onAddAudiosToGroup;
  final ValueChanged<AudioGroup> onRenameGroup;
  final ValueChanged<AudioGroup> onDeleteGroup;
  final ValueChanged<AudioGroup> onToggleGroupExpanded;
  final ValueChanged<SavedAudioEntry> onOpenAudioSource;
  final ValueChanged<SavedAudioEntry> onMoveAudioToGroup;
  final ValueChanged<SavedAudioEntry> onEditAudioName;
  final ValueChanged<SavedAudioEntry> onDeleteAudio;
  final IconData Function(SavedAudioEntry) getAudioStatusIcon;
  final Color Function(SavedAudioEntry) getAudioStatusIconColor;

  const LibraryPanel({
    super.key,
    required this.library,
    required this.audioGroups,
    required this.currentEntry,
    required this.onSelectAudio,
    required this.onCreateGroup,
    required this.onAddAudiosToGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onToggleGroupExpanded,
    required this.onOpenAudioSource,
    required this.onMoveAudioToGroup,
    required this.onEditAudioName,
    required this.onDeleteAudio,
    required this.getAudioStatusIcon,
    required this.getAudioStatusIconColor,
  });

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  String _searchQuery = "";

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    if (!_sheetController.isAttached) return;
    if (_sheetController.size > 0.8) {
      _sheetController.animateTo(
        0.72,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _sheetController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_sheetController.isAttached && _sheetController.size > 0.8) {
          _sheetController.animateTo(
            0.72,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          Navigator.of(context).pop();
        }
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 1.0,
        snap: true,
        snapSizes: const [0.35, 0.72, 1.0],
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF121212),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: true,
              bottom: false,
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleExpanded,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Audio Library",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle,
                                color: AppColors.primaryGreen,
                                size: 24,
                              ),
                              onPressed: widget.onCreateGroup,
                            ),
                            SizedBox(
                              width: 120,
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: "Search...",
                                  hintStyle: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                  isDense: true,
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: const Color(0xFF282828),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                onChanged: (val) {
                                  setState(() => _searchQuery = val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount:
                          widget.audioGroups.length +
                          (widget.library
                                  .where((e) => e.groupId == null)
                                  .isNotEmpty
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        // Ungrouped items at the top
                        if (index == 0 &&
                            widget.library
                                .where((e) => e.groupId == null)
                                .isNotEmpty) {
                          final ungroupedItems = widget.library
                              .where(
                                (e) =>
                                    e.groupId == null &&
                                    e.name.toLowerCase().contains(
                                      _searchQuery.toLowerCase(),
                                    ),
                              )
                              .toList();
                          ungroupedItems.sort(
                            (a, b) => a.sortIndex.compareTo(b.sortIndex),
                          );

                          return Column(
                            children: ungroupedItems.map((item) {
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF181818),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListTile(
                                  leading: Icon(
                                    widget.getAudioStatusIcon(item),
                                    color: widget.getAudioStatusIconColor(item),
                                  ),
                                  title: Text(
                                    item.name,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    "${item.segments.length} segments",
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    color: const Color(0xFF222222),
                                    onSelected: (value) {
                                      if (value == 'source') {
                                        widget.onOpenAudioSource(item);
                                      } else if (value == 'move') {
                                        widget.onMoveAudioToGroup(item);
                                      } else if (value == 'edit') {
                                        widget.onEditAudioName(item);
                                      } else if (value == 'delete') {
                                        widget.onDeleteAudio(item);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'source',
                                        child: Text('Open source (Imam/Surah)'),
                                      ),
                                      PopupMenuItem(
                                        value: 'move',
                                        child: Text('Move to group'),
                                      ),
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Rename'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                  onTap: () => widget.onSelectAudio(item),
                                ),
                              );
                            }).toList(),
                          );
                        }

                        // Groups
                        final groupIndex =
                            widget.library
                                .where((e) => e.groupId == null)
                                .isNotEmpty
                            ? index - 1
                            : index;
                        if (groupIndex < 0 ||
                            groupIndex >= widget.audioGroups.length) {
                          return const SizedBox.shrink();
                        }

                        final group = widget.audioGroups[groupIndex];
                        final groupItems = widget.library
                            .where(
                              (e) =>
                                  e.groupId == group.id &&
                                  e.name.toLowerCase().contains(
                                    _searchQuery.toLowerCase(),
                                  ),
                            )
                            .toList();
                        groupItems.sort(
                          (a, b) => a.sortIndex.compareTo(b.sortIndex),
                        );

                        return Column(
                          children: [
                            ListTile(
                              leading: Icon(
                                group.isExpanded
                                    ? Icons.folder_open
                                    : Icons.folder,
                                color: AppColors.primaryGreen,
                              ),
                              title: Text(
                                group.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                "${groupItems.length} items",
                                style: const TextStyle(color: Colors.grey),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      color: AppColors.primaryGreen,
                                      size: 20,
                                    ),
                                    tooltip: 'Add audio to group',
                                    onPressed: () =>
                                        widget.onAddAudiosToGroup(group),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    color: const Color(0xFF222222),
                                    onSelected: (value) {
                                      if (value == 'rename') {
                                        widget.onRenameGroup(group);
                                      } else if (value == 'delete') {
                                        widget.onDeleteGroup(group);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Text('Rename group'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete group'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () => widget.onToggleGroupExpanded(group),
                            ),
                            if (group.isExpanded)
                              ...groupItems.map((item) {
                                return Container(
                                  margin: const EdgeInsets.only(
                                    left: 10,
                                    right: 12,
                                    top: 2,
                                    bottom: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF181818),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListTile(
                                    leading: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 12.0,
                                      ),
                                      child: Icon(
                                        widget.getAudioStatusIcon(item),
                                        color: widget.getAudioStatusIconColor(
                                          item,
                                        ),
                                        size: 18,
                                      ),
                                    ),
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      "${item.segments.length} segments",
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.grey,
                                        size: 18,
                                      ),
                                      color: const Color(0xFF222222),
                                      onSelected: (value) {
                                        if (value == 'source') {
                                          widget.onOpenAudioSource(item);
                                        } else if (value == 'move') {
                                          widget.onMoveAudioToGroup(item);
                                        } else if (value == 'edit') {
                                          widget.onEditAudioName(item);
                                        } else if (value == 'delete') {
                                          widget.onDeleteAudio(item);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'source',
                                          child: Text(
                                            'Open source (Imam/Surah)',
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'move',
                                          child: Text('Move to group'),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Rename'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                    onTap: () => widget.onSelectAudio(item),
                                  ),
                                );
                              }),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
