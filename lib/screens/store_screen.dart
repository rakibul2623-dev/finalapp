import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/models/cart_item.dart';
import 'package:intl/intl.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  // Filters
  String selectedCategory = 'All';
  String searchQuery = '';
  String sortOption = 'newest'; // newest | price_asc | price_desc

  // Data state
  final List<String> _categories = <String>['All'];
  final List<Map<String, dynamic>> _products = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _featured = <Map<String, dynamic>>[];
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  String? _error;

  // UI state
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _scrollCtrl.addListener(_onScroll);
    _initLoad();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        searchQuery = _searchCtrl.text.trim();
      });
      _reload();
    });
  }

  Future<void> _initLoad() async {
    await Future.wait([
      _loadCategories(),
      _loadFeatured(),
    ]);
    await _loadPage(reset: true);
  }

  Future<void> _loadCategories() async {
    try {
      final res = await Supabase.instance.client
          .from('products')
          .select('category')
          .not('category', 'is', null)
          .order('category', ascending: true) as List<dynamic>;
      final set = <String>{};
      for (final row in res) {
        final c = (row['category'] ?? '').toString().trim();
        if (c.isNotEmpty) set.add(c);
      }
      setState(() {
        _categories
          ..clear()
          ..add('All')
          ..addAll(set.toList());
      });
    } catch (e) {
      // Fallback when backend not connected
      debugPrint('Categories fallback due to error: $e');
      setState(() {
        _categories
          ..clear()
          ..addAll(['All', 'Apparel', 'Accessories', 'Books', 'Gear']);
      });
    }
  }

  void _onScroll() {
    if (_loadingInitial || _loadingMore || !_hasMore) return;
    if (_scrollCtrl.position.pixels > _scrollCtrl.position.maxScrollExtent - 600) {
      _loadPage();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
      _hasMore = true;
      _offset = 0;
      _products.clear();
    });
    await _loadPage(reset: true);
  }

  Future<void> _loadFeatured() async {
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id,name,price,compare_at_price,image_url,category')
          .eq('is_featured', true)
          .order('created_at', ascending: false)
          .limit(8) as List<dynamic>;
      setState(() {
        _featured
          ..clear()
          ..addAll(rows.cast<Map<String, dynamic>>());
      });
    } catch (e) {
      debugPrint('Featured load failed: $e');
      setState(() => _featured.clear());
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    try {
      if (reset) {
        setState(() => _loadingInitial = true);
      } else {
        setState(() => _loadingMore = true);
      }

      final client = Supabase.instance.client;
      dynamic query = client.from('products').select('*').or('stock.eq.-1,stock.gt.0');
      if (selectedCategory != 'All') {
        query = query.eq('category', selectedCategory);
      }
      if (searchQuery.isNotEmpty) {
        query = query.ilike('name', '%$searchQuery%');
      }
      if (sortOption == 'price_asc') {
        query = query.order('price', ascending: true);
      } else if (sortOption == 'price_desc') {
        query = query.order('price', ascending: false);
      } else {
        query = query.order('created_at', ascending: false);
      }

      final rows = await query.range(_offset, _offset + 11) as List<dynamic>;
      final list = rows.cast<Map<String, dynamic>>();
      setState(() {
        _products.addAll(list);
        _offset += list.length;
        _hasMore = list.length == 12;
        _loadingInitial = false;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('Products load failed, using fallback: $e');
      // Fallback demo data
      if (reset) {
        final placeholders = List.generate(12, (i) => {
              'id': 'demo-$i',
              'name': i % 3 == 0 ? 'Premium Ihram Set' : (i % 3 == 1 ? 'Prayer Beads (Misbaha)' : 'Hajj Guide Book'),
              'price': i % 3 == 0 ? 120.0 : (i % 3 == 1 ? 24.0 : 16.0),
              'image_url': '',
              'category': i % 3 == 0 ? 'Apparel' : (i % 3 == 1 ? 'Accessories' : 'Books'),
              'stock': i % 5 == 0 ? 0 : (i % 4) + 1,
              'rating': 4.5,
              'is_limited': i % 7 == 0,
            });
        setState(() {
          _products
            ..clear()
            ..addAll(placeholders);
          _loadingInitial = false;
          _hasMore = false;
          _loadingMore = false;
          _error = null;
        });
      } else {
        setState(() {
          _loadingMore = false;
          _hasMore = false;
        });
      }
    }
  }

  void _retryCategories() => _loadCategories();
  void _retryProducts() => _reload();

  void _onSelectCategory(String value) {
    setState(() {
      selectedCategory = value;
    });
    _reload();
  }

  void _onChangeSort(String value) {
    setState(() {
      sortOption = value;
    });
    _reload();
  }

  void _addToCart(BuildContext context, Map<String, dynamic> p) {
    final app = context.read<AppState>();
    final id = (p['id'] ?? '').toString();
    final name = (p['name'] ?? '').toString();
    final price = ((p['price'] as num?) ?? 0).toDouble();
    final imageUrl = (p['image_url'] ?? '').toString();

    final existing = app.cartItems.indexWhere((e) => e.productId == id);
    if (existing >= 0) {
      app.addToCart(app.cartItems[existing]);
    } else {
      app.addToCart(CartItem(
        productId: id,
        name: name,
        price: price,
        quantity: 1,
        imageUrl: imageUrl,
        color: 'default',
        size: 'std',
        variantAdjustment: 0,
      ));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Added to cart'),
        action: SnackBarAction(
          label: 'View Cart',
          onPressed: () => context.go('/cart'),
        ),
      ),
    );
  }

  Future<void> _toggleWishlist(BuildContext context, Map<String, dynamic> p) async {
    final app = context.read<AppState>();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final productId = (p['id'] ?? '').toString();
    final isWished = app.wishlistProductIds.contains(productId);
    try {
      // Toggle locally first for immediate feedback
      app.toggleWishlist(productId);
      // Sync to backend if logged in
      if (uid != null) {
        if (isWished) {
          await Supabase.instance.client
              .from('wishlists')
              .delete()
              .eq('user_id', uid)
              .eq('product_id', productId);
        } else {
          await Supabase.instance.client
              .from('wishlists')
              .insert({'user_id': uid, 'product_id': productId});
        }
      }
    } catch (e) {
      debugPrint('Wishlist toggle failed: $e');
      // Keep local state; if needed, inform the user softly
      if (uid != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to sync wishlist. Will retry later.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cartCount = app.cartItems.fold<int>(0, (sum, e) => sum + e.quantity);

    return SafeArea(
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 64,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            elevation: 0,
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    border: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
                  ),
                ),
              ),
            ),
            title: Text('Store', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            leading: Builder(
              builder: (ctx) {
                final canPop = Navigator.of(ctx).canPop();
                if (!canPop) return const SizedBox.shrink();
                return IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.foreground),
                );
              },
            ),
            actions: [
              IconButton(
                tooltip: 'Wishlist',
                onPressed: () => context.go('/wishlist'),
                icon: const Icon(Icons.favorite_border, color: AppColors.foreground),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Cart',
                    onPressed: () => context.go('/cart'),
                    icon: const Icon(Icons.shopping_bag_outlined, color: AppColors.foreground),
                  ),
                  if (cartCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: const BoxDecoration(color: AppColors.destructive, borderRadius: BorderRadius.all(Radius.circular(10))),
                        child: Text(
                          cartCount > 99 ? '99+' : '$cartCount',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
            ],
          ),

          _buildHeroBanner(),
          if (_featured.isNotEmpty) _buildFeaturedRow(context, _featured),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              minExtent: 74,
              maxExtent: 88,
              child: _SearchBar(
                controller: _searchCtrl,
                onFilterTap: () => _showSortSheet(context),
                sortOption: sortOption,
                onSortChanged: _onChangeSort,
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              minExtent: 48,
              maxExtent: 56,
              child: _CategoryChips(
                categories: _categories,
                selected: selectedCategory,
                onSelected: _onSelectCategory,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text('${_products.length} results', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          if (_loadingInitial)
            const SliverToBoxAdapter(child: _ProductGridSkeleton()),
          if (!_loadingInitial)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Approximate 280px height on common widths
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final p = _products[index];
                    return _AnimatedFadeUp(
                      index: index,
                      child: StoreProductCardPremium(
                        product: p,
                        onAddToCart: () => _addToCart(context, p),
                        onToggleWishlist: () => _toggleWishlist(context, p),
                      ),
                    );
                  },
                  childCount: _products.length,
                ),
              ),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              ListTile(
                title: const Text('Newest'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onChangeSort('newest');
                },
              ),
              ListTile(
                title: const Text('Price: Low → High'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onChangeSort('price_asc');
                },
              ),
              ListTile(
                title: const Text('Price: High → Low'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onChangeSort('price_desc');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  SliverToBoxAdapter _buildHeroBanner() {
    return SliverToBoxAdapter(
      child: Container(
        height: 140,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF15803D), Color(0xFF16A34A)],
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Stack(
          children: [
            // Subtle geometric overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.06,
                  child: CustomPaint(painter: _PatternPainter()),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Text('COMMUNITY STORE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, letterSpacing: 0.6)),
                ),
                const SizedBox(height: 10),
                Text('Shop with Purpose', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                Text('Premium Hajj essentials', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.80))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

  SliverToBoxAdapter _buildFeaturedRow(BuildContext context, List<Map<String, dynamic>> featured) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Featured Products', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  TextButton(onPressed: () => context.go('/store'), child: const Text('View All')),
                ],
              ),
            ),
            SizedBox(
              height: 180,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemBuilder: (ctx, i) {
                  final p = featured[i];
                  final id = (p['id'] ?? '').toString();
                  final name = (p['name'] ?? '').toString();
                  final price = ((p['price'] as num?) ?? 0).toDouble();
                  final compareAt = (p['compare_at_price'] as num?)?.toDouble();
                  final imageUrl = (p['image_url'] ?? '').toString();
                  final priceText = NumberFormat('#,##0.00', 'en_US').format(price);
                  return GestureDetector(
                    onTap: () => context.push('/product/$id', extra: p),
                    child: Container(
                      width: 140,
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16), boxShadow: [
                        BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))
                      ]),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 100,
                            width: double.infinity,
                            child: Stack(children: [
                              Positioned.fill(
                                child: imageUrl.isNotEmpty
                                    ? Image.network(imageUrl, fit: BoxFit.cover)
                                    : Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF15803D), Color(0xFF16A34A)]),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                      ),
                              ),
                              if (compareAt != null && compareAt > price)
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFFF4B4B), borderRadius: BorderRadius.circular(999)),
                                    child: const Text('-SALE-', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                            ]),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                  const Spacer(),
                                  Text('\$'+priceText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: featured.length.clamp(0, 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.minExtent, required this.maxExtent, required this.child});
  @override
  final double minExtent;
  @override
  final double maxExtent;
  final Widget child;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), offset: const Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.minExtent != minExtent || oldDelegate.maxExtent != maxExtent || oldDelegate.child != child;
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onFilterTap, required this.sortOption, required this.onSortChanged});
  final TextEditingController controller;
  final VoidCallback onFilterTap;
  final String sortOption;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final sortLabel = sortOption == 'newest'
        ? 'Newest'
        : sortOption == 'price_asc'
            ? 'Price: Low → High'
            : 'Price: High → Low';
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Search products',
                prefixIcon: const Icon(Icons.search, color: AppColors.mutedForeground),
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(color: AppColors.border, width: 1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Persistent Sort control
          PopupMenuButton<String>(
            tooltip: 'Sort',
            initialValue: sortOption,
            onSelected: onSortChanged,
            position: PopupMenuPosition.under,
            itemBuilder: (ctx) => [
              const PopupMenuItem<String>(value: 'newest', child: Text('Newest')),
              const PopupMenuItem<String>(value: 'price_asc', child: Text('Price: Low → High')),
              const PopupMenuItem<String>(value: 'price_desc', child: Text('Price: High → Low')),
            ],
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sort, size: 18, color: AppColors.mutedForeground),
                  const SizedBox(width: 6),
                  Text(sortLabel, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.foreground, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onFilterTap,
            icon: const Icon(Icons.filter_list, color: AppColors.foreground),
          ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.categories, required this.selected, required this.onSelected});
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      height: 56,
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final label = categories[index];
          final isSelected = label == selected;
          return GestureDetector(
            onTap: () => onSelected(label),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 1),
              ),
              child: Text(
                label == 'all' ? 'All' : label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected ? Colors.white : AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
              ),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: categories.length,
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAddToCart, required this.onToggleWishlist});
  final Map<String, dynamic> product;
  final VoidCallback onAddToCart;
  final VoidCallback onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final id = (product['id'] ?? '').toString();
    final name = (product['name'] ?? '').toString();
    final price = ((product['price'] as num?) ?? 0).toDouble();
    final imageUrl = (product['image_url'] ?? '').toString();
    final category = (product['category'] ?? '').toString();
    final stock = (product['stock'] as int?) ?? -1; // -1 means unlimited
    final rating = ((product['rating'] as num?) ?? 0).toDouble();
    final isLimited = (product['is_limited'] as bool?) ?? false;
    final isWished = app.wishlistProductIds.contains(id);

    return GestureDetector(
      onTap: () => context.push('/product/$id', extra: product),
      child: Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Container(
                      color: AppColors.inputBackground,
                      child: imageUrl.isNotEmpty
                          ? Image.network(imageUrl, fit: BoxFit.cover)
                          : const Icon(Icons.image_outlined, size: 48, color: AppColors.mutedForeground),
                    ),
                  ),
                ),
                if (stock == 0)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.50),
                      alignment: Alignment.center,
                      child: Text('Out of Stock', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                    ),
                  ),
                if (stock > 0 && stock <= 5)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text('Only $stock left', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.foreground)),
                    ),
                  ),
                if (isLimited)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.border, width: 1),
                      ),
                      child: Text('Limited', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.foreground, fontWeight: FontWeight.w700)),
                    ),
                  ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: InkWell(
                    onTap: onToggleWishlist,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 1),
                      ),
                      child: Icon(isWished ? Icons.favorite : Icons.favorite_border, color: isWished ? AppColors.destructive : AppColors.foreground, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground, letterSpacing: 1.0, fontSize: 11)),
                const SizedBox(height: 4),
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _Stars(rating: rating),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('\$${price.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    InkWell(
                      onTap: (stock == -1 || stock > 0) ? onAddToCart : null,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.add, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});
  final double rating;
  @override
  Widget build(BuildContext context) {
    final stars = List.generate(5, (i) {
      final value = rating - i;
      IconData icon;
      if (value >= 1) {
        icon = Icons.star;
      } else if (value >= 0.5) {
        icon = Icons.star_half;
      } else {
        icon = Icons.star_border;
      }
      return Icon(icon, color: AppColors.accent, size: 16);
    });
    return Row(children: stars);
  }
}

