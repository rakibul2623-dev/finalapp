import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hajj_wallet/supabase/supabase_config.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AddFundsBottomSheet extends StatefulWidget {
  const AddFundsBottomSheet({super.key, this.onSuccess});
  final VoidCallback? onSuccess;

  @override
  State<AddFundsBottomSheet> createState() => _AddFundsBottomSheetState();
}

class _AddFundsBottomSheetState extends State<AddFundsBottomSheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _setQuick(double value) {
    setState(() {
      _amountCtrl.text = value.toStringAsFixed(2);
      _error = null;
    });
  }

  double? _parseAmount() {
    final raw = _amountCtrl.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _payViaPayPal() async {
    final amount = _parseAmount();
    if (amount == null || amount < 10 || amount > 10000) {
      setState(() => _error = 'Amount must be between \$10 and \$10,000');
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    if (session == null || user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to add funds.')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/paypal-checkout'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': 'createOrder',
          'amount': amount,
          'description': 'Hajj Wallet top-up',
          'metadata': {'type': 'wallet', 'user_id': user.id},
        }),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Failed to create PayPal order (${res.statusCode}).');
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final approvalUrl = (data['approvalUrl'] ?? data['approval_url']) as String?;
      if (approvalUrl == null || approvalUrl.isEmpty) {
        throw Exception('Missing approvalUrl in response');
      }

      await launchUrl(Uri.parse(approvalUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AddFunds createOrder error: $e');
      if (mounted) setState(() => _error = 'Unable to start payment. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static Future<void> handleReturnUrl(BuildContext context, Uri uri, {VoidCallback? onSuccess}) async {
    try {
      final params = uri.queryParameters;
      final orderId = params['orderID'] ?? params['orderId'] ?? params['order_id'] ?? params['token'];
      if (orderId == null) return;

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final res = await http.post(
        Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/paypal-checkout'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'action': 'captureOrder', 'orderID': orderId, 'type': 'wallet'}),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        onSuccess?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Funds added to your wallet!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment capture failed.')),
        );
      }
    } catch (e) {
      debugPrint('AddFunds handleReturnUrl error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      builder: (ctx, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Add Funds to Wallet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.foreground),
                    textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('Minimum \$10 · Maximum \$10,000',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13, color: AppColors.mutedForeground),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),

                // Amount input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Row(children: [
                    Text('\$',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: AppColors.mutedForeground,
                            )),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                        decoration: const InputDecoration(hintText: '0.00', border: InputBorder.none, isCollapsed: true),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                    ),
                  ]),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.destructive, fontSize: 13)),
                  ),
                ],

                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [50, 100, 250, 500].map((v) {
                    return GestureDetector(
                      onTap: () => _setQuick(v.toDouble()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: Text('\$${v.toString()}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 14,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                )),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.40), width: 1),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: AppColors.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Payments processed securely via PayPal',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13, color: AppColors.foreground)),
                    ),
                  ]),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _payViaPayPal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Pay via PayPal'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
