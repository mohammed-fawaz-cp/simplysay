import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../database/db_helper.dart';
import 'peer_profile_exchange_service.dart';
import 'webrtc_prewarm_service.dart';

/// Representation of a raw contact item for isolate processing
class RawContactItem {
  final String name;
  final String rawPhone;

  RawContactItem({required this.name, required this.rawPhone});

  Map<String, dynamic> toJson() => {'name': name, 'rawPhone': rawPhone};

  factory RawContactItem.fromJson(Map<String, dynamic> json) => RawContactItem(
        name: json['name'] as String,
        rawPhone: json['rawPhone'] as String,
      );
}

/// Representation of a hashed contact item computed in background isolate
class HashedContactItem {
  final String name;
  final String rawPhone;
  final String phoneHash;

  HashedContactItem({
    required this.name,
    required this.rawPhone,
    required this.phoneHash,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'rawPhone': rawPhone,
        'phoneHash': phoneHash,
      };

  factory HashedContactItem.fromJson(Map<String, dynamic> json) =>
      HashedContactItem(
        name: json['name'] as String,
        rawPhone: json['rawPhone'] as String,
        phoneHash: json['phoneHash'] as String,
      );
}

/// Background Isolate function to compute SHA-256 hashes off the main UI thread.
/// Runs inside Isolate.run() / compute() to prevent any UI freezing.
List<Map<String, dynamic>> _computeContactHashesIsolate(List<Map<String, dynamic>> rawContactsJson) {
  final List<Map<String, dynamic>> result = [];
  for (final item in rawContactsJson) {
    final name = item['name'] as String;
    final rawPhone = item['rawPhone'] as String;

    // Clean phone number (strip whitespace, dashes, brackets)
    final cleaned = rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.isEmpty) continue;

    final bytes = utf8.encode(cleaned);
    final phoneHash = sha256.convert(bytes).toString();

    result.add({
      'name': name,
      'rawPhone': rawPhone,
      'phoneHash': phoneHash,
    });
  }
  return result;
}

/// ContactSyncService orchestrates contact discovery:
/// 1. Reads local contacts.
/// 2. Hashes phone numbers in a Flutter Background Isolate (`compute`).
/// 3. Sends paginated batches to FastAPI (`POST /api/v1/contacts/sync`).
/// 4. Stores returned matched CITs and CSITs in local SQLite (`sqflite`).
class ContactSyncService {
  static const int batchSize = 200;

