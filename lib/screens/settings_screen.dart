import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
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

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
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
          // Profile Card
          Center(
            child: Column(
              children: [
                AvatarWidget(
                  displayName: profile?.displayName ?? 'Me',
                  avatarUrl: profile?.avatar,
                  size: 72,
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
                if (profile?.username.isNotEmpty == true)
                  Text(
                    '@${profile!.username}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Security & Keys
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

          const Divider(color: Colors.white12, height: 32),

          // Sign Out
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () => _confirmLogout(context, auth),
          ),
        ],
      ),
    );
  }
}
