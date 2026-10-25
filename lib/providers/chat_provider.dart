import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  bool _isPeerOnline = false;
  String? _peerPresenceText;
  StreamSubscription<Message>? _newMsgSub;
  StreamSubscription<Map<String, dynamic>>? _receiptSub;
  Timer? _presenceTimer;

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  Message? get replyTo => _replyTo;
  bool get isPeerOnline => _isPeerOnline;
  String? get peerPresenceText => _peerPresenceText;

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

    fetchPeerPresence();
    _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      fetchPeerPresence();
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
            final deletedAt = (map['deleted_at'] as num?)?.toInt();
            final editedAt = (map['edited_at'] as num?)?.toInt();

            String? text;
            if (deletedAt != null && deletedAt > 0) {
              text = 'This message was deleted';
            } else {
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
              editedAt: editedAt,
              deletedAt: deletedAt,
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
          fetchReactions();
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

  Future<bool> editMessage(int msgId, String newText) async {
    final clean = newText.trim();
    if (clean.isEmpty) return false;

    try {
      final ciphBytes = PotyCrypto.encryptBoxSeal(clean, peerPubkey);
      final senderCiphBytes = PotyCrypto.encryptBoxSeal(clean, myKeys.pubkey);
      final sigBytes = PotyCrypto.signBytesDetached(ciphBytes, myKeys.signSecretKey);

      final formData = FormData.fromMap({
        'id': msgId,
        'ciphertext': MultipartFile.fromBytes(ciphBytes, filename: 'ciphertext.bin'),
        'sender_ciphertext': MultipartFile.fromBytes(senderCiphBytes, filename: 'sender_ciphertext.bin'),
        'signature': MultipartFile.fromBytes(sigBytes, filename: 'signature.bin'),
      });

      final res = await ApiClient.postMultipart('edit', formData);
      if (res.ok) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(text: clean, editedAt: now);
          final db = await AppDatabase.instance;
          await db.update('messages', {'text': clean, 'edited_at': now}, where: 'id = ?', whereArgs: [msgId]);
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('[ChatProvider] Edit error: $e');
    }
    return false;
  }

  Future<bool> deleteMessage(int msgId) async {
    try {
      final res = await ApiClient.post('delete', {'id': msgId});
      if (res.ok) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(deletedAt: now, text: 'This message was deleted');
          final db = await AppDatabase.instance;
          await db.update('messages', {'deleted_at': now, 'text': 'This message was deleted'}, where: 'id = ?', whereArgs: [msgId]);
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('[ChatProvider] Delete error: $e');
    }
    return false;
  }

  Future<bool> clearChat() async {
    try {
      final res = await ApiClient.post('clear_convo', {'peer_pubkey': peerPubkey});
      if (res.ok) {
        _messages = [];
        final db = await AppDatabase.instance;
        await db.delete('messages', where: 'peer_pubkey = ?', whereArgs: [peerPubkey]);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[ChatProvider] Clear chat error: $e');
    }
    return false;
  }

  Future<void> fetchReactions() async {
    try {
      final res = await ApiClient.get('reactions', {'peer': peerPubkey});
      if (res.ok && res.data is Map && res.data['reactions'] is Map) {
        final allRx = res.data['reactions'] as Map;
        bool changed = false;

        for (int i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          final mRx = allRx[m.id.toString()];
          if (mRx is Map) {
            final Map<String, List<String>> rxMap = {};
            mRx.forEach((k, v) {
              if (v is List) {
                rxMap[k.toString()] = v.map((e) => e.toString()).toList();
              }
            });
            _messages[i] = m.copyWith(reactions: rxMap);
            changed = true;
          }
        }
        if (changed) notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> toggleReaction(int msgId, String emoji) async {
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx >= 0) {
      final msg = _messages[idx];
      final currentMap = Map<String, List<String>>.from(msg.reactions);
      final list = List<String>.from(currentMap[emoji] ?? []);
      if (list.contains(myKeys.pubkey)) {
        list.remove(myKeys.pubkey);
        if (list.isEmpty) {
          currentMap.remove(emoji);
        } else {
          currentMap[emoji] = list;
        }
      } else {
        list.add(myKeys.pubkey);
        currentMap[emoji] = list;
      }
      _messages[idx] = msg.copyWith(reactions: currentMap);
      notifyListeners();
    }

    try {
      await ApiClient.post('reactions', {
        'msg_id': msgId,
        'emoji': emoji,
      });
    } catch (_) {}
  }

  Future<void> fetchPeerPresence() async {
    try {
      final res = await ApiClient.get('presence', {'pubkeys': peerPubkey});
      if (res.ok && res.data is Map && res.data['presence'] is Map) {
        final pMap = res.data['presence'] as Map;
        final lastSeen = (pMap[peerPubkey] as num?)?.toInt() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        if (lastSeen > 0) {
          final diff = now - lastSeen;
          if (diff <= 120) {
            _isPeerOnline = true;
            _peerPresenceText = 'Online';
          } else if (diff < 3600) {
            _isPeerOnline = false;
            final mins = (diff / 60).round();
            _peerPresenceText = 'Last seen ${mins}m ago';
          } else if (diff < 86400) {
            _isPeerOnline = false;
            final hours = (diff / 3600).round();
            _peerPresenceText = 'Last seen ${hours}h ago';
          } else {
            _isPeerOnline = false;
            _peerPresenceText = 'Last seen ${DateFormat('d MMM').format(DateTime.fromMillisecondsSinceEpoch(lastSeen * 1000))}';
          }
        } else {
          _isPeerOnline = false;
          _peerPresenceText = null;
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    SyncService().setActiveChat(null);
    _newMsgSub?.cancel();
    _receiptSub?.cancel();
    super.dispose();
  }
}
