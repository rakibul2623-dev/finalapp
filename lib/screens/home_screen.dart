import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/supabase/supabase_config.dart';
import '../theme.dart';
import '../state/app_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  bool _compactHeader = false;
  bool _notifWiggle = false;

  Map<String, dynamic>? _profile; // full_name, avatar_url, tier, points_total
  Map<String, dynamic>? _wallet; // balance, goal_amount
  int _unread = 0;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _packages = [];
  // USD currency formatter per product spec
  final NumberFormat _usdCurrency = NumberFormat.currency(locale: 'en_US', symbol: r'$');
  List<Map<String, dynamic>> _trending = [];
  List<Map<String, dynamic>> _leaderboard = [];

  bool _loading = true;
  String? _error;
  RealtimeChannel? _walletChannel;
  RealtimeChannel? _notifChannel;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = SupabaseConfig.auth.currentUser;
      if (user == null && mounted) {
        context.go('/login');
        return;
      }
      _fetchAll();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _walletChannel?.unsubscribe();
    _notifChannel?.unsubscribe();
    super.dispose();
  }

  void _onScroll() {
    final compact = _scrollController.offset > 12;
    if (compact != _compactHeader) setState(() => _compactHeader = compact);
  }

  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;

      final futures = <Future>[];

      if (user != null) {
        futures.add(client.from('profiles').select('full_name, avatar_url, tier, points_total').eq('user_id', user.id).maybeSingle().then((v) => _profile = v as Map<String, dynamic>?));
        futures.add(client.from('wallets').select('balance, goal_amount').eq('user_id', user.id).maybeSingle().then((v) => _wallet = v as Map<String, dynamic>?));
        futures.add(() async {
          try {
            final rows = await client
                .from('notifications')
                .select('id')
                .eq('user_id', user.id)
                .eq('is_read', false);
            final c = (rows as List).length;
            if (c > _unread) _triggerBellWiggle();
            _unread = c;
            if (mounted) context.read<AppState>().setUnreadNotifCount(c);
          } catch (e) {
            debugPrint('Unread count fetch failed: $e');
          }
        }());
      }

      futures.add(client.from('products').select('id, name, price, image_url, slug').order('created_at', ascending: false).limit(6).then((v) => _products = List<Map<String, dynamic>>.from(v as List)));
      // Featured packages: strict fields + features; price asc, limit 4
      futures.add(client
          .from('packages')
          .select('id, name, price, duration, image_url, package_features(feature, sort_order)')
          .order('price', ascending: true)
          .limit(4)
          .then((v) => _packages = List<Map<String, dynamic>>.from(v as List)));

      // Trending in community: fetch latest 3 discussions with replies count, then hydrate profiles
      futures.add(() async {
        final disc = await client
            .from('discussions')
            .select('id, title, user_id, created_at, replies(count)')
            .order('created_at', ascending: false)
            .limit(3);
        final list = List<Map<String, dynamic>>.from(disc as List);
        final ids = list.map((e) => (e['user_id'] ?? '').toString()).where((id) => id.isNotEmpty).toSet().toList();
        Map<String, Map<String, dynamic>> profiles = {};
        if (ids.isNotEmpty) {
          final pr = await client
              .from('profiles')
              .select('user_id, full_name, avatar_url, tier')
              .inFilter('user_id', ids);
          for (final p in (pr as List)) {
            final m = Map<String, dynamic>.from(p as Map);
            profiles[m['user_id'].toString()] = m;
          }
        }
        // combine
        _trending = list
            .map((d) => {
                  ...d,
                  'profile': profiles[(d['user_id'] ?? '').toString()] ?? {}
                })
            .toList();
      }());

      futures.add(client.from('profiles').select('full_name, avatar_url, points_total, tier').order('points_total', ascending: false).limit(5).then((v) => _leaderboard = List<Map<String, dynamic>>.from(v as List)));

      await Future.wait(futures);

      _walletChannel?.unsubscribe();
      _notifChannel?.unsubscribe();
      if (client.auth.currentUser != null) {
        _walletChannel = client
            .channel('realtime:wallets-user-${client.auth.currentUser!.id}')
            .onPostgresChanges(
                event: PostgresChangeEvent.update,
                schema: 'public',
                table: 'wallets',
                filter: PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'user_id',
                    value: client.auth.currentUser!.id),
                callback: (payload) {
          final rec = payload.newRecord;
          if (rec != null && rec['balance'] != null) {
            setState(() => _wallet = {
                  'balance': rec['balance'],
                  'goal_amount': rec['goal_amount'] ?? _wallet?['goal_amount']
                });
          }
        })
            .subscribe();

        // Realtime inserts for notifications → increment unread + wiggle
        _notifChannel = client
            .channel('realtime:notifs-user-${client.auth.currentUser!.id}')
            .onPostgresChanges(
                event: PostgresChangeEvent.insert,
                schema: 'public',
                table: 'notifications',
                filter: PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'user_id',
                    value: client.auth.currentUser!.id),
                callback: (payload) {
                  setState(() {
                    _unread += 1;
                    _notifWiggle = true;
                  });
                  if (mounted) {
                    final app = context.read<AppState>();
                    app.setUnreadNotifCount(app.unreadNotifCount + 1);
                  }
                  Future.delayed(const Duration(milliseconds: 900), () {
                    if (mounted) setState(() => _notifWiggle = false);
                  });
                })
            .subscribe();
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('Home fetch error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _triggerBellWiggle() {
    setState(() => _notifWiggle = true);
    Future.delayed(const Duration(milliseconds: 900),
        () => mounted ? setState(() => _notifWiggle = false) : null);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isGuest = (SupabaseConfig.auth.currentUser == null);
    final firstName = _profile?['full_name']
            ?.toString()
            .split(' ')
            .first ??
        appState.currentUserProfile?['name']?.toString().split(' ').first ??
        'Guest';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchAll,
        color: AppColors.primary,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: false,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              expandedHeight: 72,
              flexibleSpace: LayoutBuilder(builder: (context, c) {
                return ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                        sigmaX: _compactHeader ? 10 : 0,
                        sigmaY: _compactHeader ? 10 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: _compactHeader
                            ? Colors.white.withValues(alpha: 0.75)
                            : Colors.transparent,
                        border: _compactHeader
                            ? const Border(
                                bottom:
                                    BorderSide(color: AppColors.border))
                            : null,
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _PressOpacity(
                              onTap: () => context.go('/account'),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                Builder(builder: (context) {
                                  final avatarUrl = (_profile?['avatar_url'] ??
                                          appState.currentUserProfile?['avatar_url'])
                                      ?.toString() ?? '';
                                  final fullName = (_profile?['full_name'] ??
                                          appState.currentUserProfile?['name'])
                                      ?.toString() ?? '';
                                  final initial = (fullName.isNotEmpty
                                          ? fullName.trim()[0]
                                          : 'G')
                                      .toUpperCase();
                                  if (avatarUrl.isNotEmpty) {
                                    return CircleAvatar(
                                      radius: 24, // 48x48
                                      backgroundImage: NetworkImage(avatarUrl),
                                    );
                                  }
                                  return CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AppColors.primary,
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 20),
                                    ),
                                  );
                                }),
                                const SizedBox(width: 12),
                                Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Assalamu alaikum,',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                  color: const Color(0xFF6B7280),
                                                  fontSize: 13,
                                                  height: 16 / 13,
                                                  fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 2),
                                      Text(
                                        firstName.toLowerCase(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                                color: const Color(0xFF111827),
                                                fontSize: 22,
                                                height: 26 / 22,
                                                letterSpacing: -0.3,
                                                fontWeight: FontWeight.w800),
                                      ),
                                    ])
                              ]),
                            ),
                            _BellBadge(
                                unread: _unread,
                                wiggle: _notifWiggle,
                                onTap: () => context.go('/notifications')),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),

            SliverToBoxAdapter(
                child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: isGuest
                        ? _GuestHero(onSignup: () => context.go('/signup'))
                        : _WalletHero(
                            wallet: _wallet,
                            tier: _profile?['tier'] ?? appState.currentTier,
                            currency: _usdCurrency))),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _TierProgressStrip(profile: _profile),
              ),
            ),

            SliverToBoxAdapter(
              child: SectionHeader(
                  title: 'Exclusive Shop',
                  actionLabel: 'View All →',
                  onAction: () => context.go('/store')),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                  height: 270,
                  child: _loading
                      ? _ShopSkeleton()
                      : _ShopCarousel(
                           products: _products, currency: _usdCurrency)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            SliverToBoxAdapter(
                child: SectionHeader(
                    title: 'Featured Packages',
                    actionLabel: 'View All',
                    onAction: () => context.go('/packages'))),
            SliverToBoxAdapter(
                child: SizedBox(
                    height: 230,
                    child: _loading
                        ? _PackagesSkeleton()
                        : _PackagesCarousel(
                             packages: _packages, currency: _usdCurrency))),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            SliverToBoxAdapter(child: SectionHeader(title: 'Trending in Community')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _loading
                    ? const ShimmerBox(height: 110)
                    : (_trending.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.forum_outlined, color: AppColors.mutedForeground),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('No discussions yet', style: Theme.of(context).textTheme.titleLarge),
                                      const SizedBox(height: 4),
                                      Text('Be the first to start a conversation', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
                                    ],
                                  ),
                                ),
                                TextButton(onPressed: () => context.go('/community'), child: const Text('Open Community →'))
                              ],
                            ),
                          )
                        : Column(
                            children: _trending
                                .map((d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _CommunityCard(discussion: d),
                                    ))
                                .toList(),
                          )),
              ),
            ),

            SliverToBoxAdapter(
                child: SectionHeader(title: "This Month's Top Savers")),
            SliverList.builder(
              itemCount: _loading ? 3 : _leaderboard.length,
              itemBuilder: (context, i) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: _loading
                    ? const ShimmerBox(height: 64)
                    : _LeaderboardRow(index: i, user: _leaderboard[i]),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

class _BellBadge extends StatefulWidget {
  final int unread;
  final bool wiggle;
  final VoidCallback onTap;
  const _BellBadge(
      {required this.unread, required this.wiggle, required this.onTap});
  @override
  State<_BellBadge> createState() => _BellBadgeState();
}

class _BellBadgeState extends State<_BellBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<double> _wiggle = TweenSequence([
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.12)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25),
    TweenSequenceItem(
        tween: Tween(begin: 0.12, end: -0.12)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50),
    TweenSequenceItem(
        tween: Tween(begin: -0.12, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25),
  ]).animate(_ac);

  @override
  void didUpdateWidget(covariant _BellBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wiggle && !_ac.isAnimating) _ac.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onTap,
        child: Stack(children: [
          RotationTransition(
            turns: _wiggle,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 6))
                  ]),
              child: const Icon(Icons.notifications_none_rounded,
                  color: AppColors.foreground),
            ),
          ),
          if (widget.unread > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: const BoxDecoration(
                    color: AppColors.destructive,
                    borderRadius: BorderRadius.all(Radius.circular(10))),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                    widget.unread > 99 ? '99+' : '${widget.unread}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      );
}

