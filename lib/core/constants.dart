class AppConstants {
  static const String defaultServerUrl = 'https://potygram.ir';
  static const String appTitle = 'PotyGram';
  
  // Storage Keys
  static const String keyServerUrl = 'pg_server_url';
  static const String keyPubkey = 'pg_pubkey';
  static const String keySecretKey = 'pg_secret_key';
  static const String keySignPubkey = 'pg_sign_pubkey';
  static const String keySignSecretKey = 'pg_sign_secret_key';
  static const String keyRememberToken = 'pg_remember_token';
  static const String keyCsrfToken = 'pg_csrf_token';
  static const String keyUsername = 'pg_username';
  static const String keyDisplayName = 'pg_display_name';
  static const String keyVerified = 'pg_verified';
  
  // Network
  static const String headerRequestedWith = 'X-Requested-With';
  static const String headerRequestedWithValue = 'PotyGram';
  static const String headerRememberToken = 'X-Remember-Token';
  static const String headerCsrfToken = 'X-CSRF-Token';
  static const String headerNewRememberToken = 'X-New-Remember-Token';
  static const String headerNewCsrfToken = 'X-New-CSRF-Token';
  
  // Theme Colors
  static const int primaryColorHex = 0xFF00E5A0;
  static const int backgroundColorHex = 0xFF0F141C;
  static const int cardColorHex = 0xFF182230;
  static const int bubbleSentHex = 0xFF005C4B;
  static const int bubbleReceivedHex = 0xFF202C33;
}
