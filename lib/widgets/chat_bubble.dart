import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final String? myPubkey;
  final VoidCallback? onSwipeReply;
  final VoidCallback? onLongPress;
  final Function(String emoji)? onReactionTap;

  const ChatBubble({
    super.key,
    required this.message,
    this.myPubkey,
    this.onSwipeReply,
    this.onLongPress,
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOut = message.isOut;
    final isDeleted = message.isDeleted;
    final timeStr = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(message.sentAt * 1000),
    );

    return Dismissible(
      key: ValueKey('msg_${message.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (dir) async {
        onSwipeReply?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.reply, color: Color(AppConstants.primaryColorHex)),
      ),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Align(
          alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDeleted
                  ? Colors.white.withOpacity(0.06)
                  : (isOut
                      ? const Color(AppConstants.bubbleSentHex)
                      : const Color(AppConstants.bubbleReceivedHex)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isOut ? 14 : 2),
                bottomRight: Radius.circular(isOut ? 2 : 14),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reply quote banner
                if (message.replyPreview != null && message.replyPreview!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: const Border(
                        left: BorderSide(
                          color: Color(AppConstants.primaryColorHex),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      message.replyPreview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                // Message Text or Deleted Banner
                if (isDeleted)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 14, color: Colors.white38),
                      SizedBox(width: 6),
                      Text(
                        'This message was deleted',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white38,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    message.text ?? (message.msgType == 'file' ? '📎 ${message.fileName ?? "File"}' : ''),
                    style: const TextStyle(
                      fontSize: 15.5,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),

                const SizedBox(height: 3),

                // Footer: Edited tag + Timestamp + Status Ticks
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Spacer(),
                    if (message.isEdited && !isDeleted) ...[
                      Text(
                        'edited ',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.4),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    if (isOut && !isDeleted) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(),
                    ],
                  ],
                ),

                // Reaction chips
                if (message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: message.reactions.entries.map((entry) {
                      final emoji = entry.key;
                      final count = entry.value.length;
                      final reactedByMe = myPubkey != null && entry.value.contains(myPubkey);
                      return GestureDetector(
                        onTap: () => onReactionTap?.call(emoji),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: reactedByMe
                                ? const Color(AppConstants.primaryColorHex).withOpacity(0.2)
                                : Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: reactedByMe
                                  ? const Color(AppConstants.primaryColorHex)
                                  : Colors.white12,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 12)),
                              if (count > 1) ...[
                                const SizedBox(width: 3),
                                Text(
                                  count.toString(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: reactedByMe
                                        ? const Color(AppConstants.primaryColorHex)
                                        : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (message.isPending) {
      return Icon(Icons.access_time, size: 12, color: Colors.white.withOpacity(0.6));
    }
    if (message.isFailed) {
      return const Icon(Icons.error_outline, size: 13, color: Colors.redAccent);
    }
    if (message.isRead) {
      return const Icon(Icons.done_all, size: 14, color: Color(AppConstants.primaryColorHex));
    }
    if (message.isDelivered) {
      return Icon(Icons.done_all, size: 14, color: Colors.white.withOpacity(0.7));
    }
    return Icon(Icons.done, size: 14, color: Colors.white.withOpacity(0.6));
  }
}
