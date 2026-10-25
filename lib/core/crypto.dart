import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

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
  static SodiumSumo? _sodium;

  static Future<void> init() async {
    if (_sodium != null) return;
    _sodium = await SodiumSumoInit.init();
  }

  static SodiumSumo get sodium {
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

  /// Parse user's secret key from all supported formats:
  /// - Standard: `<secretKey> | sign:<signSecretKey>`
  /// - Backup file text: containing `Secret Key: ...` and `Sign Secret Key: ...`
  /// - JSON backup: `{"pubkey": "...", "secretKey": "...", ...}`
  /// - Pipe separated: `<secretKey> | <signSecretKey>`
  static KeyPairSet parseSecretKey(String rawInput) {
    String input = rawInput.trim();
    if (input.isEmpty) {
      throw const FormatException('Please enter your secret key.');
    }

    String? secretKeyHex;
    String? signSecretKeyHex;

    // 1. Check for JSON format
    try {
      if (input.startsWith('{') && input.endsWith('}')) {
        final data = json.decode(input);
        if (data is Map) {
          secretKeyHex = data['secretKey']?.toString().trim();
          signSecretKeyHex = data['signSecretKey']?.toString().trim();
        }
      }
    } catch (_) {}

    // 2. Check for PotyGram TXT backup file format
    if (secretKeyHex == null && input.contains('Secret Key:')) {
      final lines = input.split('\n');
      for (final line in lines) {
        final l = line.trim();
        if (l.startsWith('Secret Key:')) {
          secretKeyHex = l.substring('Secret Key:'.length).trim();
        } else if (l.startsWith('Sign Secret Key:')) {
          signSecretKeyHex = l.substring('Sign Secret Key:'.length).trim();
        }
      }
    }

    // 3. Check for standard combined format: "<secretKey> | sign:<signSecretKey>"
    if (secretKeyHex == null && input.contains(' | sign:')) {
      final parts = input.split(' | sign:').map((s) => s.trim()).toList();
      secretKeyHex = parts[0];
      signSecretKeyHex = parts.length > 1 ? parts[1] : '';
    } else if (secretKeyHex == null && input.contains('|')) {
      final parts = input.split('|').map((s) => s.trim().replaceAll('sign:', '')).toList();
      secretKeyHex = parts[0];
      signSecretKeyHex = parts.length > 1 ? parts[1] : '';
    }

    // 4. Raw key if only 64 hex characters provided
    if (secretKeyHex == null) {
      secretKeyHex = input;
    }

    secretKeyHex = secretKeyHex.toLowerCase().trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(secretKeyHex)) {
      throw const FormatException('Invalid encryption secret key (expected 64 hex characters).');
    }

    final s = sodium;
    // Derive X25519 public key using crypto_scalarmult_base (identical to web libsodium)
    final skBytes = Uint8List.fromList(hex.decode(secretKeyHex));
    final secureSk = SecureKey.fromList(s, skBytes);
    final pubkeyBytes = s.crypto.scalarmult.base(n: secureSk);
    final pubkeyHex = hex.encode(pubkeyBytes).toLowerCase();
    secureSk.dispose();

    String signPubkeyHex;
    if (signSecretKeyHex != null && RegExp(r'^[0-9a-f]{64,128}$').hasMatch(signSecretKeyHex.toLowerCase())) {
      signSecretKeyHex = signSecretKeyHex.toLowerCase().trim();
      final signSkBytes = Uint8List.fromList(hex.decode(signSecretKeyHex));
      if (signSkBytes.length >= 64) {
        // Last 32 bytes of 64-byte Ed25519 secret key is the public key
        signPubkeyHex = hex.encode(signSkBytes.sublist(32, 64)).toLowerCase();
      } else {
        // 32-byte seed
        final secureSeed = SecureKey.fromList(s, signSkBytes.sublist(0, 32));
        final pair = s.crypto.sign.seedKeyPair(secureSeed);
        signPubkeyHex = hex.encode(pair.publicKey).toLowerCase();
        secureSeed.dispose();
        pair.secretKey.dispose();
      }
    } else {
      // If sign secret key wasn't provided, derive Ed25519 deterministically from the 32-byte secret key
      final secureSeed = SecureKey.fromList(s, skBytes);
      final pair = s.crypto.sign.seedKeyPair(secureSeed);
      signPubkeyHex = hex.encode(pair.publicKey).toLowerCase();
      signSecretKeyHex = hex.encode(pair.secretKey.extractBytes()).toLowerCase();
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

  /// Create detached signature of a message string (e.g. login challenge, registration proof)
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

  /// Decrypt raw bytes from sealed box
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
