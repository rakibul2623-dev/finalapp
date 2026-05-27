import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = Supabase.instance.client.auth.currentUser?.id;
  }

  Stream<List<Map<String, dynamic>>> _streamNotifs(String uid) {
    return Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(100)
        .map((rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<void> _markAllRead(BuildContext context) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
      if (mounted) context.read<AppState>().setUnreadNotifCount(0);
    } catch (e) {
      debugPrint('Failed to mark all read: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to mark all as read')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(child: Text('Please sign in to view notifications.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(context),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streamNotifs(_uid!),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load notifications'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final data = (snap.data ?? []).toList();
          if (data.isEmpty) {
            return _EmptyNotifications();
          }

          // Group by date buckets
          final groups = _groupByDateBuckets(data);

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final entry = groups.entries.elementAt(index);
              final title = entry.key;
              final items = entry.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  ...items.map((row) => _NotificationTile(
                        row: row,
                        onDeleted: () async {
                          try {
                            await Supabase.instance.client
                                .from('notifications')
                                .delete()
                                .eq('id', row['id']);
                          } catch (e) {
                            debugPrint('Failed to delete notification: $e');
                          }
                        },
                        onOpened: () async {
                          await _handleOpen(context, row);
                        },
                      )),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByDateBuckets(List<Map<String, dynamic>> items) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final startOfWeek = startOfToday.subtract(Duration(days: now.weekday % 7));

    final Map<String, List<Map<String, dynamic>>> buckets = {
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Earlier': [],
    };

    for (final row in items) {
      final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
      if (created == null) {
        buckets['Earlier']!.add(row);
        continue;
      }
      if (created.isAfter(startOfToday)) {
        buckets['Today']!.add(row);
      } else if (created.isAfter(startOfYesterday)) {
        buckets['Yesterday']!.add(row);
      } else if (created.isAfter(startOfWeek)) {
        buckets['This Week']!.add(row);
      } else {
        buckets['Earlier']!.add(row);
      }
    }

    // Remove empty groups
    final nonEmpty = <String, List<Map<String, dynamic>>>{};
    buckets.forEach((k, v) {
      if (v.isNotEmpty) nonEmpty[k] = v;
    });
    return nonEmpty;
  }

  Future<void> _handleOpen(BuildContext context, Map<String, dynamic> row) async {
    try {
      if ((row['is_read'] == null || row['is_read'] == false)) {
        await Supabase.instance.client
            .from('notifications')
            .update({'is_read': true})
            .eq('id', row['id']);
        if (mounted) {
          final app = context.read<AppState>();
          if (app.unreadNotifCount > 0) {
            app.setUnreadNotifCount(app.unreadNotifCount - 1);
          }
        }
      }

      final link = (row['link'] ?? '').toString();
      if (link.isNotEmpty && link.startsWith('http')) {
        final uri = Uri.parse(link);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }

      // If no explicit http link, navigate by type + reference_id
      final type = (row['type'] ?? '').toString();
      final refId = (row['reference_id'] ?? '').toString();
      String? route;
      switch (type) {
        case 'booking':
          route = '/my-bookings';
          break;
        case 'order':
          route = '/my-orders';
          break;
        case 'community':
          route = refId.isNotEmpty ? '/discussion/$refId' : '/community';
          break;
        case 'membership':
          route = '/account';
          break;
        case 'contribution':
          route = '/wallet';
          break;
        case 'sponsorship':
          route = '/sponsorship';
          break;
        default:
          if (link.isNotEmpty) route = link; // internal app route
      }
      if (!mounted) return;
      if (route != null && route.isNotEmpty) context.go(route);
    } catch (e) {
      debugPrint('Failed to open notification: $e');
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.row, required this.onDeleted, required this.onOpened});
  final Map<String, dynamic> row;
  final VoidCallback onDeleted;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final isRead = (row['is_read'] == true);
    final type = (row['type'] ?? 'system').toString();
    final title = (row['title'] ?? '').toString();
    final body = (row['body'] ?? '').toString();
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final timeText = _formatTime(createdAt);

    final iconAndBg = _typeVisuals(type);

    return Dismissible(
      key: ValueKey(row['id']?.toString() ?? UniqueKey().toString()),
      direction: DismissDirection.startToEnd,
      background: Container(
        color: AppColors.destructive.withValues(alpha: 0.1),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: AppColors.destructive),
      ),
      onDismissed: (_) => onDeleted(),
      child: InkWell(
        onTap: onOpened,
        child: Container(
          color: isRead ? AppColors.surface : AppColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconAndBg.$2,
                  shape: BoxShape.circle,
                ),
                child: Icon(iconAndBg.$1, color: AppColors.foreground, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    if (body.isNotEmpty)
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      timeText,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.mutedForeground,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _typeVisuals(String type) {
    switch (type) {
      case 'tier_upgrade':
        return (Icons.workspace_premium, const Color(0xFFFEF9C3));
      case 'order':
        return (Icons.receipt_long, const Color(0xFFDBEAFE));
      case 'reply':
        return (Icons.chat_bubble, const Color(0xFFF0FDF4));
      case 'like':
        return (Icons.favorite, const Color(0xFFFEF2F2));
      case 'booking':
        return (Icons.flight_takeoff, const Color(0xFFEDE9FE));
      default:
        return (Icons.info, const Color(0xFFEEF4EF));
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }
}

class _EmptyNotifications extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_none, size: 48, color: AppColors.mutedForeground),
          const SizedBox(height: 8),
          Text('All caught up!', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
