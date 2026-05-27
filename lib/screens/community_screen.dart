import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/services/points_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _searchCtrl = TextEditingController();
  String selectedFilter = 'all'; // all | unanswered | trending | mine
  String selectedCategoryId = 'all';
  String searchQuery = '';

  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _discussions = const [];
  Map<String, Map<String, dynamic>> _profilesById = const {}; // id -> profile
  Set<String> _likedByMe = const {};
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _topContributors = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadCategories(),
        _loadStats(),
        _loadTopContributors(),
      ]);
      _offset = 0;
      _hasMore = true;
      await _loadDiscussions(reset: true);
    } catch (e) {
      debugPrint('Community load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final res = await Supabase.instance.client
          .from('discussion_categories')
          .select('id, name, sort_order')
          .order('sort_order');
      _categories = List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('Categories load error: $e');
      _categories = const [];
    }
  }

  Future<void> _loadStats() async {
    try {
      final res = await Supabase.instance.client
          .from('v_community_stats')
          .select()
          .limit(1)
          .maybeSingle();
      _stats = (res as Map<String, dynamic>?) ?? const {};
    } catch (e) {
      debugPrint('Stats load error: $e');
      _stats = const {};
    }
  }

  Future<void> _loadTopContributors() async {
    try {
      final supa = Supabase.instance.client;
      final rows = await supa
          .from('profiles')
          .select('user_id, full_name, avatar_url, tier')
          .order('points_total', ascending: false)
          .limit(10);
      _topContributors = List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('Top contributors load error: $e');
      _topContributors = const [];
    }
  }

  Future<void> _loadDiscussions({bool reset = false}) async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    try {
      if (reset) {
        _offset = 0;
        _hasMore = true;
        _discussions = const [];
      }
      var base = supa
          .from('discussions')
          .select('id, title, body, created_at, category, views, user_id, image_url, is_trending, best_answer_id');

      if (selectedFilter == 'mine' && uid != null) {
        base = base.eq('user_id', uid);
      }
      if (selectedFilter == 'unanswered') {
        // We'll filter after counts too; this keeps payload smaller if backend adds a view
      }
      if (selectedFilter == 'trending') {
        // Sorting later by like_count
      }
      if (selectedCategoryId != 'all') {
        final cat = _categories.firstWhere(
          (c) => c['id']?.toString() == selectedCategoryId,
          orElse: () => const {'name': ''},
        );
        final catName = (cat['name'] ?? '').toString();
        if (catName.isNotEmpty) base = base.eq('category', catName);
      }
      if (searchQuery.isNotEmpty) {
        base = base.ilike('title', '%$searchQuery%');
      }

      // Order by latest; 'trending' handled after aggregations
      var ordered = base.order('created_at', ascending: false);

      final res = await ordered.range(_offset, _offset + _pageSize - 1);
      final list = List<Map<String, dynamic>>.from(res as List);
      if (reset) {
        _discussions = list;
      } else {
        _discussions = List<Map<String, dynamic>>.from([..._discussions, ...list]);
      }
      if (list.length < _pageSize) _hasMore = false; else _offset += _pageSize;

      // Aggregate reply and like counts
      final ids = _discussions.map((e) => e['id'] as String).toList();
      Map<String, int> replyCounts = {};
      Map<String, int> likeCounts = {};
      if (ids.isNotEmpty) {
        try {
          final reps = await supa.from('replies').select('discussion_id').inFilter('discussion_id', ids);
          for (final r in (reps as List)) {
            final dId = (r['discussion_id'] ?? '').toString();
            replyCounts[dId] = (replyCounts[dId] ?? 0) + 1;
          }
        } catch (e) {
          debugPrint('Replies agg error: $e');
        }
        try {
          final likes = await supa.from('post_likes').select('discussion_id').inFilter('discussion_id', ids);
          for (final r in (likes as List)) {
            final dId = (r['discussion_id'] ?? '').toString();
            if (dId.isEmpty) continue;
            likeCounts[dId] = (likeCounts[dId] ?? 0) + 1;
          }
        } catch (e) {
          debugPrint('Likes agg error: $e');
        }
      }

      // Attach counts
      for (final d in _discussions) {
        final id = (d['id'] ?? '').toString();
        d['reply_count'] = replyCounts[id] ?? 0;
        d['like_count'] = likeCounts[id] ?? 0;
      }

      // Filter unanswered after counts
      if (selectedFilter == 'unanswered') {
        _discussions = _discussions.where((d) => (d['reply_count'] as int? ?? 0) == 0).toList();
      }
      // Sort trending by like_count
      if (selectedFilter == 'trending') {
        _discussions.sort((a, b) => ((b['like_count'] as int? ?? 0)).compareTo((a['like_count'] as int? ?? 0)));
      }

      // Batch load profiles for authors
      final userIds = _discussions.map((e) => e['user_id'] as String).toSet().toList();
      Map<String, Map<String, dynamic>> profiles = {};
      if (userIds.isNotEmpty) {
        final p = await supa
            .from('profiles')
            .select('user_id, full_name, avatar_url, tier')
            .inFilter('user_id', userIds);
        for (final e in (p as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final key = (m['user_id'] ?? '').toString();
          if (key.isNotEmpty) profiles[key] = m;
        }
      }
      _profilesById = profiles;

      // Batch load likes by me
      Set<String> liked = {};
      if (uid != null && ids.isNotEmpty) {
        final likes = await supa.from('post_likes').select('discussion_id').eq('user_id', uid).inFilter('discussion_id', ids);
        for (final e in (likes as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final dId = (m['discussion_id'] ?? '').toString();
          if (dId.isNotEmpty) liked.add(dId);
        }
      }
      _likedByMe = liked;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Discussions load error: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> d) async {
    final supa = Supabase.instance.client;
    final uid = supa.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to like posts.')));
      }
      return;
    }

    final id = d['id'] as String;
    final authorId = d['user_id'] as String?;
    final already = _likedByMe.contains(id);

    // Optimistic UI
    setState(() {
      if (already) {
        _likedByMe.remove(id);
        d['like_count'] = (d['like_count'] as int? ?? 0) - 1;
      } else {
        _likedByMe.add(id);
        d['like_count'] = (d['like_count'] as int? ?? 0) + 1;
      }
    });

    try {
      if (already) {
        await supa
            .from('post_likes')
            .delete()
            .eq('user_id', uid)
            .eq('discussion_id', id);
        // Do NOT subtract points on unlike per spec
      } else {
        await supa.from('post_likes').insert({
          'user_id': uid,
          'discussion_id': id,
        });
        if (authorId != null && authorId != uid) {
          // Award +2 to discussion author for like received
          unawaited(PointsService.awardPoints(authorId, 2, 'like_received', id));
        }
      }
    } catch (e) {
      debugPrint('Toggle like error: $e');
      // Revert on error
      setState(() {
        if (already) {
          _likedByMe.add(id);
          d['like_count'] = (d['like_count'] as int? ?? 0) + 1;
        } else {
          _likedByMe.remove(id);
          d['like_count'] = (d['like_count'] as int? ?? 0) - 1;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to update like.')));
      }
    }
  }

  // Points adjustments handled via PointsService.awardPoints; no direct delta method needed here

  void _onAskPressed() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CreateDiscussionSheet(categories: _categories, onCreated: () async {
        // Use go_router context.pop per project navigation rules
        if (mounted) context.pop();
        await _loadDiscussions();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onAskPressed,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        label: const Text('Ask Question'),
        icon: const Icon(Icons.add),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels + 200 >= n.metrics.maxScrollExtent && !_loadingMore && _hasMore) {
            _loadingMore = true;
            _loadDiscussions().whenComplete(() => setState(() => _loadingMore = false));
          }
          return false;
        },
        child: CustomScrollView(
        slivers: [
          // Sticky glass header
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white.withValues(alpha: 0.75),
            elevation: 0,
            expandedHeight: 64,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
                ),
              ),
            ),
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Community', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Row(children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text("${(_stats['online'] ?? _stats['online_count'] ?? 0)} members online", style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                ]),
              ],
            ),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.search, color: AppColors.foreground)),
              IconButton(onPressed: () => context.go('/notifications'), icon: const Icon(Icons.notifications_none, color: AppColors.foreground)),
              const SizedBox(width: 4),
            ],
          ),

          // SLIVER 2 — Search + Ask (sticky)
          SliverPersistentHeader(
            pinned: true,
            delegate: _SimpleHeaderDelegate(
              minHeight: 82,
              maxHeight: 82,
              child: Container(
                color: AppColors.background,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(hintText: 'Search discussions...'),
                        onSubmitted: (v) {
                          searchQuery = v.trim();
                          _loadDiscussions(reset: true);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _onAskPressed,
                        icon: const Icon(Icons.add),
                        label: const Text('Ask'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // SLIVER 2.5 — Community stats mini-cards
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                _MiniStat(icon: Icons.groups_2_outlined, label: 'Members', value: (_stats['members'] ?? _stats['members_count'] ?? 0).toString()),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.forum_outlined, label: 'Discussions', value: (_stats['discussions'] ?? _stats['discussions_count'] ?? 0).toString()),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.chat_bubble_outline, label: 'Replies', value: (_stats['replies'] ?? _stats['replies_count'] ?? 0).toString()),
              ]),
            ),
          ),

          // SLIVER 3 — Top contributors ribbon
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Top Contributors This Month', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemBuilder: (ctx, i) {
                      if (_topContributors.isEmpty) {
                        return const _ContributorSkeleton();
                      }
                      final u = _topContributors[i];
                      final name = (u['full_name'] ?? '').toString();
                      final avatar = (u['avatar_url'] ?? '').toString();
                      return _ContributorAvatar(index: i, name: name, avatarUrl: avatar, tier: (u['tier'] ?? '').toString());
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: _topContributors.isEmpty ? 8 : _topContributors.length,
                  ),
                ),
              ],
            ),
          ),

          // SLIVER 3 — Filter chips (sticky)
          SliverPersistentHeader(
            pinned: true,
            delegate: _SimpleHeaderDelegate(
              minHeight: 64,
              maxHeight: 64,
              child: Container(
                color: AppColors.background,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    const SizedBox(width: 4),
                    _buildFilterChip('All', 'all'),
                    _buildFilterChip('Unanswered', 'unanswered'),
                    _buildFilterChip('Trending', 'trending'),
                    _buildFilterChip('My Posts', 'mine'),
                    const VerticalDivider(width: 20, color: AppColors.border),
                    _buildCategoryChip('All', 'all'),
                    ..._categories.map((c) => _buildCategoryChip(c['name']?.toString() ?? 'Category', c['id']?.toString() ?? '')),                    
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),

          // SLIVER 4 — Discussion cards
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_discussions.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.forum_outlined, size: 40, color: AppColors.mutedForeground),
                    const SizedBox(height: 8),
                    Text('No discussions yet', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text('Be the first to ask a question!', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: _discussions.length,
              itemBuilder: (ctx, i) {
                final d = _discussions[i];
                final categoryName = (d['category'] ?? 'General').toString();
                final prof = _profilesById[d['user_id']] ?? const {};
                final liked = _likedByMe.contains(d['id']);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _DiscussionCard(
                    data: d,
                    categoryName: categoryName,
                    profile: prof,
                    liked: liked,
                    onLike: () => _toggleLike(d),
                  ),
                );
              },
            ),

          // Load more indicator
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    ),
  );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: GestureDetector(
        onTap: () {
          setState(() => selectedFilter = value);
          _loadDiscussions();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, String value) {
    final selected = selectedCategoryId == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: GestureDetector(
        onTap: () {
          setState(() => selectedCategoryId = value);
          _loadDiscussions();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    int members = (stats['members'] as int?) ?? (stats['members_count'] as int?) ?? 0;
    int discussions = (stats['discussions'] as int?) ?? (stats['discussions_count'] as int?) ?? 0;
    int replies = (stats['replies'] as int?) ?? (stats['replies_count'] as int?) ?? 0;
    return Row(
      children: [
        _stat('Members', members, Icons.groups_2_outlined),
        const SizedBox(width: 12),
        _stat('Discussions', discussions, Icons.forum_outlined),
        const SizedBox(width: 12),
        _stat('Replies', replies, Icons.chat_bubble_outline),
      ],
    );
  }

  Expanded _stat(String label, int value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(icon, color: Colors.white70, size: 14), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700))]),
              const SizedBox(height: 4),
              Text('$value', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );
}

