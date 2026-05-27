import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return [];
      final client = Supabase.instance.client;
      final parts = await client
          .from('conversation_participants')
          .select('conversation_id, last_read_at')
          .eq('user_id', uid) as List<dynamic>;
      final List<Map<String, dynamic>> result = [];
      for (final p in parts) {
        final convId = (p['conversation_id'] ?? '').toString();
        final lastReadAt = p['last_read_at']?.toString();
        DateTime? lastRead;
        if (lastReadAt != null) lastRead = DateTime.tryParse(lastReadAt);

        // Latest message
        final latest = await client
            .from('messages')
            .select('body, created_at, sender_id')
            .eq('conversation_id', convId)
            .order('created_at', ascending: false)
            .limit(1) as List<dynamic>;
        String lastBody = '';
        DateTime? lastAt;
        if (latest.isNotEmpty) {
          final m = latest.first as Map;
          lastBody = (m['body'] ?? '').toString();
          final ts = m['created_at']?.toString();
          lastAt = ts != null ? DateTime.tryParse(ts) : null;
        }

        // Unread count (messages after last_read_at by others)
        int unread = 0;
        if (lastRead != null) {
          final unreadRows = await client
              .from('messages')
              .select('id')
              .eq('conversation_id', convId)
              .neq('sender_id', uid)
              .gte('created_at', lastRead.toIso8601String()) as List<dynamic>;
          unread = unreadRows.length;
        }

        result.add({
          'id': convId,
          'last_message': lastBody,
          'last_message_at': lastAt?.toIso8601String(),
          'unread_count': unread,
        });
      }
      // Sort by last_message_at desc
      result.sort((a, b) => (b['last_message_at'] ?? '').toString().compareTo((a['last_message_at'] ?? '').toString()));
      return result;
    } catch (e) {
      debugPrint('Failed to load conversations: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Messages'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forum_outlined, size: 40, color: AppColors.silverTier),
                  const SizedBox(height: 8),
                  Text('No conversations yet', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, index) {
              final c = items[index];
              final id = '${c['id']}';
              final title = 'Conversation';
              final last = (c['last_message'] as String?) ?? '';
              final unread = (c['unread_count'] as int?) ?? 0;
              final ts = c['last_message_at'];
              DateTime? dt;
              if (ts is String) dt = DateTime.tryParse(ts);
              if (ts is DateTime) dt = ts;
              final subtitle = last.isEmpty ? 'No messages yet' : last;

              return ListTile(
                onTap: () => context.push('/messages/$id'),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
                  child: const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
                ),
                title: Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (dt != null)
                      Text(_formatTime(dt), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                    if (unread > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.all(Radius.circular(999))),
                        child: Text('$unread', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final am = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $am';
    }
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
