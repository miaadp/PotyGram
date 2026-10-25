import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../core/api.dart';
import '../core/crypto.dart';
import '../core/storage.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  Timer? _timer;
  bool _isPolling = false;
  int _sinceTs = 0;
  int _sinceId = 0;
  String? _activePeerPubkey;
  KeyPairSet? _myKeys;

  final StreamController<Message> _newMessageController = StreamController<Message>.broadcast();
  final StreamController<Map<String, dynamic>> _receiptController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Message> get onNewMessage => _newMessageController.stream;
  Stream<Map<String, dynamic>> get onReceipt => _receiptController.stream;

  void start(KeyPairSet myKeys) {
    _myKeys = myKeys;
    _sinceTs = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30;
    _scheduleNextPoll(1000);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setActiveChat(String? peerPubkey) {
    _activePeerPubkey = peerPubkey;
    if (_timer != null) {
      _timer!.cancel();
      _scheduleNextPoll(200); // Poll immediately on chat open
    }
  }

  void _scheduleNextPoll(int delayMs) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: delayMs), () async {
      await _pollOnce();
      // Adaptive interval: 1.2s when inside active chat, 8s when on conversation list
      final nextInterval = _activePeerPubkey != null ? 1200 : 8000;
      _scheduleNextPoll(nextInterval);
    });
  }

  Future<void> _pollOnce() async {
    if (_isPolling || _myKeys == null) return;
    _isPolling = true;

    try {
      final res = await ApiClient.get('sync', {
        'since_ts': _sinceTs,
        'since_id': _sinceId,
        'hb': 1,
      });

      if (res.ok && res.data is Map) {
        final data = res.data as Map;
        final serverTs = data['server_ts'] as int?;
        final maxId = data['max_id'] as int?;

        if (serverTs != null && serverTs > 0) _sinceTs = serverTs;
        if (maxId != null && maxId > _sinceId) _sinceId = maxId;

        // Process incoming messages
        final messages = data['messages'] as List?;
        if (messages != null && messages.isNotEmpty) {
          final db = await AppDatabase.instance;
          for (final raw in messages) {
            if (raw is! Map) continue;
            final msgMap = Map<String, dynamic>.from(raw);
            final msgId = (msgMap['id'] as num?)?.toInt() ?? 0;
            final senderPk = (msgMap['sender_pubkey'] ?? '').toString().toLowerCase();
            final recipPk = (msgMap['recipient_pubkey'] ?? '').toString().toLowerCase();
            final isOut = senderPk == _myKeys!.pubkey;
            final peerPk = isOut ? recipPk : senderPk;

            // Decrypt ciphertext
            String? plainText;
            final rawCipher = isOut ? msgMap['sender_ciphertext'] : msgMap['ciphertext'];
            if (rawCipher != null && rawCipher is String) {
              try {
                final ciphBytes = base64Decode(rawCipher);
                plainText = PotyCrypto.decryptBoxSeal(
                  Uint8List.fromList(ciphBytes),
                  _myKeys!.pubkey,
                  _myKeys!.secretKey,
                );
              } catch (_) {}
            }

            final message = Message(
              id: msgId,
              peerPubkey: peerPk,
              senderPubkey: senderPk,
              recipientPubkey: recipPk,
              groupId: msgMap['group_id'] as String?,
              msgType: (msgMap['msg_type'] ?? 'text').toString(),
              text: plainText,
              fileName: msgMap['file_name'] as String?,
              fileMime: msgMap['file_mime'] as String?,
              filePath: msgMap['file_path'] as String?,
              sentAt: (msgMap['sent_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
              deliveredAt: (msgMap['delivered_at'] as num?)?.toInt(),
              readAt: (msgMap['read_at'] as num?)?.toInt(),
              isOut: isOut,
              isPending: false,
              isFailed: false,
              replyToId: (msgMap['reply_to_id'] as num?)?.toInt(),
              replyPreview: msgMap['reply_preview'] as String?,
            );

            // Insert or update in database
            await db.insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

            // Update conversation record
            await db.rawInsert('''
              INSERT INTO conversations (peer_pubkey, display_name, username, last_at, last_id, last_sender, last_msg_type, last_msg_text, unread_count, verified)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
              ON CONFLICT(peer_pubkey) DO UPDATE SET
                last_at = excluded.last_at,
                last_id = excluded.last_id,
                last_sender = excluded.last_sender,
                last_msg_type = excluded.last_msg_type,
                last_msg_text = excluded.last_msg_text,
                unread_count = unread_count + (CASE WHEN ? THEN 0 ELSE 1 END)
            ''', [
              peerPk,
              peerPk.substring(0, 8) + '…',
              peerPk.substring(0, 8),
              message.sentAt,
              message.id,
              senderPk,
              message.msgType,
              plainText ?? (message.msgType == 'file' ? '📎 Attachment' : ''),
              isOut ? 1 : 0,
              isOut,
            ]);

            _newMessageController.add(message);
          }
        }

        // Process delivery and read receipts
        final receipts = data['receipts'] as List?;
        if (receipts != null && receipts.isNotEmpty) {
          final db = await AppDatabase.instance;
          for (final rc in receipts) {
            if (rc is! Map) continue;
            final id = (rc['id'] as num?)?.toInt();
            final deliveredAt = (rc['delivered_at'] as num?)?.toInt();
            final readAt = (rc['read_at'] as num?)?.toInt();

            if (id != null) {
              await db.update(
                'messages',
                {
                  if (deliveredAt != null) 'delivered_at': deliveredAt,
                  if (readAt != null) 'read_at': readAt,
                },
                where: 'id = ?',
                whereArgs: [id],
              );
              _receiptController.add({'id': id, 'delivered_at': deliveredAt, 'read_at': readAt});
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('[SyncService] Poll error: $e');
    } finally {
      _isPolling = false;
    }
  }

  void dispose() {
    stop();
    _newMessageController.close();
    _receiptController.close();
  }
}
