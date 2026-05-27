import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/components/hajj_card.dart';
import 'package:hajj_wallet/components/fade_in.dart';
import 'package:hajj_wallet/components/subscription_gate.dart';
import 'package:hajj_wallet/supabase/supabase_config.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookings = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = SupabaseConfig.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _bookings = const [];
          _loading = false;
          _error = 'Not signed in';
        });
        return;
      }
      final res = await SupabaseConfig.client
          .from('bookings')
          .select('*, packages(name, type, image_url, duration_days)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final list = (res as List)
          .map((e) => (e as Map<String, dynamic>))
          .toList(growable: false);
      setState(() {
        _bookings = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _upcoming() {
    final now = DateTime.now();
    return _bookings.where((b) {
      final status = (b['status'] ?? '').toString().toLowerCase();
      final depStr = b['departure_date']?.toString();
      DateTime? dep;
      if (depStr != null && depStr.isNotEmpty) {
        dep = DateTime.tryParse(depStr);
      }
      return status == 'confirmed' && dep != null && !dep.isBefore(DateTime(now.year, now.month, now.day));
    }).toList();
  }

  List<Map<String, dynamic>> _cancelled() => _bookings
      .where((b) => (b['status'] ?? '').toString().toLowerCase() == 'cancelled')
      .toList();

  List<Map<String, dynamic>> _past() {
    final now = DateTime.now();
    return _bookings.where((b) {
      final status = (b['status'] ?? '').toString().toLowerCase();
      if (status == 'cancelled') return false;
      final depStr = b['departure_date']?.toString();
      final dep = depStr != null ? DateTime.tryParse(depStr) : null;
      return dep != null && dep.isBefore(DateTime(now.year, now.month, now.day));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Bookings'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            color: AppColors.foreground,
            onPressed: () => context.pop(),
          ),
          bottom: const TabBar(
            isScrollable: false,
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: SubscriptionGate(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: TabBarView(
                        children: [
                          _BookingsList(bookings: _upcoming(), onTap: _showDetails, onEmptyBrowse: () => context.go('/packages')),
                          _BookingsList(bookings: _past(), onTap: _showDetails, onEmptyBrowse: () => context.go('/packages')),
                          _BookingsList(bookings: _cancelled(), onTap: _showDetails, onEmptyBrowse: () => context.go('/packages')),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        final pkg = booking['packages'] as Map<String, dynamic>?;
        final name = (pkg?['name'] ?? '').toString();
        final type = (pkg?['type'] ?? '').toString();
        final image = (pkg?['image_url'] ?? '').toString();
        final duration = (pkg?['duration_days'] ?? 0).toString();
        final depStr = (booking['departure_date'] ?? '').toString();
        final depDate = DateTime.tryParse(depStr);
        final dateText = depDate != null ? DateFormat('MMM d, yyyy').format(depDate) : '—';
        final status = (booking['status'] ?? '').toString();
        final pm = (booking['payment_method'] ?? '').toString();
        final total = (booking['total_amount'] ?? 0).toString();
        final paid = (booking['paid_amount'] ?? 0).toString();
        final travelers = booking['traveler_count']?.toString() ?? '1';

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) => SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(name.isEmpty ? 'Package' : name, style: Theme.of(context).textTheme.titleLarge?.bold),
                    ),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 12),
                if (image.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Image.network(image, height: 160, width: double.infinity, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.calendar_today, size: 18, color: AppColors.mutedForeground),
                  const SizedBox(width: 8),
                  Text('$dateText · ${duration}d', style: Theme.of(context).textTheme.bodyMedium),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.people_alt_outlined, size: 18, color: AppColors.mutedForeground),
                  const SizedBox(width: 8),
                  Text('$travelers traveler(s)', style: Theme.of(context).textTheme.bodyMedium),
                ]),
                const SizedBox(height: 16),
                Text('Payment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Method: $pm'),
                const SizedBox(height: 6),
                Text('Paid: \$${paid} / Total: \$${total}', style: Theme.of(context).textTheme.bodyMedium?.bold.withColor(AppColors.primary)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Placeholder: could generate a voucher PDF link if available
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voucher will be available soon.')));
                      },
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Download Voucher'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.go('/messages'),
                      icon: const Icon(Icons.support_agent, size: 18, color: Colors.white),
                      label: const Text('Contact Support'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BookingsList extends StatelessWidget {
  const _BookingsList({required this.bookings, required this.onTap, required this.onEmptyBrowse});
  final List<Map<String, dynamic>> bookings;
  final void Function(Map<String, dynamic>) onTap;
  final VoidCallback onEmptyBrowse;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return _EmptyState(onBrowsePackages: onEmptyBrowse);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemBuilder: (context, index) {
        final b = bookings[index];
        return FadeIn(
          delay: Duration(milliseconds: 40 * index),
          child: _BookingCard(booking: b, onTap: () => onTap(b)),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: bookings.length,
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onTap});
  final Map<String, dynamic> booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pkg = booking['packages'] as Map<String, dynamic>?;
    final image = (pkg?['image_url'] ?? '').toString();
    final name = (pkg?['name'] ?? 'Package').toString();
    final type = (pkg?['type'] ?? '').toString();
    final duration = (pkg?['duration_days'] ?? 0) as Object?;
    final depStr = (booking['departure_date'] ?? '').toString();
    final depDate = DateTime.tryParse(depStr);
    final dateText = depDate != null ? DateFormat('MMM d, yyyy').format(depDate) : '—';
    final travelers = booking['traveler_count']?.toString() ?? '1';
    final status = (booking['status'] ?? '').toString();
    final total = (booking['total_amount'] ?? 0) as num;
    final paid = (booking['paid_amount'] ?? 0) as num;
    final progress = total > 0 ? (paid / total).clamp(0, 1).toDouble() : 0.0;

    return HajjCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
              child: Image.network(image, height: 120, width: double.infinity, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _TypeChip(type: type),
                  ],
                ),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.calendar_today, size: 18, color: AppColors.mutedForeground),
                  const SizedBox(width: 8),
                  Text('$dateText · ${duration ?? 0}d', style: Theme.of(context).textTheme.bodyMedium),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.people_alt_outlined, size: 18, color: AppColors.mutedForeground),
                  const SizedBox(width: 8),
                  Text('$travelers traveler(s)', style: Theme.of(context).textTheme.bodyMedium),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.border,
                      color: AppColors.primary,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '\$${paid.toStringAsFixed(2)} / \$${total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium?.bold.withColor(AppColors.primary),
                  ),
                ]),
                const SizedBox(height: 8),
                if (status.toLowerCase() == 'confirmed')
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voucher will be available soon.')));
                      },
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Download Voucher'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg;
    switch (s) {
      case 'pending':
        bg = Colors.orange; // per spec for orders
        break;
      case 'paid':
        bg = Colors.blue;
        break;
      case 'shipped':
        bg = Colors.purple;
        break;
      case 'delivered':
        bg = AppColors.success;
        break;
      case 'cancelled':
        bg = AppColors.destructive;
        break;
      case 'confirmed':
        bg = AppColors.primary;
        break;
      default:
        bg = AppColors.silverTier;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final String type;
  @override
  Widget build(BuildContext context) {
    final t = type.toLowerCase();
    final isPremium = t == 'premium';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isPremium ? AppColors.accent : AppColors.tierSilverBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isPremium ? AppColors.accent : AppColors.border),
      ),
      child: Text(
        isPremium ? 'Premium' : 'Essential',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isPremium ? AppColors.foreground : AppColors.tierSilverText,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBrowsePackages});
  final VoidCallback onBrowsePackages;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flight_takeoff_rounded, size: 64, color: AppColors.silverTier),
            const SizedBox(height: 12),
            Text('No bookings yet', style: Theme.of(context).textTheme.titleLarge?.bold, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Explore Hajj & Umrah packages to plan your journey.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: onBrowsePackages,
                child: const Text('View Packages'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: AppColors.destructive),
            const SizedBox(height: 12),
            Text('Something went wrong', style: Theme.of(context).textTheme.titleLarge?.bold),
            const SizedBox(height: 6),
            Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
