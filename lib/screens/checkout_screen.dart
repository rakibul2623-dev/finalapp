import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/supabase/supabase_config.dart';

enum _DeliveryMethod { standard, express, priority }
enum _PaymentMethod { paypal, cod }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _currency = NumberFormat.currency(locale: 'en_US', symbol: '\$');

  bool _summaryExpanded = true;
  bool _notesExpanded = false;
  _DeliveryMethod _delivery = _DeliveryMethod.standard;
  _PaymentMethod _payment = _PaymentMethod.paypal;
  bool _useWallet = false;

  List<Map<String, String>> _addresses = [];
  int? _selectedAddressIndex;

  String? _appliedCoupon;
  bool _isPlacing = false;
  final _emailCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();

  double _shippingCost() {
    switch (_delivery) {
      case _DeliveryMethod.standard:
        return 0.0;
      case _DeliveryMethod.express:
        return 8.0;
      case _DeliveryMethod.priority:
        return 15.0;
    }
  }

  double _tierDiscountPercent(String tier) {
    final t = tier.toLowerCase();
    return (t == 'gold' || t == 'platinum') ? 0.10 : 0.0;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.cartItems;

    final subtotal = items.fold<double>(0.0, (s, it) => s + (it.price + it.variantAdjustment) * it.quantity);
    final couponDiscount = _appliedCoupon != null ? subtotal * 0.05 : 0.0; // visual-only for now
    final tierDisc = subtotal * _tierDiscountPercent(app.currentTier);
    final shipping = _shippingCost();
    final tax = 0.0;
    final preWalletTotal = (subtotal - couponDiscount - tierDisc + shipping + tax).clamp(0.0, double.infinity);
    final walletAvailable = 0.0; // unknown without backend
    final walletApplied = _useWallet ? walletAvailable.clamp(0.0, preWalletTotal) : 0.0;
    final total = (preWalletTotal - walletApplied).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _GlassHeader(),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _Stepper()),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _OrderSummaryCard(
                  expanded: _summaryExpanded,
                  onToggle: () => setState(() => _summaryExpanded = !_summaryExpanded),
                  currency: _currency,
                  items: items
                      .map((e) => _OrderItem(
                            imageUrl: e.imageUrl,
                            name: e.name,
                            variant: [e.color, e.size].where((s) => s != null && s!.isNotEmpty).map((s) => s!).join(' • '),
                            qty: e.quantity,
                            priceEach: (e.price + e.variantAdjustment),
                          ))
                      .toList(),
                  onApplyCoupon: (code) => setState(() => _appliedCoupon = code.isNotEmpty ? code : null),
                  subtotal: subtotal,
                  couponDiscount: couponDiscount,
                  tierDiscount: tierDisc,
                  shipping: shipping,
                  tax: tax,
                  total: total,
                  tierLabel: app.currentTier,
                ),
                const SizedBox(height: 16),
                _AddressCard(
                  addresses: _addresses,
                  selectedIndex: _selectedAddressIndex,
                  onAdd: _openAddAddress,
                  onSelect: (i) => setState(() => _selectedAddressIndex = i),
                ),
                const SizedBox(height: 16),
                _ContactCard(
                  emailController: _emailCtrl,
                  phoneController: _contactPhoneCtrl,
                ),
                const SizedBox(height: 16),
                _DeliveryMethodCard(
                  selected: _delivery,
                  onChanged: (v) => setState(() => _delivery = v),
                ),
                const SizedBox(height: 16),
                _PaymentMethodCard(
                  selected: _payment,
                  onChanged: (v) => setState(() => _payment = v),
                ),
                if (walletAvailable > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _WalletToggle(
                      available: walletAvailable,
                      value: _useWallet,
                      onChanged: (v) => setState(() => _useWallet = v),
                    ),
                  ),
                const SizedBox(height: 16),
                _NotesCard(
                  expanded: _notesExpanded,
                  onToggle: () => setState(() => _notesExpanded = !_notesExpanded),
                  onChanged: (s) {},
                ),
                const SizedBox(height: 16),
                const _TrustRow(),
                const SizedBox(height: 120),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _PayBar(
        totalText: _currency.format(total),
        payment: _payment,
        loading: _isPlacing,
        onPay: items.isEmpty
            ? null
            : () async {
                await _placeOrder();
              },
      ),
    );
  }

  Future<void> _placeOrder() async {
    if (_isPlacing) return;
    final app = context.read<AppState>();
    final items = app.cartItems;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your cart is empty')));
      return;
    }
    if (_selectedAddressIndex == null || _selectedAddressIndex! < 0 || _selectedAddressIndex! >= _addresses.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add and select a delivery address')));
      return;
    }
    final email = _emailCtrl.text.trim();
    final phone = _contactPhoneCtrl.text.trim();
    if (email.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide your contact email and phone')));
      return;
    }

    setState(() => _isPlacing = true);
    try {
      // Prepare order payload
      final addr = _addresses[_selectedAddressIndex!];
      final shippingAddress = '${addr['full_name'] ?? ''}\n${addr['line1'] ?? ''}${(addr['line2']?.isNotEmpty ?? false) ? ', ' + (addr['line2']!) : ''}\n${addr['city'] ?? ''} ${(addr['postal'] ?? '')} ${(addr['country'] ?? '')}\n${addr['phone'] ?? ''}';

      final appItems = items
          .map((e) => {
                'product_id': e.productId,
                'name': e.name,
                'quantity': e.quantity,
                'price': (e.price + e.variantAdjustment),
                'image_url': e.imageUrl,
                'color': e.color,
                'size': e.size,
              })
          .toList();

      final subtotal = items.fold<double>(0.0, (s, it) => s + (it.price + it.variantAdjustment) * it.quantity);
      final couponDiscount = _appliedCoupon != null ? subtotal * 0.05 : 0.0;
      final tierDisc = subtotal * _tierDiscountPercent(context.read<AppState>().currentTier);
      final shipping = _shippingCost();
      final tax = 0.0;
      final total = (subtotal - couponDiscount - tierDisc + shipping + tax).clamp(0.0, double.infinity);

      // Create order in Supabase using the existing self-hosted config
      final userId = SupabaseConfig.auth.currentUser?.id; // may be null if guest
      final payload = {
        'user_id': userId,
        'status': 'pending',
        'payment_method': _payment == _PaymentMethod.paypal ? 'paypal' : 'cod',
        'delivery_method': switch (_delivery) {
          _DeliveryMethod.standard => 'standard',
          _DeliveryMethod.express => 'express',
          _DeliveryMethod.priority => 'priority',
        },
        'subtotal': subtotal,
        'discount_amount': (couponDiscount + tierDisc),
        'shipping_amount': shipping,
        'tax_amount': tax,
        'total_amount': total,
        'coupon_code': _appliedCoupon,
        'contact_email': email,
        'contact_phone': phone,
        'shipping_address': shippingAddress,
        'items': appItems, // store as JSON column
        'notes': null,
      };

      await SupabaseService.insert('orders', payload);

      if (!mounted) return;
      context.read<AppState>().clearCart();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed successfully')));
      context.go('/my-orders');
    } catch (e) {
      debugPrint('Checkout failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checkout failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _isPlacing = false);
    }
  }

  Future<void> _openAddAddress() async {
    final res = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AddressFormSheet(),
    );
    if (res != null) {
      setState(() {
        _addresses.add(res);
        _selectedAddressIndex = _addresses.length - 1;
      });
    }
  }
}

