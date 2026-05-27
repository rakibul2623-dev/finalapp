import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/store_screen.dart';
import 'screens/packages_screen.dart';
import 'screens/community_screen.dart';
import 'screens/account_screen.dart';
import 'screens/wallet_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/discussion_detail_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/conversation_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/sponsorship_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/my_orders_screen.dart';
import 'screens/my_bookings_screen.dart';
import 'screens/wishlist_screen.dart';
import 'theme.dart';
import 'state/app_state.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SplashScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.signup,
        name: 'signup',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SignupScreen(),
        ),
      ),
      // Authenticated area with persistent bottom navigation
      ShellRoute(
        builder: (context, state, child) => _BottomNavShell(child: child, location: state.matchedLocation),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: AppRoutes.store,
            name: 'store',
            pageBuilder: (context, state) => const NoTransitionPage(child: StoreScreen()),
          ),
          GoRoute(
            path: AppRoutes.packages,
            name: 'packages',
            pageBuilder: (context, state) => const NoTransitionPage(child: PackagesScreen()),
          ),
          GoRoute(
            path: AppRoutes.community,
            name: 'community',
            pageBuilder: (context, state) => const NoTransitionPage(child: CommunityScreen()),
          ),
          GoRoute(
            path: AppRoutes.account,
            name: 'account',
            pageBuilder: (context, state) => const NoTransitionPage(child: AccountScreen()),
          ),
          GoRoute(
            path: AppRoutes.wallet,
            name: 'wallet',
            pageBuilder: (context, state) => const NoTransitionPage(child: WalletScreen()),
          ),
          GoRoute(
            path: AppRoutes.messages,
            name: 'messages',
            pageBuilder: (context, state) => const NoTransitionPage(child: MessagesScreen()),
          ),
          GoRoute(
            path: AppRoutes.conversation,
            name: 'conversation',
            pageBuilder: (context, state) {
              final id = state.pathParameters['conversationId'] ?? '';
              return NoTransitionPage(child: ConversationScreen(conversationId: id));
            },
          ),
          GoRoute(
            path: AppRoutes.productDetail,
            name: 'product-detail',
            pageBuilder: (context, state) {
              final id = state.pathParameters['productId'] ?? '';
              final initial = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : null;
              return NoTransitionPage(child: ProductDetailScreen(productId: id, initialProduct: initial));
            },
          ),
          GoRoute(
            path: AppRoutes.discussionDetail,
            name: 'discussion-detail',
            pageBuilder: (context, state) {
              final id = state.pathParameters['discussionId'] ?? '';
              return NoTransitionPage(child: DiscussionDetailScreen(discussionId: id));
            },
          ),
          GoRoute(
            path: AppRoutes.notifications,
            name: 'notifications',
            pageBuilder: (context, state) => const NoTransitionPage(child: NotificationsScreen()),
          ),
          GoRoute(
            path: AppRoutes.cart,
            name: 'cart',
            pageBuilder: (context, state) => const NoTransitionPage(child: CartScreen()),
          ),
          GoRoute(
            path: AppRoutes.checkout,
            name: 'checkout',
            pageBuilder: (context, state) => const NoTransitionPage(child: CheckoutScreen()),
          ),
          GoRoute(
            path: AppRoutes.sponsorship,
            name: 'sponsorship',
            pageBuilder: (context, state) => const NoTransitionPage(child: SponsorshipScreen()),
          ),
          GoRoute(
            path: AppRoutes.wishlist,
            name: 'wishlist',
            pageBuilder: (context, state) => const NoTransitionPage(child: WishlistScreen()),
          ),
          GoRoute(
            path: '/my-orders',
            name: 'my-orders',
            pageBuilder: (context, state) => const NoTransitionPage(child: MyOrdersScreen()),
          ),
          GoRoute(
            path: AppRoutes.myBookings,
            name: 'my-bookings',
            pageBuilder: (context, state) => const NoTransitionPage(child: MyBookingsScreen()),
          ),
        ],
      ),
    ],
  );
}

class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String store = '/store';
  static const String packages = '/packages';
  static const String community = '/community';
  static const String account = '/account';
  static const String wallet = '/wallet';
  static const String messages = '/messages';
  static const String conversation = '/messages/:conversationId';
  static const String productDetail = '/product/:productId';
  static const String discussionDetail = '/discussion/:discussionId';
  static const String notifications = '/notifications';
  static const String cart = '/cart';
  static const String checkout = '/checkout';
  static const String sponsorship = '/sponsorship';
  static const String wishlist = '/wishlist';
  static const String myOrders = '/my-orders';
  static const String myBookings = '/my-bookings';
}

class _BottomNavShell extends StatelessWidget {
  final Widget child;
  final String location;
  const _BottomNavShell({required this.child, required this.location});

  int _locationToIndex(String loc) {
    if (loc.startsWith(AppRoutes.store)) return 1;
    if (loc.startsWith(AppRoutes.packages)) return 2;
    if (loc.startsWith(AppRoutes.community)) return 3;
    if (loc.startsWith(AppRoutes.account)) return 4;
    return 0; // home default
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<AppState>().unreadNotifCount;
    final currentIndex = _locationToIndex(location);

    void onTap(int index) {
      switch (index) {
        case 0:
          context.go(AppRoutes.home);
          break;
        case 1:
          context.go(AppRoutes.store);
          break;
        case 2:
          context.go(AppRoutes.packages);
          break;
        case 3:
          context.go(AppRoutes.community);
          break;
        case 4:
          context.go(AppRoutes.account);
          break;
      }
    }

    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
      const BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Store'),
      const BottomNavigationBarItem(icon: Icon(Icons.flight_takeoff_rounded), label: 'Packages'),
      const BottomNavigationBarItem(icon: Icon(Icons.forum_outlined), label: 'Community'),
      BottomNavigationBarItem(
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.person_outlined),
            if (unread > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: const BoxDecoration(
                    color: AppColors.destructive,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryForeground,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        label: 'Account',
      ),
    ];

    return Scaffold(
      body: child,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.70),
              border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              child: BottomNavigationBar(
                currentIndex: currentIndex,
                onTap: onTap,
                type: BottomNavigationBarType.fixed,
                elevation: 0,
                backgroundColor: Colors.transparent,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.silverTier,
                showUnselectedLabels: true,
                selectedLabelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary, fontSize: 11),
                unselectedLabelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.silverTier, fontSize: 11),
                items: items,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
