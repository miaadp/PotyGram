import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:sodium_libs/sodium_libs.dart';

class KeyPairSet {
  final String pubkey;       // 64 hex chars (32 bytes) - X25519
  final String secretKey;    // 64 hex chars (32 bytes) - X25519
  final String signPubkey;   // 64 hex chars (32 bytes) - Ed25519
  final String signSecretKey;// 128 hex chars (64 bytes) - Ed25519 (seed || pk)

  KeyPairSet({
    required this.pubkey,
    required this.secretKey,
    required this.signPubkey,
    required this.signSecretKey,
  });

  String get backupString => '$secretKey | sign:$signSecretKey';
}

class PotyCrypto {
  static Sodium? _sodium;

  static Future<void> init() async {
    if (_sodium != null) return;
    _sodium = await SodiumInit.init();
  }

  static Sodium get sodium {
    final s = _sodium;
    if (s == null) {
      throw StateError('PotyCrypto not initialized. Call await PotyCrypto.init() first.');
    }
    return s;
  }

  /// Generate fresh keypairs for registration:
  /// - X25519 for sealed boxes (encryption)
  /// - Ed25519 for detached signatures
  static KeyPairSet generateKeyPairs() {
    final s = sodium;
    // 1. Box Keypair (X25519)
    final boxPair = s.crypto.box.keyPair();
    final pubkeyHex = hex.encode(boxPair.publicKey);
    final secretKeyHex = hex.encode(boxPair.secretKey.extractBytes());
    boxPair.secretKey.dispose();

    // 2. Sign Keypair (Ed25519)
    final signPair = s.crypto.sign.keyPair();
    final signPubkeyHex = hex.encode(signPair.publicKey);
    final signSecretKeyHex = hex.encode(signPair.secretKey.extractBytes());
    signPair.secretKey.dispose();


    return KeyPairSet(
      pubkey: pubkeyHex.toLowerCase(),
      secretKey: secretKeyHex.toLowerCase(),
      signPubkey: signPubkeyHex.toLowerCase(),
      signSecretKey: signSecretKeyHex.toLowerCase(),
    );
  }

  /// Parse user's secret key backup string: `<secretKey> | sign:<signSecretKey>`
  /// or derive signing key if only secret key provided.
  static KeyPairSet parseSecretKey(String rawInput) {
    final input = rawInput.trim();
    if (!input.contains(' | sign:')) {
      throw const FormatException('Incomplete key. Make sure to copy the entire key including " | sign:"');
    }

    final parts = input.split(' | sign:').map((s) => s.trim().toLowerCase()).toList();
    final secretKeyHex = parts[0];
    final signSecretKeyHex = parts[1];

    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(secretKeyHex)) {
      throw const FormatException('Invalid encryption secret key format (expected 64 hex chars)');
    }
    if (!RegExp(r'^[0-9a-f]{64,128}$').hasMatch(signSecretKeyHex)) {
      throw const FormatException('Invalid signing secret key format (expected 128 hex chars)');
    }

    final s = sodium;
    // Derive X25519 public key from X25519 secret key
    final skBytes = Uint8List.fromList(hex.decode(secretKeyHex));
    final secureSk = SecureKey.fromList(s, skBytes);
    final boxPair = s.crypto.box.seedKeyPair(secureSk);
    final pubkeyHex = hex.encode(boxPair.publicKey).toLowerCase();
    secureSk.dispose();
    boxPair.secretKey.dispose();


    // In libsodium, Ed25519 SK is 64 bytes: [32-byte seed][32-byte pubkey]
    final signSkBytes = Uint8List.fromList(hex.decode(signSecretKeyHex));
    String signPubkeyHex;
    if (signSkBytes.length >= 64) {
      final signPkBytes = signSkBytes.sublist(32, 64);
      signPubkeyHex = hex.encode(signPkBytes).toLowerCase();
    } else {
      final secureSeed = SecureKey.fromList(s, signSkBytes.sublist(0, 32));
      final pair = s.crypto.sign.seedKeyPair(secureSeed);
      signPubkeyHex = hex.encode(pair.publicKey).toLowerCase();
      secureSeed.dispose();
      pair.secretKey.dispose();
    }

    return KeyPairSet(
      pubkey: pubkeyHex,
      secretKey: secretKeyHex,
      signPubkey: signPubkeyHex,
      signSecretKey: signSecretKeyHex,
    );
  }

  /// Create detached signature of a message (e.g. login challenge, registration proof, message hash)
  static String signDetached(String message, String signSecretKeyHex) {
    final msgBytes = Uint8List.fromList(utf8.encode(message));
    final sigBytes = signBytesDetached(msgBytes, signSecretKeyHex);
    return hex.encode(sigBytes).toLowerCase();
  }

  /// Create detached signature of raw bytes
  static Uint8List signBytesDetached(Uint8List bytes, String signSecretKeyHex) {
    final s = sodium;
    final skBytes = Uint8List.fromList(hex.decode(signSecretKeyHex));
    final secureSk = SecureKey.fromList(s, skBytes);
    final sig = s.crypto.sign.detached(
      message: bytes,
      secretKey: secureSk,
    );
    secureSk.dispose();
    return sig;
  }

  /// Verify detached signature
  static bool verifyDetached(Uint8List signature, Uint8List message, String signPubkeyHex) {
    try {
      final s = sodium;
      final pkBytes = Uint8List.fromList(hex.decode(signPubkeyHex));
      return s.crypto.sign.verifyDetached(
        signature: signature,
        message: message,
        publicKey: pkBytes,
      );
    } catch (_) {
      return false;
    }
  }

  /// Encrypt text via asymmetric sealed box (crypto_box_seal)
  static Uint8List encryptBoxSeal(String plainText, String recipientPubkeyHex) {
    final textBytes = Uint8List.fromList(utf8.encode(plainText));
    final recipPkBytes = Uint8List.fromList(hex.decode(recipientPubkeyHex));
    return sodium.crypto.box.seal(
      message: textBytes,
      publicKey: recipPkBytes,
    );
  }

  /// Decrypt asymmetric sealed box (crypto_box_seal_open)
  static String? decryptBoxSeal(Uint8List ciphertextBytes, String myPubkeyHex, String mySecretKeyHex) {
    try {
      final decryptedBytes = decryptBoxSealBytes(ciphertextBytes, myPubkeyHex, mySecretKeyHex);
      if (decryptedBytes == null) return null;
      return utf8.decode(decryptedBytes);
    } catch (_) {
      return null;
    }
  }

  /// Decrypt raw bytes from sealed box (used for files/thumbnails)
  static Uint8List? decryptBoxSealBytes(Uint8List ciphertextBytes, String myPubkeyHex, String mySecretKeyHex) {
    try {
      final s = sodium;
      final pkBytes = Uint8List.fromList(hex.decode(myPubkeyHex));
      final skBytes = Uint8List.fromList(hex.decode(mySecretKeyHex));
      final secureSk = SecureKey.fromList(s, skBytes);
      final decrypted = s.crypto.box.sealOpen(
        cipherText: ciphertextBytes,
        publicKey: pkBytes,
        secretKey: secureSk,
      );
      secureSk.dispose();
      return decrypted;
    } catch (_) {
      return null;
    }
  }
}
