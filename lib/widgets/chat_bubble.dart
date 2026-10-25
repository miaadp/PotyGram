import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onSwipeReply;
  final VoidCallback? onLongPress;

  const ChatBubble({
    super.key,
    required this.message,
    this.onSwipeReply,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isOut = message.isOut;
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
              color: isOut
                  ? const Color(AppConstants.bubbleSentHex)
                  : const Color(AppConstants.bubbleReceivedHex),
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

                // Message Text
                Text(
                  message.text ?? (message.msgType == 'file' ? '📎 ${message.fileName ?? "File"}' : ''),
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),

                // Footer: Timestamp + Status Ticks
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Spacer(),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    if (isOut) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(),
                    ],
                  ],
                ),
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
    return Icon(Icons.done, size: 14, color: Colors.white.withOpacity(0.7));
  }
}