class _DiscussionCard extends StatelessWidget {
  const _DiscussionCard({required this.data, required this.categoryName, required this.profile, required this.liked, required this.onLike});
  final Map<String, dynamic> data;
  final String categoryName;
  final Map<String, dynamic> profile;
  final bool liked;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final isPinned = (data['is_pinned'] == true);
    final isTrending = (data['is_trending'] == true);
    final hasBestAnswer = data['best_answer_id'] != null;
    final likeCount = (data['like_count'] as int?) ?? 0;
    final replyCount = (data['reply_count'] as int?) ?? 0;
    final createdAt = DateTime.tryParse(data['created_at']?.toString() ?? '');
    final timeText = createdAt != null ? _timeAgo(createdAt) : '';
    final imageUrl = (data['image_url'] ?? '').toString();
    final fullName = (profile['full_name'] ?? 'Member').toString();
    final avatarUrl = (profile['avatar_url'] ?? '').toString();

    return GestureDetector(
      onTap: () => context.push('/discussion/${data['id']}'),
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPinned)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.accent, width: 3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.push_pin, color: AppColors.accent.withValues(alpha: 0.9), size: 16),
                const SizedBox(width: 6),
                Text('Pinned by Admin', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.accent)),
              ]),
            ),
          if (isPinned) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarInitials(name: fullName, avatarUrl: avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(fullName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        Text(timeText, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(data['title']?.toString() ?? '',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      data['body']?.toString() ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.foreground),
                    ),
                  ],
                ),
              )
            ],
          ),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(imageUrl, fit: BoxFit.cover),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(categoryName, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.foreground)),
              ),
              const SizedBox(width: 12),
              if (hasBestAnswer)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: AppColors.primary.withValues(alpha: 0.25))),
                  child: Row(children: [const Icon(Icons.verified, size: 14, color: AppColors.primary), const SizedBox(width: 4), Text('Answered', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary))]),
                ),
              if (hasBestAnswer) const SizedBox(width: 8),
              if (isTrending)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: AppColors.accent.withValues(alpha: 0.25))),
                  child: Row(children: [const Icon(Icons.trending_up, size: 14, color: AppColors.accent), const SizedBox(width: 4), Text('Trending', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.accent))]),
                ),
              const Spacer(),
              const Icon(Icons.forum_outlined, size: 16, color: AppColors.mutedForeground),
              const SizedBox(width: 4),
              Text('$replyCount', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onLike,
                child: Row(
                  children: [
                    Icon(liked ? Icons.favorite : Icons.favorite_border, size: 16, color: liked ? AppColors.destructive : AppColors.mutedForeground),
                    const SizedBox(width: 4),
                    Text('$likeCount', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.remove_red_eye_outlined, size: 16, color: AppColors.mutedForeground),
              const SizedBox(width: 4),
              Text('${data['views'] ?? 0}', style: Theme.of(context).textTheme.bodySmall),
            ],
          )
        ],
      ),
    ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: [
          BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 8)),
        ]),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.mutedForeground),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
          ])),
        ]),
      ),
    );
  }
}

