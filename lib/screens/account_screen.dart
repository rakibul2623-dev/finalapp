import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/components/subscription_gate.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:flutter/services.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with SingleTickerProviderStateMixin {
  late Future<void> _loadFuture;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _wallet;
  int _ordersCount = 0;
  int _bookingsCount = 0;
  int _wishlistCount = 0;

  // Profile form controllers
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadAll();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('user_id', uid)
          .maybeSingle();

      final wallet = await Supabase.instance.client
          .from('wallets')
          .select()
          .eq('user_id', uid)
          .maybeSingle();

      final orders = await Supabase.instance.client
          .from('orders')
          .select('id')
          .eq('user_id', uid);

      final bookings = await Supabase.instance.client
          .from('bookings')
          .select('id')
          .eq('user_id', uid);

      final wish = await Supabase.instance.client
          .from('wishlists')
          .select('id')
          .eq('user_id', uid);

      setState(() {
        _profile = profile ?? {};
        _wallet = wallet ?? {};
        _ordersCount = (orders as List).length;
        _bookingsCount = (bookings as List).length;
        _wishlistCount = (wish as List).length;

        _nameCtrl.text = (_profile?['full_name'] ?? '').toString();
        _phoneCtrl.text = (_profile?['phone'] ?? '').toString();
        _goalCtrl.text = ((_wallet?['goal_amount'] ?? '')).toString();
      });
    } catch (e) {
      debugPrint('Account load error: $e');
    }
  }

  Future<void> _saveProfile() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final goal = double.tryParse(_goalCtrl.text.trim()) ?? 0.0;

      await Supabase.instance.client
          .from('profiles')
          .update({'full_name': name, 'phone': phone})
          .eq('user_id', uid);

      await Supabase.instance.client
          .from('wallets')
          .update({'goal_amount': goal})
          .eq('user_id', uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
        await _loadAll();
      }
    } catch (e) {
      debugPrint('Save profile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save profile')));
      }
    }
  }

  Future<void> _cancelSubscription() async {
    try {
      setState(() {});
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken ?? '';
      final res = await Supabase.instance.client.functions.invoke('paypal-subscription',
          body: {
            'action': 'cancel-subscription',
          },
          headers: {
            'Authorization': 'Bearer $token',
          });
      debugPrint('Cancel subscription: ${res.data}');
      // update local state
      if (mounted) {
        context.read<AppState>().setSubscriptionActive(false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription cancelled')));
      }
    } catch (e) {
      debugPrint('Cancel subscription error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to cancel')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubscriptionGate(
      child: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          return DefaultTabController(
            length: 8,
            child: Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                title: const Text('My Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(0),
                  child: const SizedBox(height: 0),
                ),
              ),
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildProfileHeader(context, loading: loading),
                  ),
                  SliverToBoxAdapter(child: const SizedBox(height: 12)),
                  SliverToBoxAdapter(child: _buildQuickStats(context, loading: loading)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabsHeaderDelegate(
                      TabBar(
                        isScrollable: true,
                        labelColor: AppColors.primary,
                        unselectedLabelColor: AppColors.mutedForeground,
                        indicatorColor: AppColors.primary,
                        tabs: const [
                          Tab(text: 'Profile'),
                          Tab(text: 'Tier'),
                          Tab(text: 'Membership'),
                          Tab(text: 'Orders'),
                          Tab(text: 'Bookings'),
                          Tab(text: 'Referrals'),
                          Tab(text: 'Security'),
                          Tab(text: 'Settings'),
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: true,
                    child: TabBarView(
                      children: [
                        _buildProfileTab(context),
                        _buildTierTab(context),
                        _buildMembershipTab(context),
                        _buildOrdersTab(context),
                        _buildBookingsTab(context),
                        _buildReferralsTab(context),
                        _buildSecurityTab(context),
                        _buildSettingsTab(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, {required bool loading}) {
    final points = context.watch<AppState>().totalPoints;
    final tier = context.watch<AppState>().currentTier;
    final fullName = (_profile?['full_name'] ?? 'Your Name').toString();
    final email = (_profile?['email'] ?? '').toString();
    final avatarUrl = (_profile?['avatar_url'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.darkTeal],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 38,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            fullName.isNotEmpty ? fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join() : 'U',
                            style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () async {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avatar upload coming soon')));
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Icon(Icons.camera_alt_rounded, size: 18, color: AppColors.primary),
                        ),
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(email, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(children: [
                      _TierBadge(tier: tier),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                        child: Text('$points pts', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tier Progress', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
               child: LinearProgressIndicator(
                  value: (((_profile?['points_total'] ?? 0) as num).toDouble() / 500.0).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Current: $tier', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                Text('Next: Gold', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context, {required bool loading}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 1)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickStat(title: 'Orders', value: _ordersCount, icon: Icons.shopping_bag_outlined, onTap: () {}),
          _DividerV(),
          _QuickStat(title: 'Bookings', value: _bookingsCount, icon: Icons.event_seat_outlined, onTap: () {}),
          _DividerV(),
          _QuickStat(title: 'Wishlist', value: _wishlistCount, icon: Icons.favorite_border, onTap: () { context.go('/wishlist'); }),
        ],
      ),
    );
  }

  Widget _buildProfileTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Profile', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
        const SizedBox(height: 12),
        TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
        const SizedBox(height: 12),
        // Bio removed (not in schema)
        TextField(controller: _goalCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Hajj Goal Amount')),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveProfile, child: const Text('Save Changes'))),
      ]),
    );
  }

  Widget _buildTierTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tier', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.darkTeal]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your Tier', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            _TierBadge(tier: context.watch<AppState>().currentTier),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final pts = ((_profile?['points_total'] ?? 0) as num).toInt();
              final t = (_profile?['tier'] ?? 'Silver').toString();
              double progress;
              String nextLabel;
              if (t == 'Silver') {
                progress = (pts / 500).clamp(0.0, 1.0);
                nextLabel = 'Gold';
              } else if (t == 'Gold') {
                progress = ((pts - 500) / 1000).clamp(0.0, 1.0);
                nextLabel = 'Platinum';
              } else {
                progress = 1.0;
                nextLabel = 'Max';
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Current: ' + t, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                  Text('Next: ' + nextLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                ])
              ]);
            }),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Points History', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Recent points activities will appear here.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _buildMembershipTab(BuildContext context) {
    final active = context.watch<AppState>().subscriptionActive;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Membership', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(active ? 'ACTIVE' : 'INACTIVE', style: TextStyle(color: active ? AppColors.primary : AppColors.destructive, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('Next billing: —', style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: active ? _cancelSubscription : null,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.destructive, side: const BorderSide(color: AppColors.destructive)),
                child: const Text('Cancel Subscription'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildOrdersTab(BuildContext context) {
    return Center(child: Text('Orders list coming soon', style: Theme.of(context).textTheme.bodySmall));
  }

  Widget _buildBookingsTab(BuildContext context) {
    return Center(child: Text('Bookings list coming soon', style: Theme.of(context).textTheme.bodySmall));
  }

  Widget _buildReferralsTab(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final code = uid.isNotEmpty ? uid.substring(0, 6).toUpperCase() : '— — —';
    final link = 'https://hajjwallet.app/ref/$code';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Referrals', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 1)),
          child: Row(children: [
            Expanded(child: Text('Your code: $code', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral code copied')));
                }
              },
            )
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral link copied')));
              }
            },
            child: const Text('Share Referral Link'),
          ),
        ),
      ]),
    );
  }

  Widget _buildSecurityTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Security', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () {}, child: const Text('Change Password'))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () {}, child: const Text('Sign Out All Devices'))),
      ]),
    );
  }

  Widget _buildSettingsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Push Notifications'),
          value: true,
          onChanged: (_) {},
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Email Notifications'),
          value: true,
          onChanged: (_) {},
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                context.read<AppState>().logout();
                if (context.mounted) context.go('/login');
              }
            },
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.destructive, side: const BorderSide(color: AppColors.destructive)),
            child: const Text('Sign Out'),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text('Delete Account → contact support', style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TabsHeaderDelegate(this.tabBar);
  final TabBar tabBar;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppColors.surface, child: tabBar);
  }
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(covariant _TabsHeaderDelegate oldDelegate) => false;
}

class _QuickStat extends StatelessWidget {
  const _QuickStat({required this.title, required this.value, required this.icon, this.onTap});
  final String title;
  final int value;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(value.toString(), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DividerV extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 36, color: AppColors.border);
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});
  final String tier;
  @override
  Widget build(BuildContext context) {
    Color color = AppColors.silverTier;
    if (tier.toLowerCase().contains('gold')) color = AppColors.goldTier;
    if (tier.toLowerCase().contains('platinum')) color = AppColors.platinumTier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium_rounded, size: 16, color: color),
        const SizedBox(width: 6),
        Text(tier, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

