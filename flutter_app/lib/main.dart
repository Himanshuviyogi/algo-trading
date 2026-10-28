import 'dart:async';



import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'blocs/auth_bloc.dart';
import 'cubits/cubits.dart';
import 'firebase_options.dart';
import 'repositories/repositories.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'services/app_control_service.dart';
import 'services/local_notification_service.dart';
import 'services/local_storage_service.dart';
import 'services/live_price_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/security_service.dart';
import 'utils/app_theme.dart';
import 'widgets/connectivity_banner.dart';
import 'widgets/notification_banner.dart';
import 'widgets/notification_toast.dart';

/// Background FCM message handler — runs in a separate isolate.
/// Shows a local notification with a "View Trade" action button.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await LocalNotificationService.instance.initialize();
  await LocalNotificationService.instance.showTradeNotification(
    title: message.data['title'] as String? ?? message.notification?.title ?? 'New notification',
    body: message.data['body'] as String? ?? message.notification?.body ?? '',
    type: message.data['type'] as String? ?? 'general',
    recommendationId: message.data['recommendation_id'] as String?,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize security config (screenshot prevention + watermark)
  await SecurityService.instance.initialize();

  // Initialize app control config (maintenance mode, force update, kill switch)
  await AppControlService.instance.initialize();

  // Initialize connectivity watcher
  await ConnectivityService.instance.init();

  // Register background FCM handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications (for action buttons on background notifications)
  await LocalNotificationService.instance.initialize();

  // Create the Android notification channel so background notifications
  // appear with the correct sound/priority on Android 8+.
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  final firestore = FirebaseFirestore.instance;
  final notificationService = NotificationServiceImpl();
  final userRepository = UserRepositoryImpl(firestore: firestore);
  final planRepository = PlanRepositoryImpl(firestore: firestore);
  final subscriptionRepository = SubscriptionRepositoryImpl(firestore: firestore);
  final recommendationRepository = RecommendationRepositoryImpl(firestore: firestore);
  final brokerRepository = BrokerRepositoryImpl(firestore: firestore);
  final authService = AuthServiceImpl();
  final localStorage = await LocalStorageService.create();

  final authBloc = AuthBloc(
    authService: authService,
    userRepository: userRepository,
  );

  final router = createAppRouter(
    authBloc: authBloc,
    userRepository: userRepository,
    subscriptionRepository: subscriptionRepository,
    localStorage: localStorage,
  );

  // Raw FCM diagnostic listener — debug only.
  if (kDebugMode) {
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('🔥 [RAW FCM] onMessage received!');
      debugPrint('🔥 [RAW FCM] title: ${msg.notification?.title}');
      debugPrint('🔥 [RAW FCM] body: ${msg.notification?.body}');
      debugPrint('🔥 [RAW FCM] data: ${msg.data}');
    });
  }

  runApp(
    MyApp(
      authBloc: authBloc,
      notificationService: notificationService,
      userRepository: userRepository,
      planRepository: planRepository,
      subscriptionRepository: subscriptionRepository,
      recommendationRepository: recommendationRepository,
      brokerRepository: brokerRepository,
      localStorage: localStorage,
      router: router,
    ),
  );
}

// ── MyApp ─────────────────────────────────────────────────────────────────────

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.authBloc,
    required this.notificationService,
    required this.userRepository,
    required this.planRepository,
    required this.subscriptionRepository,
    required this.recommendationRepository,
    required this.brokerRepository,
    required this.localStorage,
    required this.router,
  });

  final AuthBloc authBloc;
  final NotificationService notificationService;
  final UserRepository userRepository;
  final PlanRepository planRepository;
  final SubscriptionRepository subscriptionRepository;
  final RecommendationRepository recommendationRepository;
  final BrokerRepository brokerRepository;
  final LocalStorageService localStorage;
  final GoRouter router;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<RemoteMessage>? _bgTapSub;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _bgTapSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // All repositories are provided at the top level — they are stateless
    // wrappers and safe to keep alive regardless of auth state.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<UserRepository>.value(value: widget.userRepository),
        RepositoryProvider<PlanRepository>.value(value: widget.planRepository),
        RepositoryProvider<SubscriptionRepository>.value(
            value: widget.subscriptionRepository),
        RepositoryProvider<RecommendationRepository>.value(
            value: widget.recommendationRepository),
        RepositoryProvider<NotificationService>.value(
            value: widget.notificationService),
        RepositoryProvider<LocalStorageService>.value(
            value: widget.localStorage),
        RepositoryProvider<BrokerRepository>.value(
            value: widget.brokerRepository),
        RepositoryProvider<MarketDataRepository>(
          create: (_) => MarketDataRepositoryImpl(),
        ),
        RepositoryProvider<OptionChainRepository>(
          create: (_) => OptionChainRepositoryImpl(),
        ),
      ],
      child: BlocProvider<AuthBloc>.value(
        value: widget.authBloc,
        child: _SessionManager(router: widget.router),
      ),
    );
  }
}