class _GlassHeader extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      backgroundColor: Colors.white.withValues(alpha: 0.85),
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text('Checkout', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.foreground)),
      leading: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: IconButton(
          onPressed: () => context.pop(),
          style: IconButton.styleFrom(backgroundColor: Colors.white, shape: const CircleBorder(), side: const BorderSide(color: AppColors.border)),
          icon: const Icon(Icons.arrow_back, color: AppColors.foreground),
        ),
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 12),
          child: Icon(Icons.lock_outline, color: AppColors.mutedForeground),
        )
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper();
  @override
  Widget build(BuildContext context) {
    Widget node({required bool done, required bool active, required String label}) {
      final color = active || done ? AppColors.primary : AppColors.mutedForeground;
      return Expanded(
        child: Column(
          children: [
            Row(children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: done || active ? AppColors.primary : Colors.white, border: Border.all(color: color, width: 2), shape: BoxShape.circle),
                child: done ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
              ),
              Expanded(child: Container(height: 2, color: color.withValues(alpha: 0.4), margin: const EdgeInsets.symmetric(horizontal: 8))),
            ]),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        node(done: true, active: false, label: 'Cart'),
        node(done: true, active: false, label: 'Address'),
        node(done: false, active: true, label: 'Payment'),
      ]),
    );
  }
}