class _GuestHero extends StatelessWidget {
  final VoidCallback onSignup;
  const _GuestHero({required this.onSignup});
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryGlow]),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Start Your Journey',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
            'Create an account to begin saving for Hajj with goals, automation, and rewards.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: _ScaleTap(
              onTap: onSignup,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 14,
                          offset: const Offset(0, 8))
                    ]),
                alignment: Alignment.center,
                child: Text('Sign Up',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5)),
                child: Text('Learn More',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700))),
          )
        ])
      ]),
    );
  }
}

class _WalletHero extends StatefulWidget {
  final Map<String, dynamic>? wallet;
  final String tier;
  final NumberFormat currency;
  const _WalletHero(
      {required this.wallet, required this.tier, required this.currency});
  @override
  State<_WalletHero> createState() => _WalletHeroState();
}

class _WalletHeroState extends State<_WalletHero>
    with SingleTickerProviderStateMixin {
  double _displayBalance = 0;
  @override
  void didUpdateWidget(covariant _WalletHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animateToTarget();
  }

  @override
  void initState() {
    super.initState();
    _animateToTarget();
  }

  void _animateToTarget() {
    final target = (widget.wallet?['balance'] as num?)?.toDouble() ?? 0;
    final controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    final animation = Tween<double>(begin: 0, end: target)
        .animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    animation.addListener(() => setState(() => _displayBalance = animation.value));
    controller.forward();
    controller.addStatusListener((s) {
      if (s == AnimationStatus.completed) controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final goal = (widget.wallet?['goal_amount'] as num?)?.toDouble() ?? 10000.0;
    final pct = goal == 0 ? 0.0 : ((_displayBalance) / goal).clamp(0.0, 1.0);
    return _GlassCard(
      gradient: const LinearGradient(
          begin: Alignment(0.1, -1),
          end: Alignment(1, 0.2),
          colors: [AppColors.primary, AppColors.primaryGlow]),
      padding: const EdgeInsets.all(20),
      radius: 28,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total Hajj Savings',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          _TierPill(tier: widget.tier)
        ]),
        const SizedBox(height: 8),
        Text(widget.currency.format(_displayBalance),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              minHeight: 6,
              value: pct,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              color: Colors.white),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
              '${(pct * 100).toStringAsFixed(0)}% of ${
                  widget.currency.format(goal)} goal',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85))),
          Text('Target: 2026',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.white)),
        ]),
        const SizedBox(height: 16),
        _ScaleTap(
          onTap: () => context.go('/wallet'),
            child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Text('Deposit',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
        )
      ]),
    );
  }
}

