import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../models/audio_group.dart';
import '../../../../models/saved_audio_entry.dart';

class GroupDialogs {
  static void showCreateGroup(
    BuildContext context, {
    required ValueChanged<String> onCreated,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Create New Group',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Group name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primaryGreen),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'CREATE',
              style: TextStyle(color: AppColors.primaryGreen),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                onCreated(text);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  static void showRenameGroup(
    BuildContext context, {
    required AudioGroup group,
    required ValueChanged<String> onRenamed,
  }) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Rename Group',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Group name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primaryGreen),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'RENAME',
              style: TextStyle(color: AppColors.primaryGreen),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                onRenamed(text);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  static void showMoveAudioToGroup(
    BuildContext context, {
    required SavedAudioEntry entry,
    required List<AudioGroup> groups,
    required ValueChanged<String?> onSelected,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Move to Group',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 300,
          height: 200,
          child: ListView(
            children: [
              ListTile(
                title: const Text(
                  'No Group',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  onSelected(null);
                  Navigator.pop(context);
                },
              ),
              ...groups.map((group) {
                return ListTile(
                  title: Text(
                    group.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    onSelected(group.id);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  static void showAddAudiosToGroup(
    BuildContext context, {
    required AudioGroup group,
    required List<SavedAudioEntry> library,
    required ValueChanged<Set<String>> onAdded,
  }) {
    String search = '';
    final selected = <String>{};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = library
              .where((a) => a.name.toLowerCase().contains(search.toLowerCase()))
              .toList();

          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            title: Text(
              'Add audios to ${group.name}',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 360,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search audio...',
                      hintStyle: TextStyle(color: Colors.grey),
                      prefixIcon: Icon(Icons.search, color: Colors.grey),
                    ),
                    onChanged: (value) {
                      setDialogState(() => search = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No audio found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final checked = selected.contains(item.path);
                              return CheckboxListTile(
                                value: checked,
                                activeColor: AppColors.primaryGreen,
                                title: Text(
                                  item.name,
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  item.groupId == null
                                      ? 'Ungrouped'
                                      : 'In another group',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selected.add(item.path);
                                    } else {
                                      selected.remove(item.path);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  onAdded(selected);
                  Navigator.pop(context);
                },
                child: const Text(
                  'ADD',
                  style: TextStyle(color: AppColors.primaryGreen),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static void showEditAudioName(
    BuildContext context, {
    required String currentName,
    required ValueChanged<String> onSaved,
  }) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Edit Audio Name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primaryGreen),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'SAVE',
              style: TextStyle(color: AppColors.primaryGreen),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                onSaved(text);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

