import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/supabase/supabase_config.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reusable gate that restricts access to subscription-only content.
///
/// Usage:
/// SubscriptionGate(child: YourProtectedContent())
class SubscriptionGate extends StatefulWidget {
  const SubscriptionGate({super.key, required this.child});

  final Widget child;

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  bool _isLoading = false;

  Future<void> _startSubscriptionFlow() async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to subscribe.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/paypal-subscription');
      final body = jsonEncode({
        'action': 'create-subscription',
        'returnUrl': 'hajjwallet://subscription/success',
        'cancelUrl': 'hajjwallet://subscription/cancel',
      });

      final res = await http.post(
        uri,
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Create subscription failed (${res.statusCode})');
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final approvalUrl = data['approvalUrl'] as String?;
      if (approvalUrl == null || approvalUrl.isEmpty) {
        throw Exception('Missing approvalUrl in response.');
      }

      final launched = await launchUrl(
        Uri.parse(approvalUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to open approval page.');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('After approval, return to the app to finish activation.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Subscription flow error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Call this from a deep-link handler when the app is opened with the success URL
  // Example success URL: hajjwallet://subscription/success?subscription_id=XYZ
  static Future<void> handleReturnUrl(BuildContext context, Uri uri) async {
    try {
      if (uri.scheme != 'hajjwallet' || uri.host != 'subscription') return;
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken;
      if (token == null) return;

      final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      if (action != 'success') return;
      final subId = uri.queryParameters['subscription_id'];
      if (subId == null || subId.isEmpty) return;

      final activateUri = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/paypal-subscription');
      final res = await http.post(
        activateUri,
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': 'activate-subscription',
          'subscriptionId': subId,
        }),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Activation failed (${res.statusCode})');
      }

      // Mark subscription active in app state
      // ignore: use_build_context_synchronously
      context.read<AppState>().setSubscriptionActive(true);
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome! Subscription activated.')),
      );
    } catch (e) {
      debugPrint('handleReturnUrl error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = context.watch<AppState>().subscriptionActive;
    if (active) return widget.child;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              _LockBadge(),
              const SizedBox(height: 24),
              Text(
                'Unlock Your Wallet Access',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Subscribe for \$15/month to access your Hajj savings wallet,\ntrack goals, earn tier rewards, and unlock exclusive benefits.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 15,
                      height: 1.6,
                      color: AppColors.mutedForeground,
                    ),
              ),
              const SizedBox(height: 32),
              _PricingCard(
                isLoading: _isLoading,
                onSubscribe: _startSubscriptionFlow,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security, size: 14, color: AppColors.mutedForeground),
                  const SizedBox(width: 6),
                  Text(
                    'Secured by PayPal',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedForeground,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to Home'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
                icon: const Icon(Icons.logout, size: 16, color: AppColors.destructive),
                label: const Text('Sign Out'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sign Out?'),
                      content: const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await Supabase.instance.client.auth.signOut();
                  } catch (e) {
                    debugPrint('Sign out error: $e');
                  }
                  if (!mounted) return;
                  context.read<AppState>().logout();
                  context.go('/login');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      width: 72,
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30), width: 2),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.lock_open_rounded, color: AppColors.primary, size: 36),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.isLoading, required this.onSubscribe});

  final bool isLoading;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$ ',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
              ),
              Text(
                '15',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
              ),
              const SizedBox(width: 4),
              Text(
                '/month',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Billed monthly via PayPal. Cancel anytime.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: AppColors.mutedForeground,
                ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 24, color: AppColors.border),
          const SizedBox(height: 4),
          _Feature(text: 'Full Hajj savings wallet access'),
          const SizedBox(height: 10),
          _Feature(text: 'Track your savings goal & progress'),
          const SizedBox(height: 10),
          _Feature(text: 'Complete transaction history'),
          const SizedBox(height: 10),
          _Feature(text: 'Earn tier points & unlock rewards'),
          const SizedBox(height: 10),
          _Feature(text: 'Exclusive community member benefits'),
          const SizedBox(height: 10),
          _Feature(text: 'Priority customer support'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: isLoading ? null : onSubscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Subscribe Now — \$15/month',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 15,
                  color: AppColors.foreground,
                ),
          ),
        ),
      ],
    );
  }
}
