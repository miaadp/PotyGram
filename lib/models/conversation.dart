class Conversation {
  final String peerPubkey;
  final String displayName;
  final String username;
  final String? avatar;
  final String convoType; // 'dm' or 'group'
  final int lastAt;
  final int lastId;
  final String? lastSender;
  final String? lastMsgType;
  final String? lastMsgText;
  final int unreadCount;
  final bool verified;

  Conversation({
    required this.peerPubkey,
    required this.displayName,
    required this.username,
    this.avatar,
    this.convoType = 'dm',
    required this.lastAt,
    required this.lastId,
    this.lastSender,
    this.lastMsgType,
    this.lastMsgText,
    this.unreadCount = 0,
    this.verified = false,
  });

  bool get isGroup => convoType == 'group';

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      peerPubkey: (map['peer_pubkey'] ?? '').toString().toLowerCase(),
      displayName: (map['display_name'] ?? map['username'] ?? '').toString(),
      username: (map['username'] ?? '').toString(),
      avatar: map['avatar'] as String?,
      convoType: (map['convo_type'] ?? 'dm').toString(),
      lastAt: (map['last_at'] is num) ? (map['last_at'] as num).toInt() : 0,
      lastId: (map['last_id'] is num) ? (map['last_id'] as num).toInt() : 0,
      lastSender: map['last_sender'] as String?,
      lastMsgType: map['last_msg_type'] as String?,
      lastMsgText: map['last_msg_text'] as String?,
      unreadCount: (map['unread_count'] is num) ? (map['unread_count'] as num).toInt() : 0,
      verified: map['verified'] == 1 || map['verified'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'peer_pubkey': peerPubkey,
    'display_name': displayName,
    'username': username,
    'avatar': avatar,
    'convo_type': convoType,
    'last_at': lastAt,
    'last_id': lastId,
    'last_sender': lastSender,
    'last_msg_type': lastMsgType,
    'last_msg_text': lastMsgText,
    'unread_count': unreadCount,
    'verified': verified ? 1 : 0,
  };

  Conversation copyWith({
    String? displayName,
    String? username,
    String? avatar,
    int? lastAt,
    int? lastId,
    String? lastSender,
    String? lastMsgType,
    String? lastMsgText,
    int? unreadCount,
    bool? verified,
  }) {
    return Conversation(
      peerPubkey: peerPubkey,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      convoType: convoType,
      lastAt: lastAt ?? this.lastAt,
      lastId: lastId ?? this.lastId,
      lastSender: lastSender ?? this.lastSender,
      lastMsgType: lastMsgType ?? this.lastMsgType,
      lastMsgText: lastMsgText ?? this.lastMsgText,
      unreadCount: unreadCount ?? this.unreadCount,
      verified: verified ?? this.verified,
    );
  }
}
