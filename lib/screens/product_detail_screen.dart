import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hajj_wallet/theme.dart';
import 'package:hajj_wallet/state/app_state.dart';
import 'package:hajj_wallet/models/cart_item.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId, this.initialProduct});
  final String productId;
  final Map<String, dynamic>? initialProduct;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Map<String, dynamic>? product;
  List<Map<String, dynamic>> images = [];
  List<Map<String, dynamic>> variants = [];
  List<Map<String, dynamic>> reviews = [];
  List<Map<String, dynamic>> related = [];
  bool loading = true;
  String? error;
  bool _usedFallback = false;

  String? selectedColor;
  String? selectedSize;
  int quantity = 1;
  int currentImageIndex = 0;
  bool _descOpen = false;

  final ScrollController _scroll = ScrollController();
  double _headerT = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _pageController = PageController();
    // Pre-hydrate with initial product (from Store) so UI is never blank
    if (widget.initialProduct != null) {
      product = Map<String, dynamic>.from(widget.initialProduct!);
      final firstImage = (product?['image_url'] ?? '').toString();
      if (firstImage.isNotEmpty && images.isEmpty) {
        images = [
          {'url': firstImage},
        ];
      }
      final colors = _availableColors();
      final sizes = _availableSizes();
      if (colors.isNotEmpty) selectedColor = colors.first;
      if (sizes.isNotEmpty) selectedSize = sizes.first;
      loading = false; // show content immediately
      // Kick off a background fetch to enrich details without blocking UI
      scheduleMicrotask(() {
        if (mounted) _loadAll(silent: true);
      });
    } else if (widget.productId.isEmpty) {
      setState(() {
        loading = false;
        error = 'Invalid product ID';
      });
    } else {
      _loadAll();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final t = (_scroll.hasClients ? _scroll.offset : 0) / 80.0;
    final clamped = t.clamp(0.0, 1.0);
    if (clamped != _headerT) setState(() => _headerT = clamped);
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    } else {
      error = null; // silent refresh clears error
    }
    try {
      final client = Supabase.instance.client;
      final pid = widget.productId;

      final prodF = client.from('products').select().eq('id', pid).maybeSingle();
      final imgsF = client.from('product_images').select().eq('product_id', pid).order('sort_order');
      final varsF = client.from('product_variants').select().eq('product_id', pid);
      final revsF = client
          .from('product_reviews')
          .select('id, rating, comment, created_at, user_id, profiles!inner(full_name, avatar_url)')
          .eq('product_id', pid)
          .order('created_at', ascending: false);

      final results = await Future.wait([prodF, imgsF, varsF, revsF]).timeout(const Duration(seconds: 6));
      final prod = results[0] as Map<String, dynamic>?;
      final imgs = (results[1] as List).cast<Map<String, dynamic>>();
      final vars = (results[2] as List).cast<Map<String, dynamic>>();
      final revs = (results[3] as List).cast<Map<String, dynamic>>();

      // Related products (same category, exclude self, require image)
      List<Map<String, dynamic>> rel = [];
      try {
        final cat = (prod?['category'] ?? '').toString();
        if (cat.isNotEmpty) {
          final relRes = await client
              .from('products')
              .select('id,name,price,image_url,category,created_at')
              .eq('category', cat)
              .neq('id', pid)
              .not('image_url', 'is', null)
              .order('created_at', ascending: false)
              .limit(4) as List<dynamic>;
          rel = relRes.map((e) => Map<String, dynamic>.from(e as Map)).where((m) => ((m['image_url'] ?? '').toString()).isNotEmpty).toList();
        }
      } catch (e) {
        debugPrint('Related products load failed: $e');
      }

      if (!mounted) return;
      setState(() {
        if (prod != null) product = prod;
        if (imgs.isNotEmpty) images = imgs;
        variants = vars;
        reviews = revs;
        related = rel;
        final colors = _availableColors();
        final sizes = _availableSizes();
        if (colors.isNotEmpty && (selectedColor == null || !colors.contains(selectedColor))) selectedColor = colors.first;
        if (sizes.isNotEmpty && (selectedSize == null || !sizes.contains(selectedSize))) selectedSize = sizes.first;
        loading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('Product detail load timeout: $e');
      if (!mounted) return;
      setState(() => error = 'Network timeout.');
      if (product == null) _applyDemoFallback();
    } catch (e) {
      debugPrint('Failed to load product detail: $e');
      if (!mounted) return;
      setState(() => error = 'Could not load product details.');
      if (product == null) _applyDemoFallback();
    }
  }

  void _applyDemoFallback() {
    setState(() {
      _usedFallback = true;
      product = {
        'id': widget.productId,
        'name': 'Premium Ihram Set',
        'price': 120.0,
        'compare_at_price': 150.0,
        'category': 'Apparel',
        'stock': 7,
        'description': 'Ultra-soft, breathable cotton ihram with quick-dry technology and anti-slip belt. Includes travel pouch.'
      };
      images = [
        {'url': 'https://images.unsplash.com/photo-1603575449297-3ea9e2ca61dc?q=80&w=1024&auto=format&fit=crop'},
        {'url': 'https://images.unsplash.com/photo-1503342217505-b0a15cf70489?q=80&w=1024&auto=format&fit=crop'},
        {'url': 'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?q=80&w=1024&auto=format&fit=crop'},
      ];
      variants = [
        {'color': 'White', 'size': 'M', 'price_adjustment': 0},
        {'color': 'White', 'size': 'L', 'price_adjustment': 0},
        {'color': 'Sand', 'size': 'M', 'price_adjustment': 5},
        {'color': 'Sand', 'size': 'L', 'price_adjustment': 5},
      ];
      reviews = [
        {
          'id': 'r1',
          'rating': 5,
          'comment': 'Super comfortable and high quality. Arrived quickly and fits perfectly.',
          'created_at': DateTime.now().subtract(const Duration(days: 12)).toIso8601String(),
          'profiles': {'full_name': 'Yusuf', 'avatar_url': ''}
        },
        {
          'id': 'r2',
          'rating': 4,
          'comment': 'Great fabric. The belt included is very useful.',
          'created_at': DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
          'profiles': {'full_name': 'Aisha', 'avatar_url': ''}
        }
      ];
      related = [
        {
          'id': 'rel1',
          'name': 'Ihram Belt Pro',
          'price': 24.99,
          'image_url': 'https://images.unsplash.com/photo-1520975922284-5f1f87b35c34?q=80&w=800&auto=format&fit=crop',
          'category': 'Accessories',
          'stock': 20
        },
        {
          'id': 'rel2',
          'name': 'Cooling Towel Set',
          'price': 14.50,
          'image_url': 'https://images.unsplash.com/photo-1499951360447-b19be8fe80f5?q=80&w=800&auto=format&fit=crop',
          'category': 'Accessories',
          'stock': 3
        },
      ];
      final colors = _availableColors();
      final sizes = _availableSizes();
      if (colors.isNotEmpty) selectedColor = colors.first;
      if (sizes.isNotEmpty) selectedSize = sizes.first;
      loading = false;
    });
  }

  List<String> _availableColors() {
    final set = <String>{};
    for (final v in variants) {
      final c = (v['color'] ?? '').toString();
      if (c.isNotEmpty) set.add(c);
    }
    return set.toList();
  }

  List<String> _availableSizes() {
    final set = <String>{};
    for (final v in variants) {
      final s = (v['size'] ?? '').toString();
      if (s.isNotEmpty) set.add(s);
    }
    return set.toList();
  }

  double _variantAdjustment() {
    if (variants.isEmpty) return 0;
    for (final v in variants) {
      final c = (v['color'] ?? '').toString();
      final s = (v['size'] ?? '').toString();
      if ((selectedColor == null || selectedColor == c || c.isEmpty) && (selectedSize == null || selectedSize == s || s.isEmpty)) {
        return ((v['price_adjustment'] as num?) ?? 0).toDouble();
      }
    }
    return 0;
  }

  double _avgRating() {
    if (reviews.isEmpty) return 0;
    double sum = 0;
    for (final r in reviews) {
      sum += ((r['rating'] as num?) ?? 0).toDouble();
    }
    return sum / reviews.length;
  }

  void _toggleWishlist() async {
    final app = context.read<AppState>();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || product == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to use wishlist')));
      return;
    }
    final productId = (product!['id'] ?? '').toString();
    final isWished = app.wishlistProductIds.contains(productId);
    try {
      if (isWished) {
        await Supabase.instance.client
            .from('wishlists')
            .delete()
            .eq('user_id', uid)
            .eq('product_id', productId);
      } else {
        await Supabase.instance.client.from('wishlists').insert({'user_id': uid, 'product_id': productId});
      }
      app.toggleWishlist(productId);
    } catch (e) {
      debugPrint('Wishlist toggle failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update wishlist')));
    }
  }

  void _addToCart({bool andGoToCart = false}) {
    if (product == null) return;
    final app = context.read<AppState>();
    final id = (product!['id'] ?? '').toString();
    final name = (product!['name'] ?? '').toString();
    final basePrice = ((product!['price'] as num?) ?? 0).toDouble();
    final imageUrl = (product!['image_url'] ?? (images.isNotEmpty ? images.first['url'] : '')).toString();
    final adj = _variantAdjustment();
    final item = CartItem(
      productId: id,
      name: name,
      price: basePrice,
      quantity: quantity,
      imageUrl: imageUrl,
      color: selectedColor ?? 'default',
      size: selectedSize ?? 'std',
      variantAdjustment: adj,
    );
    // Merge quantity logic by calling addToCart repeatedly for quantity
    for (int i = 0; i < quantity; i++) {
      app.addToCart(item.copyWith(quantity: 1));
    }
    if (andGoToCart) {
      context.push('/checkout');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart')));
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('ProductDetailScreen build: loading=$loading productNull=${product==null} images=${images.length} variants=${variants.length} reviews=${reviews.length}');
    final app = context.watch<AppState>();
    final isWished = product != null && app.wishlistProductIds.contains((product!['id'] ?? '').toString());
    final basePrice = ((product?['price'] as num?) ?? 0).toDouble();
    final total = (basePrice + _variantAdjustment()) * quantity;

    // If finished loading but have no product, show a friendly error state
    if (!loading && product == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: const Text('Product'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_dissatisfied_outlined, size: 48, color: AppColors.mutedForeground),
              const SizedBox(height: 12),
              Text(error ?? 'Unable to load product', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadAll, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Foreground content scroll
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _buildImageGallery()),
                SliverToBoxAdapter(child: _buildProductInfoCard()),
                if (variants.isNotEmpty) SliverToBoxAdapter(child: _buildVariants()),
                SliverToBoxAdapter(child: _buildQuantity()),
                SliverToBoxAdapter(child: _buildTierBanner(app.currentTier)),
                SliverToBoxAdapter(child: _buildDeliveryInfo()),
                SliverToBoxAdapter(child: _buildReviews()),
                SliverToBoxAdapter(child: _buildRelated()),
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            ),
            // Floating controls
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _CircleButton(icon: Icons.arrow_back, onTap: () => context.pop(), bg: Colors.white.withValues(alpha: 0.95 * (0.4 + 0.6 * _headerT))),
                  Row(children: [
                    _CircleButton(icon: isWished ? Icons.favorite : Icons.favorite_border, iconColor: isWished ? AppColors.destructive : AppColors.foreground, onTap: _toggleWishlist, bg: Colors.white.withValues(alpha: 0.95 * (0.4 + 0.6 * _headerT))),
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: Icons.ios_share_outlined,
                      onTap: () async {
                        final id = (product?['id'] ?? '').toString();
                        final link = 'https://hajjwallet.app/product/$id';
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                        }
                      },
                      bg: Colors.white.withValues(alpha: 0.95 * (0.4 + 0.6 * _headerT)),
                    ),
                    const SizedBox(width: 8),
                    _CartIcon(),
                  ])
                ]),
              ),
            ),
            if (loading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x10FFFFFF),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (_headerT > 0.2)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(height: 56, color: Colors.white.withValues(alpha: 0.2 * _headerT)),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: _BottomBar(total: total, onAdd: () => _addToCart(andGoToCart: false), onBuy: () => _addToCart(andGoToCart: true)),
      ),
    );
  }

  Widget _buildImageGallery() {
    debugPrint('PD:_buildImageGallery images=${images.length} productImageUrl=${(product?['image_url'] ?? '').toString()}');
    // Build gallery list: use product.image_url as fallback if product_images empty
    final media = images.isNotEmpty
        ? images
        : ((product?['image_url'] ?? '').toString().isNotEmpty
            ? [
                {'url': (product?['image_url'] ?? '').toString()}
              ]
            : images);
    final width = MediaQuery.of(context).size.width;
    final height = width; // 1:1 aspect
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _pageController,
            itemCount: media.isEmpty ? 1 : media.length,
            onPageChanged: (i) => setState(() => currentImageIndex = i),
            itemBuilder: (context, index) {
              if (media.isEmpty) {
                return Container(
                  color: AppColors.inputBackground,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined, size: 64, color: AppColors.mutedForeground),
                );
              }
                final url = (media[index]['url'] ?? media[index]['image_url'] ?? '').toString();
              return Container(
                color: AppColors.inputBackground,
                alignment: Alignment.center,
                child: url.isNotEmpty
                    ? InteractiveViewer(child: Image.network(url, fit: BoxFit.cover, width: width, height: height))
                    : const Icon(Icons.image_outlined, size: 64, color: AppColors.mutedForeground),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(media.isEmpty ? 1 : media.length, (i) {
            final active = i == currentImageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 10 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
        if (media.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (context, i) {
                final url = (media[i]['url'] ?? media[i]['image_url'] ?? '').toString();
                final active = i == currentImageIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() => currentImageIndex = i);
                    _pageController.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: active ? AppColors.primary : AppColors.border, width: active ? 2 : 1),
                      color: AppColors.inputBackground,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: url.isNotEmpty ? Image.network(url, fit: BoxFit.cover) : const Icon(Icons.image_outlined, color: AppColors.mutedForeground),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: media.length,
            ),
          )
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildProductInfoCard() {
    debugPrint('PD:_buildProductInfoCard name="'+((product?['name']??'').toString())+'"');
    final name = (product?['name'] ?? '').toString();
    final price = ((product?['price'] as num?) ?? 0).toDouble();
    final compareAt = ((product?['compare_at_price'] as num?) ?? 0).toDouble();
    final stock = (product?['stock'] as int?) ?? 0;
    final desc = (product?['description'] ?? '').toString();
    final avg = _avgRating();
    final category = (product?['category'] ?? '').toString();
    final hasDiscount = compareAt > price && compareAt > 0;

    return Container(
      margin: const EdgeInsets.only(top: -12),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x140A3A2A), blurRadius: 24, offset: Offset(0, -8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (error != null && _usedFallback)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFFFF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFD0D0))),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Color(0xFFB00020), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Showing demo content. Open the Supabase panel to connect your backend and load real product details.', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFFB00020)))),
            ]),
          ),
        if (category.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: AppColors.border)),
            child: Text(category.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground, letterSpacing: 1)),
          ),
        const SizedBox(height: 10),
        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 8),
        Row(children: [
          _Stars(rating: avg),
          const SizedBox(width: 6),
          Text('(${reviews.length} reviews)', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
          const SizedBox(width: 6),
          Text('•', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
          const SizedBox(width: 6),
          Text('342 sold', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          if (hasDiscount)
            Text('\$${compareAt.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough, color: AppColors.mutedForeground)),
          const SizedBox(width: 8),
          if (hasDiscount)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text('Save ${(((compareAt - price) / compareAt) * 100).round()}%', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 10),
        Builder(builder: (_) {
          late Color c;
          late String text;
          if (stock <= 0) {
            c = Colors.red;
            text = 'Out of Stock';
          } else if (stock > 0 && stock <= 3) {
            c = const Color(0xFFFF8C00);
            text = 'Only $stock left';
          } else {
            c = Colors.green;
            text = 'In Stock';
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: c)),
            child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
          );
        }),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _descOpen = !_descOpen),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Description', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Icon(_descOpen ? Icons.expand_less : Icons.expand_more),
          ]),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(desc, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground, height: 1.6)),
          ),
          crossFadeState: _descOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ]),
    );
  }

  Widget _buildVariants() {
    final colors = _availableColors();
    final sizes = _availableSizes();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (colors.isNotEmpty) ...[
            Text('Color', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: colors.map((c) {
              final isSel = selectedColor == c;
              return GestureDetector(
                onTap: () => setState(() => selectedColor = c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSel ? AppColors.primary : AppColors.border, width: isSel ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.inputBackground,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }).toList()),
            const SizedBox(height: 16),
          ],
          if (sizes.isNotEmpty) ...[
            Text('Size', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: sizes.map((s) {
              final isSel = selectedSize == s;
              return ChoiceChip(
                label: Text(s),
                selected: isSel,
                onSelected: (_) => setState(() => selectedSize = s),
                selectedColor: AppColors.primary,
                labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: isSel ? Colors.white : AppColors.foreground),
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border, width: 1),
              );
            }).toList()),
          ],
        ],
      ),
    );
  }

  Widget _buildQuantity() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('Quantity', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          _PillIconButton(icon: Icons.remove, onTap: quantity > 1 ? () => setState(() => quantity -= 1) : null),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$quantity', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          _PillIconButton(icon: Icons.add, onTap: () => setState(() => quantity += 1)),
        ],
      ),
    );
  }

  Widget _buildReviews() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reviews (${reviews.length})', style: Theme.of(context).textTheme.titleLarge),
              TextButton(onPressed: () {}, child: const Text('See all →')),
            ],
          ),
          const SizedBox(height: 8),
          if (reviews.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border, width: 1), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [const Icon(Icons.rate_review_outlined, color: AppColors.mutedForeground), const SizedBox(width: 8), Text('No reviews yet', style: Theme.of(context).textTheme.bodySmall)]),
            )
          else
            ListView.separated(
              itemCount: reviews.length > 2 ? 2 : reviews.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final r = reviews[index];
                final rating = ((r['rating'] as num?) ?? 0).toDouble();
                final comment = (r['comment'] ?? '').toString();
                final createdAt = DateTime.tryParse((r['created_at'] ?? '').toString());
                final profile = (r['profiles'] as Map?)?.cast<String, dynamic>();
                final name = (profile?['full_name'] ?? 'Anonymous').toString();
                final avatar = (profile?['avatar_url'] ?? '').toString();
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border, width: 1), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person) : null),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                            Text(createdAt != null ? _fmtDate(createdAt) : '', style: Theme.of(context).textTheme.bodySmall),
                          ]),
                          const SizedBox(height: 4),
                          _Stars(rating: rating),
                          const SizedBox(height: 6),
                          Text(comment, style: Theme.of(context).textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _buildRelated() {
    if (related.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('You may also like', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, i) {
              final p = related[i];
              final id = (p['id'] ?? '').toString();
              final name = (p['name'] ?? '').toString();
              final price = ((p['price'] as num?) ?? 0).toDouble();
              final image = (p['image_url'] ?? '').toString();
              return GestureDetector(
                onTap: () => context.push('/product/$id'),
                child: Container(
                  width: 150,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: image.isNotEmpty ? Image.network(image, fit: BoxFit.cover, width: 150) : const ColoredBox(color: AppColors.inputBackground)),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('\$' + price.toStringAsFixed(2), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                      ]),
                    )
                  ]),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemCount: related.length,
          ),
        )
      ]),
    );
  }

  Widget _buildTierBanner(String tier) {
    if (!(tier == 'Gold' || tier == 'Platinum')) return const SizedBox.shrink();
    final percent = tier == 'Platinum' ? 15 : 10;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFE7B3), Color(0xFFFFF5D6)]),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: const Color(0xFFF2B928)),
        ),
        child: Text('You save $percent% as a $tier member', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF8A6B00))),
      ),
    );
  }

  Widget _buildDeliveryInfo() {
    Widget item(IconData icon, String text) => Row(children: [Icon(icon, size: 18, color: AppColors.mutedForeground), const SizedBox(width: 6), Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedForeground))]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        item(Icons.local_shipping_outlined, 'Free delivery over \$50'),
        item(Icons.verified_user_outlined, 'Secure checkout'),
        item(Icons.autorenew, '7-day return'),
      ]),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, this.onTap, this.bg, this.iconColor});
  final IconData icon; final VoidCallback? onTap; final Color? bg; final Color? iconColor;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg ?? Colors.white, shape: BoxShape.circle, boxShadow: [
          BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 8)),
        ], border: Border.all(color: AppColors.border)),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: iconColor ?? AppColors.foreground),
      ),
    );
  }
}


class _CartIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final count = context.watch<AppState>().cartCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(onPressed: () => context.go('/cart'), icon: const Icon(Icons.shopping_cart_outlined)),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: const BoxDecoration(color: AppColors.destructive, borderRadius: BorderRadius.all(Radius.circular(10))),
              child: Text('$count', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontSize: 10)),
            ),
          ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.total, required this.onAdd, required this.onBuy});
  final double total;
  final VoidCallback onAdd;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), border: const Border(top: BorderSide(color: AppColors.border, width: 1))),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total', style: Theme.of(context).textTheme.bodySmall),
              Text('\$${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary)),
            ]),
          ),
          Expanded(
            child: Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: onAdd, style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('Add to Cart')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(onPressed: onBuy, style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: const Text('Buy Now')),
              ),
            ]),
          ),
        ],
      ),
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

class _PillIconButton extends StatelessWidget {
  const _PillIconButton({required this.icon, this.onTap});
  final IconData icon; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: 1,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(999), boxShadow: [
            BoxShadow(color: const Color(0xFF145032).withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 6)),
          ]),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: AppColors.foreground),
        ),
      ),
    );
  }
}
