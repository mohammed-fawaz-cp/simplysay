import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/db_helper.dart';
import '../../domain/models/call_record.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final activeTabProvider = StateProvider<int>((ref) => 0); // 0: Call, 1: Contacts, 2: Settings

class RecentCallsNotifier extends StateNotifier<List<CallRecord>> {
  RecentCallsNotifier() : super([]) {
    loadRecentCalls();
  }

  Future<void> loadRecentCalls() async {
    final peers = await DatabaseHelper.instance.getPeers();
    final records = peers.map((p) {
      final name = (p['name'] ?? p['display_name'] ?? 'Unknown Peer').toString();
      final initials = name.isNotEmpty ? name[0].toUpperCase() : 'P';
      return CallRecord(
        id: (p['peer_id'] ?? p['id'] ?? 'peer_1').toString(),
        name: name,
        initials: initials,
        type: CallType.incoming,
        subtitle: 'Instant Call connected',
        timestamp: 'Just now',
      );
    }).toList();
    state = records;
  }
}

final recentCallsNotifierProvider =
    StateNotifierProvider<RecentCallsNotifier, List<CallRecord>>((ref) {
  return RecentCallsNotifier();
});

final recentCallsProvider = Provider<List<CallRecord>>((ref) {
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final allCalls = ref.watch(recentCallsNotifierProvider);

  if (query.isEmpty) return allCalls;

  return allCalls
      .where((call) =>
          call.name.toLowerCase().contains(query) ||
          call.subtitle.toLowerCase().contains(query))
      .toList();
});
