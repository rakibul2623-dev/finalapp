import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/components/hajj_button.dart';
import 'package:hajj_wallet/nav.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      debugPrint('Login: blocked empty fields (email or password missing)');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;
      debugPrint('Login: calling signInWithPassword (see main.dart for configured URL) email=$email');
      final response = await client.auth.signInWithPassword(email: email, password: password);
      debugPrint('Login: signInWithPassword completed. user=${response.user?.id}');

      if (response.user != null && mounted) {
        final userId = response.user!.id;

        debugPrint('Login: fetching profile for user_id=$userId');
        final profile = await client
            .from('profiles')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        debugPrint('Login: profile result -> ${profile == null ? 'null' : 'found'}');

        debugPrint('Login: fetching active subscription for user_id=$userId');
        final subscription = await client
            .from('wallet_subscriptions')
            .select()
            .eq('user_id', userId)
            .eq('status', 'active')
            .maybeSingle();
        debugPrint('Login: subscription result -> ${subscription == null ? 'none' : 'found'}');

        // Skip unread notifications query due to schema mismatch (no `read` column)
        // Default to 0 for now; we can revisit once the correct column is confirmed.
        debugPrint('Login: skipping unread notifications query (no `read` column). Defaulting count to 0');

        if (mounted) {
          context.read<AppState>().setCurrentUserProfile(profile);
          context.read<AppState>().setSubscriptionActive(subscription != null);
          final count = 0;
          context.read<AppState>().setUnreadNotifCount(count);
          context.go(AppRoutes.home);
          debugPrint('Login: navigation to /home triggered');
        }
      }
    } on AuthException catch (e) {
      debugPrint('Login: AuthException -> ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Login: unexpected error -> $e');
      debugPrint('Login: stack -> $st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      debugPrint('Login: done, resetting loading state');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reset link sent to your email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send reset email. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.darkTeal, AppColors.primary],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/hajj_wallet_logo.png',
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.account_balance_wallet,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Hajj Wallet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .displayMedium
                        ?.copyWith(color: AppColors.primaryForeground),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your journey begins with saving.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppColors.border),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(21, 40, 33, 0.08),
                          offset: Offset(0, 4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'Email address',
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: AppColors.mutedForeground,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading ? null : _handleForgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        HajjButton(
                          text: _isLoading ? 'Signing in…' : 'Sign In',
                          onPressed: () {
                            // Quick signal to confirm the button press path is firing
                            debugPrint('Login: button pressed');
                            if (_isLoading) return; // guard while loading
                            _handleLogin();
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : () => context.go('/signup'),
                            icon: const Icon(Icons.person_add_outlined, size: 18),
                            label: const Text('Create New Account'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom prompt replaced with outlined button inside the card per spec
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