// quick actions and stat tiles removed per product spec

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader(
      {super.key, required this.title, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (actionLabel != null)
            GestureDetector(
                onTap: onAction,
                child: Text(actionLabel!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)))
        ]),
      );
}

class _ShopCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final NumberFormat currency;
  const _ShopCarousel({required this.products, required this.currency});
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.only(left: 20, right: 20),
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = products[i];
          return SizedBox(
            width: MediaQuery.of(context).size.width * 0.7,
            child: _ScaleTap(
              onTap: () => context.go('/product/${p['id']}'),
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF145032)
                              .withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                          borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20)),
                          child: _SmartImage(
                              url: (p['image_url'] ?? '').toString(),
                              height: 180)),
                      Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text((p['name'] ?? '').toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 6),
                                      Text(
                                          currency
                                              .format((p['price'] ?? 0) as num),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                  color: AppColors.primary,
                                                  fontWeight:
                                                      FontWeight.w800))
                                    ])),
                                Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        shape: BoxShape.circle),
                                    child: const Icon(
                                        Icons.add_shopping_cart_rounded,
                                        color: AppColors.primary))
                              ]))
                    ]),
              ),
            ),
          );
        },
      );
}

class _PackagesCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> packages;
  final NumberFormat currency;
  const _PackagesCarousel({required this.packages, required this.currency});
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.only(left: 20, right: 20),
        scrollDirection: Axis.horizontal,
        itemCount: packages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = packages[i];
          return SizedBox(
            width: 280,
            child: _ScaleTap(
              onTap: () => context.go('/packages'),
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF145032)
                              .withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24)),
                    child: _PackageImageOrPlaceholder(
                      imageUrl: (p['image_url'] ?? '').toString(),
                      title: (p['name'] ?? '').toString(),
                      height: 140,
                    ),
                  ),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((p['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge),
                            const SizedBox(height: 6),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      currency.format(
                                          (p['price'] ?? 0) as num),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w800)),
                                   Container(
                                       height: 40,
                                       padding: const EdgeInsets.symmetric(
                                           horizontal: 16),
                                       alignment: Alignment.center,
                                       decoration: BoxDecoration(
                                           color: AppColors.primary,
                                           borderRadius: BorderRadius.circular(
                                               AppRadius.pill)),
                                       child: Text('View Details →',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                  color: Colors.white)))
                                ])
                          ]))
                ]),
              ),
            ),
          );
        },
      );
}

