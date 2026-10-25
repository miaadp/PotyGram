import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../core/api.dart';
import '../core/storage.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/sync_service.dart';

class ConvosProvider with ChangeNotifier {
  List<Conversation> _convos = [];
  bool _isLoading = false;
  String _searchQuery = '';
  StreamSubscription<Message>? _syncSub;

  List<Conversation> get convos {
    if (_searchQuery.isEmpty) return _convos;
    final q = _searchQuery.toLowerCase();
    return _convos.where((c) =>
      c.displayName.toLowerCase().contains(q) ||
      c.username.toLowerCase().contains(q) ||
      c.peerPubkey.contains(q)
    ).toList();
  }

  bool get isLoading => _isLoading;

  ConvosProvider() {
    _syncSub = SyncService().onNewMessage.listen((msg) {
      _onIncomingMessage(msg);
    });
  }

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Load from local SQLite cache first for instant display
      final db = await AppDatabase.instance;
      final cachedRows = await db.query('conversations', orderBy: 'last_at DESC');
      _convos = cachedRows.map((r) => Conversation.fromMap(r)).toList();
      notifyListeners();

      // 2. Fetch from server
      final res = await ApiClient.get('conversations');
      if (res.ok && res.data is Map) {
        final serverList = res.data['conversations'] as List?;
        if (serverList != null) {
          final batch = db.batch();
          final updatedConvos = <Conversation>[];

          for (final raw in serverList) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final c = Conversation.fromMap(map);
            updatedConvos.add(c);
            batch.insert('conversations', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
          }

          await batch.commit(noResult: true);
          _convos = updatedConvos;
        }
      }
    } catch (e) {
      debugPrint('[ConvosProvider] Load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void _onIncomingMessage(Message msg) {
    final idx = _convos.indexWhere((c) => c.peerPubkey == msg.peerPubkey);
    final snippet = msg.text ?? (msg.msgType == 'file' ? '📎 Attachment' : '');

    if (idx >= 0) {
      final existing = _convos[idx];
      final updated = existing.copyWith(
        lastAt: msg.sentAt,
        lastId: msg.id,
        lastSender: msg.senderPubkey,
        lastMsgType: msg.msgType,
        lastMsgText: snippet,
        unreadCount: msg.isOut ? existing.unreadCount : existing.unreadCount + 1,
      );
      _convos.removeAt(idx);
      _convos.insert(0, updated);
    } else {
      final newConvo = Conversation(
        peerPubkey: msg.peerPubkey,
        displayName: msg.peerPubkey.substring(0, 8) + '…',
        username: msg.peerPubkey.substring(0, 8),
        convoType: msg.groupId != null ? 'group' : 'dm',
        lastAt: msg.sentAt,
        lastId: msg.id,
        lastSender: msg.senderPubkey,
        lastMsgType: msg.msgType,
        lastMsgText: snippet,
        unreadCount: msg.isOut ? 0 : 1,
      );
      _convos.insert(0, newConvo);
    }
    notifyListeners();
  }

  void markConvoRead(String peerPubkey) {
    final idx = _convos.indexWhere((c) => c.peerPubkey == peerPubkey);
    if (idx >= 0 && _convos[idx].unreadCount > 0) {
      _convos[idx] = _convos[idx].copyWith(unreadCount: 0);
      notifyListeners();

      AppDatabase.instance.then((db) {
        db.update('conversations', {'unread_count': 0}, where: 'peer_pubkey = ?', whereArgs: [peerPubkey]);
      });
    }
  }

  Future<void> deleteConversation(String peerPubkey) async {
    _convos.removeWhere((c) => c.peerPubkey == peerPubkey);
    notifyListeners();

    try {
      final db = await AppDatabase.instance;
      await db.delete('conversations', where: 'peer_pubkey = ?', whereArgs: [peerPubkey]);
      await db.delete('messages', where: 'peer_pubkey = ?', whereArgs: [peerPubkey]);
      await ApiClient.post('clear_convo', {'peer_pubkey': peerPubkey});
    } catch (_) {}
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }
}
