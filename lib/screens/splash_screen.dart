import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/components/fade_in.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/nav.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _navTimer = Timer(const Duration(milliseconds: 2500), _handleNavigation);
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleNavigation() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        context.go(AppRoutes.login);
        return;
      }

      // Fetch profile
      Map<String, dynamic>? profile;
      try {
        profile = await client.from('profiles').select().eq('user_id', user.id).maybeSingle();
      } catch (e) {
        debugPrint('Splash: failed to fetch profile -> $e');
      }

      // Fetch active subscription
      bool hasActiveSub = false;
      try {
        final sub = await client
            .from('wallet_subscriptions')
            .select()
            .eq('user_id', user.id)
            .eq('status', 'active')
            .maybeSingle();
        hasActiveSub = sub != null;
      } catch (e) {
        debugPrint('Splash: failed to fetch subscription -> $e');
      }

      // Fetch unread notifications count (best-effort)
      int unread = 0;
      try {
        final rows = await client
            .from('notifications')
            .select('id')
            .eq('user_id', user.id)
            .eq('read', false)
            .limit(200);
        if (rows is List) unread = rows.length;
      } catch (e) {
        debugPrint('Splash: unread notifications query failed -> $e');
      }

      if (!mounted) return;
      final appState = context.read<AppState>();
      appState
        ..setCurrentUserProfile(profile)
        ..setSubscriptionActive(hasActiveSub)
        ..setUnreadNotifCount(unread);
      context.go(AppRoutes.home);
    } catch (e, st) {
      debugPrint('Splash: unexpected error -> $e');
      debugPrint('Splash: stack -> $st');
      if (!mounted) return;
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.darkTeal, // #0F4C3A
              AppColors.primary, // #168041
              AppColors.primaryGlow, // #22B85F
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const FadeIn(
                duration: Duration(milliseconds: 800),
                child: SizedBox(
                  height: 100,
                  width: 100,
                  child: Image(
                    image: AssetImage('assets/images/hajj_wallet_logo.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeIn(
                delay: const Duration(milliseconds: 300),
                child: Text(
                  'HAJJ WALLET',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4.0,
                        color: Colors.white,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              FadeIn(
                delay: const Duration(milliseconds: 600),
                child: Text(
                  'Your Sacred Journey Starts Here',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                ),
              ),
              const SizedBox(height: 48),
              FadeIn(
                delay: const Duration(milliseconds: 900),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
