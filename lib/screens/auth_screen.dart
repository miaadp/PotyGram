import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/crypto.dart';
import '../core/storage.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginKeyController = TextEditingController();
  final _regDisplayNameController = TextEditingController();
  final _regUsernameController = TextEditingController();
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginKeyController.dispose();
    _regDisplayNameController.dispose();
    _regUsernameController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final keyStr = _loginKeyController.text.trim();
    if (keyStr.isEmpty) {
      _showSnackBar('Please paste your Secret Key');
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.loginWithSecretKey(keyStr);

    if (!mounted) return;
    if (success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else if (auth.authError != null) {
      _showSnackBar(auth.authError!);
    }
  }

  Future<void> _handleRegister() async {
    final displayName = _regDisplayNameController.text.trim();
    final username = _regUsernameController.text.trim();

    if (displayName.isEmpty) {
      _showSnackBar('Please enter your display name');
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final keys = await auth.register(
      displayName: displayName,
      username: username.isNotEmpty ? username : null,
    );

    if (!mounted) return;
    if (keys != null) {
      _showKeyBackupDialog(keys);
    } else if (auth.authError != null) {
      _showSnackBar(auth.authError!);
    }
  }

  void _showKeyBackupDialog(KeyPairSet keys) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.key, color: Color(AppConstants.primaryColorHex)),
            SizedBox(width: 10),
            Text('Save Your Secret Key', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PotyGram has NO passwords. This key is the ONLY way to access your account. If you lose it, your account is gone forever.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                keys.backupString,
                style: const TextStyle(
                  color: Color(AppConstants.primaryColorHex),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Key'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: keys.backupString));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Secret key copied to clipboard!')),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(AppConstants.primaryColorHex),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
            child: const Text('I Saved It, Continue'),
          ),
        ],
      ),
    );
  }

  void _showServerSettingsDialog() async {
    final currentUrl = await SecureKeyStorage.getServerUrl();
    final controller = TextEditingController(text: currentUrl);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        title: const Text('Server Configuration', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Server Base URL',
            hintText: 'https://potygram.ir',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await SecureKeyStorage.saveServerUrl(newUrl);
                Navigator.pop(ctx);
                _showSnackBar('Server updated to $newUrl');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(AppConstants.backgroundColorHex),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: _showServerSettingsDialog,
            tooltip: 'Server Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 56,
                  color: Color(AppConstants.primaryColorHex),
                ),
                const SizedBox(height: 12),
                const Text(
                  AppConstants.appTitle,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),

                // Tabs
                Container(
                  decoration: BoxDecoration(
                    color: const Color(AppConstants.cardColorHex),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(AppConstants.primaryColorHex),
                    labelColor: const Color(AppConstants.primaryColorHex),
                    unselectedLabelColor: Colors.white54,
                    tabs: const [
                      Tab(text: 'Sign In'),
                      Tab(text: 'Create Account'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Tab Content
                SizedBox(
                  height: 310,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // 1. Sign In
                      _buildLoginTab(auth),

                      // 2. Register
                      _buildRegisterTab(auth),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginTab(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginKeyController,
          obscureText: _obscureKey,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          maxLines: 1,
          decoration: InputDecoration(
            labelText: 'Paste Secret Key',
            hintText: '64hex | sign:128hex',
            prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.white54),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off, color: Colors.white54),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
                IconButton(
                  icon: const Icon(Icons.paste, color: Color(AppConstants.primaryColorHex)),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _loginKeyController.text = data!.text!.trim();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(AppConstants.primaryColorHex),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: auth.isLoading ? null : _handleLogin,
          child: auth.isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildRegisterTab(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _regDisplayNameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Display Name (Required)',
            hintText: 'Alice',
            prefixIcon: Icon(Icons.person_outline, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regUsernameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Username (Optional)',
            hintText: 'alice',
            prefixIcon: Icon(Icons.alternate_email, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(AppConstants.primaryColorHex),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: auth.isLoading ? null : _handleRegister,
          child: auth.isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Text('Generate Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