// ── _SessionManager ───────────────────────────────────────────────────────────
//
// Provides session-scoped blocs permanently in the widget tree.
// The MultiBlocProvider is NEVER removed — blocs are replaced on login
// and closed+replaced with fresh idle instances on logout.
// This eliminates all "Provider not found" crashes during navigation transitions.

class _SessionManager extends StatefulWidget {
  const _SessionManager({required this.router});
  final GoRouter router;

  @override
  State<_SessionManager> createState() => _SessionManagerState();
}

class _SessionManagerState extends State<_SessionManager> {
  late SubscriptionCubit _subscriptionCubit;
  late FeedCubit _feedCubit;
  late PlansCubit _plansCubit;
  late NotificationCubit _notificationCubit;
  late MarketDataCubit _marketDataCubit;
  late LivePriceCubit _livePriceCubit;
  late BrokerCubit _brokerCubit;
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _initIdleBlocs();
    final current = context.read<AuthBloc>().state;
    if (current is AuthAuthenticated) {
      _replaceWithSession(current.uid);
    }
  }

  void _initIdleBlocs() {
    final planRepo = context.read<PlanRepository>();
    final subRepo = context.read<SubscriptionRepository>();
    final notifSvc = context.read<NotificationService>();
    final userRepo = context.read<UserRepository>();
    final recRepo = context.read<RecommendationRepository>();

    _subscriptionCubit = SubscriptionCubit(
      subscriptionRepository: subRepo,
      planRepository: planRepo,
      notificationService: notifSvc,
      userId: '',
    );
    _feedCubit = FeedCubit(recommendationRepository: recRepo);
    _plansCubit = PlansCubit(planRepository: planRepo);

    // NotificationCubit is created ONCE and kept alive for the entire app session.
    // The foreground message subscription must never be recreated — doing so
    // causes the BlocListener in _AppShell to lose its connection to the stream.
    _notificationCubit = NotificationCubit(
      notificationService: notifSvc,
      userRepository: userRepo,
      userId: '',
    )..initialize();

    final marketRepo = MarketDataRepositoryImpl();
    _marketDataCubit = MarketDataCubit(repository: marketRepo);

    _livePriceCubit = LivePriceCubit();

    // BrokerCubit starts idle (no uid) — load() is called on login.
    final brokerRepo = context.read<BrokerRepository>();
    _brokerCubit = BrokerCubit(
      brokerRepository: brokerRepo,
      userId: '',
    );
  }

  void _replaceWithSession(String uid) {
    if (_currentUid == uid) return;
    _currentUid = uid;

    final planRepo = context.read<PlanRepository>();
    final subRepo = context.read<SubscriptionRepository>();
    final notifSvc = context.read<NotificationService>();
    final recRepo = context.read<RecommendationRepository>();

    // Close and replace session-scoped blocs (NOT NotificationCubit)
    _subscriptionCubit.close();
    _feedCubit.close();
    _plansCubit.close();
    _marketDataCubit.close();
    _brokerCubit.close();

    _subscriptionCubit = SubscriptionCubit(
      subscriptionRepository: subRepo,
      planRepository: planRepo,
      notificationService: notifSvc,
      userId: uid,
    )..loadSubscriptions();

    _feedCubit = FeedCubit(recommendationRepository: recRepo);
    _plansCubit = PlansCubit(planRepository: planRepo)..loadPlans();

    final marketRepo = MarketDataRepositoryImpl();
    _marketDataCubit = MarketDataCubit(repository: marketRepo);

    // Create a fresh BrokerCubit for this session and start streaming.
    final brokerRepo = context.read<BrokerRepository>();
    _brokerCubit = BrokerCubit(
      brokerRepository: brokerRepo,
      userId: uid,
    )..load();

    // Connect live price service after login — reuse existing cubit, just connect
    _livePriceCubit.connect();

    // Subscribe every logged-in user to the all_users FCM topic so they
    // receive daily update notifications regardless of subscription plan.
    notifSvc.subscribeToTopic('all_users').catchError((_) {});

    // Just update the userId on the existing NotificationCubit — do NOT recreate it.
    _notificationCubit.updateUserId(uid);
  }

  void _closeAllBlocs() {
    _subscriptionCubit.close();
    _feedCubit.close();
    _plansCubit.close();
    _notificationCubit.close();
    _marketDataCubit.close();
    _livePriceCubit.close();
    _brokerCubit.close();
  }

  void _resetToIdle() {
    _subscriptionCubit.close();
    _feedCubit.close();
    _plansCubit.close();
    _marketDataCubit.close();
    _brokerCubit.close();
    // NotificationCubit stays alive — just clear the userId
    _notificationCubit.updateUserId('');
    // LivePriceCubit stays alive — disconnect the socket on logout
    _livePriceCubit.disconnect();
    _currentUid = null;

    final planRepo = context.read<PlanRepository>();
    final subRepo = context.read<SubscriptionRepository>();
    final notifSvc = context.read<NotificationService>();
    final recRepo = context.read<RecommendationRepository>();

    _subscriptionCubit = SubscriptionCubit(
      subscriptionRepository: subRepo,
      planRepository: planRepo,
      notificationService: notifSvc,
      userId: '',
    );
    _feedCubit = FeedCubit(recommendationRepository: recRepo);
    _plansCubit = PlansCubit(planRepository: planRepo);

    final marketRepo = MarketDataRepositoryImpl();
    _marketDataCubit = MarketDataCubit(repository: marketRepo);

    // Reset BrokerCubit to idle (uid = '') on logout.
    final brokerRepo = context.read<BrokerRepository>();
    _brokerCubit = BrokerCubit(
      brokerRepository: brokerRepo,
      userId: '',
    );
  }

  @override
  void dispose() {
    _closeAllBlocs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          setState(() => _replaceWithSession(state.uid));
        } else if (state is AuthInitial) {
          // Reset to idle blocs AFTER the router has navigated away.
          // Poll each frame until we're on a safe auth route.
          _waitForNavThenReset();
        }
      },
      // MultiBlocProvider stays in the tree permanently.
      child: MultiBlocProvider(
        providers: [
          BlocProvider<NotificationCubit>.value(value: _notificationCubit),
          BlocProvider<PlansCubit>.value(value: _plansCubit),
          BlocProvider<SubscriptionCubit>.value(value: _subscriptionCubit),
          BlocProvider<FeedCubit>.value(value: _feedCubit),
          BlocProvider<MarketDataCubit>.value(value: _marketDataCubit),
          BlocProvider<LivePriceCubit>.value(value: _livePriceCubit),
          BlocProvider<BrokerCubit>.value(value: _brokerCubit),
        ],
        child: _AppShell(router: widget.router),
      ),
    );
  }

  void _waitForNavThenReset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final location = widget.router.routerDelegate.currentConfiguration
          .matches.last.matchedLocation;
      if (location == '/phone-entry' || location == '/splash') {
        setState(() => _resetToIdle());
      } else {
        _waitForNavThenReset();
      }
    });
  }
}

