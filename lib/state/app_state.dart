import 'package:flutter/material.dart';
import 'package:hajj_wallet/models/cart_item.dart';

class AppState extends ChangeNotifier {
  Map<String, dynamic>? _currentUserProfile;

  final List<CartItem> _cartItems = [];
  final List<String> _wishlistProductIds = [];

  bool _subscriptionActive = false;
  int _unreadNotifCount = 0;
  String _currentTier = 'Silver';
  int _totalPoints = 0;
  bool _tierJustUpgraded = false;

  Map<String, dynamic>? get currentUserProfile => _currentUserProfile;
  List<CartItem> get cartItems => _cartItems;
  List<String> get wishlistProductIds => _wishlistProductIds;
  bool get subscriptionActive => _subscriptionActive;
  int get unreadNotifCount => _unreadNotifCount;
  String get currentTier => _currentTier;
  int get totalPoints => _totalPoints;
  bool get tierJustUpgraded => _tierJustUpgraded;

  double get cartTotal => _cartItems.fold(0, (sum, item) => sum + ((item.price + item.variantAdjustment) * item.quantity));
  int get cartCount => _cartItems.fold(0, (sum, item) => sum + item.quantity);

  // Login থেকে profile set করা
  void setCurrentUserProfile(Map<String, dynamic>? profile) {
    _currentUserProfile = profile;
    if (profile != null) {
      _currentTier = profile['tier'] ?? 'Silver';
      _totalPoints = profile['points_total'] ?? 0;
    }
    notifyListeners();
  }

  // Backward compatibility
  void setUserProfile(Map<String, dynamic>? profile) => setCurrentUserProfile(profile);

  void loginMockUser() {
    _currentUserProfile = {
      'name': 'Ahmed Ali',
      'email': 'ahmed@example.com',
      'avatar_url': 'https://i.pravatar.cc/150?img=11',
    };
    notifyListeners();
  }

  void setSubscriptionActive(bool value) {
    _subscriptionActive = value;
    notifyListeners();
  }

  void setUnreadNotifCount(int value) {
    _unreadNotifCount = value;
    notifyListeners();
  }

  void setTotalPoints(int value) {
    _totalPoints = value;
    notifyListeners();
  }

  void setTier(String tier) {
    _currentTier = tier;
    _tierJustUpgraded = true;
    notifyListeners();
  }

  void clearTierUpgradeFlag() {
    _tierJustUpgraded = false;
    notifyListeners();
  }

  void addToCart(CartItem item) {
    final existingIndex = _cartItems.indexWhere(
      (e) => e.productId == item.productId && e.color == item.color && e.size == item.size,
    );
    if (existingIndex >= 0) {
      final existing = _cartItems[existingIndex];
      _cartItems[existingIndex] = existing.copyWith(quantity: existing.quantity + 1);
    } else {
      _cartItems.add(item);
    }
    notifyListeners();
  }

  void removeFromCart(String productId) {
    _cartItems.removeWhere((e) => e.productId == productId);
    notifyListeners();
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
  }

  void toggleWishlist(String productId) {
    if (_wishlistProductIds.contains(productId)) {
      _wishlistProductIds.remove(productId);
    } else {
      _wishlistProductIds.add(productId);
    }
    notifyListeners();
  }

  void logout() {
    _currentUserProfile = null;
    _subscriptionActive = false;
    _unreadNotifCount = 0;
    _currentTier = 'Silver';
    _totalPoints = 0;
    _tierJustUpgraded = false;
    _cartItems.clear();
    _wishlistProductIds.clear();
    notifyListeners();
  }
}
