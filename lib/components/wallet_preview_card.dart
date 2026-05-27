import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';

class WalletPreviewCard extends StatefulWidget {
  const WalletPreviewCard({super.key});

  @override
  State<WalletPreviewCard> createState() => _WalletPreviewCardState();
}

class _WalletPreviewCardState extends State<WalletPreviewCard>
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
      debugPrint('Failed to load wallet: $e');
      rethrow;
    }
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Savings',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              GestureDetector(
                onTap: () => context.go('/wallet'),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  '→ View Wallet',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _LoadingSection(pulse: _pulse);
              }
              if (snapshot.hasError) {
                return GestureDetector(
                  onTap: _retry,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Unable to load wallet data. Tap to retry.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.90),
                          ),
                    ),
                  ),
                );
              }

              final data = snapshot.data ?? const {};
              final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
              final goal = math.max((data['goal_amount'] as num?)?.toDouble() ?? 0.0, 0.0);
              final pct = goal > 0 ? (balance / goal).clamp(0.0, 1.0) : 0.0;
              final pctText = goal > 0 ? ((pct * 100).round()).toString() : '0';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$' + balance.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'of \$' + goal.toStringAsFixed(2) + ' goal',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.20),
                      color: const Color(0xFFF2B928),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$pctText% to your Hajj goal',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 12,
                          ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Balance placeholder shows "$0.00" with a subtle shimmer
        FadeTransition(
          opacity: Tween(begin: 0.5, end: 1.0).animate(pulse),
          child: Text(
            '\$0.00',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(height: 12),
        // Goal text placeholder
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
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: null,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.20),
            color: const Color(0xFFF2B928).withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FadeTransition(
            opacity: Tween(begin: 0.4, end: 1.0).animate(pulse),
            child: Container(
              height: 10,
              width: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
