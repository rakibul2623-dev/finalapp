import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:hajj_wallet/supabase/supabase_config.dart';
import 'package:hajj_wallet/services/points_service.dart';
import 'package:hajj_wallet/services/packages_service.dart';
import 'package:intl/intl.dart';

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = const [];
  Map<String, List<Map<String, dynamic>>> _featuresByPackage = const {};

  // Filters / Sort
  String _season = 'all'; // all | hajj | umrah | ramadan
  String _year = 'all'; // all | 2026 | 2027
  String _sort = 'recommended'; // recommended | price_low | price_high
  bool _grid = false; // reserved; default list per spec

  // Wishlist/Compare (local state; real toggle uses Supabase when connected)
  final Set<String> _wishlist = <String>{};
  final Set<String> _compare = <String>{};

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
      // Use local service until Supabase is connected via Dreamflow's Supabase panel
      final service = PackagesService();
      final packages = await service.fetchPackages(season: _season, year: _year, sort: _sort);
      final feats = await service.fetchFeaturesByPackage(packages);
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _featuresByPackage = feats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load packages: $e');
      setState(() {
        _error = 'Unable to load packages.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                elevation: 0,
                backgroundColor: Colors.white.withValues(alpha: 0.85),
                surfaceTintColor: Colors.transparent,
                titleSpacing: 0,
                leadingWidth: 72,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _CircleIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => context.pop(),
                  ),
                ),
                title: const Text('Hajj Packages', style: TextStyle(fontWeight: FontWeight.w800)),
                centerTitle: true,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _CircleIconButton(
                      icon: Icons.tune,
                      onTap: _openFilterSheet,
                    ),
                  ),
                ],
              ),

              // Hero section
              SliverToBoxAdapter(child: _HeroCard(total: _packages.length)),

              // Year/Season chips
              SliverToBoxAdapter(
                child: _ChipsRow(
                  season: _season,
                  year: _year,
                  onSeason: (v) => setState(() => _season = v),
                  onYear: (v) => setState(() => _year = v),
                  onChanged: _load,
                ),
              ),

              // Sort / view toggle
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_packages.length} packages', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
                      Row(children: [
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sort,
                            items: const [
                              DropdownMenuItem(value: 'recommended', child: Text('Recommended')),
                              DropdownMenuItem(value: 'price_low', child: Text('Price: Low to High')),
                              DropdownMenuItem(value: 'price_high', child: Text('Price: High to Low')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _sort = v);
                              _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        _CircleIconButton(icon: _grid ? Icons.grid_view_rounded : Icons.view_agenda_outlined, onTap: () => setState(() => _grid = !_grid)),
                      ]),
                    ],
                  ),
                ),
              ),

              // Content
              if (_loading)
                SliverList.builder(
                  itemBuilder: (ctx, i) => const _PackageSkeleton(),
                  itemCount: 4,
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              else if (_packages.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No packages found', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground)),
                  ),
                )
              else
                SliverList.separated(
                  itemBuilder: (ctx, i) {
                    final p = _packages[i];
                    final pid = p['id']?.toString() ?? '';
                    final feats = _featuresByPackage[pid] ?? const [];
                    final wished = _wishlist.contains(pid);
                    final compared = _compare.contains(pid);
                    return _TripPackageCard(
                      data: p,
                      features: feats,
                      wished: wished,
                      compared: compared,
                      onToggleWish: () => _onToggleWishlist(pid),
                      onCompare: () => _onToggleCompare(pid),
                      onDetails: () => _openBookingSheet(context, p),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemCount: _packages.length,
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _compare.length >= 2
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.border), boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8)),
                  ]),
                  child: Row(
                    children: [
                      Expanded(child: Text('${_compare.length} packages selected', style: Theme.of(context).textTheme.bodyMedium)),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Compare →'),
                      )
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  void _onToggleWishlist(String id) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    setState(() {
      if (_wishlist.contains(id)) {
        _wishlist.remove(id);
      } else {
        _wishlist.add(id);
      }
    });
    if (uid == null) return; // prompt login could be added
    try {
      final exists = await Supabase.instance.client
          .from('package_wishlists')
          .select('package_id')
          .eq('user_id', uid)
          .eq('package_id', id)
          .maybeSingle();
      if (exists == null) {
        await Supabase.instance.client.from('package_wishlists').insert({'user_id': uid, 'package_id': id});
      } else {
        await Supabase.instance.client.from('package_wishlists').delete().eq('user_id', uid).eq('package_id', id);
      }
    } catch (e) {
      debugPrint('Wishlist toggle failed: $e');
    }
  }

  void _onToggleCompare(String id) {
    setState(() {
      if (_compare.contains(id)) {
        _compare.remove(id);
      } else {
        _compare.add(id);
      }
    });
  }

  Future<void> _openFilterSheet() async {
    String tmpSeason = _season;
    String tmpYear = _year;
    String tmpSort = _sort;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        Widget radio(String label, String val, String group, ValueChanged<String> onChanged) => RadioListTile<String>(
              value: val,
              groupValue: group,
              onChanged: (v) => setM(() => onChanged(v ?? val)),
              title: Text(label),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filters', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Season', style: Theme.of(context).textTheme.titleMedium),
              radio('All', 'all', tmpSeason, (v) => tmpSeason = v),
              radio('Hajj', 'hajj', tmpSeason, (v) => tmpSeason = v),
              radio('Umrah', 'umrah', tmpSeason, (v) => tmpSeason = v),
              radio('Ramadan Umrah', 'ramadan', tmpSeason, (v) => tmpSeason = v),
              const Divider(height: 24),
              Text('Year', style: Theme.of(context).textTheme.titleMedium),
              radio('All', 'all', tmpYear, (v) => tmpYear = v),
              radio('2026', '2026', tmpYear, (v) => tmpYear = v),
              radio('2027', '2027', tmpYear, (v) => tmpYear = v),
              const Divider(height: 24),
              Text('Sort by', style: Theme.of(context).textTheme.titleMedium),
              radio('Recommended', 'recommended', tmpSort, (v) => tmpSort = v),
              radio('Price: Low to High', 'price_low', tmpSort, (v) => tmpSort = v),
              radio('Price: High to Low', 'price_high', tmpSort, (v) => tmpSort = v),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() {
                      _season = tmpSeason;
                      _year = tmpYear;
                      _sort = tmpSort;
                    });
                    _load();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _openBookingSheet(BuildContext context, Map<String, dynamic> pkg) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _BookingSheet(package: pkg, onConfirmed: () {}),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'HAJJ PACKAGES 2026',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
        ),
        const SizedBox(height: 12),
        Text('Journey of a Lifetime', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          'Handpicked packages for a spiritually fulfilling and comfortable Hajj in 2026.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground),
        ),
      ],
    );
  }
}

