import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

    _textController.clear();
    await chat.sendTextMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = Provider.of<ChatProvider>(context);

    // Auto-scroll on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 150) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: const Color(AppConstants.backgroundColorHex),
      appBar: AppBar(
        backgroundColor: const Color(AppConstants.cardColorHex),
        elevation: 1,
        titleSpacing: 0,
        title: Row(
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
                  Text(
                    widget.conversation.username.isNotEmpty
                        ? '@${widget.conversation.username}'
                        : '${widget.conversation.peerPubkey.substring(0, 10)}…',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                          onSwipeReply: () => chat.setReplyTo(msg),
                        );
                      },
                    ),
            ),

            // Reply bar preview
            if (chat.replyTo != null)
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
                        decoration: const InputDecoration(
                          hintText: 'Message…',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
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
