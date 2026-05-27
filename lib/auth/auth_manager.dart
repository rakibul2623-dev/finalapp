// Authentication Manager - Base interface for auth implementations
//
// This abstract class and mixins define the contract for authentication systems.
// Implement this with concrete classes for Firebase, Supabase, or local auth.
//
// Usage:
// 1. Create a concrete class extending AuthManager
// 2. Mix in the required authentication provider mixins
// 3. Implement all abstract methods with your auth provider logic

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Core authentication operations that all auth implementations must provide
abstract class AuthManager {
  Future<void> signOut();
  Future<void> deleteUser(BuildContext context);
  Future<void> updateEmail({required String email, required BuildContext context});
  Future<void> resetPassword({required String email, required BuildContext context});
  Future<void> sendEmailVerification({required BuildContext context});
  Future<void> refreshUser();
}

// Email/password authentication mixin
mixin EmailSignInManager on AuthManager {
  Future<User?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  );

  Future<User?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  );
}

// Anonymous authentication for guest users
mixin AnonymousSignInManager on AuthManager {
  Future<User?> signInAnonymously(BuildContext context);
}

// Apple Sign-In authentication (iOS/web)
mixin AppleSignInManager on AuthManager {
  Future<User?> signInWithApple(BuildContext context);
}

// Google Sign-In authentication (all platforms)
mixin GoogleSignInManager on AuthManager {
  Future<User?> signInWithGoogle(BuildContext context);
}

// JWT token authentication for custom backends
mixin JwtSignInManager on AuthManager {
  Future<User?> signInWithJwtToken(
    BuildContext context,
    String jwtToken,
  );
}

// Phone number authentication with SMS verification
mixin PhoneSignInManager on AuthManager {
  Future beginPhoneAuth({
    required BuildContext context,
    required String phoneNumber,
    required void Function(BuildContext) onCodeSent,
  });

  Future verifySmsCode({
    required BuildContext context,
    required String smsCode,
  });
}

// Facebook Sign-In authentication
mixin FacebookSignInManager on AuthManager {
  Future<User?> signInWithFacebook(BuildContext context);
}

// Microsoft Sign-In authentication (Azure AD)
mixin MicrosoftSignInManager on AuthManager {
  Future<User?> signInWithMicrosoft(
    BuildContext context,
    List<String> scopes,
    String tenantId,
  );
}

// GitHub Sign-In authentication (OAuth)
mixin GithubSignInManager on AuthManager {
  Future<User?> signInWithGithub(BuildContext context);
}

/// Supabase-backed implementation of AuthManager for email/password auth.
class SupabaseAuthManager extends AuthManager with EmailSignInManager {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<User?> signInWithEmail(BuildContext context, String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(email: email, password: password);
      return res.user;
    } on AuthException catch (e) {
      debugPrint('SupabaseAuthManager.signInWithEmail failed: ${e.message}');
      _showSnack(context, e.message, Colors.red);
      return null;
    } catch (e) {
      debugPrint('SupabaseAuthManager.signInWithEmail unexpected error: $e');
      _showSnack(context, 'Failed to sign in. Try again.', Colors.red);
      return null;
    }
  }

  @override
  Future<User?> createAccountWithEmail(BuildContext context, String email, String password) async {
    try {
      final res = await _client.auth.signUp(email: email, password: password);
      return res.user;
    } on AuthException catch (e) {
      debugPrint('SupabaseAuthManager.createAccountWithEmail failed: ${e.message}');
      _showSnack(context, e.message, Colors.red);
      return null;
    } catch (e) {
      debugPrint('SupabaseAuthManager.createAccountWithEmail unexpected error: $e');
      _showSnack(context, 'Failed to create account. Try again.', Colors.red);
      return null;
    }
  }

  @override
  Future<void> resetPassword({required String email, required BuildContext context}) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      _showSnack(context, 'Reset link sent to your email', Colors.green);
    } on AuthException catch (e) {
      debugPrint('SupabaseAuthManager.resetPassword failed: ${e.message}');
      _showSnack(context, e.message, Colors.red);
    } catch (e) {
      debugPrint('SupabaseAuthManager.resetPassword unexpected error: $e');
      _showSnack(context, 'Failed to send reset link', Colors.red);
    }
  }

  @override
  Future<void> updateEmail({required String email, required BuildContext context}) async {
    try {
      await _client.auth.updateUser(UserAttributes(email: email));
      _showSnack(context, 'Email update requested. Check your inbox.', Colors.green);
    } on AuthException catch (e) {
      debugPrint('SupabaseAuthManager.updateEmail failed: ${e.message}');
      _showSnack(context, e.message, Colors.red);
    } catch (e) {
      debugPrint('SupabaseAuthManager.updateEmail unexpected error: $e');
      _showSnack(context, 'Failed to update email', Colors.red);
    }
  }

  @override
  Future<void> sendEmailVerification({required BuildContext context}) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        _showSnack(context, 'You need to be logged in first', Colors.orange);
        return;
      }
      await _client.auth.resend(type: OtpType.signup, email: user.email!);
      _showSnack(context, 'Verification email sent', Colors.green);
    } on AuthException catch (e) {
      debugPrint('SupabaseAuthManager.sendEmailVerification failed: ${e.message}');
      _showSnack(context, e.message, Colors.red);
    } catch (e) {
      debugPrint('SupabaseAuthManager.sendEmailVerification unexpected error: $e');
      _showSnack(context, 'Failed to send verification', Colors.red);
    }
  }

  @override
  Future<void> refreshUser() async {
    try {
      await _client.auth.getUser();
    } catch (e) {
      debugPrint('SupabaseAuthManager.refreshUser error: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('SupabaseAuthManager.signOut error: $e');
    }
  }

  @override
  Future<void> deleteUser(BuildContext context) async {
    try {
      // Requires service role on backend; typically not allowed from client.
      _showSnack(context, 'Contact support to delete account', Colors.orange);
    } catch (e) {
      debugPrint('SupabaseAuthManager.deleteUser error: $e');
    }
  }

  void _showSnack(BuildContext context, String message, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }
}