// Premium product card (new design)
class StoreProductCardPremium extends StatelessWidget {
  const StoreProductCardPremium({super.key, required this.product, required this.onAddToCart, required this.onToggleWishlist});
  final Map<String, dynamic> product;
  final VoidCallback onAddToCart;
  final VoidCallback onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final id = (product['id'] ?? '').toString();
    final name = (product['name'] ?? '').toString();
    final price = ((product['price'] as num?) ?? 0).toDouble();
    final compareAt = (product['compare_at_price'] as num?)?.toDouble();
    final imageUrl = (product['image_url'] ?? '').toString();
    final category = (product['category'] ?? '').toString();
    final stock = (product['stock_quantity'] as int?) ?? (product['stock'] as int?) ?? -1;
    final rating = ((product['rating'] as num?) ?? 0).toDouble();
    final reviews = (product['review_count'] as int?) ?? 0;
    final isLimited = (product['is_limited'] as bool?) ?? false;
    final isWished = app.wishlistProductIds.contains(id);

    final priceText = NumberFormat('#,##0.00', 'en_US').format(price);
    final compareText = compareAt != null ? NumberFormat('#,##0.00', 'en_US').format(compareAt) : null;

    return GestureDetector(
      onTap: () => context.push('/product/$id', extra: product),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
          decoration: BoxDecoration(
          color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: [BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Container(
                        color: AppColors.inputBackground,
                        child: imageUrl.isNotEmpty
                            ? Image.network(imageUrl, fit: BoxFit.cover)
                            : const Icon(Icons.image_outlined, size: 48, color: AppColors.mutedForeground),
                      ),
                    ),
                  ),
                  if (compareAt != null && compareAt > price)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFF4B4B), borderRadius: BorderRadius.circular(999)),
                        child: Text('-${(((compareAt - price) / compareAt) * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  if (stock == 0)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.50),
                        alignment: Alignment.center,
                        child: Text('Out of Stock', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                      ),
                    ),
                  if (stock > 0 && stock <= 5)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFFE8B3), borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: Text('Only $stock left', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF8B5E00))),
                      ),
                    ),
                  if (isLimited)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: AppColors.border, width: 1)),
                        child: Text('Limited', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.foreground, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: InkWell(
                      onTap: onToggleWishlist,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 1)),
                        child: Icon(isWished ? Icons.favorite : Icons.favorite_border, color: isWished ? AppColors.destructive : AppColors.foreground, size: 20),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: (stock == -1 || stock > 0) ? onAddToCart : null,
                      child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 20)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF6B7280), letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                  const SizedBox(height: 6),
                  Row(children: [
                    _Stars(rating: rating),
                    const SizedBox(width: 6),
                    if (reviews > 0) Text('($reviews)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground)),
                  ]),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('\$'+priceText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                        if (compareText != null) Text('\$'+compareText, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground, decoration: TextDecoration.lineThrough)),
                      ]),
                      if (stock == 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFFD5D5), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFFFB1B1))),
                          child: Text('OUT OF STOCK', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF8C1D1D), fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Skeleton shimmer grid while products load