class _TrustBadges extends StatelessWidget {
  final List<String> _badges = const [
    '✓ Fully Licensed',
    '🧭 Expert Guides',
    '📞 24/7 Support',
    '⭐ 5-Star Rated',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: _badges.map((b) => _BadgeChip(label: b)).toList(),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.border)),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.foreground, fontWeight: FontWeight.w600)),
      );
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.data, required this.features, required this.onBook});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> features;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final featured = (data['is_popular'] == true) || (data['is_popular']?.toString() == 'true');
    final name = data['name']?.toString() ?? 'Package';
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final duration = data['duration']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: featured ? AppColors.primary : AppColors.border, width: featured ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.darkTeal],
                    ),
                  ),
                  child: const Icon(Icons.flight_takeoff, color: Colors.white, size: 48),
                ),
              ),
              if (featured)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF2B928), borderRadius: BorderRadius.circular(999)),
                    child: Text('MOST POPULAR', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.darkTeal)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                // Description column removed (schema has no description)
                const SizedBox(height: 10),
                Text('\$${price.toStringAsFixed(2)}/person ${duration.isNotEmpty ? '· $duration Days' : ''}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: features.map((f) => _FeatureRow(text: f['feature']?.toString() ?? f['name']?.toString() ?? '')).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: onBook,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                    ),
                    child: const Text('Book Now →', style: TextStyle(fontWeight: FontWeight.w700)),
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

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.foreground))),
        ]),
      );
}

