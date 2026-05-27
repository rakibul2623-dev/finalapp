import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/components/hajj_button.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/nav.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralCodeController = TextEditingController();
  bool _termsAccepted = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    final referralCode = _referralCodeController.text.trim();

    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept Terms & Privacy Policy.'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (fullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your full name'), backgroundColor: Colors.red),
      );
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password'), backgroundColor: Colors.red),
      );
      return;
    }

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters'), backgroundColor: Colors.red),
      );
      return;
    }

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;
      final authResponse = await client.auth.signUp(email: email, password: password);

      final user = authResponse.user;
      if (user != null && mounted) {
        // Create or upsert profile with allowed columns only
        try {
          await client.from('profiles').upsert({
            'user_id': user.id,
            'full_name': fullName,
            'email': email,
            'phone': phone.isEmpty ? null : phone,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id');
        } catch (e) {
          debugPrint('Failed to insert profile: $e');
        }

        if (referralCode.isNotEmpty) {
          try {
            // Lookup referral record by referral_code
            final referralResult = await client
                .from('referrals')
                .select('id, referrer_id, referred_id, referral_code, status, points_awarded')
                .eq('referral_code', referralCode)
                .maybeSingle();

            if (referralResult != null && referralResult['referrer_id'] != null) {
              // Fetch current points of the referrer
              final currentProfile = await client
                  .from('profiles')
                  .select('points_total')
                  .eq('user_id', referralResult['referrer_id'])
                  .single();

              final currentPoints = (currentProfile['points_total'] as int?) ?? 0;

              // Update referrer's points directly (no RPC)
              await client
                  .from('profiles')
                  .update({
                    'points_total': currentPoints + 100,
                    'updated_at': DateTime.now().toIso8601String(),
                  })
                  .eq('user_id', referralResult['referrer_id']);

              // Mark points awarded on referral record
              await client
                  .from('referrals')
                  .update({'points_awarded': 100})
                  .eq('id', referralResult['id']);
            } else {
              debugPrint('Referral code not found or missing referrer_id: $referralCode');
            }
          } catch (e) {
            debugPrint('Failed to process referral code: $e');
          }
        }

        // Fetch profile to seed app state
        Map<String, dynamic>? profile;
        try {
          profile = await client.from('profiles').select().eq('user_id', user.id).maybeSingle();
        } catch (e) {
          debugPrint('Failed to fetch profile after signup: $e');
        }

        context.read<AppState>().setCurrentUserProfile(profile);
        context.read<AppState>().setSubscriptionActive(false);
        context.read<AppState>().setUnreadNotifCount(0);
        context.go(AppRoutes.home);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
          child: IntrinsicHeight(
            child: Container(
              constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
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
                    'Create your account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineLarge
                        ?.copyWith(color: AppColors.primaryForeground),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: const [
                        BoxShadow(color: Color.fromRGBO(21, 40, 33, 0.08), offset: Offset(0, 4), blurRadius: 16),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 1. Full Name
                        TextField(
                          controller: _fullNameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            hintText: 'Your full name',
                            prefixIcon: Icon(Icons.person_outline, color: AppColors.mutedForeground),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 2. Email Address
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            hintText: 'you@example.com',
                            prefixIcon: Icon(Icons.email_outlined, color: AppColors.mutedForeground),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 3. Phone Number (optional)
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            hintText: '+1 (555) 000-0000',
                            helperText: 'Optional',
                            prefixIcon: Icon(Icons.phone_outlined, color: AppColors.mutedForeground),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 4. Password
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Min 8 characters',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.mutedForeground),
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
                        // 5. Confirm Password
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            hintText: 'Repeat password',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.mutedForeground),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                              icon: Icon(
                                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 6. Referral Code (optional)
                        TextField(
                          controller: _referralCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Referral Code',
                            hintText: 'E.G. ABC12345',
                            helperText: 'Optional — enter a friend\'s referral code',
                            prefixIcon: Icon(Icons.card_giftcard_outlined, color: AppColors.mutedForeground),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 7. Terms acceptance
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _termsAccepted,
                              onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                              activeColor: AppColors.primary,
                            ),
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('I agree to the ', style: Theme.of(context).textTheme.bodyMedium),
                                  TextButton(
                                    onPressed: () {
                                      // TODO: open Terms & Privacy Policy link
                                    },
                                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                                    child: const Text('Terms & Privacy Policy'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 8. Create Account button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_isLoading || !_termsAccepted) ? null : _handleSignup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            ),
                            child: _isLoading
                                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                                : const Text('Create Account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 9. Sign in prompt
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.border, fontSize: 14),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : () => context.go('/login'),
                        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                        child: const Text('Sign In', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          // Close IntrinsicHeight
        ),
        // Close ConstrainedBox
      ),
      // Close SingleChildScrollView
    ),
    // Extra safety close (if nested)
    ),
    );
  }
}
