import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/storage.dart';
import '../providers/auth_provider.dart';
import '../widgets/avatar_widget.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showKeyDialog(BuildContext context, String title, String keyText) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            keyText,
            style: const TextStyle(
              color: Color(AppConstants.primaryColorHex),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: keyText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard!')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, AuthProvider auth) {
    final nameCtrl = TextEditingController(text: auth.myProfile?.displayName ?? '');
    final userCtrl = TextEditingController(text: auth.myProfile?.username ?? '');
    bool isSaving = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(AppConstants.cardColorHex),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'Your name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'username (optional)',
                  prefixText: '@',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(AppConstants.primaryColorHex),
                foregroundColor: Colors.black,
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      setModalState(() {
                        isSaving = true;
                        error = null;
                      });

                      final ok = await auth.updateProfile(
                        displayName: nameCtrl.text.trim(),
                        username: userCtrl.text.trim(),
                      );

                      if (context.mounted) {
                        setModalState(() => isSaving = false);
                        if (ok) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Profile updated!')),
                          );
                        } else {
                          setModalState(() => error = auth.authError ?? 'Update failed');
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showServerSettingsDialog(BuildContext context) async {
    final currentUrl = await SecureKeyStorage.getServerUrl();
    final urlCtrl = TextEditingController(text: currentUrl);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Server Configuration', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Specify your PotyGram server URL:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://chat.potygram.ir/',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(AppConstants.primaryColorHex),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              var url = urlCtrl.text.trim();
              if (url.isNotEmpty) {
                if (!url.endsWith('/')) url = '$url/';
                await SecureKeyStorage.saveServerUrl(url);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Server URL updated!')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Local Cache?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will purge locally cached messages. Your identity keys remain safe, and recent messages will re-sync from the server.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await AppDatabase.clearDatabase();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Local cache cleared successfully!')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Make sure you have saved your Secret Key. Without it, you will never be able to access this account again.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await auth.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Account Permanently?', style: TextStyle(color: Colors.redAccent)),
        content: const Text(
          'This will permanently delete your identity, username, and all messages from the server.\n\nTHIS CANNOT BE UNDONE.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await auth.deleteAccount();
              if (context.mounted) {
                if (ok) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to delete account')),
                  );
                }
              }
            },
            child: const Text('Delete Account', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final profile = auth.myProfile;
    final keys = auth.myKeys;

    return Scaffold(
      backgroundColor: const Color(AppConstants.backgroundColorHex),
      appBar: AppBar(
        backgroundColor: const Color(AppConstants.cardColorHex),
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Profile Header Card
          Center(
            child: Column(
              children: [
                AvatarWidget(
                  displayName: profile?.displayName ?? 'Me',
                  avatarUrl: profile?.avatar,
                  size: 76,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      profile?.displayName ?? '',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (profile?.verified == true) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.verified, size: 18, color: Color(AppConstants.primaryColorHex)),
                    ],
                  ],
                ),
                if (profile?.username.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${profile!.username}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(AppConstants.primaryColorHex),
                    side: const BorderSide(color: Color(AppConstants.primaryColorHex)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Profile'),
                  onPressed: () => _showEditProfileDialog(context, auth),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Security & Keys Section
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Security & Encryption',
              style: TextStyle(color: Color(AppConstants.primaryColorHex), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.white70),
            title: const Text('Public Identity Key', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              keys?.pubkey ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: const Icon(Icons.copy, size: 18, color: Colors.white54),
            onTap: () {
              if (keys != null) _showKeyDialog(context, 'Your Public Key', keys.pubkey);
            },
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined, color: Colors.white70),
            title: const Text('Backup Secret Key', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Tap to view and export full account key', style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              if (keys != null) _showKeyDialog(context, 'Secret Key Backup', keys.backupString);
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined, color: Colors.white70),
            title: const Text('Export Full Backup Text', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Copy key backup in PotyGram backup file format', style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.copy, size: 18, color: Colors.white54),
            onTap: () {
              if (keys != null) {
                final backupText = [
                  '=== PotyGram Key Backup ===',
                  'Saved: ${DateTime.now().toIso8601String()}',
                  'Display Name: ${profile?.displayName ?? ""}',
                  if (profile?.username.isNotEmpty == true) 'Username: ${profile!.username}',
                  'Public Key: ${keys.pubkey}',
                  'Secret Key: ${keys.secretKey}',
                  'Sign Public Key: ${keys.signPubkey}',
                  'Sign Secret Key: ${keys.signSecretKey}',
                  '',
                  'Keep this private and safe.',
                  'Anyone with your Secret Key can access your account.',
                ].join('\n');
                _showKeyDialog(context, 'Full Backup File Text', backupText);
              }
            },
          ),

          const Divider(color: Colors.white12, height: 28),

          // Network & Storage Section
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Network & Storage',
              style: TextStyle(color: Color(AppConstants.primaryColorHex), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined, color: Colors.white70),
            title: const Text('Server Connection', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Configure backend server endpoint', style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _showServerSettingsDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined, color: Colors.white70),
            title: const Text('Clear Message Cache', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Free local SQLite database storage', style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _confirmClearCache(context),
          ),

          const Divider(color: Colors.white12, height: 28),

          // Account Actions Section
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orangeAccent),
            title: const Text('Sign Out', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            onTap: () => _confirmLogout(context, auth),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Delete Account', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () => _confirmDeleteAccount(context, auth),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'PotyGram v1.0.0 • E2E Encrypted',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