class _BookingSheet extends StatefulWidget {
  const _BookingSheet({required this.package, required this.onConfirmed});
  final Map<String, dynamic> package;
  final VoidCallback onConfirmed;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  // Required form fields per schema
  final _travellerNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passportCtrl = TextEditingController();
  final _requestsCtrl = TextEditingController();
  String _paymentMethod = 'wallet'; // wallet | card | payment_plan
  int? _installmentMonths; // only if payment_plan
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillFromProfile();
  }

  Future<void> _prefillFromProfile() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final prof = await client
          .from('profiles')
          .select('full_name,email,phone')
          .eq('user_id', uid)
          .maybeSingle();
      if (prof != null) {
        _travellerNameCtrl.text = (prof['full_name'] ?? '').toString();
        _emailCtrl.text = (prof['email'] ?? '').toString();
        _phoneCtrl.text = (prof['phone'] ?? '').toString();
      }
    } catch (e) {
      debugPrint('Prefill profile failed: $e');
    }
  }

  @override
  void dispose() {
    _travellerNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passportCtrl.dispose();
    _requestsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to continue')));
      return;
    }
    final traveller = _travellerNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final passport = _passportCtrl.text.trim();
    final requests = _requestsCtrl.text.trim();
    if (traveller.isEmpty || email.isEmpty || phone.isEmpty || passport.isEmpty) {
      setState(() => _error = 'Please fill in all required fields.');
      return;
    }
    if (_paymentMethod == 'payment_plan' && _installmentMonths == null) {
      setState(() => _error = 'Please select installment months.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final pkgId = widget.package['id'];
      final inserted = await client
          .from('bookings')
          .insert({
            'user_id': uid,
            'package_id': pkgId,
            'traveller_name': traveller,
            'email': email,
            'phone': phone,
            'passport_number': passport,
            'special_requests': requests,
            'payment_method': _paymentMethod,
            'installment_months': _paymentMethod == 'payment_plan' ? _installmentMonths : null,
            'status': 'pending',
          })
          .select('id')
          .single();

      final bookingId = inserted['id'] as String;
      await PointsService.awardPoints(uid, 50, 'booking', bookingId);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎉 Booking submitted! We'll confirm shortly.")));
        context.go('/account');
      }
    } catch (e) {
      debugPrint('Booking failed: $e');
      setState(() => _error = 'Unable to submit booking. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.package['name']?.toString() ?? 'Package',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 8),
          _LabeledField(label: 'Traveller Full Name', controller: _travellerNameCtrl),
          _LabeledField(label: 'Email Address', controller: _emailCtrl, keyboard: TextInputType.emailAddress),
          _LabeledField(label: 'Phone Number', controller: _phoneCtrl, keyboard: TextInputType.phone),
          _LabeledField(label: 'Passport Number', controller: _passportCtrl),
          const SizedBox(height: 8),
          TextField(
            controller: _requestsCtrl,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Special Requests (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text('Payment Method', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          RadioListTile<String>(
            value: 'wallet',
            groupValue: _paymentMethod,
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'wallet'),
            title: const Text('Pay from Wallet'),
          ),
          RadioListTile<String>(
            value: 'card',
            groupValue: _paymentMethod,
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'card'),
            title: const Text('Credit/Debit Card'),
          ),
          RadioListTile<String>(
            value: 'payment_plan',
            groupValue: _paymentMethod,
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'payment_plan'),
            title: const Text('Installment Plan'),
            subtitle: const Text('Split your payments over several months'),
          ),
          if (_paymentMethod == 'payment_plan') ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _installmentMonths,
              items: const [3, 6, 12].map((m) => DropdownMenuItem(value: m, child: Text('$m months'))).toList(),
              onChanged: (v) => setState(() => _installmentMonths = v),
              decoration: const InputDecoration(labelText: 'Installment Months', border: OutlineInputBorder()),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.destructive)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
              child: _loading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Booking →', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.controller, this.keyboard});
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.foreground),
        ),
      );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.label, required this.value, required this.groupValue, required this.onChanged, this.note});
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;
  final String? note;
  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: (v) => onChanged(v ?? value),
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: note == null ? null : Text(note!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
    );
  }
}

class PackageBookingHandler {
  static Future<void> handleBookingReturnUrl(BuildContext context, Uri uri) async {
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) return;
      // Expect either orderId or token in query, and bookingId in metadata returned by your edge function redirect
      final orderId = uri.queryParameters['orderId'] ?? uri.queryParameters['token'];
      final bookingId = uri.queryParameters['bookingId'];
      if (orderId == null || bookingId == null) return;

