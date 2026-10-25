class UserProfile {
  final String pubkey;
  final String username;
  final String displayName;
  final String? avatar;
  final bool verified;
  final String? bio;

  UserProfile({
    required this.pubkey,
    required this.username,
    required this.displayName,
    this.avatar,
    this.verified = false,
    this.bio,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      pubkey: (json['pubkey'] ?? '').toString().toLowerCase(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['username'] ?? '').toString(),
      avatar: json['avatar'] as String?,
      verified: json['verified'] == 1 || json['verified'] == true,
      bio: json['bio'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'pubkey': pubkey,
    'username': username,
    'display_name': displayName,
    'avatar': avatar,
    'verified': verified ? 1 : 0,
    'bio': bio,
  };
}