class _OrderItem {
  final String imageUrl;
  final String name;
  final String variant;
  final int qty;
  final double priceEach;
  const _OrderItem({required this.imageUrl, required this.name, required this.variant, required this.qty, required this.priceEach});
}

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({
    required this.expanded,
    required this.onToggle,
    required this.currency,
    required this.items,
    required this.onApplyCoupon,
    required this.subtotal,
    required this.couponDiscount,
    required this.tierDiscount,
    required this.shipping,
    required this.tax,
    required this.total,
    required this.tierLabel,
  });
  final bool expanded;
  final VoidCallback onToggle;
  final NumberFormat currency;
  final List<_OrderItem> items;
  final ValueChanged<String> onApplyCoupon;
  final double subtotal;
  final double couponDiscount;
  final double tierDiscount;
  final double shipping;
  final double tax;
  final double total;
  final String tierLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [
        BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
      ], border: Border.all(color: AppColors.border, width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Text('Order Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.foreground)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(999)),
                child: Text('${items.fold<int>(0, (s, e) => s + e.qty)}', style: Theme.of(context).textTheme.labelSmall),
              ),
              const Spacer(),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.mutedForeground),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          firstChild: const SizedBox.shrink(),
          secondChild: Column(children: [
            const Divider(height: 1, color: AppColors.border),
            ...items.map((e) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(e.imageUrl, width: 56, height: 56, fit: BoxFit.cover)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${e.variant} • x${e.qty}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                    ])),
                    Text(currency.format(e.priceEach * e.qty), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                )),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.border)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      onChanged: onApplyCoupon,
                      decoration: const InputDecoration.collapsed(hintText: 'Promo code'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), side: const BorderSide(color: AppColors.primary, width: 1.4), foregroundColor: AppColors.primary),
                    child: const Text('Apply'),
                  ),
                )
              ]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            _KVRow(label: 'Subtotal', value: currency.format(subtotal)),
            if (couponDiscount > 0) _KVRow(label: 'Discount', value: '-${currency.format(couponDiscount)}', valueColor: AppColors.primary),
            if (tierDiscount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFFE7A3), Color(0xFFFFF3D1)]),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Color(0xFFE9C46A)),
                    ),
                    child: Text('-10% $tierLabel', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Color(0xFF946200), fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text('-${currency.format(tierDiscount)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                ]),
              ),
            _KVRow(label: 'Shipping', value: shipping == 0 ? 'Free' : currency.format(shipping)),
            _KVRow(label: 'Tax', value: currency.format(tax)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(children: [
                Text('TOTAL', style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800, color: AppColors.foreground)),
                const Spacer(),
                Text(currency.format(total), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
              ]),
            )
          ]),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        ),
      ]),
    );
  }
}

class _KVRow extends StatelessWidget {
  const _KVRow({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground)),
        const Spacer(),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: valueColor ?? AppColors.foreground, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.addresses, required this.selectedIndex, required this.onAdd, required this.onSelect});
  final List<Map<String, String>> addresses;
  final int? selectedIndex;
  final VoidCallback onAdd;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border, width: 1)),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Shipping Address', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          if (addresses.isNotEmpty) TextButton(onPressed: onAdd, child: const Text('Edit')),
        ]),
        const SizedBox(height: 8),
        if (addresses.isEmpty)
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 64,
              decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 1)),
              child: Center(child: Text('+ Add address', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground))),
            ),
          )
        else
          Column(
            children: List.generate(addresses.length, (i) {
              final a = addresses[i];
              final selected = selectedIndex == i;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1)),
                    padding: const EdgeInsets.all(12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.primary : AppColors.mutedForeground),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a['full_name'] ?? '', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${a['line1'] ?? ''}${(a['line2']?.isNotEmpty ?? false) ? ', ' + (a['line2']!) : ''}', style: Theme.of(context).textTheme.labelSmall),
                          Text('${a['city'] ?? ''} ${(a['postal'] ?? '')} ${(a['country'] ?? '')}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                          const SizedBox(height: 6),
                          Text(a['phone'] ?? '', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                        ]),
                      ),
                      TextButton(onPressed: onAdd, child: const Text('Edit')),
                    ]),
                  ),
                ),
              );
            }),
          )
      ]),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.emailController, required this.phoneController});
  final TextEditingController emailController;
  final TextEditingController phoneController;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Contact Info', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        _TextField(controller: emailController, label: 'Email', keyboardType: TextInputType.emailAddress),
        _TextField(controller: phoneController, label: 'Phone (for delivery updates)', keyboardType: TextInputType.phone),
      ]),
    );
  }
}