  /// Main entrypoint executed during InitializationScreen Stage 3
  static Future<int> syncContactsInBackground() async {
    try {
      developer.log('⚡ [ContactSyncService.syncContactsInBackground] STAGE 3B: Starting background contact sync...', name: 'ContactSyncService');

      // 1. Request Contacts permission and fetch contacts
      final permissionGranted = await FlutterContacts.requestPermission(readonly: true);
      if (!permissionGranted) {
        developer.log('ℹ️ [ContactSyncService.syncContactsInBackground] Contact permission not granted or unsupported. Skipping contact sync.', name: 'ContactSyncService');
        return 0;
      }

      final contacts = await FlutterContacts.getContacts(withProperties: true);
      if (contacts.isEmpty) {
        developer.log('ℹ️ [ContactSyncService.syncContactsInBackground] No contacts found on device.', name: 'ContactSyncService');
        return 0;
      }

      // Extract raw name and phone numbers
      final List<Map<String, dynamic>> rawList = [];
      for (final c in contacts) {
        for (final p in c.phones) {
          if (p.number.trim().isNotEmpty) {
            rawList.add({
              'name': c.displayName,
              'rawPhone': p.number.trim(),
            });
          }
        }
      }

      developer.log('⚡ [ContactSyncService.syncContactsInBackground] Fetched ${rawList.length} raw phone numbers. Spawing compute Isolate for SHA-256 hashing...', name: 'ContactSyncService');

      // 2. Offload SHA-256 hashing to Background Isolate using compute() (UI remains smooth!)
      final List<Map<String, dynamic>> hashedContactsJson = await compute(
        _computeContactHashesIsolate,
        rawList,
      );

      final List<HashedContactItem> hashedItems = hashedContactsJson
          .map((json) => HashedContactItem.fromJson(json))
          .toList();

      developer.log('✅ [ContactSyncService.syncContactsInBackground] Isolate hashing completed for ${hashedItems.length} items. Syncing with FastAPI in batches of $batchSize...', name: 'ContactSyncService');

      // 3. Paginated API Sync
      int matchedCount = 0;
      final List<Map<String, String>> dbContactsToSave = [];

      for (int i = 0; i < hashedItems.length; i += batchSize) {
        final batch = hashedItems.sublist(
          i,
          i + batchSize > hashedItems.length ? hashedItems.length : i + batchSize,
        );

        final List<String> batchHashes = batch.map((item) => item.phoneHash).toList();

        developer.log('⚡ [ContactSyncService.syncContactsInBackground] Sending batch ${i ~/ batchSize + 1} (${batchHashes.length} hashes) to FastAPI...', name: 'ContactSyncService');

        // Call FastAPI REST Endpoint
        final matchedResponse = await _queryServerForContacts(batchHashes);

        // Create lookup map of matched phone_hash -> { cit, csit }
        final Map<String, Map<String, String>> matchMap = {};
        for (final match in matchedResponse) {
          final hash = match['phone_hash'] ?? '';
          final cit = match['cit'] ?? '';
          final csit = match['csit'] ?? '';
          if (hash.isNotEmpty) {
            matchMap[hash] = {'cit': cit, 'csit': csit};
          }
        }

        // Prepare local DB entries
        for (final item in batch) {
          final matchedData = matchMap[item.phoneHash];
          if (matchedData != null) {
            matchedCount++;
            dbContactsToSave.add({
              'name': item.name,
              'phone_number': item.rawPhone,
              'phone_hash': item.phoneHash,
              'cit': matchedData['cit'] ?? '',
              'csit': matchedData['csit'] ?? '',
            });
          } else {
            dbContactsToSave.add({
              'name': item.name,
              'phone_number': item.rawPhone,
              'phone_hash': item.phoneHash,
              'cit': '',
              'csit': '',
            });
          }
        }
      }

      // 4. Save to local SQLite Database (sqflite)
      await DatabaseHelper.instance.saveContacts(dbContactsToSave);

      // 5. Trigger P2P Encrypted Profile Exchange & WebRTC Session Pre-Warm for matched SimplySay users
      for (final item in dbContactsToSave) {
        final cit = item['cit'];
        if (cit != null && cit.isNotEmpty) {
          try {
            await PeerProfileExchangeService.instance.requestPeerProfile(cit);
            await WebRTCPrewarmService.instance.prewarmSessionWithPeer(cit);
          } catch (e) {
            developer.log('⚠️ [ContactSyncService] Profile exchange/pre-warm trigger error for $cit: $e', name: 'ContactSyncService');
          }
        }
      }

      developer.log(
        '🎉 [ContactSyncService.syncContactsInBackground] Contact sync finished! Saved ${dbContactsToSave.length} total contacts ($matchedCount SimplySay users matched).',
        name: 'ContactSyncService',
      );

      return matchedCount;
    } catch (e, stack) {
      developer.log(
        '❌ [ContactSyncService.syncContactsInBackground] Error during contact sync: $e',
        name: 'ContactSyncService',
        error: e,
        stackTrace: stack,
      );
      return 0;
    }
  }

  /// Sends batched phone hashes to FastAPI server POST /contacts/sync
  static Future<List<Map<String, dynamic>>> _queryServerForContacts(List<String> phoneHashes) async {
    try {
      final url = Uri.parse('${AppConfig.apiBaseUrl}/contacts/sync');
      developer.log('⚡ [ContactSyncService._queryServerForContacts] POST $url (Count: ${phoneHashes.length})...', name: 'ContactSyncService');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_hashes': phoneHashes}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('matches')) {
          final List matches = data['matches'];
          developer.log('✅ [ContactSyncService._queryServerForContacts] Received ${matches.length} matches from FastAPI.', name: 'ContactSyncService');
          return matches.cast<Map<String, dynamic>>();
        }
      }
      developer.log('⚠️ [ContactSyncService._queryServerForContacts] Server response status ${response.statusCode}: ${response.body}', name: 'ContactSyncService');
      return [];
    } catch (e) {
      developer.log('⚠️ [ContactSyncService._queryServerForContacts] FastAPI query failed (server offline): $e', name: 'ContactSyncService');
      return [];
    }
  }
}