      final res = await http.post(
        Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/paypal-checkout'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'action': 'captureOrder', 'orderID': orderId, 'type': 'package'}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Update booking status and award points via PointsService
        final client = Supabase.instance.client;
        await client.from('bookings').update({'status': 'confirmed'}).eq('id', bookingId);

        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          await PointsService.awardPoints(uid, 50, 'booking', bookingId);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 Booking confirmed!')));
          context.go('/account');
        }
      } else {
        debugPrint('Capture failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('handleBookingReturnUrl error: $e');
    }
  }
}

// ===================== Helper UI Widgets for premium Packages UI =====================

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.border), boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 6)),
          ]),
          child: Icon(icon, color: AppColors.foreground, size: 20),
        ),
      );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.total});
  final int total;
  @override
  Widget build(BuildContext context) {
    const imageUrl = 'https://images.unsplash.com/photo-1596178060671-7a80dc8059ac?q=80&w=1600&auto=format&fit=crop';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.network(imageUrl, fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.80)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF2B928), borderRadius: BorderRadius.circular(999)),
                  child: const Text('HAJJ 2026', style: TextStyle(color: Color(0xFF0A2E23), fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                ),
                const SizedBox(height: 10),
                const Text('Your Sacred Journey Awaits', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Curated packages, trusted guides', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
              ]),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                child: Text('$total packages available', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  const _ChipsRow({required this.season, required this.year, required this.onSeason, required this.onYear, required this.onChanged});
  final String season;
  final String year;
  final ValueChanged<String> onSeason;
  final ValueChanged<String> onYear;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String value, String group, ValueChanged<String> onSel) {
      final active = value == group;
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 8),
        child: InkWell(
          onTap: () {
            onSel(value);
            onChanged();
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? AppColors.primary : AppColors.border),
              boxShadow: active ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 8))] : null,
            ),
            child: Text(label, style: TextStyle(color: active ? Colors.white : AppColors.foreground, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('Hajj 2026', 'hajj', season, onSeason),
        chip('Umrah 2026', 'umrah', season, onSeason),
        chip('Hajj 2027', 'hajj_2027', (season == 'hajj' && year == '2027') ? 'hajj_2027' : 'x', (_) {}),
        chip('Ramadan Umrah', 'ramadan', season, onSeason),
        // Years quick-select
        chip('2026', '2026', year, onYear),
        chip('2027', '2027', year, onYear),
      ]),
    );
  }
}

class _PackageSkeleton extends StatelessWidget {
  const _PackageSkeleton();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Container(height: 180, decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: const BorderRadius.vertical(top: Radius.circular(28)))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Shimmer(blockWidth: 160),
                const SizedBox(height: 8),
                _Shimmer(blockWidth: 220),
                const SizedBox(height: 8),
                _Shimmer(blockWidth: 120),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                _Shimmer(blockWidth: 100),
              ]),
            )
          ]),
        ),
      );
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({this.blockWidth});
  final double? blockWidth;
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (ctx, _) => Container(
          width: widget.blockWidth ?? double.infinity,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.inputBackground,
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: [AppColors.inputBackground, Colors.white, AppColors.inputBackground],
              stops: [(_c.value - 0.3).clamp(0.0, 1.0), _c.value, (_c.value + 0.3).clamp(0.0, 1.0)],
            ),
          ),
        ),
      );
}

class _TripPackageCard extends StatelessWidget {
  const _TripPackageCard({required this.data, required this.features, required this.wished, required this.compared, required this.onToggleWish, required this.onCompare, required this.onDetails});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> features;
  final bool wished;
  final bool compared;
  final VoidCallback onToggleWish;
  final VoidCallback onCompare;
  final VoidCallback onDetails;

  String _fmtPrice(num v) => NumberFormat.currency(locale: 'en_US', symbol: '4').format(v); // explicit "$"

  String _fmtUsd(num v) {
    final f = NumberFormat.currency(locale: 'en_US', symbol: '');
    return r'$' + f.format(v).trim();
  }

