import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

/// DatabaseHelper manages all local SQLite storage.
/// Objective: All data is stored strictly on the user's local device. Zero data on server.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  // In-memory fallback storage for Flutter Web
  final Map<String, dynamic> _webClientIdentity = {};
  final List<Map<String, dynamic>> _webContacts = [];
  final Map<String, Map<String, dynamic>> _webCallSessions = {};

  DatabaseHelper._init();

  Future<Database?> get database async {
    if (kIsWeb) return null;
    if (_database != null) return _database!;
    _database = await _initDB('simplysay_local.db');
    return _database!;
  }

  Future<Database?> _initDB(String filePath) async {
    if (kIsWeb) return null;
    developer.log('⚡ [DatabaseHelper._initDB] Initializing SQLite database ($filePath)...', name: 'DatabaseHelper');
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    developer.log('📂 [DatabaseHelper._initDB] Resolved SQLite file path: $path', name: 'DatabaseHelper');

    final db = await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS call_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_cit TEXT NOT NULL,
        peer_name TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        duration_seconds INTEGER DEFAULT 0,
        timestamp INTEGER NOT NULL
      )
    ''');
    developer.log('✅ [DatabaseHelper._initDB] SQLite database initialized successfully.', name: 'DatabaseHelper');
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    developer.log('⚡ [DatabaseHelper._createDB] Creating tables for schema v$version...', name: 'DatabaseHelper');
    // Peer connections table
    await db.execute('''
      CREATE TABLE peers (
        id TEXT PRIMARY KEY,
        name TEXT,
        peer_id TEXT NOT NULL,
        last_seen INTEGER,
        created_at INTEGER
      )
    ''');

    // Local secure storage table for ephemeral session state
    await db.execute('''
      CREATE TABLE local_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Client Identity (CIT and CSIT)
    await db.execute('''
      CREATE TABLE client_identity (
        cit TEXT PRIMARY KEY,
        csit TEXT NOT NULL,
        device_id TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        display_name TEXT,
        profile_image_base64 TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // Device Contacts (Synced locally)
    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        phone_hash TEXT,
        cit TEXT,
        csit TEXT,
        display_name TEXT,
        profile_image_base64 TEXT,
        is_encrypted INTEGER DEFAULT 0,
        is_simplysay_user INTEGER DEFAULT 0,
        synced_at INTEGER NOT NULL
      )
    ''');

    // Pre-warmed WebRTC Call Sessions (SDP Offer & ICE Candidates)
    await db.execute('''
      CREATE TABLE call_sessions (
        peer_cit TEXT PRIMARY KEY,
        sdp_offer TEXT,
        ice_candidates TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    developer.log('✅ [DatabaseHelper._createDB] Tables created successfully for schema v$version.', name: 'DatabaseHelper');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    developer.log('⚡ [DatabaseHelper._onUpgrade] Upgrading database schema from v$oldVersion to v$newVersion...', name: 'DatabaseHelper');
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS client_identity (
          cit TEXT PRIMARY KEY,
          csit TEXT NOT NULL,
          device_id TEXT NOT NULL,
          phone_number TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE contacts ADD COLUMN csit TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN phone_hash TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN is_simplysay_user INTEGER DEFAULT 0');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE client_identity ADD COLUMN display_name TEXT');
      await db.execute('ALTER TABLE client_identity ADD COLUMN profile_image_base64 TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN display_name TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN profile_image_base64 TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN is_encrypted INTEGER DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS call_sessions (
          peer_cit TEXT PRIMARY KEY,
          sdp_offer TEXT,
          ice_candidates TEXT,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    developer.log('✅ [DatabaseHelper._onUpgrade] Schema upgrade to v$newVersion completed.', name: 'DatabaseHelper');
  }

  /// Saves client identity (CIT & CSIT) to local DB
  Future<void> saveClientIdentity({
    required String cit,
    required String csit,
    required String deviceId,
    required String phoneNumber,
    String? displayName,
    String? profileImageBase64,
  }) async {
    developer.log('⚡ [DatabaseHelper.saveClientIdentity] Saving identity (cit=$cit, csit=$csit, phone=$phoneNumber)...', name: 'DatabaseHelper');
    final existing = await getClientIdentity();
    final resolvedDisplayName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (existing?['display_name'] as String?);
    final resolvedImage = (profileImageBase64 != null && profileImageBase64.isNotEmpty)
        ? profileImageBase64
        : (existing?['profile_image_base64'] as String?);

    final data = {
      'cit': cit,
      'csit': csit,
      'device_id': deviceId,
      'phone_number': phoneNumber,
      'display_name': resolvedDisplayName,
      'profile_image_base64': resolvedImage,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (kIsWeb) {
      _webClientIdentity.clear();
      _webClientIdentity.addAll(data);
      developer.log('✅ [DatabaseHelper.saveClientIdentity] Client identity saved in Web memory.', name: 'DatabaseHelper');
      return;
    }

    final db = await database;
    if (db != null) {
      await db.insert(
        'client_identity',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      developer.log('✅ [DatabaseHelper.saveClientIdentity] Client identity saved locally.', name: 'DatabaseHelper');
    }
  }

  /// Updates local user's profile info (display name & Base64 image)
  Future<void> updateUserProfile({
    required String displayName,
    String? profileImageBase64,
  }) async {
    developer.log('⚡ [DatabaseHelper.updateUserProfile] Updating local user profile (name=$displayName)...', name: 'DatabaseHelper');
    if (kIsWeb) {
      _webClientIdentity['display_name'] = displayName;
      if (profileImageBase64 != null) {
        _webClientIdentity['profile_image_base64'] = profileImageBase64;
      }
      developer.log('✅ [DatabaseHelper.updateUserProfile] Local user profile updated in Web memory.', name: 'DatabaseHelper');
      return;
    }

    final db = await database;
    if (db == null) return;
    final current = await getClientIdentity();
    if (current != null) {
      await db.update(
        'client_identity',
        {
          'display_name': displayName,
          if (profileImageBase64 != null) 'profile_image_base64': profileImageBase64,
        },
        where: 'cit = ?',
        whereArgs: [current['cit']],
      );
      developer.log('✅ [DatabaseHelper.updateUserProfile] Local user profile updated successfully.', name: 'DatabaseHelper');
    }
  }

  /// Updates contact's encrypted profile info
  Future<void> updateContactProfile({
    required String cit,
    String? displayName,
    String? profileImageBase64,
    bool isEncrypted = true,
  }) async {
    developer.log('⚡ [DatabaseHelper.updateContactProfile] Updating contact profile for CIT=$cit...', name: 'DatabaseHelper');
    if (kIsWeb) {
      for (final c in _webContacts) {
        if (c['cit'] == cit) {
          if (displayName != null) c['display_name'] = displayName;
          if (profileImageBase64 != null) c['profile_image_base64'] = profileImageBase64;
          c['is_encrypted'] = isEncrypted ? 1 : 0;
        }
      }
      developer.log('✅ [DatabaseHelper.updateContactProfile] Contact profile updated in Web memory.', name: 'DatabaseHelper');
      return;
    }

    final db = await database;
    if (db == null) return;
    await db.update(
      'contacts',
      {
        if (displayName != null) 'display_name': displayName,
        if (profileImageBase64 != null) 'profile_image_base64': profileImageBase64,
        'is_encrypted': isEncrypted ? 1 : 0,
      },
      where: 'cit = ?',
      whereArgs: [cit],
    );
    developer.log('✅ [DatabaseHelper.updateContactProfile] Contact profile updated.', name: 'DatabaseHelper');
  }

  /// Saves pre-warmed WebRTC session tokens (SDP offer & ICE candidates)
  Future<void> saveCallSession({
    required String peerCit,
    required String sdpOffer,
    required String iceCandidates,
  }) async {
    developer.log('⚡ [DatabaseHelper.saveCallSession] Pre-warming WebRTC session for peer_cit=$peerCit...', name: 'DatabaseHelper');
    final data = {
      'peer_cit': peerCit,
      'sdp_offer': sdpOffer,
      'ice_candidates': iceCandidates,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (kIsWeb) {
      _webCallSessions[peerCit] = data;
      developer.log('✅ [DatabaseHelper.saveCallSession] Call session pre-warmed & stored in Web memory.', name: 'DatabaseHelper');
      return;
    }

    final db = await database;
    if (db != null) {
      await db.insert(
        'call_sessions',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      developer.log('✅ [DatabaseHelper.saveCallSession] Call session pre-warmed & stored in SQLite.', name: 'DatabaseHelper');
    }
  }

  /// Retrieves pre-warmed WebRTC session for a peer
  Future<Map<String, dynamic>?> getCallSession(String peerCit) async {
    if (kIsWeb) return _webCallSessions[peerCit];
    final db = await database;
    if (db == null) return null;
    final results = await db.query(
      'call_sessions',
      where: 'peer_cit = ?',
      whereArgs: [peerCit],
      limit: 1,
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }

  /// Gets stored Client Identity
  Future<Map<String, dynamic>?> getClientIdentity() async {
    developer.log('⚡ [DatabaseHelper.getClientIdentity] Checking existing client identity...', name: 'DatabaseHelper');
    if (kIsWeb) {
      if (_webClientIdentity.isNotEmpty) {
        developer.log('✅ [DatabaseHelper.getClientIdentity] Found existing Web identity (CIT: ${_webClientIdentity['cit']})', name: 'DatabaseHelper');
        return Map<String, dynamic>.from(_webClientIdentity);
      }
      developer.log('ℹ️ [DatabaseHelper.getClientIdentity] No existing Web identity found.', name: 'DatabaseHelper');
      return null;
    }

    final db = await database;
    if (db == null) return null;
    final results = await db.query('client_identity', limit: 1);
    if (results.isNotEmpty) {
      developer.log('✅ [DatabaseHelper.getClientIdentity] Found existing identity (CIT: ${results.first['cit']})', name: 'DatabaseHelper');
      return results.first;
    }
    developer.log('ℹ️ [DatabaseHelper.getClientIdentity] No existing identity found.', name: 'DatabaseHelper');
    return null;
  }

  /// Saves contacts silently to local DB
  Future<void> saveContacts(List<Map<String, String>> contacts) async {
    developer.log('⚡ [DatabaseHelper.saveContacts] Saving ${contacts.length} contacts...', name: 'DatabaseHelper');
    final now = DateTime.now().millisecondsSinceEpoch;

    if (kIsWeb) {
      _webContacts.clear();
      for (final contact in contacts) {
        _webContacts.add({
          'name': contact['name'] ?? 'Unknown',
          'phone_number': contact['phone_number'] ?? '',
          'cit': contact['cit'] ?? '',
          'csit': contact['csit'] ?? '',
          'phone_hash': contact['phone_hash'] ?? '',
          'is_simplysay_user': (contact['cit'] != null && contact['cit']!.isNotEmpty) ? 1 : 0,
          'synced_at': now,
        });
      }
      developer.log('✅ [DatabaseHelper.saveContacts] Contacts saved to Web memory.', name: 'DatabaseHelper');
      return;
    }

    final db = await database;
    if (db == null) return;
    final batch = db.batch();
    for (final contact in contacts) {
      batch.insert(
        'contacts',
        {
          'name': contact['name'] ?? 'Unknown',
          'phone_number': contact['phone_number'] ?? '',
          'cit': contact['cit'] ?? '',
          'csit': contact['csit'] ?? '',
          'phone_hash': contact['phone_hash'] ?? '',
          'is_simplysay_user': (contact['cit'] != null && contact['cit']!.isNotEmpty) ? 1 : 0,
          'synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    developer.log('✅ [DatabaseHelper.saveContacts] Contacts saved to SQLite.', name: 'DatabaseHelper');
  }

  /// Retrieves all local contacts (both SimplySay registered users & normal contacts)
  Future<List<Map<String, dynamic>>> getContacts({bool onlyRegistered = false}) async {
    developer.log('⚡ [DatabaseHelper.getContacts] Querying contacts (onlyRegistered=$onlyRegistered)...', name: 'DatabaseHelper');
    if (kIsWeb) {
      if (onlyRegistered) {
        return _webContacts.where((c) => c['is_simplysay_user'] == 1).toList();
      }
      return List<Map<String, dynamic>>.from(_webContacts);
    }

    final db = await database;
    if (db == null) return [];
    List<Map<String, dynamic>> results;
    if (onlyRegistered) {
      results = await db.query(
        'contacts',
        where: 'is_simplysay_user = 1',
        orderBy: 'name ASC',
      );
    } else {
      results = await db.query('contacts', orderBy: 'name ASC');
    }
    developer.log('✅ [DatabaseHelper.getContacts] Returned ${results.length} contacts.', name: 'DatabaseHelper');
    return results;
  }

  /// Saves a connected peer (from Instant Call or WebRTC connection) to local storage & contacts
  /// Reuses existing peer record if already present, updating last_seen and custom name.
  Future<void> savePeer({
    required String peerId,
    required String name,
  }) async {
    developer.log('⚡ [DatabaseHelper.savePeer] Saving/updating connected peer (id=$peerId, name=$name)...', name: 'DatabaseHelper');
    final now = DateTime.now().millisecondsSinceEpoch;

    if (kIsWeb) {
      final existingIndex = _webContacts.indexWhere((c) => c['cit'] == peerId || c['name'] == name);
      final cleanName = (name.isNotEmpty && name != 'Host User' && name != 'Joiner User')
          ? name
          : (existingIndex != -1 ? (_webContacts[existingIndex]['name'] ?? name) : name);

      final contactData = {
        'name': cleanName,
        'phone_number': '',
        'cit': peerId,
        'csit': 'csit_$peerId',
        'display_name': cleanName,
        'is_simplysay_user': 1,
        'synced_at': now,
      };

      if (existingIndex != -1) {
        _webContacts[existingIndex] = contactData;
      } else {
        _webContacts.add(contactData);
      }
      return;
    }

    final db = await database;
    if (db == null) return;

    // Check if peer already exists in SQLite
    final existingPeers = await db.query(
      'peers',
      where: 'id = ? OR peer_id = ?',
      whereArgs: [peerId, peerId],
      limit: 1,
    );

    String resolvedName = name;
    if (existingPeers.isNotEmpty) {
      final oldName = existingPeers.first['name'] as String? ?? '';
      if ((resolvedName.isEmpty || resolvedName == 'Host User' || resolvedName == 'Joiner User') && oldName.isNotEmpty) {
        resolvedName = oldName;
      }
      // Update existing peer record
      await db.update(
        'peers',
        {
          'name': resolvedName,
          'last_seen': now,
        },
        where: 'id = ? OR peer_id = ?',
        whereArgs: [peerId, peerId],
      );
    } else {
      // Insert new peer record
      await db.insert(
        'peers',
        {
          'id': peerId,
          'name': resolvedName,
          'peer_id': peerId,
          'last_seen': now,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Update contacts table without creating duplicate records
    final existingContacts = await db.query(
      'contacts',
      where: 'cit = ?',
      whereArgs: [peerId],
      limit: 1,
    );

    if (existingContacts.isNotEmpty) {
      await db.update(
        'contacts',
        {
          'name': resolvedName,
          'display_name': resolvedName,
          'synced_at': now,
        },
        where: 'cit = ?',
        whereArgs: [peerId],
      );
    } else {
      await db.insert(
        'contacts',
        {
          'name': resolvedName,
          'phone_number': '',
          'cit': peerId,
          'csit': 'csit_$peerId',
          'display_name': resolvedName,
          'is_simplysay_user': 1,
          'synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    developer.log('✅ [DatabaseHelper.savePeer] Saved peer & contact locally in SQLite (reused existing=${existingPeers.isNotEmpty}).', name: 'DatabaseHelper');
  }

  /// Retrieves all connected peers for Recent Calls display
  Future<List<Map<String, dynamic>>> getPeers() async {
    if (kIsWeb) return List<Map<String, dynamic>>.from(_webContacts);
    final db = await database;
    if (db == null) return [];
    return await db.query('peers', orderBy: 'last_seen DESC');
  }

  /// Saves a local key-value setting
  Future<void> setSetting(String key, String value) async {
    if (kIsWeb) return;
    final db = await database;
    if (db == null) return;
    await db.insert(
      'local_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves a local key-value setting
  Future<String?> getSetting(String key) async {
    if (kIsWeb) return null;
    final db = await database;
    if (db == null) return null;
    final res = await db.query(
      'local_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (res.isNotEmpty) {
      return res.first['value'] as String?;
    }
    return null;
  }

  /// Inserts a call event into the local call_history table
  Future<void> insertCallRecord({
    required String peerCit,
    required String peerName,
    required String direction, // 'incoming' or 'outgoing'
    required String status,    // 'COMPLETED', 'MISSED', 'REJECTED'
    int durationSeconds = 0,
    int? timestamp,
  }) async {
    if (kIsWeb) return;
    final db = await database;
    if (db == null) return;
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'call_history',
      {
        'peer_cit': peerCit,
        'peer_name': peerName,
        'direction': direction,
        'status': status,
        'duration_seconds': durationSeconds,
        'timestamp': ts,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await savePeer(peerId: peerCit, name: peerName);
    developer.log('📜 [DatabaseHelper.insertCallRecord] Recorded call: $direction $status ($durationSeconds s) with $peerName', name: 'DatabaseHelper');
  }

  /// Retrieves all recorded calls ordered by most recent first
  Future<List<Map<String, dynamic>>> getCallHistory() async {
    if (kIsWeb) return [];
    final db = await database;
    if (db == null) return [];
    try {
      return await db.query('call_history', orderBy: 'timestamp DESC');
    } catch (e) {
      developer.log('⚠️ [DatabaseHelper.getCallHistory] Error reading call_history: $e', name: 'DatabaseHelper');
      return [];
    }
  }

  Future<void> close() async {
    if (!kIsWeb) {
      final db = await database;
      await db?.close();
    }
  }
}