class _ProductGridSkeleton extends StatefulWidget {
  const _ProductGridSkeleton();
  @override
  State<_ProductGridSkeleton> createState() => _ProductGridSkeletonState();
}

class _ProductGridSkeletonState extends State<_ProductGridSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72),
        itemBuilder: (ctx, i) => _Shimmer(ac: _ac, child: _skeletonCard()),
      ),
    );
  }

  Widget _skeletonCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Container(height: 140, decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)))),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _block(width: 60, height: 10),
            const SizedBox(height: 8),
            _block(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            _block(width: 100, height: 10),
            const SizedBox(height: 10),
            _block(width: 80, height: 14),
          ]),
        )
      ]),
    );
  }

  Widget _block({required double width, required double height}) => Container(width: width, height: height, decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(6)));
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.ac, required this.child});
  final AnimationController ac;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ac,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (rect) {
            final gradient = LinearGradient(
              begin: Alignment(-1.0 + ac.value * 2, 0),
              end: Alignment(1.0 + ac.value * 2, 0),
              colors: [
                Colors.white.withValues(alpha: 0.2),
                Colors.white.withValues(alpha: 0.5),
                Colors.white.withValues(alpha: 0.2),
              ],
              stops: const [0.2, 0.5, 0.8],
            );
            return gradient.createShader(Rect.fromLTWH(0, 0, rect.width, rect.height));
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }
}

class _AnimatedFadeUp extends StatelessWidget {
  const _AnimatedFadeUp({required this.child, required this.index});
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Transform.translate(offset: Offset(0, (1 - t) * 16), child: Opacity(opacity: t, child: c)),
      child: child,
    );
  }
}

class _PatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        final rect = Rect.fromLTWH(x, y, step, step);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