  @override
  Widget build(BuildContext context) {
    final id = data['id']?.toString() ?? '';
    final slug = data['slug']?.toString();
    final name = data['name']?.toString() ?? 'Package';
    final price = (data['price'] as num?) ?? 0;
    final durationDays = (data['duration_days'] as num?)?.toInt();
    final hotelRating = (data['hotel_rating'] as num?)?.toInt();
    final groupSize = (data['group_size'] as num?)?.toInt();
    final location = (data['locations'] ?? 'Makkah · Madinah').toString();
    final dep = data['departure_date']?.toString();
    final ret = data['return_date']?.toString();
    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = (data['review_count'] as num?)?.toInt() ?? 0;
    final tier = (data['tier'] ?? '').toString();
    final installment = data['installment_available'] == true;
    final instMonths = (data['installment_months'] as num?)?.toInt();
    final instAmt = (data['installment_amount'] as num?)?.toDouble();
    final imageUrl = (() {
      final g = data['gallery_images'];
      if (g is List && g.isNotEmpty) return g.first.toString();
      final u = data['image_url']?.toString();
      return (u == null || u.isEmpty)
          ? 'https://images.unsplash.com/photo-1596178060671-7a80dc8059ac?q=80&w=1600&auto=format&fit=crop'
          : u;
    })();
    final top3 = features.take(3).map((f) => (f['feature'] ?? f['name'] ?? '').toString()).where((e) => e.isNotEmpty).toList();

    Widget badge(String label, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
        );

    Color gold = const Color(0xFFF2B928);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.border), boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10)),
          ]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // TOP Image with overlays
            Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: AspectRatio(aspectRatio: 16 / 10, child: Image.network(imageUrl, fit: BoxFit.cover)),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: tier.toLowerCase() == 'premium'
                    ? badge('PREMIUM', AppColors.primary.withValues(alpha: 0.95), Colors.white)
                    : (tier.toLowerCase() == 'essential'
                        ? badge('ESSENTIAL', Colors.white.withValues(alpha: 0.95), AppColors.foreground)
                        : badge('MOST POPULAR', gold, const Color(0xFF0A2E23))),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _CircleIconButton(icon: wished ? Icons.favorite : Icons.favorite_border, onTap: onToggleWish),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                  child: Row(children: [
                    const Icon(Icons.star, color: Color(0xFFF2B928), size: 16),
                    const SizedBox(width: 6),
                    Text('${rating.toStringAsFixed(1)} ($ratingCount reviews)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),

            // MIDDLE info
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _Meta(icon: Icons.flight_takeoff, label: durationDays != null ? '${durationDays} days' : 'Duration N/A'),
                  if (hotelRating != null) _Meta(icon: Icons.hotel, label: '${hotelRating}-star hotels'),
                  if (groupSize != null) _Meta(icon: Icons.groups_2_outlined, label: 'Group of $groupSize'),
                  _Meta(icon: Icons.location_on_outlined, label: location),
                ]),
                const SizedBox(height: 10),
                if (dep != null && ret != null)
                  Row(children: [const Icon(Icons.calendar_today, size: 16, color: AppColors.mutedForeground), const SizedBox(width: 6), Text(_fmtDateRange(dep, ret), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground))]),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final t in top3) _FeaturePreview(text: t),
                    if (features.length > top3.length)
                      TextButton(onPressed: onDetails, child: Text('+ ${features.length - top3.length} more inclusions')),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('From', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(_fmtUsd(price), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 24)),
                          const SizedBox(width: 6),
                          Text('/person', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                        ]),
                        if (installment && instMonths != null && (instAmt ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
                              child: Text('Pay in $instMonths installments of ${_fmtUsd(instAmt!)} / mo', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ]),
                    ),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: onDetails,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                        ),
                        child: const Text('View Details →', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: onCompare, icon: Icon(compared ? Icons.check_circle : Icons.circle_outlined, color: compared ? AppColors.primary : AppColors.mutedForeground, size: 18), label: const Text('Compare')),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  String _fmtDateRange(String dep, String ret) {
    DateTime? d1 = DateTime.tryParse(dep);
    DateTime? d2 = DateTime.tryParse(ret);
    if (d1 == null || d2 == null) return '';
    final df = DateFormat('MMM d, yyyy');
    return '${df.format(d1)} – ${df.format(d2)}';
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: AppColors.mutedForeground), const SizedBox(width: 6), Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground))]);
}

class _FeaturePreview extends StatelessWidget {
  const _FeaturePreview({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check_circle, color: AppColors.primary, size: 16), const SizedBox(width: 8), Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis))]),
      );
}

