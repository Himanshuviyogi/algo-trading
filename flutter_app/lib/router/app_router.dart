import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';import '../screens/algo_config_screen.dart';
import '../screens/order_book_screen.dart';
import '../screens/positions_screen.dart';

import '../blocs/auth_bloc.dart';
import '../cubits/cubits.dart';
import '../cubits/order_cubit.dart';
import '../repositories/repositories.dart';
import '../screens/screens.dart';
import '../services/app_control_service.dart';
import '../services/local_storage_service.dart';
import '../services/order_service.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(AuthBloc bloc) {
    Future.delayed(const Duration(milliseconds: 1500), () {
      _timerDone = true;
      notifyListeners();
    });
    _subscription = bloc.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;
  bool _timerDone = false;
  bool get timerDone => _timerDone;

  // Public so the onboarding fetch can trigger a re-run after loading.
  void refresh() => notifyListeners();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter createAppRouter({
  required AuthBloc authBloc,
  required UserRepository userRepository,
  required SubscriptionRepository subscriptionRepository,
  required LocalStorageService localStorage,
  String? pendingRecommendationId,
}) {
  // pendingRecommendationId kept in signature for backward-compat but no longer used.
  // ignore: unused_local_variable
  String? _pendingId;
  final notifier = _RouterRefreshNotifier(authBloc);
  
  // Create a GlobalKey for the navigator to access overlay
  final navigatorKey = GlobalKey<NavigatorState>();

  // Cache onboarding state per session so we don't re-check Firestore on
  // every redirect call. Reset when user logs out.
  bool? _profileComplete;
  bool? _hasSubscription;
  String? _cachedUid;
  bool _fetchInProgress = false;

  Future<void> _loadOnboardingState(String uid) async {
    if (_cachedUid != uid) {
      _profileComplete = null;
      _hasSubscription = null;
      _cachedUid = uid;
      _fetchInProgress = false;
    }
    // Already loaded or fetch in progress — don't start another.
    if (_profileComplete != null) return;
    if (_fetchInProgress) return;
    _fetchInProgress = true;

    // Check local storage first — instant, no network needed.
    if (localStorage.hasSkippedOnboarding(uid) || localStorage.isProfileComplete(uid)) {
      _hasSubscription = true;
      _profileComplete = true;
      try {
        // Still verify profile in background but don't block navigation
        final profile = await userRepository.getUserProfile(uid);
        if (profile != null && !profile.isProfileComplete) {
          _profileComplete = false;
        }
      } catch (_) {}
      _fetchInProgress = false;
      notifier.refresh();
      return;
    }

    try {
      final profile = await userRepository.getUserProfile(uid);
      _profileComplete = profile?.isProfileComplete ?? false;

      // If profile is complete, cache it in local storage so we skip
      // this check on future app starts (avoids the re-prompt bug).
      if (_profileComplete == true) {
        await localStorage.setProfileComplete(uid);
      }

      final subs = await subscriptionRepository.getUserSubscriptions(uid).first;
      final hasActiveSub = subs.any((s) => s.isEffectivelyActive);
      _hasSubscription = hasActiveSub || (profile?.shouldSkipPlanOnboarding ?? false);
    } catch (_) {
      _profileComplete = true;
      _hasSubscription = true;
    }
    _fetchInProgress = false;
    notifier.refresh(); // re-run redirect with loaded data
  }

  void _clearOnboardingCache() {
    _profileComplete = null;
    _hasSubscription = null;
    _cachedUid = null;
    _fetchInProgress = false;
  }

  void _invalidateProfileCache() {
    _profileComplete = true;
  }

  void _invalidateSubscriptionCache() {
    _hasSubscription = true;
  }

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (BuildContext context, GoRouterState state) async {
      final authState = authBloc.state;
      final isLoading = authState is AuthLoading;
      final isAuthenticated = authState is AuthAuthenticated;
      final isUnauthenticated =
          authState is AuthInitial || authState is AuthFailure;
      final location = state.matchedLocation;

      // ── App control gate (checked before everything else) ────────────────
      // These routes are always accessible so we avoid redirect loops.
      const controlRoutes = ['/maintenance', '/force-update'];
      if (!controlRoutes.contains(location)) {
        if (AppControlService.instance.maintenanceMode) return '/maintenance';
        if (AppControlService.instance.isUpdateRequired) return '/force-update';
      }
      // If we're on a control route but the condition is no longer true,
      // bounce back to splash so the normal flow takes over.
      if (location == '/maintenance' &&
          !AppControlService.instance.maintenanceMode) {
        return '/splash';
      }
      if (location == '/force-update' &&
          !AppControlService.instance.isUpdateRequired) {
        return '/splash';
      }

      // ── Splash gate ──────────────────────────────────────────────────────
      if (location == '/splash') {
        if (isLoading || !notifier.timerDone) return null;
        if (isAuthenticated) {
          await _loadOnboardingState(authState.uid);
          // Wait for fetch to complete before redirecting.
          if (_profileComplete == null || _hasSubscription == null) return null;
          if (_profileComplete == false) return '/profile-setup';
          if (_hasSubscription == false) return '/onboarding-plans';
          return '/home/dashboard';
        }
        return '/phone-entry';
      }

      if (isLoading) return null;

      // ── Unauthenticated guard ────────────────────────────────────────────
      const authRoutes = ['/phone-entry', '/otp-verify'];
      if (isUnauthenticated) {
        // Only clear cache when we're actually on an auth route (post-logout).
        if (authRoutes.contains(location)) _clearOnboardingCache();
        if (!authRoutes.contains(location)) return '/phone-entry';
      }

      // ── Post-login onboarding redirect ───────────────────────────────────
      if (isAuthenticated && authRoutes.contains(location)) {
        await _loadOnboardingState(authState.uid);
        // If fetch is still in progress, don't redirect yet — wait for next refresh.
        if (_profileComplete == null || _hasSubscription == null) return null;
        if (_profileComplete == false) return '/profile-setup';
        if (_hasSubscription == false) return '/onboarding-plans';
        return '/home/dashboard';
      }

      // Let onboarding screens render without redirect loops.
      if (isAuthenticated && location == '/profile-setup') return null;
      if (isAuthenticated && location == '/onboarding-plans') return null;

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/phone-entry',
        builder: (context, state) => const PhoneEntryScreen(),
      ),
      GoRoute(
        path: '/otp-verify',
        builder: (context, state) => const OtpVerificationScreen(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) {
          final extra = state.extra as Map?;
          final isEditing = extra?['isEditing'] as bool? ?? false;
          return ProfileSetupScreen(
            isEditing: isEditing,
            onSaved: () {
              _invalidateProfileCache();
              if (!isEditing) _invalidateSubscriptionCache();
            },
          );
        },
      ),
      GoRoute(
        path: '/onboarding-plans',
        builder: (context, state) => OnboardingPlansScreen(
          onSubscribed: _invalidateSubscriptionCache,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeScreen(navigationShell: navigationShell),
        branches: [
          // index 0 — Home dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/dashboard',
                builder: (context, state) => const HomeDashboardScreen(),
              ),
            ],
          ),
          // index 1 — Strategies
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/strategies',
                builder: (context, state) => const UserStrategiesScreen(),
              ),
            ],
          ),
          // index 2 — Orders
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/orders',
                builder: (context, state) => RepositoryProvider<OrderRepository>(
                  create: (_) => OrderRepositoryImpl(
                    firestore: FirebaseFirestore.instance,
                  ),
                  child: const OrderBookScreen(),
                ),
              ),
            ],
          ),
          // index 3 — Positions
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/positions',
                builder: (context, state) => RepositoryProvider<PositionRepository>(
                  create: (_) => PositionRepositoryImpl(
                    firestore: FirebaseFirestore.instance,
                  ),
                  child: RepositoryProvider<OrderRepository>(
                    create: (_) => OrderRepositoryImpl(
                      firestore: FirebaseFirestore.instance,
                    ),
                    child: const PositionsScreen(),
                  ),
                ),
              ),
            ],
          ),
          // index 4 — Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // Standalone full-screen routes (no bottom nav)
      GoRoute(
        path: '/market',
        builder: (context, state) => const MarketScreen(),
      ),
      GoRoute(
        path: '/plans',
        builder: (context, state) => const PlansScreen(),
      ),
      GoRoute(
        path: '/breakouts',
        builder: (context, state) => const BreakoutsScreen(),
      ),
      GoRoute(
        path: '/option-chain',
        builder: (context, state) {
          final extra  = state.extra as Map<String, dynamic>?;
          final symbol = extra?['symbol'] as String? ?? 'NIFTY';
          return OptionChainScreen(initialSymbol: symbol);
        },
      ),
      // /recommendation/:id — signal detail with order placement
      GoRoute(
        path: '/recommendation/:id',
        builder: (context, state) {
          final id        = state.pathParameters['id']!;
          final authState = authBloc.state;
          final userId    = authState is AuthAuthenticated ? authState.uid : '';

          return MultiBlocProvider(
            providers: [
              // RecommendationDetailCubit — drives the detail data + access control
              BlocProvider<RecommendationDetailCubit>(
                create: (ctx) => RecommendationDetailCubit(
                  recommendationRepository: ctx.read<RecommendationRepository>(),
                  subscriptionCubit: ctx.read<SubscriptionCubit>(),
                ),
              ),
              // OrderRepository provided locally (same pattern as OrderBookScreen)
              RepositoryProvider<OrderRepository>(
                create: (_) => OrderRepositoryImpl(
                  firestore: FirebaseFirestore.instance,
                ),
              ),
            ],
            child: Builder(
              builder: (ctx) => BlocProvider<OrderCubit>(
                create: (_) => OrderCubit(
                  orderRepository: ctx.read<OrderRepository>(),
                  orderService: OrderService.instance,
                  userId: userId,
                ),
                child: RecommendationDetailScreen(id: id),
              ),
            ),
          );
        },
      ),
      // /broker-setup — broker credential setup & management
      GoRoute(
        path: '/broker-setup',
        builder: (context, state) => const BrokerSetupScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationHistoryScreen(),
      ),
      // /orders — canonical deep-link path for OrderBookScreen
      GoRoute(
        path: '/orders',
        builder: (context, state) => RepositoryProvider<OrderRepository>(
          create: (_) => OrderRepositoryImpl(
            firestore: FirebaseFirestore.instance,
          ),
          child: const OrderBookScreen(),
        ),
      ),
      GoRoute(
        path: '/order-book',
        builder: (context, state) => const OrderBookScreen(),
      ),
      // /positions — canonical deep-link path for PositionsScreen
      GoRoute(
        path: '/positions',
        builder: (context, state) => RepositoryProvider<PositionRepository>(
          create: (_) => PositionRepositoryImpl(
            firestore: FirebaseFirestore.instance,
          ),
          child: RepositoryProvider<OrderRepository>(
            create: (_) => OrderRepositoryImpl(
              firestore: FirebaseFirestore.instance,
            ),
            child: const PositionsScreen(),
          ),
        ),
      ),
      // /algo-config
      GoRoute(
        path: '/algo-config',
        builder: (context, state) => const AlgoConfigScreen(),
      ),
      GoRoute(
        path: '/news_updates',
        builder: (context, state) => const NewsUpdatesScreen(),
      ),
      GoRoute(
        path: '/chart/:symbol',
        builder: (context, state) {
          final symbol = state.pathParameters['symbol']!;
          return StockChartScreen(symbol: symbol);
        },
      ),
      GoRoute(
        path: '/maintenance',
        builder: (context, state) => const MaintenanceScreen(),
      ),
      GoRoute(
        path: '/force-update',
        builder: (context, state) => const ForceUpdateScreen(),
      ),
      // /create-strategy — user strategy creation / edit form
      // extra (optional): {
      //   'editDocId': String,     — edit mode: doc id in users/{uid}/strategies
      //   'editUid':   String,     — edit mode: owner uid
      //   'prefill':   Map<String,dynamic>, — edit mode: full raw Firestore doc
      //   'prefillSymbol': String, — screener quick-add
      //   'prefillName':   String,
      //   'prefillPrice':  double,
      // }
      GoRoute(
        path: '/create-strategy',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          if (extra == null) return const CreateStrategyScreen();
          return CreateStrategyScreen(
            editDocId:    extra['editDocId']    as String?,
            editUid:      extra['editUid']      as String?,
            prefillData:  extra['prefill']      as Map<String, dynamic>?,
            prefillSymbol: extra['prefillSymbol'] as String?,
            prefillName:   extra['prefillName']   as String?,
            prefillPrice:  (extra['prefillPrice'] as num?)?.toDouble(),
            scrollToBacktest: extra['scrollToBacktest'] as bool? ?? false,
          );
        },
      ),
      // /strategy-detail — strategy detail with price ladder, P&L, close action
      GoRoute(
        path: '/strategy-detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return StrategyDetailScreen(
            docId:  extra['docId']  as String? ?? '',
            uid:    extra['uid']    as String? ?? '',
            isOwn:  extra['isOwn'] as bool?   ?? false,
            data:   extra['data']  as Map<String, dynamic>? ?? {},
          );
        },
      ),
      // /admin — temporary admin seed screen (accessible from profile)
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminSeedScreen(),
      ),
    ],
  );
}
