import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/theme.dart';

class SponsorshipScreen extends StatefulWidget {
  const SponsorshipScreen({super.key});

  @override
  State<SponsorshipScreen> createState() => _SponsorshipScreenState();
}

class _SponsorshipScreenState extends State<SponsorshipScreen> {
  Map<String, dynamic>? _existing;
  DateTime? _memberSince;
  bool _loading = true;

  // Form controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _essayCtrl = TextEditingController();
  final _passportCtrl = TextEditingController();
  final _hajjYearCtrl = TextEditingController();
  String? _country;
  bool _submitting = false;
  bool _hasPerformedHajj = false;

  final _countries = const [
    'Saudi Arabia','Bangladesh','Pakistan','India','Malaysia','Indonesia','United Arab Emirates','United Kingdom','United States','Canada','Turkey','Egypt','Nigeria','South Africa','Other'
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (mounted) context.go('/login');
        return;
      }

      // Prefill profile basics
      final profileRes = await client
          .from('profiles')
          .select('full_name,email,phone,created_at')
          .eq('user_id', user.id)
          .maybeSingle();
      if (profileRes != null) {
        _nameCtrl.text = (profileRes['full_name'] ?? '').toString();
        _emailCtrl.text = (profileRes['email'] ?? '').toString();
        _phoneCtrl.text = (profileRes['phone'] ?? '').toString();
        final createdAt = profileRes['created_at'];
        if (createdAt is String) _memberSince = DateTime.tryParse(createdAt);
      }

      // Check existing application
      final existing = await client
          .from('sponsorship_applications')
          .select('id,status,created_at')
          .eq('user_id', user.id)
          .inFilter('status', ['pending', 'approved'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      setState(() {
        _existing = existing;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Sponsorship init failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _essayCtrl.dispose();
    _passportCtrl.dispose();
    _hajjYearCtrl.dispose();
    super.dispose();
  }

  int _monthsActive() {
    if (_memberSince == null) return 0;
    final now = DateTime.now();
    final diffMonths = (now.year - _memberSince!.year) * 12 + (now.month - _memberSince!.month);
    return diffMonths.clamp(0, 1000);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tier = app.currentTier;
    final totalPoints = app.totalPoints;
    final isGoldOrPlatinum = tier == 'Gold' || tier == 'Platinum';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Sponsorship', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (!isGoldOrPlatinum ? _LockScreen(totalPoints: totalPoints) : _FormOrStatus(
              existing: _existing,
              nameCtrl: _nameCtrl,
              emailCtrl: _emailCtrl,
              phoneCtrl: _phoneCtrl,
              essayCtrl: _essayCtrl,
              passportCtrl: _passportCtrl,
              hasPerformedHajj: _hasPerformedHajj,
              onHasPerformedChanged: (v) => setState(() => _hasPerformedHajj = v ?? false),
              hajjYearCtrl: _hajjYearCtrl,
              country: _country,
              onCountryChanged: (v) => setState(() => _country = v),
              monthsActive: _monthsActive(),
              subscriptionActive: app.subscriptionActive,
              countries: _countries,
              onSubmit: _submit,
              submitting: _submitting,
              totalPoints: totalPoints,
            )),
    );
  }

  Future<void> _submit() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final fullName = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final essay = _essayCtrl.text.trim();
    final country = _country ?? '';
    final passport = _passportCtrl.text.trim();
    final hasPerformed = _hasPerformedHajj;
    final yearText = _hajjYearCtrl.text.trim();
    final int? prevYear = (hasPerformed && yearText.isNotEmpty) ? int.tryParse(yearText) : null;

    if (fullName.isEmpty || email.isEmpty || phone.isEmpty || country.isEmpty || passport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all fields.')));
      return;
    }
    if (essay.length < 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Essay must be at least 200 characters.')));
      return;
    }