class _ContributorAvatar extends StatelessWidget {
  const _ContributorAvatar({required this.index, required this.name, required this.avatarUrl, required this.tier});
  final int index;
  final String name;
  final String avatarUrl;
  final String tier;
  @override
  Widget build(BuildContext context) {
    Color ring;
    if (index == 0) {
      ring = const Color(0xFFFFC94A); // gold
    } else if (index == 1) {
      ring = const Color(0xFFCBD5E1); // silver
    } else if (index == 2) {
      ring = const Color(0xFFB45309); // bronze
    } else {
      ring = AppColors.border;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
            child: ClipOval(child: avatarUrl.isNotEmpty ? Image.network(avatarUrl, fit: BoxFit.cover) : _AvatarInitials(name: name, avatarUrl: '')),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.border)),
              child: Text(tier.isEmpty ? '—' : tier, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        SizedBox(width: 72, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall)),
      ],
    );
  }
}

class _ContributorSkeleton extends StatelessWidget {
  const _ContributorSkeleton();
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.background, shape: BoxShape.circle, border: Border.all(color: AppColors.border))),
        const SizedBox(height: 6),
        Container(width: 56, height: 10, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4))),
      ]);
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.name, required this.avatarUrl});
  final String name;
  final String avatarUrl;
  @override
  Widget build(BuildContext context) {
    if (avatarUrl.isNotEmpty) {
      return CircleAvatar(radius: 20, backgroundImage: NetworkImage(avatarUrl));
    }
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r"\s+"))
            .take(2)
            .map((s) => s.isNotEmpty ? s[0].toUpperCase() : '')
            .join();
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
      child: Text(initials, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
    );
  }
}