class _CommunityCard extends StatelessWidget {
  final Map<String, dynamic>? discussion;
  const _CommunityCard({required this.discussion});
  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
  int _replyCount(dynamic replies) {
    try {
      if (replies is List && replies.isNotEmpty) {
        final first = replies.first as Map;
        final c = first['count'];
        if (c is int) return c;
        if (c is num) return c.toInt();
      }
    } catch (_) {}
    return 0;
  }
  @override
  Widget build(BuildContext context) {
    if (discussion == null) return const SizedBox.shrink();
    final prof = Map<String, dynamic>.from(discussion!['profile'] ?? {});
    final replies = _replyCount(discussion!['replies']);
    final createdAt = (discussion!['created_at'] ?? '').toString();
    return _ScaleTap(
      onTap: () => context.go('/community'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF145032).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.border,
              backgroundImage: (prof['avatar_url']?.toString().isNotEmpty ?? false)
                  ? NetworkImage(prof['avatar_url'])
                  : null,
              child: (prof['avatar_url']?.toString().isEmpty ?? true)
                  ? const Icon(Icons.person_outline, color: AppColors.mutedForeground)
                  : null),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((discussion!['title'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(
                  '${prof['full_name']?.toString() ?? 'Member'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Text('• $replies replies · ${_timeAgo(createdAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground))
            ])
          ]))
        ]),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> user;
  const _LeaderboardRow({required this.index, required this.user});
  @override
  Widget build(BuildContext context) {
    final colors = [AppColors.accent, AppColors.silverTier, const Color(0xFFCD7F32)];
    return _ScaleTap(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(
              width: 28,
              height: 28,
              decoration:
                  BoxDecoration(color: colors[index], shape: BoxShape.circle)),
          const SizedBox(width: 12),
          CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.border,
              backgroundImage:
                  (user['avatar_url']?.toString().isNotEmpty ?? false)
                      ? NetworkImage(user['avatar_url'])
                      : null,
              child: (user['avatar_url']?.toString().isEmpty ?? true)
                  ? const Icon(Icons.person_outline,
                      color: AppColors.mutedForeground)
                  : null),
          const SizedBox(width: 12),
          Expanded(
              child: Text((user['full_name'] ?? '').toString(),
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700))),
          Text(((user['points_total'] ?? 0)).toString(),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800))
        ]),
      ),
    );
  }
}