// ── _AppShell ─────────────────────────────────────────────────────────────────

class _AppShell extends StatefulWidget {
  const _AppShell({required this.router});
  final GoRouter router;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      LivePriceService.instance.log('lifecycle_resumed');
      final livePriceCubit = context.read<LivePriceCubit>();
      livePriceCubit.connect();
    } else if (state == AppLifecycleState.paused) {
      LivePriceService.instance.log('lifecycle_paused');
      LivePriceService.instance.disconnect();
    } else if (state == AppLifecycleState.inactive) {
      LivePriceService.instance.log('lifecycle_inactive');
    } else if (state == AppLifecycleState.detached) {
      LivePriceService.instance.log('lifecycle_detached');
    }
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      // title: 'Recom',
      title: 'Stockara',
      debugShowCheckedModeBanner: false,
      theme: auroraTheme,
      routerConfig: widget.router,
      builder: (context, child) {
        return MultiBlocListener(
          listeners: [
            // ── Subscription expiry toast (≤ 2 days) ──────────────────────
            BlocListener<SubscriptionCubit, SubscriptionState>(
              listenWhen: (prev, curr) =>
                  curr is SubscriptionExpiringSoon &&
                  prev is! SubscriptionExpiringSoon,
              listener: (context, state) {
                if (state is! SubscriptionExpiringSoon) return;
                final days = state.daysRemaining;
                final label = days == 0
                    ? 'Your subscription expires today!'
                    : days == 1
                        ? 'Your subscription expires tomorrow!'
                        : 'Your subscription expires in $days days.';

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  // Play subscription expiry sound
                  LocalNotificationService.instance
                      .triggerForegroundFeedback(type: 'subscription_expiry');

                  final navigatorState =
                      widget.router.routerDelegate.navigatorKey.currentState;
                  final overlay = navigatorState?.overlay;
                  if (overlay != null) {
                    NotificationToast.show(
                      overlay.context,
                      title: '⏳ Subscription Expiring',
                      body: label,
                      style: NotificationToastStyle.warning,
                      duration: const Duration(seconds: 6),
                      onTap: () => widget.router.push('/plans'),
                    );
                  }
                });
              },
            ),
            // ── Foreground FCM messages ────────────────────────────────────
            BlocListener<NotificationCubit, NotificationState>(
              listener: (context, state) {
                debugPrint('🎯 [AppShell] BlocListener fired — state: ${state.runtimeType}');

                if (state is! NotificationForegroundMessage) {
                  debugPrint('🎯 [AppShell] Not a foreground message, ignoring');
                  return;
                }
            //
            // print('🎯 [AppShell] Processing foreground message...');
            // print('🎯 [AppShell] title: ${state.message.notification?.title}');
            // print('🎯 [AppShell] data: ${state.message.data}');

            final title = state.message.data['title'] as String? ??
                state.message.notification?.title ??
                'New notification';
            final body = state.message.data['body'] as String? ??
                state.message.notification?.body ?? '';
            final type = state.message.data['type'] as String?;

            IconData icon;
            Color backgroundColor;

            switch (type) {
              case 'trade':
                icon = Icons.swap_vert_rounded;
                backgroundColor = const Color(0xFF10B981);
                break;
              case 'alert':
              case 'warning':
                icon = Icons.warning_amber_rounded;
                backgroundColor = const Color(0xFFF59E0B);
                break;
              case 'target_hit':
                icon = Icons.check_circle_rounded;
                backgroundColor = const Color(0xFF16A34A);
                break;
              case 'stoploss_hit':
                icon = Icons.cancel_rounded;
                backgroundColor = const Color(0xFFEF4444);
                break;
              case 'daily_news':
                icon = Icons.newspaper_rounded;
                backgroundColor = const Color(0xFF0EA5E9);
                break;
              case 'subscription_expiry':
                icon = Icons.access_time_rounded;
                backgroundColor = const Color(0xFFF97316);
                break;
              default:
                icon = Icons.notifications_active_rounded;
                backgroundColor = const Color(0xFF4C46E5);
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              debugPrint('🎯 [AppShell] postFrameCallback — looking for navigator overlay...');

              // Trigger foreground haptic/sound feedback with per-type audio
              LocalNotificationService.instance.triggerForegroundFeedback(type: type);

              final navigatorState =
                  widget.router.routerDelegate.navigatorKey.currentState;
              debugPrint('🎯 [AppShell] navigatorState: $navigatorState');

              final overlay = navigatorState?.overlay;
              debugPrint('🎯 [AppShell] overlay: $overlay');

              if (overlay != null) {
                debugPrint('✅ [AppShell] Showing NotificationBanner via overlay');
                NotificationBanner.showOnOverlay(
                  overlay,
                  title: title,
                  body: body,
                  icon: icon,
                  backgroundColor: backgroundColor,
                  onTap: null,
                );
              } else {
                debugPrint('⚠️ [AppShell] overlay is null — falling back to SnackBar');
                final navContext =
                    widget.router.routerDelegate.navigatorKey.currentContext;
                debugPrint('🎯 [AppShell] navContext: $navContext');
                if (navContext != null && navContext.mounted) {
                  ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
                    SnackBar(
                      content: Text(title),
                      backgroundColor: backgroundColor,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                } else {
                  debugPrint('❌ [AppShell] navContext is null or unmounted — notification lost');
                }
              }
            });
          },
        ),
          ],
          child: ConnectivityBanner(
            onReconnect: () {
              // Reconnect the price socket when internet is restored
              final livePriceCubit = context.read<LivePriceCubit>();
              livePriceCubit.connect();
            },
            child: SecurityService.instance.watermarkEnabled
                ? _WatermarkOverlay(child: child ?? const SizedBox.shrink())
                : child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

// ── Watermark overlay ─────────────────────────────────────────────────────────

class _WatermarkOverlay extends StatelessWidget {
  final Widget child;
  const _WatermarkOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    // Get the logged-in user's phone number for the watermark
    final authState = context.read<AuthBloc>().state;
    final userLabel = authState is AuthAuthenticated
        ? authState.phoneNumber
        : 'Stockara';

    return Stack(
      children: [
        child,
        // Diagonal repeating watermark
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _WatermarkPainter(text: userLabel),
            ),
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;
  const _WatermarkPainter({required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x18000000); // 10% opacity black

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0x18000000),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.rotate(-0.4); // ~23 degrees diagonal

    const spacingX = 160.0;
    const spacingY = 100.0;

    for (double y = -size.height; y < size.height * 2; y += spacingY) {
      for (double x = -size.width; x < size.width * 2; x += spacingX) {
        textPainter.paint(canvas, Offset(x, y));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) => old.text != text;
}