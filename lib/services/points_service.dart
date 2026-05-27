import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/state/app_state.dart';

/// Centralized points and tier management.
/// Use these helpers instead of duplicating points logic across screens.
class PointsService {
  PointsService._();

  static final SupabaseClient _client = Supabase.instance.client;

  // Optional: bind AppState so UI can react to tier upgrades immediately.
  static AppState? _appState;
  static void bindAppState(AppState appState) => _appState = appState;

  /// Awards [points] to [userId] with a [reason] and a [referenceId] (e.g., row id).
  /// Also checks tier thresholds and upgrades tier when crossed.
  static Future<void> awardPoints(String userId, int points, String reason, String referenceId) async {
    try {
      // 1) Insert into points_ledger
      await _client.from('points_ledger').insert({
        'user_id': userId,
        'points': points,
        'reason': reason,
        'reference_id': referenceId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2) Read current total (and current tier if needed)
      final profile = await _client
          .from('profiles')
          .select('points_total, tier')
          .eq('user_id', userId)
          .maybeSingle();

      final int oldPoints = (profile != null && profile['points_total'] is num) ? (profile['points_total'] as num).toInt() : 0;

      // 3) Increment points_total
      await _client
          .from('profiles')
          .update({'points_total': oldPoints + points})
          .eq('user_id', userId);

      // 4) Compute new total
      final int newTotal = oldPoints + points;

      // 5) Tier upgrade checks (Silver -> Gold at 500, Gold -> Platinum at 1500)
      if (oldPoints < 500 && newTotal >= 500) {
        await updateTier(userId, 'Gold');
      }
      if (oldPoints < 1500 && newTotal >= 1500) {
        await updateTier(userId, 'Platinum');
      }
    } catch (e) {
      debugPrint('PointsService.awardPoints error: $e');
      rethrow;
    }
  }

  /// Updates the user's tier both in the database and (optionally) locally via AppState
  /// to trigger the tierJustUpgraded UI.
  static Future<void> updateTier(String userId, String newTier) async {
    try {
      await _client.from('profiles').update({'tier': newTier}).eq('user_id', userId);
      // Inform local UI if bound
      _appState?.setTier(newTier);
    } catch (e) {
      debugPrint('PointsService.updateTier error: $e');
      rethrow;
    }
  }
}