class _SimpleHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SimpleHeaderDelegate({required this.minHeight, required this.maxHeight, required this.child});
  final double minHeight;
  final double maxHeight;
  final Widget child;
  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  bool shouldRebuild(covariant _SimpleHeaderDelegate oldDelegate) =>
      minHeight != oldDelegate.minHeight || maxHeight != oldDelegate.maxHeight || child != oldDelegate.child;
}

class _CreateDiscussionSheet extends StatefulWidget {
  const _CreateDiscussionSheet({required this.categories, required this.onCreated});
  final List<Map<String, dynamic>> categories;
  final VoidCallback onCreated;

  @override
  State<_CreateDiscussionSheet> createState() => _CreateDiscussionSheetState();
}

class _CreateDiscussionSheetState extends State<_CreateDiscussionSheet> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) _categoryId = widget.categories.first['id']?.toString();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete all fields.')));
      return;
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in first.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final cat = widget.categories.firstWhere((c) => c['id']?.toString() == _categoryId, orElse: () => const {'name': ''});
      final categoryName = (cat['name'] ?? '').toString();
      final inserted = await Supabase.instance.client
          .from('discussions')
          .insert({
            'title': title,
            'body': content,
            'category': categoryName,
            'user_id': uid,
          })
          .select('id')
          .maybeSingle();
      final discussionId = (inserted?['id'] as String?) ?? '';
      // Award +10 for posting discussion
      if (discussionId.isNotEmpty) {
        unawaited(PointsService.awardPoints(uid, 10, 'post_discussion', discussionId));
      }
      widget.onCreated();
    } catch (e) {
      debugPrint('Create discussion error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create discussion: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Ask a Question', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _categoryId,
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c['id']?.toString(), child: Text(c['name']?.toString() ?? 'Category')))
                  .toList(),
              onChanged: (v) => setState(() => _categoryId = v),
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Post Question'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
