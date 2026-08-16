import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/db_helper.dart';
import '../../../../services/contact_sync_service.dart';

class SyncedContactsState {
  final List<Map<String, dynamic>> allContacts;
  final List<Map<String, dynamic>> filteredContacts;
  final Map<String, List<Map<String, dynamic>>> groupedContacts;
  final bool isLoading;
  final String searchQuery;

  const SyncedContactsState({
    this.allContacts = const [],
    this.filteredContacts = const [],
    this.groupedContacts = const {},
    this.isLoading = false,
    this.searchQuery = '',
  });

  SyncedContactsState copyWith({
    List<Map<String, dynamic>>? allContacts,
    List<Map<String, dynamic>>? filteredContacts,
    Map<String, List<Map<String, dynamic>>>? groupedContacts,
    bool? isLoading,
    String? searchQuery,
  }) {
    return SyncedContactsState(
      allContacts: allContacts ?? this.allContacts,
      filteredContacts: filteredContacts ?? this.filteredContacts,
      groupedContacts: groupedContacts ?? this.groupedContacts,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class SyncedContactsNotifier extends StateNotifier<SyncedContactsState> {
  SyncedContactsNotifier() : super(const SyncedContactsState()) {
    loadContacts();
  }

  Future<void> loadContacts() async {
    state = state.copyWith(isLoading: true);
    try {
      developer.log('⚡ [SyncedContactsNotifier.loadContacts] Querying SQLite contacts...', name: 'SyncedContactsNotifier');
      final list = await DatabaseHelper.instance.getContacts();
      _processAndSetContacts(list, state.searchQuery);
    } catch (e) {
      developer.log('❌ [SyncedContactsNotifier.loadContacts] Error: $e', name: 'SyncedContactsNotifier');
      state = state.copyWith(isLoading: false);
    }
  }

  void filterContacts(String query) {
    _processAndSetContacts(state.allContacts, query);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      developer.log('⚡ [SyncedContactsNotifier.refresh] Triggering background contact sync...', name: 'SyncedContactsNotifier');
      await ContactSyncService.syncContactsInBackground();
      final list = await DatabaseHelper.instance.getContacts();
      _processAndSetContacts(list, state.searchQuery);
    } catch (e) {
      developer.log('❌ [SyncedContactsNotifier.refresh] Error: $e', name: 'SyncedContactsNotifier');
      state = state.copyWith(isLoading: false);
    }
  }

  void _processAndSetContacts(List<Map<String, dynamic>> rawList, String query) {
    final trimmedQuery = query.trim().toLowerCase();
    
    // Sort contacts alphabetically
    final sortedList = List<Map<String, dynamic>>.from(rawList)
      ..sort((a, b) {
        final nameA = (a['display_name'] ?? a['name'] ?? '').toString().toUpperCase();
        final nameB = (b['display_name'] ?? b['name'] ?? '').toString().toUpperCase();
        return nameA.compareTo(nameB);
      });

    // Apply search query filter
    final filtered = sortedList.where((c) {
      if (trimmedQuery.isEmpty) return true;
      final name = (c['display_name'] ?? c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone_number'] ?? '').toString().toLowerCase();
      return name.contains(trimmedQuery) || phone.contains(trimmedQuery);
    }).toList();

    // Group alphabetically (A-Z)
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final contact in filtered) {
      final name = (contact['display_name'] ?? contact['name'] ?? '').toString().trim();
      String letter = name.isNotEmpty ? name[0].toUpperCase() : '#';
      if (!RegExp(r'[A-Z]').hasMatch(letter)) {
        letter = '#';
      }
      grouped.putIfAbsent(letter, () => []).add(contact);
    }

    state = state.copyWith(
      allContacts: sortedList,
      filteredContacts: filtered,
      groupedContacts: grouped,
      isLoading: false,
      searchQuery: query,
    );
  }
}

final syncedContactsProvider = StateNotifierProvider.autoDispose<SyncedContactsNotifier, SyncedContactsState>(
  (ref) => SyncedContactsNotifier(),
);
