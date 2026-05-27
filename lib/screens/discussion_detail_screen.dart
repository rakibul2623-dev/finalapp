import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/nav.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/services/points_service.dart';

class DiscussionDetailScreen extends StatefulWidget {
  final String discussionId;
  const DiscussionDetailScreen({super.key, required this.discussionId});

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen> {
  final _client = Supabase.instance.client;
  final _scrollController = ScrollController();
  final TextEditingController _replyCtrl = TextEditingController();
  Map<String, dynamic>? _discussion; // includes profile + category
  bool _loadingDiscussion = true;
  bool _posting = false;
  bool _togglingLike = false;
  bool _isLikedByMeDiscussion = false;
  String? _authorId;

  // Profiles cache for replies
  final Map<String, Map<String, dynamic>> _profiles = {};
  StreamSubscription<List<Map<String, dynamic>>>? _repliesSub;
  List<Map<String, dynamic>> _replies = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _listenReplies();
  }

  @override
  void dispose() {
    _repliesSub?.cancel();
    _replyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      setState(() => _loadingDiscussion = true);
      // Q1: discussion
      final dRes = await _client.from('discussions').select('*').eq('id', widget.discussionId).maybeSingle();
      if (dRes != null) {
        _discussion = Map<String, dynamic>.from(dRes as Map);
        _authorId = _discussion?['user_id'] as String?;
        // increment views (best effort)
        unawaited(_client.from('discussions').update({'views': (_discussion?['views'] ?? 0) + 1}).eq('id', widget.discussionId));

        // fetch author profile
        if (_authorId != null) {
          try {
            final prof = await _client.from('profiles').select('user_id, full_name, avatar_url, tier').eq('user_id', _authorId!).maybeSingle();
            if (prof != null) _discussion!['profile'] = prof;
          } catch (e) {
            debugPrint('Profile fetch error: $e');
          }
        }

        // fetch likes count
        try {
          final likes = await _client.from('post_likes').select('id').eq('discussion_id', widget.discussionId);
          _discussion!['like_count'] = (likes as List).length;
        } catch (e) {
          _discussion!['like_count'] = 0;
        }

        // is_liked_by_me for discussion
        final uid = _client.auth.currentUser?.id;
        if (uid != null) {
          final like = await _client.from('post_likes').select('id').eq('user_id', uid).eq('discussion_id', widget.discussionId).maybeSingle();
          _isLikedByMeDiscussion = like != null;
        }
      }
    } catch (e) {
      debugPrint('Failed to load discussion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to load discussion')));
      }
    } finally {
      if (mounted) setState(() => _loadingDiscussion = false);
    }
  }

  void _listenReplies() {
    final stream = _client
        .from('replies')
        .stream(primaryKey: ['id'])
        .eq('discussion_id', widget.discussionId)
        .order('is_best_answer', ascending: false)
        .order('created_at', ascending: true);

    _repliesSub = stream.listen((rows) async {
      _replies = rows;
      // Fetch profiles for new user ids
      final userIds = rows.map((r) => r['user_id'] as String).toSet();
      final missing = userIds.where((id) => !_profiles.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        try {
          final profRows = await _client.from('profiles').select('user_id, full_name, avatar_url, tier').inFilter('user_id', missing);
          for (final p in (profRows as List)) {
            final m = Map<String, dynamic>.from(p as Map);
            final key = (m['user_id'] ?? '').toString();
            if (key.isNotEmpty) _profiles[key] = m;
          }
        } catch (e) {
          debugPrint('Failed fetching reply profiles: $e');
        }
      }
      // Enrich liked_by_me flags batch
      final uid = _client.auth.currentUser?.id;
      if (uid != null && rows.isNotEmpty) {
        final ids = rows.map((r) => r['id'] as String).toList();
        try {
          final likes = await _client.from('post_likes').select('reply_id').eq('user_id', uid).inFilter('reply_id', ids);
          final likedIds = (likes as List).map((e) => (e as Map)['reply_id']).toSet();
          _replies = _replies
              .map((r) => {
                    ...r,
                    'liked_by_me': likedIds.contains(r['id']),
                  })
              .toList();
        } catch (e) {
          debugPrint('Failed fetching liked_by_me for replies: $e');
        }
      }
      if (mounted) setState(() {});
    });
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleLikeDiscussion() async {
    if (_discussion == null || _togglingLike) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _togglingLike = true);
    final didLike = _isLikedByMeDiscussion;
    setState(() {
      _isLikedByMeDiscussion = !didLike;
      _discussion!['like_count'] = (_discussion!['like_count'] ?? 0) + (didLike ? -1 : 1);
    });
    try {
      if (didLike) {
        await _client
            .from('post_likes')
            .delete()
            .eq('user_id', uid)
            .eq('discussion_id', widget.discussionId);
      } else {
        await _client.from('post_likes').insert({
          'user_id': uid,
          'discussion_id': widget.discussionId,
        });
        // award +2 points to author (like_received)
        if (_authorId != null && _authorId != uid) {
          unawaited(PointsService.awardPoints(_authorId!, 2, 'like_received', widget.discussionId));
        }
      }
    } catch (e) {
      debugPrint('Failed to toggle like on discussion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update like')));
      }
      // revert
      setState(() {
        _isLikedByMeDiscussion = didLike;
        _discussion!['like_count'] = (_discussion!['like_count'] ?? 0) + (didLike ? 1 : -1);
      });
    } finally {
      if (mounted) setState(() => _togglingLike = false);
    }
  }

  Future<void> _toggleLikeReply(Map<String, dynamic> reply) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final liked = reply['liked_by_me'] == true;
    final id = reply['id'];
    setState(() {
      reply['liked_by_me'] = !liked;
      if (reply.containsKey('like_count')) {
        reply['like_count'] = (reply['like_count'] ?? 0) + (liked ? -1 : 1);
      }
    });
    try {
      if (liked) {
        await _client.from('post_likes').delete().eq('user_id', uid).eq('reply_id', id);
        // Do not decrement replies.likes on unlike per spec
      } else {
        await _client.from('post_likes').insert({'user_id': uid, 'reply_id': id});
        // Increment replies.likes
        final currentLikes = (reply['likes'] as int?) ?? 0;
        unawaited(_client.from('replies').update({'likes': currentLikes + 1}).eq('id', id));
        // Award +2 to reply author for like received
        final replyAuthor = reply['user_id'] as String?;
        if (replyAuthor != null && replyAuthor != uid) {
          unawaited(PointsService.awardPoints(replyAuthor, 2, 'like_received', id.toString()));
        }
      }
    } catch (e) {
      debugPrint('Failed toggle like reply: $e');
      setState(() {
        reply['liked_by_me'] = liked;
        if (reply.containsKey('like_count')) {
          reply['like_count'] = (reply['like_count'] ?? 0) + (liked ? 1 : -1);
        }
      });
    }
  }

  Future<void> _submitReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _posting = true);
    try {
      final inserted = await _client.from('replies').insert({
        'discussion_id': widget.discussionId,
        'user_id': uid,
        'body': text,
      }).select('id').maybeSingle();

      // Points +5 for posting reply
      final replyId = (inserted?['id'] as String?) ?? '';
      unawaited(PointsService.awardPoints(uid, 5, 'post_reply', replyId.isNotEmpty ? replyId : widget.discussionId));

      // Notification to discussion author
      if (_authorId != null && _authorId != uid) {
        unawaited(_client.from('notifications').insert({
          'user_id': _authorId,
          'type': 'reply',
          'title': 'New reply on your discussion',
          'body': text.length > 80 ? text.substring(0, 80) + '…' : text,
          'reference_id': widget.discussionId,
        }));
      }

      _replyCtrl.clear();
      // scroll to bottom
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      debugPrint('Failed to submit reply: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send reply')));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _markBestAnswer(Map<String, dynamic> reply) async {
    if (_authorId == null) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid != _authorId) return; // only discussion author
    try {
      await _client.from('replies').update({'is_best_answer': true}).eq('id', reply['id']);
      // Award +25 to reply author (best_answer)
      final replyAuthor = reply['user_id'] as String?;
      if (replyAuthor != null) {
        unawaited(PointsService.awardPoints(replyAuthor, 25, 'best_answer', reply['id'].toString()));
        unawaited(_client.from('notifications').insert({
          'user_id': replyAuthor,
          'type': 'best_answer',
          'title': 'Your reply was marked Best Answer',
          'body': 'Your reply received Best Answer.',
          'reference_id': reply['id'],
        }));
      }
    } catch (e) {
      debugPrint('Failed to mark best answer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to mark best answer')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionActive = context.watch<AppState>().subscriptionActive;
    final isAuthor = _client.auth.currentUser?.id == _authorId;
    final disc = _discussion;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.foreground),
          onPressed: () => context.pop(),
        ),
        centerTitle: false,
        title: Text('Discussion', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.foreground)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.foreground),
            onPressed: () async {
              final link = 'https://hajjwallet.app${AppRoutes.discussionDetail.replaceFirst(':discussionId', widget.discussionId)}';
              await Clipboard.setData(ClipboardData(text: link));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingDiscussion
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _DiscussionCard(
                            discussion: disc!,
                            isLikedByMe: _isLikedByMeDiscussion,
                            onToggleLike: _toggleLikeDiscussion,
                            isAuthor: isAuthor,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('${_replies.length} Replies', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final r = _replies[index];
                            final prof = _profiles[r['user_id']] ?? {};
                            final createdAt = DateTime.tryParse(r['created_at']?.toString() ?? '');
                            final isBest = r['is_best_answer'] == true;
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: isBest ? AppColors.primary : AppColors.border, width: isBest ? 2 : 1),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isBest)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.verified_rounded, size: 16, color: AppColors.primary),
                                            SizedBox(width: 6),
                                            Text('Best Answer', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: AppColors.background,
                                          backgroundImage: (prof['avatar_url'] != null && (prof['avatar_url'] as String).isNotEmpty)
                                              ? NetworkImage(prof['avatar_url'])
                                              : null,
                                          child: (prof['avatar_url'] == null || (prof['avatar_url'] as String).isEmpty)
                                              ? Text((prof['full_name'] ?? '?').toString().isNotEmpty ? (prof['full_name'] as String)[0] : '?')
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      (prof['full_name'] ?? 'User') as String,
                                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                                    ),
                                                  ),
                                                  Text(createdAt != null ? _timeAgo(createdAt.toLocal()) : '' ,
                                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                (r['body'] ?? '') as String,
                                                style: Theme.of(context).textTheme.bodyMedium,
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                children: [
                                                  IconButton(
                                                    icon: Icon(
                                                      r['liked_by_me'] == true ? Icons.favorite : Icons.favorite_border,
                                                      color: r['liked_by_me'] == true ? AppColors.primary : AppColors.mutedForeground,
                                                      size: 20,
                                                    ),
                                                    onPressed: () => _toggleLikeReply(r),
                                                   ),
                                                  Text('${r['likes'] ?? 0}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                                                  const SizedBox(width: 8),
                                                  if (isAuthor && !isBest)
                                                    TextButton(
                                                      onPressed: () => _markBestAnswer(r),
                                                      child: const Text('Mark Best Answer'),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _replies.length,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
          ),
          // Fixed reply bar (only if subscribed)
          if (subscriptionActive)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10 + 8),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.background,
                    child: const Icon(Icons.person, size: 18, color: AppColors.mutedForeground),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a reply...',
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        filled: true,
                        fillColor: AppColors.inputBackground,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _posting ? null : _submitReply,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: _posting
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.mutedForeground),
                  const SizedBox(width: 6),
                  Text('Subscribe to reply', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscussionCard extends StatelessWidget {
  final Map<String, dynamic> discussion;
  final bool isLikedByMe;
  final VoidCallback onToggleLike;
  final bool isAuthor;
  const _DiscussionCard({required this.discussion, required this.isLikedByMe, required this.onToggleLike, required this.isAuthor});

  @override
  Widget build(BuildContext context) {
    final prof = (discussion['profile'] ?? {}) as Map;
    final createdAt = DateTime.tryParse(discussion['created_at']?.toString() ?? '');
    final likeCount = discussion['like_count'] ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text((discussion['category'] ?? '').toString(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (createdAt != null)
                Text(
                  '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text((discussion['title'] ?? '') as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text((discussion['body'] ?? '') as String, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.background,
                backgroundImage: (prof['avatar_url'] != null && (prof['avatar_url'] as String).isNotEmpty)
                    ? NetworkImage(prof['avatar_url'])
                    : null,
                child: (prof['avatar_url'] == null || (prof['avatar_url'] as String).isEmpty)
                    ? Text((prof['full_name'] ?? '?').toString().isNotEmpty ? (prof['full_name'] as String)[0] : '?')
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text((prof['full_name'] ?? 'User') as String, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: onToggleLike,
                icon: Icon(isLikedByMe ? Icons.favorite : Icons.favorite_border, color: isLikedByMe ? AppColors.primary : AppColors.mutedForeground),
              ),
              Text('$likeCount', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
            ],
          ),
          if (isAuthor)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit')),
            ),
        ],
      ),
    );
  }
}
