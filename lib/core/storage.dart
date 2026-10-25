import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'constants.dart';
import 'crypto.dart';

class SecureKeyStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> saveServerUrl(String url) =>
      _storage.write(key: AppConstants.keyServerUrl, value: url);

  static Future<String> getServerUrl() async =>
      await _storage.read(key: AppConstants.keyServerUrl) ?? AppConstants.defaultServerUrl;

  static Future<void> saveKeys(KeyPairSet keys) async {
    await _storage.write(key: AppConstants.keyPubkey, value: keys.pubkey);
    await _storage.write(key: AppConstants.keySecretKey, value: keys.secretKey);
    await _storage.write(key: AppConstants.keySignPubkey, value: keys.signPubkey);
    await _storage.write(key: AppConstants.keySignSecretKey, value: keys.signSecretKey);
  }

  static Future<KeyPairSet?> loadKeys() async {
    final pk = await _storage.read(key: AppConstants.keyPubkey);
    final sk = await _storage.read(key: AppConstants.keySecretKey);
    final spk = await _storage.read(key: AppConstants.keySignPubkey);
    final ssk = await _storage.read(key: AppConstants.keySignSecretKey);

    if (pk != null && sk != null && spk != null && ssk != null) {
      return KeyPairSet(
        pubkey: pk,
        secretKey: sk,
        signPubkey: spk,
        signSecretKey: ssk,
      );
    }
    return null;
  }

  static Future<void> saveRememberToken(String token) =>
      _storage.write(key: AppConstants.keyRememberToken, value: token);

  static Future<String?> loadRememberToken() =>
      _storage.read(key: AppConstants.keyRememberToken);

  static Future<void> saveCsrfToken(String token) =>
      _storage.write(key: AppConstants.keyCsrfToken, value: token);

  static Future<String?> loadCsrfToken() =>
      _storage.read(key: AppConstants.keyCsrfToken);

  static Future<void> saveProfile({
    required String username,
    required String displayName,
    required int verified,
  }) async {
    await _storage.write(key: AppConstants.keyUsername, value: username);
    await _storage.write(key: AppConstants.keyDisplayName, value: displayName);
    await _storage.write(key: AppConstants.keyVerified, value: verified.toString());
  }

  static Future<Map<String, dynamic>> loadProfile() async {
    return {
      'username': await _storage.read(key: AppConstants.keyUsername) ?? '',
      'displayName': await _storage.read(key: AppConstants.keyDisplayName) ?? '',
      'verified': int.tryParse(await _storage.read(key: AppConstants.keyVerified) ?? '0') ?? 0,
    };
  }

  static Future<void> clearAll() async {
    final sUrl = await getServerUrl();
    await _storage.deleteAll();
    await saveServerUrl(sUrl);
  }
}

class AppDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'potygram_cache.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            peer_pubkey TEXT PRIMARY KEY,
            display_name TEXT,
            username TEXT,
            avatar TEXT,
            convo_type TEXT,
            last_at INTEGER,
            last_id INTEGER,
            last_sender TEXT,
            last_msg_type TEXT,
            last_msg_text TEXT,
            unread_count INTEGER,
            verified INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY,
            peer_pubkey TEXT,
            sender_pubkey TEXT,
            recipient_pubkey TEXT,
            group_id TEXT,
            msg_type TEXT,
            text TEXT,
            file_name TEXT,
            file_mime TEXT,
            file_path TEXT,
            sent_at INTEGER,
            delivered_at INTEGER,
            read_at INTEGER,
            edited_at INTEGER,
            deleted_at INTEGER,
            is_out INTEGER,
            is_pending INTEGER,
            is_failed INTEGER,
            reply_to_id INTEGER,
            reply_preview TEXT
          )
        ''');

        await db.execute('CREATE INDEX idx_msg_peer ON messages (peer_pubkey, id DESC)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE messages ADD COLUMN edited_at INTEGER');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE messages ADD COLUMN deleted_at INTEGER');
          } catch (_) {}
        }
      },
    );
  }

  static Future<void> clearDatabase() async {
    final db = await instance;
    await db.delete('conversations');
    await db.delete('messages');
  }
}
