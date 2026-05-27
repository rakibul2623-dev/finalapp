import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/state/app_state.dart';

class ConversationScreen extends StatefulWidget {
  final String conversationId;
  const ConversationScreen({super.key, required this.conversationId});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  Future<void> _markRead() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client
          .from('conversation_participants')
          .update({'last_read_at': DateTime.now().toIso8601String()})
          .eq('conversation_id', widget.conversationId)
          .eq('user_id', uid);
    } catch (e) {
      debugPrint('markRead error: $e');
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': uid,
        'body': text,
      });
      await Supabase.instance.client.from('conversations').update({'updated_at': DateTime.now().toIso8601String()}).eq('id', widget.conversationId);
      _ctrl.clear();
      await _markRead();
      await Future.delayed(const Duration(milliseconds: 50));
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } catch (e) {
      debugPrint('send message error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send message')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.foreground,
        title: const Text('Conversation'),
        elevation: 0,
      ),
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('conversation_id', widget.conversationId)
                  .order('created_at', ascending: true)
                  .map((rows) => rows.cast<Map<String, dynamic>>()),
              builder: (context, snapshot) {
                final msgs = snapshot.data ?? const [];
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                });
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  itemCount: msgs.length,
                  itemBuilder: (context, index) {
                    final m = msgs[index];
                    final isMe = uid != null && '${m['sender_id']}' == uid;
                    final content = (m['body'] as String?) ?? '';
                    return _MessageBubble(content: content, isMe: isMe);
                  },
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  const CircleAvatar(radius: 18, backgroundColor: AppColors.background, child: Icon(Icons.person, color: AppColors.mutedForeground)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(hintText: 'Type a message...', border: InputBorder.none),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: (_ctrl.text.trim().isEmpty || _sending) ? null : _send,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_ctrl.text.trim().isEmpty || _sending) ? AppColors.border : AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isMe;
  const _MessageBubble({required this.content, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? AppColors.primary : Colors.white;
    final fg = isMe ? Colors.white : AppColors.foreground;
    final border = isMe ? Colors.transparent : AppColors.border;
    final radius = isMe
        ? const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(3))
        : const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18));
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: radius),
          child: Text(content, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg)),
        ),
      ),
    );
  }
}
