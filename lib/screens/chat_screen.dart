import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/constants.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatelessWidget {
  final Conversation conversation;

  const ChatScreen({
    super.key,
    required this.conversation,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return ChangeNotifierProvider(
      create: (_) => ChatProvider(
        peerPubkey: conversation.peerPubkey,
        myKeys: auth.myKeys!,
      )..loadMessages(),
      child: _ChatScreenView(conversation: conversation),
    );
  }
}

class _ChatScreenView extends StatefulWidget {
  final Conversation conversation;

  const _ChatScreenView({required this.conversation});

  @override
  State<_ChatScreenView> createState() => _ChatScreenViewState();
}

class _ChatScreenViewState extends State<_ChatScreenView> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  Message? _editingMessage;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage(ChatProvider chat) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_editingMessage != null) {
      final msgId = _editingMessage!.id;
      setState(() => _editingMessage = null);
      _textController.clear();
      await chat.editMessage(msgId, text);
      return;
    }

    _textController.clear();
    await chat.sendTextMessage(text);
    _scrollToBottom();
  }

  void _showMessageContextMenu(BuildContext context, ChatProvider chat, Message msg) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isMine = msg.senderPubkey == auth.myKeys?.pubkey;
    final quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥', '🎉', '👏'];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(AppConstants.cardColorHex),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Emoji reaction quick bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: quickEmojis.map((emoji) {
                  final hasReacted = msg.reactions[emoji]?.contains(auth.myKeys?.pubkey) ?? false;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.pop(ctx);
                        chat.toggleReaction(msg.id, emoji);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: hasReacted
                              ? const Color(AppConstants.primaryColorHex).withOpacity(0.2)
                              : Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: Colors.white12, height: 20),

            // Reply
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.white70),
              title: const Text('Reply', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                chat.setReplyTo(msg);
              },
            ),

            // Copy text
            if (msg.text != null && msg.text!.isNotEmpty && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white70),
                title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text!));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied to clipboard')),
                  );
                },
              ),

            // Edit
            if (isMine && !msg.isDeleted && msg.msgType == 'text')
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editingMessage = msg;
                    _textController.text = msg.text ?? '';
                  });
                },
              ),

            // Message Info
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: const Text('Message Details', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showMessageDetailsDialog(context, msg);
              },
            ),

            // Delete
            if (isMine || msg.peerPubkey == widget.conversation.peerPubkey)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Message', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteMessage(context, chat, msg);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showMessageDetailsDialog(BuildContext context, Message msg) {
    String formatTs(int? ts) {
      if (ts == null || ts <= 0) return '—';
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(
        DateTime.fromMillisecondsSinceEpoch(ts * 1000),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Message Info', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Sent', formatTs(msg.sentAt)),
            const SizedBox(height: 8),
            _buildInfoRow('Delivered', formatTs(msg.deliveredAt)),
            const SizedBox(height: 8),
            _buildInfoRow('Read', formatTs(msg.readAt)),
            if (msg.editedAt != null && msg.editedAt! > 0) ...[
              const SizedBox(height: 8),
              _buildInfoRow('Edited', formatTs(msg.editedAt)),
            ],
            const SizedBox(height: 8),
            _buildInfoRow('Sender', msg.isOut ? 'You' : '@${widget.conversation.username}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _confirmDeleteMessage(BuildContext context, ChatProvider chat, Message msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Message?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This message will be permanently deleted for both participants.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              chat.deleteMessage(msg.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPeerProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWidget(
              displayName: widget.conversation.displayName,
              avatarUrl: widget.conversation.avatar,
              size: 72,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.conversation.displayName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (widget.conversation.verified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, size: 16, color: Color(AppConstants.primaryColorHex)),
                ],
              ],
            ),
            if (widget.conversation.username.isNotEmpty)
              Text(
                '@${widget.conversation.username}',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                widget.conversation.peerPubkey,
                style: const TextStyle(
                  color: Color(AppConstants.primaryColorHex),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Key'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.conversation.peerPubkey));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Public key copied!')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmClearChat(BuildContext context, ChatProvider chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat History?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to clear all messages in this conversation?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await chat.clearChat();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat history cleared')),
                );
              }
            },
            child: const Text('Clear History', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockUser(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Block @${widget.conversation.username}?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'They will no longer be able to send you messages.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await ApiClient.post('block', {'blocked_pubkey': widget.conversation.peerPubkey});
              if (context.mounted) {
                if (res.ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User blocked')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.error ?? 'Failed to block')),
                  );
                }
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = Provider.of<ChatProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // Auto-scroll on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 150) {
        _scrollToBottom();
      }
    });

    final presenceText = chat.peerPresenceText ??
        (widget.conversation.username.isNotEmpty
            ? '@${widget.conversation.username}'
            : '${widget.conversation.peerPubkey.substring(0, 10)}…');

    return Scaffold(
      backgroundColor: const Color(AppConstants.backgroundColorHex),
      appBar: AppBar(
        backgroundColor: const Color(AppConstants.cardColorHex),
        elevation: 1,
        titleSpacing: 0,
        title: InkWell(
          onTap: () => _showPeerProfileDialog(context),
          child: Row(
            children: [
              AvatarWidget(
                displayName: widget.conversation.displayName,
                avatarUrl: widget.conversation.avatar,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.conversation.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (widget.conversation.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 14, color: Color(AppConstants.primaryColorHex)),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        if (chat.isPeerOnline) ...[
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: const BoxDecoration(
                              color: Color(AppConstants.primaryColorHex),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        Text(
                          presenceText,
                          style: TextStyle(
                            fontSize: 11,
                            color: chat.isPeerOnline
                                ? const Color(AppConstants.primaryColorHex)
                                : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            color: const Color(AppConstants.cardColorHex),
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (v) {
              if (v == 'profile') _showPeerProfileDialog(context);
              if (v == 'clear') _confirmClearChat(context, chat);
              if (v == 'block') _confirmBlockUser(context);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 20, color: Colors.white70),
                    SizedBox(width: 10),
                    Text('View Profile & Key', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, size: 20, color: Colors.white70),
                    SizedBox(width: 10),
                    Text('Clear History', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, size: 20, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Block User', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages List
            Expanded(
              child: chat.isLoading && chat.messages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(AppConstants.primaryColorHex)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: chat.messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = chat.messages[i];
                        return ChatBubble(
                          message: msg,
                          myPubkey: auth.myKeys?.pubkey,
                          onSwipeReply: () => chat.setReplyTo(msg),
                          onLongPress: () => _showMessageContextMenu(context, chat, msg),
                          onReactionTap: (emoji) => chat.toggleReaction(msg.id, emoji),
                        );
                      },
                    ),
            ),

            // Editing Banner
            if (_editingMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(AppConstants.cardColorHex),
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 18, color: Color(AppConstants.primaryColorHex)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing: ${_editingMessage!.text ?? ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                      onPressed: () {
                        setState(() {
                          _editingMessage = null;
                          _textController.clear();
                        });
                      },
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),

            // Reply bar preview
            if (chat.replyTo != null && _editingMessage == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(AppConstants.cardColorHex),
                child: Row(
                  children: [
                    const Icon(Icons.reply, size: 18, color: Color(AppConstants.primaryColorHex)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chat.replyTo!.text ?? 'Replying to attachment',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                      onPressed: () => chat.setReplyTo(null),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),

            // Bottom Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: const Color(AppConstants.cardColorHex),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: _editingMessage != null ? 'Edit message…' : 'Message…',
                          hintStyle: const TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(AppConstants.primaryColorHex),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _editingMessage != null ? Icons.check : Icons.send_rounded,
                        color: Colors.black,
                        size: 20,
                      ),
                      onPressed: () => _sendMessage(chat),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