class _ShopSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.only(left: 16, right: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, __) => const ShimmerBox(width: 280, height: 240, radius: 20),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: 3,
      );
}

class _PackagesSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.only(left: 16, right: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, __) => const ShimmerBox(width: 260, height: 210, radius: 20),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: 3,
      );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final LinearGradient gradient;
  final double radius;
  const _GlassCard(
      {required this.child,
      required this.padding,
      required this.gradient,
      this.radius = 24});
  @override
  Widget build(BuildContext context) => _ScaleTap(
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: gradient,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF145032).withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 14))
              ]),
          child: Stack(children: [
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02)))),
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0),
                  child: Container(padding: padding)),
            ),
            Padding(padding: padding, child: child),
          ]),
        ),
      );
}

class _GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool outlined;
  const _GlassButton._(
      {required this.label, required this.onTap, required this.outlined});
  factory _GlassButton.filled(
          {required String label, required VoidCallback onTap}) =>
      _GlassButton._(label: label, onTap: onTap, outlined: false);
  factory _GlassButton.outlined(
          {required String label, required VoidCallback onTap}) =>
      _GlassButton._(label: label, onTap: onTap, outlined: true);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: outlined ? Border.all(color: Colors.white, width: 1.2) : null,
          boxShadow: outlined
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 6))
                ],
        ),
        child: Text(label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: outlined ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _TierProgressStrip extends StatelessWidget {
  final Map<String, dynamic>? profile;
  const _TierProgressStrip({required this.profile});
  @override
  Widget build(BuildContext context) {
    final points = ((profile?['points_total'] as num?) ?? 0).toDouble();
    String tier;
    double target;
    String nextLabel;
    if (points < 500) {
      tier = 'Silver';
      target = 500;
      nextLabel = 'to Gold';
    } else if (points < 2000) {
      tier = 'Gold';
      target = 2000;
      nextLabel = 'to Platinum';
    } else {
      tier = 'Platinum';
      target = points <= 0 ? 1 : points; // avoid div by zero
      nextLabel = 'Max tier achieved';
    }
    final pct = (tier == 'Platinum') ? 1.0 : (points / target).clamp(0.0, 1.0);

    return _ScaleTap(
      onTap: () => context.go('/account'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: const Border.fromBorderSide(BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _TierPill(tier: tier),
            const SizedBox(width: 8),
            Text('${points.toStringAsFixed(0)} points', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
            const Spacer(),
            Text(
              tier == 'Platinum'
                  ? nextLabel
                  : '${(target - points).clamp(0, target).toStringAsFixed(0)} points $nextLabel',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: pct,
              backgroundColor: AppColors.inputBackground,
              color: AppColors.primary,
            ),
          ),
        ]),
      ),
    );
  }
}

