import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/services/points_service.dart';
import 'package:hajj_wallet/supabase/supabase_config.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isCheckingOut = false;

  Future<void> _checkout() async {
    final app = context.read<AppState>();
    if (app.cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your cart is empty')));
      return;
    }
    if (!mounted) return;
    context.push('/checkout');
  }

  static Future<void> handleReturnUrl(BuildContext context, Uri uri) async {
    try {
      // Expect ?token= or ?PayerID= and orderId in query or fragment depending on PayPal flow
      final orderId = uri.queryParameters['orderId'] ?? uri.queryParameters['token'];
      if (orderId == null) {
        debugPrint('No orderId found in return URL');
        return;
      }
      final client = Supabase.instance.client;
      final token = client.auth.currentSession?.accessToken;
      final user = client.auth.currentUser;
      if (token == null || user == null) return;

      final captureRes = await http.post(
        Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/paypal-checkout'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'action': 'captureOrder', 'orderID': orderId, 'type': 'order'}),
      );

      if (captureRes.statusCode < 200 || captureRes.statusCode >= 300) {
        debugPrint('Capture failed: ${captureRes.statusCode} ${captureRes.body}');
        return;
      }

      // Persist order in DB (best-effort; schema assumptions)
      final app = context.read<AppState>();
      final total = app.cartTotal;
      final items = app.cartItems;

      Map<String, dynamic>? orderRow;
      try {
        orderRow = await client.from('orders').insert({
          'user_id': user.id,
          'total_amount': double.parse(total.toStringAsFixed(2)),
          'status': 'paid',
        }).select('id').maybeSingle();
      } catch (e) {
        debugPrint('Insert order failed (ignored): $e');
      }

      final orderIdDb = orderRow?['id'];
      if (orderIdDb != null) {
        for (final it in items) {
          try {
            await client.from('order_items').insert({
              'order_id': orderIdDb,
              'product_id': it.productId,
              'name': it.name,
              'price': it.price + it.variantAdjustment,
              'quantity': it.quantity,
              'color': it.color,
              'size': it.size,
            });
          } catch (e) {
            debugPrint('Insert order_item failed (ignored): $e');
          }
        }
      }

      // Award purchase points
      try {
        await PointsService.awardPoints(user.id, 10, 'purchase', orderId ?? 'paypal');
      } catch (e) {
        debugPrint('Award points failed (ignored): $e');
      }

      app.clearCart();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Order placed successfully!')));
        context.go('/account');
      }
    } catch (e) {
      debugPrint('handleReturnUrl error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.cartItems;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Cart'),
      ),
      body: items.isEmpty
          ? Center(
              child: Text('Your cart is empty', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final it = items[index];
                final price = (it.price + it.variantAdjustment) * it.quantity;
                return Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 1)),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(it.imageUrl, width: 64, height: 64, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${it.color} • ${it.size}  •  x${it.quantity}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                          const SizedBox(height: 6),
                          Text('\$${price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      IconButton(
                        onPressed: () => context.read<AppState>().removeFromCart(it.productId),
                        icon: const Icon(Icons.delete_outline, color: AppColors.destructive),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border, width: 1))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                  const SizedBox(height: 4),
                  Text('\$${app.cartTotal.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                ]),
              ),
              SizedBox(
                width: 180,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isCheckingOut || items.isEmpty ? null : _checkout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: _isCheckingOut
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Review & Pay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
