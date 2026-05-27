import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hajj_wallet/components/subscription_gate.dart';
import 'package:hajj_wallet/components/add_funds_sheet.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late Future<Map<String, dynamic>?> _future;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return null;
      final res = await Supabase.instance.client
          .from('wallets')
          .select('balance, goal_amount')
          .eq('user_id', userId)
          .single();
      return res as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('WalletScreen load error: $e');
      rethrow;
    }
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return SubscriptionGate(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                title: const Text('My Wallet'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                    onPressed: () => _openAddFundsSheet(context),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _BalanceCard(
                    future: _future,
                    pulse: _pulse,
                    onRetry: _retry,
                    onAddFunds: () => _openAddFundsSheet(context),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeaderDelegate(
                  child: Container(
                    color: AppColors.surface,
                    child: const TabBar(
                      indicatorColor: AppColors.primary,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.mutedForeground,
                      tabs: [
                        Tab(text: 'Transactions'),
                        Tab(text: 'Statistics'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: const TabBarView(
              children: [
                _TransactionsTab(),
                _StatisticsTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAddFundsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AddFundsBottomSheet(
        onSuccess: () {
          if (mounted) setState(() => _future = _load());
        },
      ),
    );
  }
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TabHeaderDelegate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab();

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) return '';
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final m = months[dt.month - 1];
      return '$m ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return const Center(child: Text('Not signed in'));
    }
    final stream = Supabase.instance.client
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(50);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.mutedForeground),
                  const SizedBox(height: 12),
                  Text('No transactions yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.foreground)),
                  const SizedBox(height: 6),
                  Text('Add funds to get started', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final t = items[index];
            final status = (t['status'] ?? 'completed').toString();
            final createdAt = (t['created_at'] ?? '').toString();
            final amountNum = (t['amount'] as num?)?.toDouble() ?? 0.0;
            final type = (t['type'] ?? 'one-time').toString();
            final desc = type == 'recurring' ? 'Recurring contribution' : 'One-time contribution';
            final isSuccess = status == 'completed';
            final isPending = status == 'pending';
            final amountText = '\$' + amountNum.abs().toStringAsFixed(2);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_downward, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(desc, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(_formatDate(createdAt), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground, fontSize: 13)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        amountText,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: isSuccess
                                  ? AppColors.primary
                                  : (isPending ? AppColors.mutedForeground : const Color(0xFFDD3838)),
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isSuccess
                                  ? AppColors.primary
                                  : (isPending ? AppColors.border : const Color(0xFFDD3838)))
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: isSuccess
                                    ? AppColors.primary
                                    : (isPending ? AppColors.mutedForeground : const Color(0xFFDD3838)),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatisticsTab extends StatelessWidget {
  const _StatisticsTab();

  List<String> _last6MonthLabels(DateTime now) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final list = <String>[];
    for (int i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      list.add(months[(d.month - 1) % 12]);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return const Center(child: Text('Not signed in'));

    final stream = Supabase.instance.client
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final txs = snapshot.data!;
        final now = DateTime.now();
        final months = <DateTime>[];
        for (int i = 5; i >= 0; i--) {
          months.add(DateTime(now.year, now.month - i, 1));
        }

        final sums = List<double>.filled(6, 0.0);
        double totalCredits = 0.0;
        double totalDebits = 0.0;
        for (final t in txs) {
          final createdAt = DateTime.tryParse((t['created_at'] ?? '').toString());
          if (createdAt == null) continue;
          final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
          final status = (t['status'] ?? 'completed').toString();
          // Treat completed amounts as deposits; there is no debit type in schema
          if (status == 'completed') {
            totalCredits += amt.abs();
          }

          for (int i = 0; i < months.length; i++) {
            final m = months[i];
            if (createdAt.year == m.year && createdAt.month == m.month) {
              if (status == 'completed') sums[i] += amt.abs();
              break;
            }
          }
        }

        final labels = _last6MonthLabels(now);
        final maxY = (sums.fold<double>(0, (p, n) => math.max(p, n)) * 1.2).clamp(100.0, double.infinity);
        final monthsActive = months.length;
        final avgMonthly = monthsActive > 0 ? totalCredits / monthsActive : 0.0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              height: 240,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(color: AppColors.border, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) => Text(
                          '\$' + value.toStringAsFixed(0),
                          style: const TextStyle(color: AppColors.mutedForeground, fontSize: 10),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(labels[idx], style: const TextStyle(color: AppColors.mutedForeground, fontSize: 11)),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    6,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: sums[i],
                          color: AppColors.primary,
                          width: 16,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  maxY: maxY,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SummaryTile(title: 'Total Deposited', value: '\$' + totalCredits.toStringAsFixed(2)),
                  _SummaryTile(title: 'Total Withdrawn', value: '\$' + totalDebits.toStringAsFixed(2)),
                  _SummaryTile(title: 'Average Monthly', value: '\$' + avgMonthly.toStringAsFixed(2)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.foreground, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.future, required this.pulse, required this.onRetry, required this.onAddFunds});

  final Future<Map<String, dynamic>?> future;
  final Animation<double> pulse;
  final VoidCallback onRetry;
  final VoidCallback onAddFunds;

  @override
  Widget build(BuildContext context) {
    final tier = context.select<AppState, String>((s) => s.currentTier);
    final points = context.select<AppState, int>((s) => s.totalPoints);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.darkTeal, AppColors.deepTeal],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _LoadingBalance(pulse: pulse);
          }
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Unable to load wallet data.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            );
          }

          final data = snapshot.data ?? const {};
          final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
          final goal = math.max((data['goal_amount'] as num?)?.toDouble() ?? 0.0, 0.0);
          final pct = goal > 0 ? (balance / goal).clamp(0.0, 1.0) : 0.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT BALANCE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$' + balance.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                        ),
                        child: Text(
                          '$tier Member',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$points pts',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Savings Progress',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.20),
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '\$' + balance.toStringAsFixed(2) + ' saved',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                  ),
                  Text(
                    'Goal: ' + (goal > 0 ? ('\$' + goal.toStringAsFixed(2)) : '—'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: onAddFunds,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.darkTeal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        child: const Text(
                          '＋ Add Funds',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => _onSetGoal(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.50), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        child: const Text('Set Goal'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _onSetGoal(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set Goal coming soon.')),
      );
}

class _LoadingBalance extends StatelessWidget {
  const _LoadingBalance({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeTransition(
                  opacity: Tween(begin: 0.4, end: 1.0).animate(pulse),
                  child: Container(
                    height: 10,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeTransition(
                  opacity: Tween(begin: 0.5, end: 1.0).animate(pulse),
                  child: Text(
                    '\$0.00',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FadeTransition(
                  opacity: Tween(begin: 0.4, end: 1.0).animate(pulse),
                  child: Container(
                    height: 24,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeTransition(
                  opacity: Tween(begin: 0.4, end: 1.0).animate(pulse),
                  child: Container(
                    height: 10,
                    width: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        FadeTransition(
          opacity: Tween(begin: 0.4, end: 1.0).animate(pulse),
          child: Container(
            height: 10,
            width: 140,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: null,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.20),
            color: AppColors.accent.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FadeTransition(
              opacity: Tween(begin: 0.4, end: 1.0).animate(pulse),
              child: Container(
                height: 10,
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            FadeTransition(
              opacity: Tween(begin: 0.4, end: 1.0).animate(pulse),
              child: Container(
                height: 10,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.7),
                    foregroundColor: AppColors.darkTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                  child: const Text('＋ Add Funds'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.40), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                  child: const Text('Set Goal'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// AddFundsBottomSheet now lives in lib/components/add_funds_sheet.dart
