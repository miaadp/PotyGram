class Message {
  final int id;
  final String peerPubkey;
  final String senderPubkey;
  final String? recipientPubkey;
  final String? groupId;
  final String msgType; // 'text', 'file', 'voice', etc.
  final String? text;
  final String? fileName;
  final String? fileMime;
  final String? filePath;
  final int sentAt;
  final int? deliveredAt;
  final int? readAt;
  final int? editedAt;
  final int? deletedAt;
  final Map<String, List<String>> reactions;
  final bool isOut;
  final bool isPending;
  final bool isFailed;
  final int? replyToId;
  final String? replyPreview;

  Message({
    required this.id,
    required this.peerPubkey,
    required this.senderPubkey,
    this.recipientPubkey,
    this.groupId,
    this.msgType = 'text',
    this.text,
    this.fileName,
    this.fileMime,
    this.filePath,
    required this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.editedAt,
    this.deletedAt,
    this.reactions = const {},
    required this.isOut,
    this.isPending = false,
    this.isFailed = false,
    this.replyToId,
    this.replyPreview,
  });

  bool get isRead => readAt != null && readAt! > 0;
  bool get isDelivered => deliveredAt != null && deliveredAt! > 0;
  bool get isEdited => editedAt != null && editedAt! > 0;
  bool get isDeleted => deletedAt != null && deletedAt! > 0;

  factory Message.fromMap(Map<String, dynamic> map) {
    Map<String, List<String>> rxMap = {};
    if (map['reactions'] != null) {
      if (map['reactions'] is Map) {
        (map['reactions'] as Map).forEach((k, v) {
          if (v is List) {
            rxMap[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }
    }

    return Message(
      id: (map['id'] is num) ? (map['id'] as num).toInt() : 0,
      peerPubkey: (map['peer_pubkey'] ?? '').toString().toLowerCase(),
      senderPubkey: (map['sender_pubkey'] ?? '').toString().toLowerCase(),
      recipientPubkey: map['recipient_pubkey']?.toString().toLowerCase(),
      groupId: map['group_id']?.toString(),
      msgType: (map['msg_type'] ?? 'text').toString(),
      text: map['text'] as String?,
      fileName: map['file_name'] as String?,
      fileMime: map['file_mime'] as String?,
      filePath: map['file_path'] as String?,
      sentAt: (map['sent_at'] is num) ? (map['sent_at'] as num).toInt() : 0,
      deliveredAt: (map['delivered_at'] is num) ? (map['delivered_at'] as num).toInt() : null,
      readAt: (map['read_at'] is num) ? (map['read_at'] as num).toInt() : null,
      editedAt: (map['edited_at'] is num) ? (map['edited_at'] as num).toInt() : null,
      deletedAt: (map['deleted_at'] is num) ? (map['deleted_at'] as num).toInt() : null,
      reactions: rxMap,
      isOut: map['is_out'] == 1 || map['is_out'] == true,
      isPending: map['is_pending'] == 1 || map['is_pending'] == true,
      isFailed: map['is_failed'] == 1 || map['is_failed'] == true,
      replyToId: (map['reply_to_id'] is num) ? (map['reply_to_id'] as num).toInt() : null,
      replyPreview: map['reply_preview'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'peer_pubkey': peerPubkey,
    'sender_pubkey': senderPubkey,
    'recipient_pubkey': recipientPubkey,
    'group_id': groupId,
    'msg_type': msgType,
    'text': text,
    'file_name': fileName,
    'file_mime': fileMime,
    'file_path': filePath,
    'sent_at': sentAt,
    'delivered_at': deliveredAt,
    'read_at': readAt,
    'edited_at': editedAt,
    'deleted_at': deletedAt,
    'is_out': isOut ? 1 : 0,
    'is_pending': isPending ? 1 : 0,
    'is_failed': isFailed ? 1 : 0,
    'reply_to_id': replyToId,
    'reply_preview': replyPreview,
  };

  Message copyWith({
    int? id,
    String? text,
    int? deliveredAt,
    int? readAt,
    int? editedAt,
    int? deletedAt,
    Map<String, List<String>>? reactions,
    bool? isPending,
    bool? isFailed,
  }) {
    return Message(
      id: id ?? this.id,
      peerPubkey: peerPubkey,
      senderPubkey: senderPubkey,
      recipientPubkey: recipientPubkey,
      groupId: groupId,
      msgType: msgType,
      text: text ?? this.text,
      fileName: fileName,
      fileMime: fileMime,
      filePath: filePath,
      sentAt: sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      reactions: reactions ?? this.reactions,
      isOut: isOut,
      isPending: isPending ?? this.isPending,
      isFailed: isFailed ?? this.isFailed,
      replyToId: replyToId,
      replyPreview: replyPreview,
    );
  }
}