class _TierPill extends StatelessWidget {
  final String tier;
  const _TierPill({required this.tier});
  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tier.toLowerCase()) {
      case 'gold':
        bg = AppColors.tierGoldBg;
        fg = AppColors.tierGoldText;
        break;
      case 'platinum':
        bg = AppColors.tierPlatinumBg;
        fg = AppColors.tierPlatinumText;
        break;
      default:
        bg = AppColors.tierSilverBg;
        fg = AppColors.tierSilverText;
        break;
    }
    return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, color: AppColors.accent, size: 16),
          const SizedBox(width: 4),
          Text(tier, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg))
        ]));
  }
}

class _SmartImage extends StatelessWidget {
  final String url;
  final double height;
  const _SmartImage({required this.url, required this.height});
  @override
  Widget build(BuildContext context) {
    if (url.startsWith('http')) {
      return Image.network(url,
          height: height, width: double.infinity, fit: BoxFit.cover);
    }
    return Image.asset(
        url.isNotEmpty
            ? url
            : 'assets/images/mosque_transparent_1777185327186.jpg',
        height: height,
        width: double.infinity,
        fit: BoxFit.cover);
  }
}

/// Renders network image when available; otherwise a green gradient placeholder
/// with the package name centered. Used by Featured Packages on Home.
class _PackageImageOrPlaceholder extends StatelessWidget {
  final String imageUrl;
  final String title;
  final double height;
  const _PackageImageOrPlaceholder({required this.imageUrl, required this.title, required this.height});
  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
      return Image.network(imageUrl, height: height, width: double.infinity, fit: BoxFit.cover);
    }
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryGlow],
        ),
      ),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _ScaleTap({required this.child, this.onTap});
  @override
  State<_ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<_ScaleTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.06);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) async {
          await Future.delayed(const Duration(milliseconds: 40));
          _c.reverse();
          widget.onTap?.call();
        },
        onTapCancel: () => _c.reverse(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final s = 1 - _c.value;
            return Transform.scale(scale: s, child: child);
          },
          child: widget.child,
        ),
      );
}

/// Simple press-feedback wrapper that fades the child to 0.7 opacity on press
class _PressOpacity extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _PressOpacity({required this.child, this.onTap});
  @override
  State<_PressOpacity> createState() => _PressOpacityState();
}

class _PressOpacityState extends State<_PressOpacity>
    with SingleTickerProviderStateMixin {
  double _opacity = 1.0;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _opacity = 0.7),
        onTapUp: (_) {
          setState(() => _opacity = 1.0);
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _opacity = 1.0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          opacity: _opacity,
          child: widget.child,
        ),
      );
}

class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const ShimmerBox({super.key, this.width, required this.height, this.radius = 16});
  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
                begin: Alignment(-1 + _c.value * 2, 0),
                end: Alignment(0 + _c.value * 2, 0),
                colors: [
                  AppColors.inputBackground,
                  Colors.white,
                  AppColors.inputBackground
                ],
                stops: const [0.25, 0.5, 0.75])),
      ),
    );
  }
}
