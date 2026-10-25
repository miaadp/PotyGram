import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../core/api.dart';
import '../core/crypto.dart';
import '../core/storage.dart';
import '../models/message.dart';
import '../services/sync_service.dart';

class ChatProvider with ChangeNotifier {
  final String peerPubkey;
  final KeyPairSet myKeys;

  List<Message> _messages = [];
  bool _isLoading = false;
  Message? _replyTo;
  StreamSubscription<Message>? _newMsgSub;
  StreamSubscription<Map<String, dynamic>>? _receiptSub;

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  Message? get replyTo => _replyTo;

  ChatProvider({
    required this.peerPubkey,
    required this.myKeys,
  }) {
    SyncService().setActiveChat(peerPubkey);

    _newMsgSub = SyncService().onNewMessage.listen((msg) {
      if (msg.peerPubkey == peerPubkey) {
        final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
        if (existingIdx >= 0) {
          _messages[existingIdx] = msg;
        } else {
          _messages.add(msg);
        }
        notifyListeners();
        markRead(msg.id);
      }
    });

    _receiptSub = SyncService().onReceipt.listen((rc) {
      final id = rc['id'] as int?;
      if (id != null) {
        final idx = _messages.indexWhere((m) => m.id == id);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            deliveredAt: rc['delivered_at'] as int?,
            readAt: rc['read_at'] as int?,
          );
          notifyListeners();
        }
      }
    });
  }

  void setReplyTo(Message? msg) {
    _replyTo = msg;
    notifyListeners();
  }

  Future<void> loadMessages() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Load cached messages from SQLite
      final db = await AppDatabase.instance;
      final cachedRows = await db.query(
        'messages',
        where: 'peer_pubkey = ?',
        whereArgs: [peerPubkey],
        orderBy: 'sent_at ASC',
      );
      _messages = cachedRows.map((r) => Message.fromMap(r)).toList();
      notifyListeners();

      // 2. Fetch history from server
      final res = await ApiClient.get('messages', {
        'peer': peerPubkey,
        'last': 50,
      });

      if (res.ok && res.data is Map) {
        final serverMsgs = res.data['messages'] as List?;
        if (serverMsgs != null) {
          final batch = db.batch();
          final updatedList = <Message>[];

          for (final raw in serverMsgs) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final msgId = (map['id'] as num?)?.toInt() ?? 0;
            final senderPk = (map['sender_pubkey'] ?? '').toString().toLowerCase();
            final recipPk = (map['recipient_pubkey'] ?? '').toString().toLowerCase();
            final isOut = senderPk == myKeys.pubkey;

            String? text;
            final cipher = isOut ? map['sender_ciphertext'] : map['ciphertext'];
            if (cipher != null && cipher is String) {
              try {
                final ciphBytes = base64Decode(cipher);
                text = PotyCrypto.decryptBoxSeal(
                  Uint8List.fromList(ciphBytes),
                  myKeys.pubkey,
                  myKeys.secretKey,
                );
              } catch (_) {}
            }

            final msg = Message(
              id: msgId,
              peerPubkey: peerPubkey,
              senderPubkey: senderPk,
              recipientPubkey: recipPk,
              groupId: map['group_id'] as String?,
              msgType: (map['msg_type'] ?? 'text').toString(),
              text: text,
              fileName: map['file_name'] as String?,
              fileMime: map['file_mime'] as String?,
              filePath: map['file_path'] as String?,
              sentAt: (map['sent_at'] as num?)?.toInt() ?? 0,
              deliveredAt: (map['delivered_at'] as num?)?.toInt(),
              readAt: (map['read_at'] as num?)?.toInt(),
              isOut: isOut,
              isPending: false,
              isFailed: false,
              replyToId: (map['reply_to_id'] as num?)?.toInt(),
              replyPreview: map['reply_preview'] as String?,
            );

            updatedList.add(msg);
            batch.insert('messages', msg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
          }

          await batch.commit(noResult: true);
          _messages = updatedList;

          if (_messages.isNotEmpty) {
            markRead(_messages.last.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[ChatProvider] Load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendTextMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final sentAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final reply = _replyTo;
    _replyTo = null; // Clear reply bar immediately

    // 1. Optimistic message
    final pendingMsg = Message(
      id: tempId,
      peerPubkey: peerPubkey,
      senderPubkey: myKeys.pubkey,
      recipientPubkey: peerPubkey,
      msgType: 'text',
      text: cleanText,
      sentAt: sentAt,
      isOut: true,
      isPending: true,
      isFailed: false,
      replyToId: reply?.id,
      replyPreview: reply?.text?.substring(0, reply.text!.length > 100 ? 100 : reply.text!.length),
    );

    _messages.add(pendingMsg);
    notifyListeners();

    try {
      // 2. Encrypt & Sign
      final ciphBytes = PotyCrypto.encryptBoxSeal(cleanText, peerPubkey);
      final senderCiphBytes = PotyCrypto.encryptBoxSeal(cleanText, myKeys.pubkey);
      final sigBytes = PotyCrypto.signBytesDetached(ciphBytes, myKeys.signSecretKey);

      // 3. Prepare FormData
      final formData = FormData.fromMap({
        'recipient_pubkey': peerPubkey,
        'signing_pubkey': myKeys.signPubkey,
        'msg_type': 'text',
        'ciphertext': MultipartFile.fromBytes(ciphBytes, filename: 'ciphertext.bin'),
        'signature': MultipartFile.fromBytes(sigBytes, filename: 'signature.bin'),
        'sender_ciphertext': MultipartFile.fromBytes(senderCiphBytes, filename: 'sender_ciphertext.bin'),
        if (reply != null) 'reply_to_id': reply.id,
        if (reply?.text != null) 'reply_preview': reply!.text!.substring(0, reply.text!.length > 100 ? 100 : reply.text!.length),
      });

      final res = await ApiClient.postMultipart('send', formData);

      final db = await AppDatabase.instance;
      if (res.ok && res.data is Map && res.data['id'] != null) {
        final realId = (res.data['id'] as num).toInt();
        final confirmedMsg = pendingMsg.copyWith(id: realId, isPending: false);

        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx >= 0) _messages[idx] = confirmedMsg;

        await db.insert('messages', confirmedMsg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        notifyListeners();
        return true;
      } else {
        // Mark failed
        final failedMsg = pendingMsg.copyWith(isPending: false, isFailed: true);
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx >= 0) _messages[idx] = failedMsg;
        await db.insert('messages', failedMsg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        notifyListeners();
        return false;
      }
    } catch (e) {
      final failedMsg = pendingMsg.copyWith(isPending: false, isFailed: true);
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx >= 0) _messages[idx] = failedMsg;
      notifyListeners();
      return false;
    }
  }

  void markRead(int lastId) {
    if (lastId <= 0) return;
    ApiClient.post('mark_read', {
      'ids': [lastId],
    }).catchError((_) {});
  }

  @override
  void dispose() {
    SyncService().setActiveChat(null);
    _newMsgSub?.cancel();
    _receiptSub?.cancel();
    super.dispose();
  }
}
