import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hajj_wallet/components/fade_in.dart';
import 'package:hajj_wallet/components/hajj_card.dart';
import 'package:hajj_wallet/theme.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _orders = [];
          _loading = false;
        });
        return;
      }
      final data = await _supabase
          .from('orders')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final list = (data as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _filtered(String tab, List<Map<String, dynamic>> input) {
    if (tab == 'All') return input;
    if (tab == 'Active') {
      return input.where((o) {
        final s = (o['status'] ?? '').toString();
        return s == 'pending' || s == 'paid' || s == 'shipped';
      }).toList();
    }
    // Completed
    return input.where((o) {
      final s = (o['status'] ?? '').toString();
      return s == 'delivered' || s == 'cancelled';
    }).toList();
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.blue;
      case 'shipped':
        return Colors.purple;
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.destructive;
      default:
        return AppColors.border;
    }
  }

  String _orderIdShort(String id) => id.length <= 8 ? id : id.substring(id.length - 8);

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.tryParse(iso);
      if (dt == null) return '';
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> _parseItems(dynamic raw) {
    try {
      if (raw == null) return const [];
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.cast<Map<String, dynamic>>();
        return const [];
      }
      if (raw is List) {
        return raw.cast<Map<String, dynamic>>();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  String _itemsPreview(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return 'No items';
    final names = items.map((e) => (e['name'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
    if (names.isEmpty) return 'No items';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} and ${names.length - 2} more';
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final items = _parseItems(order['items']);
    final total = (order['total_amount'] is num) ? (order['total_amount'] as num).toDouble() : 0.0;
    final paymentMethod = (order['payment_method'] ?? '').toString();
    final address = (order['shipping_address'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Order ${_orderIdShort(order['id'].toString())}', style: Theme.of(context).textTheme.titleLarge?.semiBold),
                      Text('\$${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.semiBold?.withColor(AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Placed on ${_formatDate(order['created_at']?.toString())}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Text('Items', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ...items.map((it) {
                    final name = (it['name'] ?? '').toString();
                    final qty = (it['quantity'] ?? it['qty'] ?? 1).toString();
                    final price = (it['price'] is num) ? (it['price'] as num).toDouble() : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(child: Text(name, style: Theme.of(context).textTheme.bodyMedium)),
                          Text('x$qty', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(width: 12),
                          Text('\$${price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.semiBold),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 32),
                  Text('Shipping Address', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(address.isEmpty ? '—' : address, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Text('Payment Method', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(paymentMethod.isEmpty ? '—' : paymentMethod, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Orders'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          bottom: const TabBar(tabs: [
            Tab(text: 'All'),
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
          ]),
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: Builder(
            builder: (context) {
              if (_loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_error != null) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    Icon(Icons.error_outline, size: 48, color: AppColors.destructive),
                    const SizedBox(height: 12),
                    Text('Failed to load orders', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    Align(
                      child: OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                );
              }

              return TabBarView(
                children: [
                  _OrdersList(orders: _filtered('All', _orders), onTap: _showOrderDetails),
                  _OrdersList(orders: _filtered('Active', _orders), onTap: _showOrderDetails),
                  _OrdersList(orders: _filtered('Completed', _orders), onTap: _showOrderDetails),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final bg = _statusBg(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(status, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _orderCard(Map<String, dynamic> order, int index) {
    final id = (order['id'] ?? '').toString();
    final status = (order['status'] ?? '').toString();
    final createdAt = order['created_at']?.toString();
    final items = _parseItems(order['items']);
    final total = (order['total_amount'] is num) ? (order['total_amount'] as num).toDouble() : 0.0;
    return FadeIn(
      delay: Duration(milliseconds: 40 * index),
      child: HajjCard(
        onTap: () => _showOrderDetails(order),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_orderIdShort(id), style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.foreground)),
                const SizedBox(width: 8),
                _statusChip(status),
                const Spacer(),
                Text(_formatDate(createdAt), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(_itemsPreview(items), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                Text('\$${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.semiBold?.withColor(AppColors.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final void Function(Map<String, dynamic>) onTap;
  const _OrdersList({required this.orders, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.shopping_bag_outlined, size: 64, color: AppColors.mutedForeground),
          const SizedBox(height: 12),
          Text('No orders yet', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Start exploring our store and place your first order.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Align(
            child: OutlinedButton.icon(
              onPressed: () => context.go('/store'),
              icon: const Icon(Icons.store_mall_directory_outlined),
              label: const Text('Browse Store'),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final screenState = context.findAncestorStateOfType<_MyOrdersScreenState>();
        if (screenState == null) return const SizedBox.shrink();
        return screenState._orderCard(orders[i], i);
      },
    );
  }
}
