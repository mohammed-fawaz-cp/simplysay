import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../database/db_helper.dart';
import '../../../../services/call_signaling_service.dart';
import 'providers/synced_contacts_provider.dart';

/// ContactsScreen: Riverpod ConsumerWidget displaying local SQLite synced contacts.
/// Matches the exact HTML design specification with A-Z section grouping, search pill bar,
/// "+ New Contact" primary action, user avatar header, and chat/videocam action buttons.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Uint8List? _myAvatarBytes;
  String? _myDisplayName;

  @override
  void initState() {
    super.initState();
    _loadMyIdentity();
    Future.microtask(() {
      ref.read(syncedContactsProvider.notifier).loadContacts();
    });
  }

  Future<void> _loadMyIdentity() async {
    try {
      final identity = await DatabaseHelper.instance.getClientIdentity();
      if (identity != null && mounted) {
        final b64 = identity['profile_image_base64'] as String?;
        final name = identity['display_name'] as String?;
        setState(() {
          _myDisplayName = name;
          if (b64 != null && b64.isNotEmpty) {
            _myAvatarBytes = base64Decode(b64);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _callContact(BuildContext context, Map<String, dynamic> contact) async {
    final displayName = (contact['display_name'] ?? contact['name'] ?? 'Unknown').toString();
    String cit = (contact['cit'] as String?)?.trim() ?? '';
    if (cit.isEmpty) {
      cit = (contact['peer_id'] as String?)?.trim() ?? '';
    }
    if (cit.isEmpty) {
      // Look up in peers table by name
      final peers = await DatabaseHelper.instance.getPeers();
      final match = peers.firstWhere(
        (p) => (p['name'] as String?)?.trim().toLowerCase() == displayName.toLowerCase(),
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        cit = (match['peer_id'] ?? match['id'] ?? '').toString().trim();
      }
    }

    if (cit.isEmpty || cit.length < 5) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot call $displayName: Contact is not yet paired. Connect via Instant Call first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      await CallSignalingService.instance.startDirectCall(
        context: context,
        peerCit: cit,
        peerName: displayName,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncedContactsProvider);
    final notifier = ref.read(syncedContactsProvider.notifier);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surfaceColor = isDark ? AppColors.darkSurfaceContainer : Colors.white;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final subtitleColor = isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant;
    final inputBgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F3F4);
    final primaryColor = isDark ? const Color(0xFF1A73E8) : AppColors.lightPrimaryContainer;
    final outlineColor = isDark ? Colors.white10 : AppColors.lightOutline.withValues(alpha: 0.2);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            IconButton(
              icon: Icon(Icons.menu, color: subtitleColor),
              onPressed: () {},
            ),
            const SizedBox(width: 4),
            Text(
              'SimplySay',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: subtitleColor),
            tooltip: 'Sync Contacts',
            onPressed: () => notifier.refresh(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? const Color(0xFF2A2A2A) : AppColors.lightSurfaceContainerHigh,
              backgroundImage: _myAvatarBytes != null ? MemoryImage(_myAvatarBytes!) : null,
              child: _myAvatarBytes == null
                  ? Text(
                      (_myDisplayName != null && _myDisplayName!.isNotEmpty)
                          ? _myDisplayName![0].toUpperCase()
                          : 'ME',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => notifier.refresh(),
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Section: Contacts
                  Text(
                    'Contacts',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Search & Actions Bar
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;
                      if (isMobile) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: inputBgColor,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) => notifier.filterContacts(value),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  color: textColor,
                                ),
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.search, color: subtitleColor),
                                  hintText: 'Search contacts...',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    color: subtitleColor,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Syncing contacts from device...')),
                                );
                                notifier.refresh();
                              },
                              icon: const Icon(Icons.add, size: 20, color: Colors.white),
                              label: const Text(
                                'New Contact',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: inputBgColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (value) => notifier.filterContacts(value),
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    color: textColor,
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(Icons.search, color: subtitleColor),
                                    hintText: 'Search contacts...',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 16,
                                      color: subtitleColor,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Syncing contacts from device...')),
                                );
                                notifier.refresh();
                              },
                              icon: const Icon(Icons.add, size: 20, color: Colors.white),
                              label: const Text(
                                'New Contact',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 32),

                  // Loading State Indicator
                  if (state.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  // Empty State Prompt
                  else if (state.groupedContacts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.contacts_outlined, size: 64, color: subtitleColor),
                            const SizedBox(height: 16),
                            Text(
                              'No contacts found',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap "New Contact" or pull down to sync your device contacts.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  // A-Z Grouped Contact List
                  else
                    Column(
                      children: state.groupedContacts.entries.map((entry) {
                        final letter = entry.key;
                        final contactsInGroup = entry.value;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Group Letter Header (A, B, C)
                              Padding(
                                padding: const EdgeInsets.only(left: 16, bottom: 8),
                                child: Text(
                                  letter,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: subtitleColor,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),

                              // Group Section Card Box
                              Container(
                                decoration: BoxDecoration(
                                  color: surfaceColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: outlineColor),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0F000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: List.generate(contactsInGroup.length, (index) {
                                    final contact = contactsInGroup[index];
                                    final displayName = (contact['display_name'] ?? contact['name'] ?? 'Unknown').toString();
                                    final phone = (contact['phone_number'] ?? '').toString();
                                    final b64Image = contact['profile_image_base64'] as String?;
                                    final isSimplySayUser = (contact['is_simplysay_user'] == 1);
                                    final isLast = index == contactsInGroup.length - 1;

                                    Uint8List? avatarBytes;
                                    if (b64Image != null && b64Image.isNotEmpty) {
                                      try {
                                        avatarBytes = base64Decode(b64Image);
                                      } catch (_) {}
                                    }

                                    return Column(
                                      children: [
                                        InkWell(
                                          onTap: () => _callContact(context, contact),
                                          borderRadius: BorderRadius.vertical(
                                            top: index == 0 ? const Radius.circular(16) : Radius.zero,
                                            bottom: isLast ? const Radius.circular(16) : Radius.zero,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            child: Row(
                                              children: [
                                                // Avatar (Image or Initial Letter)
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isDark ? const Color(0xFF2A2A2A) : AppColors.lightSurfaceContainerHigh,
                                                  ),
                                                  child: ClipOval(
                                                    child: avatarBytes != null
                                                        ? Image.memory(avatarBytes, fit: BoxFit.cover)
                                                        : Center(
                                                            child: Text(
                                                              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                                              style: TextStyle(
                                                                fontFamily: 'Inter',
                                                                fontSize: 20,
                                                                fontWeight: FontWeight.w500,
                                                                color: textColor,
                                                              ),
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),

                                                // Contact Details (Name & Phone/Title)
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              displayName,
                                                              style: TextStyle(
                                                                fontFamily: 'Inter',
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.w500,
                                                                color: textColor,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                          if (isSimplySayUser) ...[
                                                            const SizedBox(width: 6),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: primaryColor.withValues(alpha: 0.15),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: Text(
                                                                'SimplySay',
                                                                style: TextStyle(
                                                                  fontFamily: 'Inter',
                                                                  fontSize: 10,
                                                                  fontWeight: FontWeight.w600,
                                                                  color: primaryColor,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        phone,
                                                        style: TextStyle(
                                                          fontFamily: 'Inter',
                                                          fontSize: 14,
                                                          color: subtitleColor,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // Quick Actions (Chat & Video Call)
                                                IconButton(
                                                  icon: Icon(Icons.chat_bubble_outline, size: 22, color: subtitleColor),
                                                  tooltip: 'Message $displayName',
                                                  onPressed: () {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text('Starting chat with $displayName...')),
                                                    );
                                                  },
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.videocam_outlined, size: 24, color: subtitleColor),
                                                  tooltip: 'Video Call $displayName',
                                                  onPressed: () => _callContact(context, contact),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (!isLast)
                                          Divider(
                                            height: 1,
                                            indent: 80,
                                            color: outlineColor,
                                          ),
                                      ],
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
