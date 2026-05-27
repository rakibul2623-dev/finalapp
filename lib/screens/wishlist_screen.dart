import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/components/hajj_card.dart';
import 'package:hajj_wallet/components/fade_in.dart';
import 'package:hajj_wallet/models/cart_item.dart';
import 'package:hajj_wallet/theme.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _products = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refetch();
  }

  Future<void> _refetch() async {
    final wishlistIds = context.read<AppState>().wishlistProductIds;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (wishlistIds.isEmpty) {
        setState(() => _products = []);
      } else {
        final res = await Supabase.instance.client
            .from('products')
            .select()
            .inFilter('id', wishlistIds);
        setState(() => _products = (res as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleWishlist(String productId) {
    context.read<AppState>().toggleWishlist(productId);
    _refetch();
  }

  void _addToCart(Map<String, dynamic> p) {
    final item = CartItem(
      productId: (p['id'] ?? '').toString(),
      name: (p['name'] ?? 'Product').toString(),
      price: ((p['price'] ?? 0) as num).toDouble(),
      quantity: 1,
      imageUrl: (p['image_url'] ?? '').toString(),
      color: '',
      size: '',
      variantAdjustment: 0,
    );
    context.read<AppState>().addToCart(item);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart')));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, app, _) {
      final count = app.wishlistProductIds.length;

      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('Wishlist ($count items)'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: RefreshIndicator(
          onRefresh: _refetch,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _refetch)
                  : count == 0
                      ? _EmptyState(onBrowse: () => context.go('/store'))
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: _products.length,
                            itemBuilder: (context, index) {
                              final p = _products[index];
                              return FadeIn(
                                delay: Duration(milliseconds: 60 * index),
                                child: _ProductTile(
                                  product: p,
                                  onOpen: () => context.push('/product/${p['id']}', extra: p),
                                  onToggleWishlist: () => _toggleWishlist((p['id'] ?? '').toString()),
                                  onAddToCart: () => _addToCart(p),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      );
    });
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBrowse});
  final VoidCallback onBrowse;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_border, size: 64, color: AppColors.silverTier),
          const SizedBox(height: 12),
          Text('Your wishlist is empty', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SizedBox(width: 180, child: OutlinedButton(onPressed: onBrowse, child: const Text('Browse Store'))),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 56, color: AppColors.destructive),
        const SizedBox(height: 8),
        Text('Failed to load wishlist', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onOpen, required this.onToggleWishlist, required this.onAddToCart});
  final Map<String, dynamic> product;
  final VoidCallback onOpen;
  final VoidCallback onToggleWishlist;
  final VoidCallback onAddToCart;
  @override
  Widget build(BuildContext context) {
    final name = (product['name'] ?? 'Product').toString();
    final price = ((product['price'] ?? 0) as num).toDouble();
    final img = (product['image_url'] ?? '').toString();

    return HajjCard(
      onTap: onOpen,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Image
        Stack(children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              child: img.isNotEmpty
                  ? Image.network(img, fit: BoxFit.cover)
                  : Container(color: AppColors.border, child: const Icon(Icons.image_outlined, color: Colors.white)),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onToggleWishlist,
                child: const Padding(
                  padding: EdgeInsets.all(6.0),
                  child: Icon(Icons.favorite, color: Colors.red),
                ),
              ),
            ),
          )
        ]),
        // Content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Text('\$${price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18))),
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: onAddToCart,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
                    child: const Text('Add to Cart'),
                  ),
                ),
              ])
            ]),
          ),
        )
      ]),
    );
  }
}
