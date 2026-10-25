import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/crypto.dart';
import '../core/storage.dart';
import '../models/user.dart';
import '../services/sync_service.dart';

class AuthProvider with ChangeNotifier {
  KeyPairSet? _myKeys;
  UserProfile? _myProfile;
  bool _isLoading = true;
  String? _authError;

  KeyPairSet? get myKeys => _myKeys;
  UserProfile? get myProfile => _myProfile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _myKeys != null && _myProfile != null;
  String? get authError => _authError;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      await PotyCrypto.init();
      final keys = await SecureKeyStorage.loadKeys();
      final profileMap = await SecureKeyStorage.loadProfile();
      final rememberToken = await SecureKeyStorage.loadRememberToken();

      if (keys != null) {
        _myKeys = keys;
        _myProfile = UserProfile(
          pubkey: keys.pubkey,
          username: profileMap['username'] ?? '',
          displayName: profileMap['displayName'] ?? (keys.pubkey.substring(0, 8) + '…'),
          verified: profileMap['verified'] == 1,
        );

        if (rememberToken != null && rememberToken.isNotEmpty) {
          // Verify with server via bootstrap
          final res = await ApiClient.get('bootstrap');
          if (res.ok && res.data is Map) {
            final meData = res.data['me'];
            if (meData is Map && meData['authenticated'] == true) {
              _myProfile = UserProfile.fromJson(Map<String, dynamic>.from(meData));
              await SecureKeyStorage.saveProfile(
                username: _myProfile!.username,
                displayName: _myProfile!.displayName,
                verified: _myProfile!.verified ? 1 : 0,
              );
              SyncService().start(_myKeys!);
            } else {
              // Re-authenticate using keys
              await _silentReauth(keys);
            }
          } else {
            // Offline mode - proceed with cached session
            SyncService().start(_myKeys!);
          }
        } else {
          // Re-authenticate using keys
          await _silentReauth(keys);
        }
      }
    } catch (e) {
      debugPrint('[AuthProvider] Init error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _silentReauth(KeyPairSet keys) async {
    try {
      final meRes = await ApiClient.get('me');
      if (!meRes.ok || meRes.data is! Map) return false;

      final challenge = meRes.data['challenge'] as String?;
      if (challenge == null || challenge.isEmpty) return false;

      final proofMsg = 'login:$challenge:${keys.pubkey}';
      final proof = PotyCrypto.signDetached(proofMsg, keys.signSecretKey);

      final loginRes = await ApiClient.post('login', {
        'pubkey': keys.pubkey,
        'signing_pubkey': keys.signPubkey,
        'proof': proof,
        'proof_message': proofMsg,
      });

      if (loginRes.ok && loginRes.data is Map) {
        final d = loginRes.data as Map;
        final remToken = d['remember_token'] as String?;
        final csrfToken = d['csrf_token'] as String?;
        if (remToken != null) await SecureKeyStorage.saveRememberToken(remToken);
        if (csrfToken != null) await SecureKeyStorage.saveCsrfToken(csrfToken);

        _myProfile = UserProfile(
          pubkey: keys.pubkey,
          username: (d['username'] ?? '').toString(),
          displayName: (d['display_name'] ?? d['username'] ?? keys.pubkey.substring(0, 8)).toString(),
          verified: d['verified'] == 1 || d['verified'] == true,
        );

        SyncService().start(keys);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> loginWithSecretKey(String rawSecretKey) async {
    _authError = null;
    _isLoading = true;
    notifyListeners();

    try {
      final keys = PotyCrypto.parseSecretKey(rawSecretKey);

      final meRes = await ApiClient.get('me');
      if (!meRes.ok) {
        _authError = meRes.error ?? 'Could not reach server';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final challenge = meRes.data?['challenge'] as String?;
      if (challenge == null) {
        if (meRes.data?['authenticated'] == true &&
            (meRes.data?['pubkey'] as String?)?.toLowerCase() == keys.pubkey.toLowerCase()) {
          // Already authenticated with this pubkey
          await SecureKeyStorage.saveKeys(keys);
          _myKeys = keys;
          _myProfile = UserProfile(
            pubkey: keys.pubkey,
            username: (meRes.data?['username'] ?? '').toString(),
            displayName: (meRes.data?['display_name'] ?? meRes.data?['username'] ?? keys.pubkey.substring(0, 8)).toString(),
            verified: meRes.data?['verified'] == 1 || meRes.data?['verified'] == true,
          );
          SyncService().start(keys);
          _isLoading = false;
          notifyListeners();
          return true;
        }
        _authError = 'No login challenge received from server';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final proofMsg = 'login:$challenge:${keys.pubkey}';
      final proof = PotyCrypto.signDetached(proofMsg, keys.signSecretKey);

      final res = await ApiClient.post('login', {
        'pubkey': keys.pubkey,
        'signing_pubkey': keys.signPubkey,
        'proof': proof,
        'proof_message': proofMsg,
      });

      if (!res.ok) {
        _authError = res.error ?? 'Login rejected';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final data = res.data as Map;
      final remToken = data['remember_token'] as String?;
      final csrfToken = data['csrf_token'] as String?;

      await SecureKeyStorage.saveKeys(keys);
      if (remToken != null) await SecureKeyStorage.saveRememberToken(remToken);
      if (csrfToken != null) await SecureKeyStorage.saveCsrfToken(csrfToken);

      _myKeys = keys;
      _myProfile = UserProfile(
        pubkey: keys.pubkey,
        username: (data['username'] ?? '').toString(),
        displayName: (data['display_name'] ?? data['username'] ?? keys.pubkey.substring(0, 8)).toString(),
        verified: data['verified'] == 1 || data['verified'] == true,
      );

      await SecureKeyStorage.saveProfile(
        username: _myProfile!.username,
        displayName: _myProfile!.displayName,
        verified: _myProfile!.verified ? 1 : 0,
      );

      SyncService().start(keys);
      _isLoading = false;
      notifyListeners();
      return true;
    } on FormatException catch (e) {
      _authError = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _authError = 'Login error: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<KeyPairSet?> register({
    required String displayName,
    String? username,
  }) async {
    _authError = null;
    _isLoading = true;
    notifyListeners();

    try {
      final keys = PotyCrypto.generateKeyPairs();
      final proofMsg = 'register:${keys.pubkey}';
      final proof = PotyCrypto.signDetached(proofMsg, keys.signSecretKey);

      final res = await ApiClient.post('register', {
        'pubkey': keys.pubkey,
        'signing_pubkey': keys.signPubkey,
        'username': username?.trim() ?? '',
        'display_name': displayName.trim(),
        'proof': proof,
        'proof_message': proofMsg,
      });

      if (!res.ok) {
        _authError = res.error ?? 'Registration failed';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      final data = res.data as Map;
      final remToken = data['remember_token'] as String?;
      final csrfToken = data['csrf_token'] as String?;

      await SecureKeyStorage.saveKeys(keys);
      if (remToken != null) await SecureKeyStorage.saveRememberToken(remToken);
      if (csrfToken != null) await SecureKeyStorage.saveCsrfToken(csrfToken);

      _myKeys = keys;
      _myProfile = UserProfile(
        pubkey: keys.pubkey,
        username: (data['username'] ?? username ?? '').toString(),
        displayName: (data['display_name'] ?? displayName).toString(),
        verified: false,
      );

      await SecureKeyStorage.saveProfile(
        username: _myProfile!.username,
        displayName: _myProfile!.displayName,
        verified: 0,
      );

      SyncService().start(keys);
      _isLoading = false;
      notifyListeners();
      return keys;
    } catch (e) {
      _authError = 'Registration error: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateProfile({String? displayName, String? username, String? bio}) async {
    try {
      final payload = <String, dynamic>{};
      if (displayName != null) payload['display_name'] = displayName.trim();
      if (username != null) payload['username'] = username.trim().replaceAll('@', '');
      if (bio != null) payload['bio'] = bio.trim();

      final res = await ApiClient.post('profile', payload);
      if (res.ok && res.data is Map) {
        final d = res.data['profile'] as Map? ?? res.data as Map;
        _myProfile = UserProfile(
          pubkey: _myKeys!.pubkey,
          username: (d['username'] ?? _myProfile?.username ?? '').toString(),
          displayName: (d['display_name'] ?? _myProfile?.displayName ?? '').toString(),
          verified: _myProfile?.verified ?? false,
          avatar: _myProfile?.avatar,
        );

        await SecureKeyStorage.saveProfile(
          username: _myProfile!.username,
          displayName: _myProfile!.displayName,
          verified: _myProfile!.verified ? 1 : 0,
        );
        notifyListeners();
        return true;
      } else {
        _authError = res.error ?? 'Failed to update profile';
        notifyListeners();
      }
    } catch (e) {
      _authError = 'Profile update error: $e';
      notifyListeners();
    }
    return false;
  }

  Future<bool> deleteAccount() async {
    if (_myKeys == null) return false;
    try {
      final chRes = await ApiClient.get('delete_account_challenge');
      if (!chRes.ok || chRes.data is! Map) return false;
      final challenge = chRes.data['challenge'] as String?;
      if (challenge == null) return false;

      final proofMsg = 'delete_account:$challenge:${_myKeys!.pubkey}';
      final proof = PotyCrypto.signDetached(proofMsg, _myKeys!.signSecretKey);

      final res = await ApiClient.post('delete_account', {
        'signing_pubkey': _myKeys!.signPubkey,
        'proof': proof,
        'proof_message': proofMsg,
      });

      if (res.ok) {
        await logout();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> logout() async {
    SyncService().stop();
    await ApiClient.post('logout', {});
    await SecureKeyStorage.clearAll();
    await AppDatabase.clearDatabase();
    _myKeys = null;
    _myProfile = null;
    _authError = null;
    notifyListeners();
  }
}