class _AddressFormSheet extends StatefulWidget {
  const _AddressFormSheet();
  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _country = TextEditingController();
  bool _saveForFuture = true;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 48, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 12),
              Text('Add address', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _TextField(controller: _fullName, label: 'Full name', validator: _required),
              _TextField(controller: _phone, label: 'Phone', keyboardType: TextInputType.phone, validator: _required),
              _TextField(controller: _line1, label: 'Address line 1', validator: _required),
              _TextField(controller: _line2, label: 'Address line 2 (optional)'),
              Row(children: [
                Expanded(child: _TextField(controller: _city, label: 'City', validator: _required)),
                const SizedBox(width: 12),
                Expanded(child: _TextField(controller: _postal, label: 'Postal', validator: _required)),
              ]),
              _TextField(controller: _country, label: 'Country', validator: _required),
              const SizedBox(height: 8),
              Row(children: [
                Switch(value: _saveForFuture, onChanged: (v) => setState(() => _saveForFuture = v)),
                const SizedBox(width: 8),
                Expanded(child: Text('Save for future orders', style: Theme.of(context).textTheme.bodyMedium)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState?.validate() != true) return;
                    Navigator.of(context).pop({
                      'full_name': _fullName.text.trim(),
                      'phone': _phone.text.trim(),
                      'line1': _line1.text.trim(),
                      'line2': _line2.text.trim(),
                      'city': _city.text.trim(),
                      'postal': _postal.text.trim(),
                      'country': _country.text.trim(),
                      'save': _saveForFuture.toString(),
                    });
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                  child: const Text('Save address'),
                ),
              )
            ]),
          ),
        ),
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
}

class _TextField extends StatelessWidget {
  const _TextField({required this.controller, required this.label, this.keyboardType, this.validator});
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.inputBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
        ),
      ),
    );
  }
}

class _DeliveryMethodCard extends StatelessWidget {
  const _DeliveryMethodCard({required this.selected, required this.onChanged});
  final _DeliveryMethod selected;
  final ValueChanged<_DeliveryMethod> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget option(_DeliveryMethod value, String title, String subtitle, String price) {
      final active = selected == value;
      return InkWell(
        onTap: () => onChanged(value),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? AppColors.primary : AppColors.border, width: active ? 1.6 : 1)),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(active ? Icons.radio_button_checked : Icons.radio_button_off, color: active ? AppColors.primary : AppColors.mutedForeground),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
            ])),
            Text(price, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Delivery Method', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        option(_DeliveryMethod.standard, 'Standard', '5-7 days', 'Free'),
        const SizedBox(height: 10),
        option(_DeliveryMethod.express, 'Express', '2-3 days', '\$8.00'),
        const SizedBox(height: 10),
        option(_DeliveryMethod.priority, 'Priority', '1-2 days', '\$15.00'),
      ]),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({required this.selected, required this.onChanged});
  final _PaymentMethod selected;
  final ValueChanged<_PaymentMethod> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget option(_PaymentMethod value, String title, String subtitle) {
      final active = selected == value;
      return InkWell(
        onTap: () => onChanged(value),
        child: Container(
          decoration: BoxDecoration(color: active ? AppColors.primary.withValues(alpha: 0.06) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? AppColors.primary : AppColors.border, width: active ? 1.6 : 1)),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(active ? Icons.radio_button_checked : Icons.radio_button_off, color: active ? AppColors.primary : AppColors.mutedForeground),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
            ])),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Payment Method', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        option(_PaymentMethod.paypal, 'PayPal', 'Pay securely with PayPal'),
        const SizedBox(height: 10),
        option(_PaymentMethod.cod, 'Cash on Delivery', 'Pay when you receive'),
      ]),
    );
  }
}

class _WalletToggle extends StatelessWidget {
  const _WalletToggle({required this.available, required this.value, required this.onChanged});
  final double available;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(child: Text('Use wallet balance (\$${available.toStringAsFixed(2)} available)', style: Theme.of(context).textTheme.bodyMedium)),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.expanded, required this.onToggle, required this.onChanged});
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              Text('Order Notes (optional)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.mutedForeground),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              maxLines: 4,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Add note for seller (optional)',
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
              ),
            ),
          ),
        )
      ]),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow();
  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String text) => Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: AppColors.mutedForeground, size: 18),
            const SizedBox(width: 6),
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground))),
          ]),
        );
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        item(Icons.verified_user_outlined, 'Secure SSL'),
        item(Icons.cached, 'Easy returns'),
        item(Icons.bolt, 'Fast support'),
      ]),
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({required this.totalText, required this.payment, required this.loading, required this.onPay});
  final String totalText;
  final _PaymentMethod payment;
  final bool loading;
  final VoidCallback? onPay;
  @override
  Widget build(BuildContext context) {
    final label = payment == _PaymentMethod.paypal ? 'Pay $totalText with PayPal' : 'Place Order';
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), border: const Border(top: BorderSide(color: AppColors.border)), boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, -8)),
      ]),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Total', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
            const Spacer(),
            Text(totalText, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: loading ? null : onPay,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
              child: loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
      ),
    );
  }
}