    try {
      setState(() => _submitting = true);
      await client.from('sponsorship_applications').insert({
        'user_id': user.id,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'passport_number': passport,
        'country': country,
        'reason': essay,
        'has_performed_hajj': hasPerformed,
        'previous_hajj_year': prevYear,
        'status': 'pending',
      });

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [Icon(Icons.check_circle, color: AppColors.primary, size: 28), SizedBox(width: 8), Text('Application Submitted!')]),
          content: const Text("We'll review and contact you within 7-10 business days."),
          actions: [
            TextButton(onPressed: () => context.go('/home'), child: const Text('Return Home')),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Submit application failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit application. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.totalPoints});
  final int totalPoints;

  @override
  Widget build(BuildContext context) {
    final progress = (totalPoints / 500).clamp(0.0, 1.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
            child: const Icon(Icons.lock, color: Color(0xFFD97706), size: 40),
          ),
          const SizedBox(height: 24),
          Text('Gold Tier Required', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('The Sponsorship Program is available for Gold and Platinum members only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 15, color: AppColors.mutedForeground), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your Progress to Gold:', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: Color(0xFFD1D5DB), color: AppColors.accent),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$totalPoints pts'),
                Text('500 pts needed', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => context.go('/community'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
              child: const Text('Earn Points in Community'))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FormOrStatus extends StatelessWidget {
  const _FormOrStatus({
    required this.existing,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.essayCtrl,
    required this.passportCtrl,
    required this.hasPerformedHajj,
    required this.onHasPerformedChanged,
    required this.hajjYearCtrl,
    required this.country,
    required this.onCountryChanged,
    required this.monthsActive,
    required this.subscriptionActive,
    required this.countries,
    required this.onSubmit,
    required this.submitting,
    required this.totalPoints,
  });

  final Map<String, dynamic>? existing;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController essayCtrl;
  final TextEditingController passportCtrl;
  final bool hasPerformedHajj;
  final ValueChanged<bool?> onHasPerformedChanged;
  final TextEditingController hajjYearCtrl;
  final String? country;
  final ValueChanged<String?> onCountryChanged;
  final int monthsActive;
  final bool subscriptionActive;
  final List<String> countries;
  final VoidCallback onSubmit;
  final bool submitting;
  final int totalPoints;

  @override
  Widget build(BuildContext context) {
    if (existing != null) {
      final status = (existing!['status'] ?? '').toString();
      if (status == 'pending') {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.hourglass_bottom, color: AppColors.primary, size: 48),
              const SizedBox(height: 12),
              const Text('Your application is under review.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      }
      if (status == 'approved') {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.celebration, color: AppColors.primary, size: 48),
              const SizedBox(height: 12),
              const Text('🎉 Congratulations! Application approved!', style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      }
    }

    final qualifiesTier = true; // we already gated by tier screen; show checks as visual cues
    final qualifiesSubscription = subscriptionActive;
    final qualifiesMonths = monthsActive >= 6;
    final qualifiesEssay = (essayCtrl.text.length >= 200);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero section
          Container(
            height: 220,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF22B85F), AppColors.primary]),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Icon(Icons.volunteer_activism, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: const Text('🎁 FULLY FUNDED PROGRAM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              const Text('Monthly Sponsorship Program', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              Text('Apply for a fully-sponsored Hajj journey', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
            ]),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Eligibility checklist
              _EligibilityRow(label: 'Gold or Platinum tier', ok: qualifiesTier),
              _EligibilityRow(label: 'Active \$15/month subscription', ok: qualifiesSubscription),
              _EligibilityRow(label: 'Minimum 6 months as a member', ok: qualifiesMonths),
              _EligibilityRow(label: 'Community participation', ok: true),
              _EligibilityRow(label: 'Compelling essay (min 200 characters)', ok: qualifiesEssay),

              const SizedBox(height: 12),
              // Application form card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _Input(label: 'Full Name', controller: nameCtrl),
                  _Input(label: 'Email', controller: emailCtrl, keyboard: TextInputType.emailAddress),
                  _Input(label: 'Phone', controller: phoneCtrl, keyboard: TextInputType.phone),
              _Input(label: 'Passport Number', controller: passportCtrl),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: country,
                    items: countries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: onCountryChanged,
                    decoration: const InputDecoration(labelText: 'Country of Residence', border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border))),
                  ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: hasPerformedHajj,
                onChanged: onHasPerformedChanged,
                title: const Text('I have previously performed Hajj'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (hasPerformedHajj)
                _Input(label: 'Year of Hajj', controller: hajjYearCtrl, keyboard: TextInputType.number),
                  const SizedBox(height: 12),
                  Text('Why do you need sponsorship? (min 200 chars)', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: essayCtrl,
                    minLines: 5,
                    maxLines: 10,
                    onChanged: (_) => (context as Element).markNeedsBuild(),
                    decoration: const InputDecoration(hintText: 'Tell us your story...', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Builder(builder: (context) {
                      final len = essayCtrl.text.length;
                      final ok = len >= 200;
                      return Text(ok ? '$len ✓' : '$len/200', style: TextStyle(color: ok ? AppColors.primary : Colors.red, fontWeight: FontWeight.w700));
                    }),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: submitting ? null : onSubmit,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                      child: submitting ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit Application →'),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _EligibilityRow extends StatelessWidget {
  const _EligibilityRow({required this.label, required this.ok});
  final String label;
  final bool ok;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? AppColors.primary : AppColors.border, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({required this.label, required this.controller, this.keyboard});
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}
