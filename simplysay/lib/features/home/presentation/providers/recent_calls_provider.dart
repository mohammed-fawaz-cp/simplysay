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
    final history = await DatabaseHelper.instance.getCallHistory();
    if (history.isNotEmpty) {
      final records = history.map((h) {
        final name = (h['peer_name'] ?? 'Peer User').toString();
        final peerId = (h['peer_cit'] ?? '').toString().trim();
        final initials = name.isNotEmpty ? name[0].toUpperCase() : 'P';
        final status = (h['status'] ?? '').toString();
        final direction = (h['direction'] ?? '').toString();
        final duration = (h['duration_seconds'] as int?) ?? 0;
        final ts = (h['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch;

        CallType type;
        if (status == 'MISSED') {
          type = CallType.missed;
        } else if (direction == 'incoming') {
          type = CallType.incoming;
        } else {
          type = CallType.outgoing;
        }

        String subtitle;
        if (status == 'COMPLETED') {
          final m = duration ~/ 60;
          final s = duration % 60;
          subtitle = 'Completed (${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')})';
        } else if (status == 'MISSED') {
          subtitle = 'Missed';
        } else if (status == 'REJECTED') {
          subtitle = 'Declined';
        } else {
          subtitle = 'Tap to call';
        }

        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        final now = DateTime.now();
        String timeStr;
        if (now.difference(dt).inDays == 0) {
          timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else if (now.difference(dt).inDays == 1) {
          timeStr = 'Yesterday';
        } else {
          timeStr = '${dt.day}/${dt.month}';
        }

        return CallRecord(
          id: peerId,
          name: name,
          initials: initials,
          type: type,
          subtitle: subtitle,
          timestamp: timeStr,
        );
      }).where((r) => r.id.isNotEmpty).toList();
      state = records;
      return;
    }

    final peers = await DatabaseHelper.instance.getPeers();
    final records = peers.map((p) {
      final name = (p['name'] ?? p['display_name'] ?? 'Peer User').toString();
      final peerId = (p['peer_id'] ?? p['id'] ?? '').toString().trim();
      final initials = name.isNotEmpty ? name[0].toUpperCase() : 'P';
      return CallRecord(
        id: peerId,
        name: name,
        initials: initials,
        type: CallType.incoming,
        subtitle: 'Tap to call',
        timestamp: 'Just now',
      );
    }).where((r) => r.id.isNotEmpty).toList();
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
