import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/constants.dart';
import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../providers/convos_provider.dart';
import '../widgets/avatar_widget.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ConvosProvider>(context, listen: false).loadConversations();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openNewChatDialog() {
    final controller = TextEditingController();
    bool isSearchingUser = false;
    String? searchError;
    Map<String, dynamic>? foundUser;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(AppConstants.cardColorHex),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Chat', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Username or Public Key',
                  hintText: '@alice or 64-hex key',
                  errorText: searchError,
                  prefixIcon: const Icon(Icons.person_search, color: Colors.white54),
                ),
              ),
              if (foundUser != null) ...[
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AvatarWidget(
                    displayName: foundUser!['display_name'] ?? foundUser!['username'] ?? '',
                    avatarUrl: foundUser!['avatar'],
                  ),
                  title: Text(
                    foundUser!['display_name'] ?? foundUser!['username'] ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '@${foundUser!['username'] ?? foundUser!['pubkey'].toString().substring(0, 10)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (foundUser == null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(AppConstants.primaryColorHex),
                  foregroundColor: Colors.black,
                ),
                onPressed: isSearchingUser
                    ? null
                    : () async {
                        final q = controller.text.trim().replaceAll('@', '');
                        if (q.isEmpty) return;

                        setModalState(() {
                          isSearchingUser = true;
                          searchError = null;
                        });

                        ApiResponse res;
                        if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(q)) {
                          res = await ApiClient.get('user', {'pubkey': q.toLowerCase()});
                        } else {
                          res = await ApiClient.get('search', {'q': q});
                        }

                        setModalState(() {
                          isSearchingUser = false;
                          if (res.ok && res.data is Map) {
                            final d = res.data as Map;
                            if (d['users'] is List && (d['users'] as List).isNotEmpty) {
                              foundUser = Map<String, dynamic>.from(d['users'][0]);
                            } else if (d['pubkey'] != null) {
                              foundUser = Map<String, dynamic>.from(d);
                            } else {
                              searchError = 'User not found (@$q)';
                            }
                          } else {
                            searchError = res.error ?? 'User not found';
                          }
                        });
                      },
                child: isSearchingUser
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Search'),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(AppConstants.primaryColorHex),
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  final convo = Conversation(
                    peerPubkey: foundUser!['pubkey'].toString().toLowerCase(),
                    displayName: (foundUser!['display_name'] ?? foundUser!['username'] ?? '').toString(),
                    username: (foundUser!['username'] ?? '').toString(),
                    avatar: foundUser!['avatar'] as String?,
                    lastAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    lastId: 0,
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(conversation: convo)),
                  );
                },
                child: const Text('Start Chat'),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int epochSec) {
    if (epochSec <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    final now = DateTime.now();

    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('HH:mm').format(dt);
    }
    if (now.difference(dt).inDays < 7) {
      return DateFormat('E').format(dt);
    }
    return DateFormat('d MMM').format(dt);
  }

  void _showConvoOptions(BuildContext context, ConvosProvider convosProv, Conversation c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(AppConstants.cardColorHex),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AvatarWidget(displayName: c.displayName, avatarUrl: c.avatar, size: 40),
              title: Text(c.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('@${c.username.isNotEmpty ? c.username : c.peerPubkey.substring(0, 10)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.mark_chat_read_outlined, color: Colors.white70),
              title: const Text('Mark as Read', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                convosProv.markConvoRead(c.peerPubkey);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white70),
              title: const Text('Copy Public Key', style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: c.peerPubkey));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Public key copied!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete Conversation', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteConvo(context, convosProv, c);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteConvo(BuildContext context, ConvosProvider convosProv, Conversation c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(AppConstants.cardColorHex),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete conversation with ${c.displayName}?', style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: const Text(
          'This will permanently delete this conversation and all messages from this device and the server.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              convosProv.deleteConversation(c.peerPubkey);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final convosProv = Provider.of<ConvosProvider>(context);

    return Scaffold(
      backgroundColor: const Color(AppConstants.backgroundColorHex),
      appBar: AppBar(
        backgroundColor: const Color(AppConstants.cardColorHex),
        elevation: 1,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search chats…',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (v) => convosProv.setSearchQuery(v),
              )
            : Row(
                children: [
                  const Icon(Icons.shield, color: Color(AppConstants.primaryColorHex), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    AppConstants.appTitle,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  convosProv.setSearchQuery('');
                }
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              child: AvatarWidget(
                displayName: auth.myProfile?.displayName ?? 'Me',
                avatarUrl: auth.myProfile?.avatar,
                size: 34,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(AppConstants.primaryColorHex),
        backgroundColor: const Color(AppConstants.cardColorHex),
        onRefresh: () => convosProv.loadConversations(),
        child: convosProv.convos.isEmpty && !convosProv.isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'No conversations yet',
                      style: TextStyle(color: Colors.white70, fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Tap the button below to start a new encrypted chat',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: convosProv.convos.length,
                separatorBuilder: (ctx, i) => const Divider(
                  color: Colors.white10,
                  height: 1,
                  indent: 72,
                ),
                itemBuilder: (ctx, i) {
                  final c = convosProv.convos[i];
                  return Dismissible(
                    key: ValueKey('convo_${c.peerPubkey}'),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (dir) async {
                      _confirmDeleteConvo(context, convosProv, c);
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.redAccent.withOpacity(0.8),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      onLongPress: () => _showConvoOptions(context, convosProv, c),
                      leading: AvatarWidget(
                        displayName: c.displayName,
                        avatarUrl: c.avatar,
                        size: 50,
                      ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (c.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 15, color: Color(AppConstants.primaryColorHex)),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      c.lastMsgText ?? (c.username.isNotEmpty ? '@${c.username}' : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.unreadCount > 0 ? Colors.white : Colors.white54,
                        fontWeight: c.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13.5,
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(c.lastAt),
                          style: TextStyle(
                            color: c.unreadCount > 0 ? const Color(AppConstants.primaryColorHex) : Colors.white38,
                            fontSize: 11.5,
                            fontWeight: c.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (c.unreadCount > 0) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: const BoxDecoration(
                              color: Color(AppConstants.primaryColorHex),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              c.unreadCount > 99 ? '99+' : c.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    onTap: () {
                      convosProv.markConvoRead(c.peerPubkey);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
                      );
                    },
                  ),
                );
              },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(AppConstants.primaryColorHex),
        foregroundColor: Colors.black,
        onPressed: _openNewChatDialog,
        child: const Icon(Icons.edit_note, size: 28),
      ),
    );
  }
}
