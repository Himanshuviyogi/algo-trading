import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../blocs/auth_bloc.dart';
import '../cubits/broker_cubit.dart';
import '../cubits/live_price_cubit.dart';
import '../widgets/animated_market_strip.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens — vibrant day theme
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _DT {
  // Surfaces
  static const bg       = Color(0xFFF0F2F8); // cool blue-grey page base
  static const surface  = Color(0xFFFFFFFF); // white card
  static const surface2 = Color(0xFFE8ECF6); // shimmer / inset tint
  static const ink      = Color(0xFF1A1D2E); // hero card dark surface
  static const divider  = Color(0xFFE4E8F2); // crisp blue-grey hairline

  // Brand — vivid indigo-violet
  static const primary  = Color(0xFF6C63FF); // signature purple

  // Live signal dot
  static const signal = Color(0xFF00D18C); // bright green ping

  // Semantic
  static const profit  = Color(0xFF00A96E); // vivid green
  static const loss    = Color(0xFFE53935); // clear red
  static const warning = Color(0xFFF59E0B); // amber
  static const info    = Color(0xFF2196F3); // sky blue

  // Text
  static const t1     = Color(0xFF0D0F1A); // near-black
  static const t2     = Color(0xFF4A4F6A); // mid-slate
  static const t3     = Color(0xFF9399B8); // muted
  static const onInk1 = Color(0xFFF1F3FF); // on dark hero — primary text
  static const onInk2 = Color(0xFF8B91B0); // on dark hero — secondary text

  // Corner radii
  static const r14 = 14.0;
  static const r24 = 24.0;

  // Numeric text — tabular figures so P&L columns line up like a ledger.
  static TextStyle numeral({
    required double size,
    required FontWeight weight,
    required Color color,
    double letterSpacing = -0.4,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HomeDashboardScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen>
    with TickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;

  // ── KPI stats ──────────────────────────────────────────────────────────────
  int _deployedStrategies = 0;
  int _activeBots = 0;
  double _todayPnl = 0;
  double _overallPnl = 0;
  bool _statsLoading = true;

  // ── Broker banner ──────────────────────────────────────────────────────────
  bool _brokerBannerDismissed = false;

  // ── Positions ──────────────────────────────────────────────────────────────
  int _openPositions = 0;

  // ── Streams ────────────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _positionsSub;
  StreamSubscription<DocumentSnapshot>? _statsSub;

  // ── Enter animation ────────────────────────────────────────────────────────
  late AnimationController _enterCtrl;
  late Animation<double> _enterAnim;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _enterAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
    _enterCtrl.forward();

    _subscribeToAlgoStats();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _subscribeToOpenPositions(authState.uid);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LivePriceCubit>().subscribe(const [
        'NIFTY', 'BANKNIFTY', 'SENSEX', 'RELIANCE', 'TCS',
        'HDFCBANK', 'INFY', 'SBIN', 'ICICIBANK', 'GOLD',
        'CRUDEOIL', 'USDINR',
      ]);
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _statsSub?.cancel();
    _positionsSub?.cancel();
    super.dispose();
  }

  void _subscribeToOpenPositions(String uid) {
    _positionsSub?.cancel();
    _positionsSub = _firestore
        .collection('positions')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _openPositions = snap.docs.length);
    }, onError: (_) {});
  }

  void _subscribeToAlgoStats() {
    _statsSub = _firestore
        .collection('app_config')
        .doc('algo_stats')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data() ?? {};
      setState(() {
        _deployedStrategies = (data['deployed_strategies'] as num?)?.toInt() ?? 0;
        _activeBots         = (data['active_bots'] as num?)?.toInt() ?? 0;
        _todayPnl           = (data['today_pnl'] as num?)?.toDouble() ?? 0;
        _overallPnl         = (data['overall_pnl'] as num?)?.toDouble() ?? 0;
        _statsLoading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _statsLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthBloc>().state;
    return Scaffold(
      backgroundColor: _DT.bg,
      body: FadeTransition(
        opacity: _enterAnim,
        child: RefreshIndicator(
          color: _DT.primary,
          backgroundColor: _DT.surface,
          onRefresh: () async {
            setState(() => _statsLoading = true);
            _subscribeToAlgoStats();
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // ── App Bar ─────────────────────────────────────────────────
              _DashboardAppBar(
                onMarketTap:        () => context.push('/market'),
                onPlansTap:         () => context.push('/plans'),
                onNotificationsTap: () => context.push('/notifications'),
              ),

              // ── Broker setup banner ──────────────────────────────────────
              BlocBuilder<BrokerCubit, BrokerState>(
                builder: (context, brokerState) {
                  final hasConnected = brokerState is BrokerLoaded &&
                      brokerState.hasConnectedBroker;
                  if (hasConnected || _brokerBannerDismissed) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }
                  return SliverToBoxAdapter(
                    child: _BrokerSetupBanner(
                      onSetupTap: () => context.push('/broker-setup'),
                      onDismiss: () =>
                          setState(() => _brokerBannerDismissed = true),
                    ),
                  );
                },
              ),

              // ── Market Ticker Strip ──────────────────────────────────────
              SliverToBoxAdapter(
                child: _TickerWrapper(child: const AnimatedMarketStrip()),
              ),

              // ── Body content ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Hero P&L card ──────────────────────────────────
                      _PnlHeroCard(
                        todayPnl: _todayPnl,
                        overallPnl: _overallPnl,
                        openPositions: _openPositions,
                        activeBots: _activeBots,
                        isLoading: _statsLoading,
                        onTap: () => context.go('/home/positions'),
                      ),
                      const SizedBox(height: 14),

                      // ── Metric grid ────────────────────────────────────
                      _MetricStrip(
                        strategies: _deployedStrategies,
                        positions: _openPositions,
                        todayPnl: _todayPnl,
                        overallPnl: _overallPnl,
                        isLoading: _statsLoading,
                        onStrategiesTap: () => context.go('/home/strategies'),
                        onPositionsTap: () => context.go('/home/positions'),
                      ),
                      const SizedBox(height: 24),

                      // ── Quick Actions ─────────────────────────────────
                      _QuickActionsRow(
                        onStrategies:  () => context.go('/home/strategies'),
                        onOrders:      () => context.go('/home/orders'),
                        onPositions:   () => context.go('/home/positions'),
                        onMarket:      () => context.push('/market'),
                        onPlans:       () => context.push('/plans'),
                        onBreakouts:   () => context.push('/breakouts'),
                        onOptionChain: () => context.push('/option-chain'),
                        onNews:        () => context.push('/news_updates'),
                      ),
                      const SizedBox(height: 26),

                      // ── Market Snapshot ───────────────────────────────
                      _SectionLabel(
                        icon: Icons.candlestick_chart_rounded,
                        iconColor: _DT.info,
                        title: 'Market snapshot',
                        actionLabel: 'All markets',
                        onAction: () => context.push('/market'),
                      ),
                      const SizedBox(height: 10),
                      const _MarketSnapshot(),
                      const SizedBox(height: 26),

                      // ── Deployed Strategies ────────────────────────────
                      _SectionLabel(
                        icon: Icons.auto_graph_rounded,
                        iconColor: _DT.primary,
                        title: 'Deployed strategies',
                        actionLabel: 'View all',
                        onAction: () => context.go('/home/strategies'),
                      ),
                      const SizedBox(height: 10),
                      const _StrategyOverviewSection(),
                      const SizedBox(height: 26),

                      // ── Recent Trades ──────────────────────────────────
                      _SectionLabel(
                        icon: Icons.receipt_long_rounded,
                        iconColor: _DT.t2,
                        title: 'Recent trades',
                        actionLabel: 'View all',
                        onAction: () => context.go('/home/orders'),
                      ),
                      const SizedBox(height: 10),
                      const _RecentTradesSection(),

                      // ── Bottom padding for nav bar ─────────────────────
                      SizedBox(height: MediaQuery.of(context).padding.bottom + 96),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardAppBar extends StatelessWidget {
  const _DashboardAppBar({
    required this.onMarketTap,
    required this.onPlansTap,
    required this.onNotificationsTap,
  });
  final VoidCallback onMarketTap;
  final VoidCallback onPlansTap;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: _DT.bg,
      elevation: 0,
      floating: true,
      pinned: false,
      titleSpacing: 16,
      title: Row(
        children: [
          // Logo mark — gradient tile
          Container(
            height: 38, width: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF48C6EF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: _DT.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset('assets/images/small_logo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Algo Trader',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _DT.t1,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              Row(children: [
                _PulseDot(color: _DT.signal),
                const SizedBox(width: 5),
                const Text(
                  'Markets live',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _DT.t2),
                ),
              ]),
            ],
          ),
        ],
      ),
      actions: [
        _AppBarAction(
          icon: Icons.show_chart_rounded,
          onTap: onMarketTap,
        ),
        const SizedBox(width: 8),
        _AppBarAction(
          icon: Icons.notifications_outlined,
          onTap: onNotificationsTap,
        ),
        const SizedBox(width: 8),
        _AppBarActionBadged(
          icon: Icons.workspace_premium_rounded,
          onTap: onPlansTap,
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

class _AppBarAction extends StatelessWidget {
  const _AppBarAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36, width: 36,
        decoration: BoxDecoration(
          color: _DT.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _DT.divider, width: 1),
        ),
        child: Icon(icon, color: _DT.t1, size: 17),
      ),
    );
  }
}

class _AppBarActionBadged extends StatelessWidget {
  const _AppBarActionBadged({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _AppBarAction(icon: icon, onTap: onTap),
        Positioned(
          top: 1, right: 1,
          child: Container(
            height: 7, width: 7,
            decoration: BoxDecoration(
              color: _DT.loss,
              shape: BoxShape.circle,
              border: Border.all(color: _DT.bg, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ticker strip wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _TickerWrapper extends StatelessWidget {
  const _TickerWrapper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _DT.surface,
        border: Border(
          top: BorderSide(color: _DT.divider, width: 1),
          bottom: BorderSide(color: _DT.divider, width: 1),
        ),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero P&L Card — the one bold moment: flat ink surface, ledger-style
//  numerals, a slim signal-colored rule instead of a glow/gradient wash.
// ─────────────────────────────────────────────────────────────────────────────

class _PnlHeroCard extends StatelessWidget {
  const _PnlHeroCard({
    required this.todayPnl,
    required this.overallPnl,
    required this.openPositions,
    required this.activeBots,
    required this.isLoading,
    required this.onTap,
  });

  final double todayPnl;
  final double overallPnl;
  final int openPositions;
  final int activeBots;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isProfit = todayPnl >= 0;
    final moveColor = isProfit ? _DT.signal : const Color(0xFFFF6B6B);
    final sign = todayPnl >= 0 ? '+' : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: _DT.ink,
          borderRadius: BorderRadius.circular(_DT.r24),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1D2E), Color(0xFF252845)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _DT.primary.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: isLoading
            ? const _HeroShimmer()
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "TODAY'S P&L",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _DT.onInk2,
                    letterSpacing: 1.1,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isProfit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: moveColor,
                        size: 12,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        overallPnl != 0
                            ? '${((todayPnl.abs() / (overallPnl.abs() == 0 ? 1 : overallPnl.abs())) * 100).toStringAsFixed(1)}%'
                            : '—',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: moveColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$sign₹${todayPnl.toStringAsFixed(0)}',
              style: _DT.numeral(size: 36, weight: FontWeight.w800, color: _DT.onInk1, letterSpacing: -1.2),
            ),
            const SizedBox(height: 18),
            // Slim signal rule — replaces the gradient glow.
            Container(
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.32,
                child: Container(
                  decoration: BoxDecoration(
                    color: moveColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _HeroStat(
                  label: 'Overall P&L',
                  value: '${overallPnl >= 0 ? '+' : ''}₹${overallPnl.toStringAsFixed(0)}',
                ),
                _VertDivider(),
                _HeroStat(
                  label: 'Open positions',
                  value: '$openPositions',
                ),
                _VertDivider(),
                _HeroStat(
                  label: 'Active bots',
                  value: '$activeBots',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: _DT.numeral(size: 15, weight: FontWeight.w700, color: _DT.onInk1, letterSpacing: -0.2),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: _DT.onInk2),
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26, width: 1,
      color: Colors.white.withValues(alpha: 0.10),
      margin: const EdgeInsets.symmetric(horizontal: 14),
    );
  }
}

class _HeroShimmer extends StatelessWidget {
  const _HeroShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShimmerBox(width: 100, height: 11, radius: 6, dark: true),
        const SizedBox(height: 12),
        _ShimmerBox(width: 180, height: 36, radius: 8, dark: true),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: _ShimmerBox(height: 28, radius: 6, dark: true)),
          const SizedBox(width: 14),
          Expanded(child: _ShimmerBox(height: 28, radius: 6, dark: true)),
          const SizedBox(width: 14),
          Expanded(child: _ShimmerBox(height: 28, radius: 6, dark: true)),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Metric strip — a single hairline-divided panel instead of four identical
//  shadowed cards (avoids the repeated-card-kit look, still fully tappable).
// ─────────────────────────────────────────────────────────────────────────────

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({
    required this.strategies,
    required this.positions,
    required this.todayPnl,
    required this.overallPnl,
    required this.isLoading,
    required this.onStrategiesTap,
    required this.onPositionsTap,
  });

  final int strategies, positions;
  final double todayPnl, overallPnl;
  final bool isLoading;
  final VoidCallback onStrategiesTap, onPositionsTap;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Row(
        children: List.generate(4, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
            child: _ShimmerBox(height: 64, radius: _DT.r14),
          ),
        )),
      );
    }

    final items = [
      _MetricItem(
        label: 'Strategies',
        value: '$strategies',
        icon: Icons.auto_graph_rounded,
        color: _DT.primary,
        onTap: onStrategiesTap,
      ),
      _MetricItem(
        label: 'Positions',
        value: '$positions',
        icon: Icons.account_balance_wallet_rounded,
        color: _DT.info,
        onTap: onPositionsTap,
      ),
      _MetricItem(
        label: "Today",
        value: '${todayPnl >= 0 ? '+' : ''}₹${todayPnl.toStringAsFixed(0)}',
        icon: Icons.today_rounded,
        color: todayPnl >= 0 ? _DT.profit : _DT.loss,
        onTap: onPositionsTap,
      ),
      _MetricItem(
        label: 'Overall',
        value: '${overallPnl >= 0 ? '+' : ''}₹${overallPnl.toStringAsFixed(0)}',
        icon: Icons.stacked_line_chart_rounded,
        color: overallPnl >= 0 ? _DT.profit : _DT.loss,
        onTap: onPositionsTap,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _DT.surface,
        borderRadius: BorderRadius.circular(_DT.r14),
        border: Border.all(color: _DT.divider, width: 1),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i != 0)
              Container(width: 1, height: 56, color: _DT.divider),
            Expanded(child: _MetricCell(item: items[i])),
          ],
        ],
      ),
    );
  }
}

class _MetricItem {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _MetricCell extends StatefulWidget {
  const _MetricCell({required this.item});
  final _MetricItem item;

  @override
  State<_MetricCell> createState() => _MetricCellState();
}

class _MetricCellState extends State<_MetricCell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.item.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.55 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(widget.item.icon, size: 12, color: widget.item.color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _DT.t2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _DT.numeral(size: 15, weight: FontWeight.w800, color: _DT.t1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Quick Actions Row  (horizontal scroll, flat outline chips)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onStrategies,
    required this.onOrders,
    required this.onPositions,
    required this.onMarket,
    required this.onPlans,
    required this.onBreakouts,
    required this.onOptionChain,
    required this.onNews,
  });
  final VoidCallback onStrategies, onOrders, onPositions, onMarket, onPlans;
  final VoidCallback onBreakouts, onOptionChain, onNews;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QA(icon: Icons.auto_graph_rounded,             label: 'Strategies',   color: _DT.primary,  onTap: onStrategies),
      _QA(icon: Icons.receipt_long_rounded,           label: 'Orders',       color: _DT.info,     onTap: onOrders),
      _QA(icon: Icons.account_balance_wallet_rounded, label: 'Positions',    color: _DT.profit,   onTap: onPositions),
      _QA(icon: Icons.candlestick_chart_rounded,      label: 'Market',       color: _DT.t1,       onTap: onMarket),
      _QA(icon: Icons.workspace_premium_rounded,      label: 'Plans',        color: _DT.warning,  onTap: onPlans),
      _QA(icon: Icons.bolt_rounded,                   label: 'Breakouts',    color: const Color(0xFF7C3AED), onTap: onBreakouts),
      _QA(icon: Icons.table_chart_outlined,           label: 'Option Chain', color: const Color(0xFF0891B2), onTap: onOptionChain),
      _QA(icon: Icons.newspaper_rounded,              label: 'News',         color: const Color(0xFFD97706), onTap: onNews),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick access',
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: _DT.t1, letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: actions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _QuickActionChip(qa: actions[i]),
          ),
        ),
      ],
    );
  }
}

class _QA {
  const _QA({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _QuickActionChip extends StatefulWidget {
  const _QuickActionChip({required this.qa});
  final _QA qa;

  @override
  State<_QuickActionChip> createState() => _QuickActionChipState();
}

class _QuickActionChipState extends State<_QuickActionChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.qa.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          height: 40,
          decoration: BoxDecoration(
            color: _DT.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _DT.divider, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.qa.icon, color: widget.qa.color, size: 15),
              const SizedBox(width: 7),
              Text(
                widget.qa.label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _DT.t1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Market Snapshot — horizontal scrolling chip cards
// ─────────────────────────────────────────────────────────────────────────────

const List<(String, String)> _kSnapSymbols = [
  ('NIFTY', 'Nifty 50'),
  ('BANKNIFTY', 'Bank Nifty'),
  ('SENSEX', 'Sensex'),
  ('GOLD', 'Gold'),
  ('CRUDEOIL', 'Crude Oil'),
  ('USDINR', 'USD/INR'),
  ('RELIANCE', 'Reliance'),
  ('TCS', 'TCS'),
  ('HDFCBANK', 'HDFC Bank'),
  ('INFY', 'Infosys'),
  ('SBIN', 'SBI'),
  ('ICICIBANK', 'ICICI Bank'),
];

class _MarketSnapshot extends StatelessWidget {
  const _MarketSnapshot();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LivePriceCubit, LivePriceState>(
      builder: (context, state) {
        return SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _kSnapSymbols.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (sym, label) = _kSnapSymbols[i];
              final tick = state.prices[sym];
              final ltp = tick?.ltp;
              final pct = tick?.changePercent ?? 0.0;
              final isPos = pct >= 0;
              final trendColor = isPos ? _DT.profit : _DT.loss;

              return GestureDetector(
                onTap: () => context.push('/chart/$sym'),
                child: Container(
                  width: 108,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _DT.surface,
                    borderRadius: BorderRadius.circular(_DT.r14),
                    border: Border.all(color: _DT.divider, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        sym,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _DT.t2,
                          letterSpacing: 0.1,
                        ),
                      ),
                      Text(
                        ltp != null ? '₹${ltp.toStringAsFixed(ltp >= 1000 ? 0 : 2)}' : '—',
                        style: _DT.numeral(size: 14, weight: FontWeight.w800, color: _DT.t1, letterSpacing: -0.2),
                      ),
                      Row(
                        children: [
                          Icon(
                            isPos ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 10,
                            color: trendColor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            ltp != null ? '${pct.abs().toStringAsFixed(2)}%' : '—',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: trendColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section Label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _DT.t1,
            letterSpacing: -0.2,
          ),
        ),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _DT.primary,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 14, color: _DT.primary),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Strategy Overview Section
// ─────────────────────────────────────────────────────────────────────────────

class _StrategyOverviewSection extends StatefulWidget {
  const _StrategyOverviewSection();
  @override
  State<_StrategyOverviewSection> createState() => _StrategyOverviewSectionState();
}

class _StrategyOverviewSectionState extends State<_StrategyOverviewSection> {
  List<Map<String, dynamic>> _strategies = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _adminSub;
  StreamSubscription<QuerySnapshot>? _userSub;
  String? _uid;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _uid = authState is AuthAuthenticated ? authState.uid : null;
    _subscribeAdminStrategies();
    if (_uid != null) _subscribeUserStrategies(_uid!);
  }

  void _subscribeAdminStrategies() {
    _adminSub = FirebaseFirestore.instance
        .collection('algo_signals')
        .where('source', isEqualTo: 'admin')
        .where('is_published', isEqualTo: true)
        .where('status', isEqualTo: 'live')
        .orderBy('posted_at', descending: true)
        .limit(3)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final adminDocs = snap.docs.map((d) {
        final data = d.data();
        final stock = data['stock'] as Map? ?? {};
        return {
          'id': d.id,
          'name': stock['name'] as String? ?? data['title'] as String? ?? 'Admin Strategy',
          'instrument': stock['symbol'] as String? ?? '—',
          'is_active': data['status'] == 'live',
          'pnl': (data['performance']?['gain_so_far'] as num?)?.toDouble() ?? 0.0,
          'total_trades': 0,
          'source': 'admin',
        };
      }).toList();
      if (!mounted) return;
      setState(() {
        _strategies = [
          ...adminDocs,
          ..._strategies.where((s) => s['source'] == 'user'),
        ];
        _loading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _subscribeUserStrategies(String uid) {
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('strategies')
        .orderBy('created_at', descending: true)
        .limit(2)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final userDocs = snap.docs.map((d) {
        final data = d.data();
        final stock = data['stock'] as Map? ?? {};
        return {
          'id': d.id,
          'name': stock['name'] as String? ?? 'My Strategy',
          'instrument': stock['symbol'] as String? ?? '—',
          'is_active': data['status'] == 'live',
          'pnl': 0.0,
          'total_trades': 0,
          'source': 'user',
        };
      }).toList();
      if (!mounted) return;
      setState(() {
        _strategies = [
          ..._strategies.where((s) => s['source'] == 'admin'),
          ...userDocs,
        ];
        _loading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _adminSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(
        children: List.generate(2, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ShimmerBox(height: 72, radius: _DT.r14),
        )),
      );
    }
    if (_strategies.isEmpty) {
      return _EmptyState(
        icon: Icons.auto_graph_rounded,
        iconColor: _DT.primary,
        message: 'No strategies deployed yet',
        subMessage: 'Create a strategy to start automated trading',
        actionLabel: 'Go to strategies',
        onAction: () => context.go('/home/strategies'),
      );
    }
    return Column(
      children: _strategies.map((s) => _StrategyCard(strategy: s)).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Strategy Card
// ─────────────────────────────────────────────────────────────────────────────

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({required this.strategy});
  final Map<String, dynamic> strategy;

  @override
  Widget build(BuildContext context) {
    final name       = strategy['name'] as String? ?? 'Unnamed Strategy';
    final isActive   = strategy['is_active'] as bool? ?? false;
    final pnl        = (strategy['pnl'] as num?)?.toDouble() ?? 0.0;
    final trades     = (strategy['total_trades'] as num?)?.toInt() ?? 0;
    final instrument = strategy['instrument'] as String? ?? '—';
    final pnlColor   = pnl >= 0 ? _DT.profit : _DT.loss;
    final statusColor = isActive ? _DT.profit : _DT.t3;
    final sign = pnl >= 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _DT.surface,
        borderRadius: BorderRadius.circular(_DT.r14),
        border: Border.all(
          color: isActive ? _DT.profit.withValues(alpha: 0.35) : _DT.divider,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Status indicator bar
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // Icon
          Container(
            height: 38, width: 38,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              isActive ? Icons.bolt_rounded : Icons.pause_rounded,
              color: statusColor,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          // Name + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _DT.t1,
                  ),
                ),
                const SizedBox(height: 3),
                Row(children: [
                  _MiniChip(label: instrument, color: _DT.primary),
                  const SizedBox(width: 6),
                  Text(
                    '$trades trades',
                    style: const TextStyle(fontSize: 10, color: _DT.t3),
                  ),
                ]),
              ],
            ),
          ),
          // P&L + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign₹${pnl.toStringAsFixed(0)}',
                style: _DT.numeral(size: 15, weight: FontWeight.w800, color: pnlColor, letterSpacing: -0.3),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 5, width: 5,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isActive ? 'Live' : 'Paused',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Recent Trades Section
// ─────────────────────────────────────────────────────────────────────────────

class _RecentTradesSection extends StatefulWidget {
  const _RecentTradesSection();
  @override
  State<_RecentTradesSection> createState() => _RecentTradesSectionState();
}

class _RecentTradesSectionState extends State<_RecentTradesSection> {
  List<Map<String, dynamic>> _trades = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    final uid = authState is AuthAuthenticated ? authState.uid : null;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('orders')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'complete')
        .orderBy('placed_at', descending: true)
        .limit(5)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _trades = snap.docs.map((d) {
          final data = d.data();
          return {
            'id': d.id,
            'symbol':      data['symbol']   as String? ?? '—',
            'action':      data['action']   as String? ?? 'BUY',
            'quantity':    data['quantity'] as num?    ?? 0,
            'price':       data['price']    as num?    ?? 0.0,
            'pnl':         null,
            'executed_at': data['placed_at'],
          };
        }).toList();
        _loading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(
        children: List.generate(3, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _ShimmerBox(height: 58, radius: _DT.r14),
        )),
      );
    }
    if (_trades.isEmpty) {
      return _EmptyState(
        icon: Icons.receipt_long_rounded,
        iconColor: _DT.t2,
        message: 'No trades yet',
        subMessage: 'Executed trades will appear here',
        actionLabel: 'View orders',
        onAction: () => context.go('/home/orders'),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _trades.asMap().entries.map((entry) {
          final isLast = entry.key == _trades.length - 1;
          return _TradeRow(trade: entry.value, isLast: isLast);
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Trade Row  (flat full-width card — no timeline indent)
// ─────────────────────────────────────────────────────────────────────────────

class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade, this.isLast = false});
  final Map<String, dynamic> trade;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final symbol    = trade['symbol'] as String? ?? '—';
    final action    = (trade['action'] as String? ?? 'BUY').toUpperCase();
    final qty       = (trade['quantity'] as num?)?.toInt() ?? 0;
    final price     = (trade['price'] as num?)?.toDouble() ?? 0.0;
    final pnl       = (trade['pnl'] as num?)?.toDouble();
    final isBuy     = action == 'BUY';
    final sideColor = isBuy ? _DT.profit : _DT.loss;
    final ts        = trade['executed_at'];
    String timeStr  = '';
    if (ts != null) {
      try {
        final dt = (ts as Timestamp).toDate();
        timeStr =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}  '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _DT.surface,
        borderRadius: BorderRadius.circular(_DT.r14),
        border: Border.all(color: _DT.divider, width: 1),
      ),
      child: Row(
        children: [
          // Side icon
          Container(
            height: 36, width: 36,
            decoration: BoxDecoration(
              color: sideColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: sideColor,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          // Symbol + details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    symbol,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _DT.t1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _MiniChip(label: action, color: sideColor),
                ]),
                const SizedBox(height: 2),
                Text(
                  'Qty: $qty  •  ₹${price.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 10.5, color: _DT.t3),
                ),
              ],
            ),
          ),
          // P&L + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pnl != null)
                Text(
                  '${pnl >= 0 ? '+' : ''}₹${pnl.toStringAsFixed(0)}',
                  style: _DT.numeral(
                    size: 13,
                    weight: FontWeight.w800,
                    color: pnl >= 0 ? _DT.profit : _DT.loss,
                  ),
                ),
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: const TextStyle(fontSize: 10, color: _DT.t3),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.iconColor,
    required this.message,
    required this.subMessage,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final Color iconColor;
  final String message, subMessage, actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        color: _DT.surface,
        borderRadius: BorderRadius.circular(_DT.r14),
        border: Border.all(color: _DT.divider, width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor.withValues(alpha: 0.45), size: 26),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _DT.t1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _DT.t3),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: _DT.ink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _DT.onInk1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Mini coloured chip/badge.
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Pulsing dot indicator.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_anim),
      child: Container(
        height: 6, width: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Generic shimmer placeholder. Set [dark] true when used on the ink hero.
class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({this.width, required this.height, required this.radius, this.dark = false});
  final double? width;
  final double height;
  final double radius;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.08) : _DT.surface2,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Broker Setup Banner
// ─────────────────────────────────────────────────────────────────────────────

/// Shown at the top of the home feed when no broker has been connected.
/// The user can tap "Set up now" to navigate to [BrokerSetupScreen] or
/// dismiss the banner for the current session via the × button.
class _BrokerSetupBanner extends StatelessWidget {
  const _BrokerSetupBanner({
    required this.onSetupTap,
    required this.onDismiss,
  });

  final VoidCallback onSetupTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // ── Icon ──────────────────────────────────────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // ── Text ──────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Connect your broker',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Link Angel One to start live trading.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // ── CTA button ────────────────────────────────────────────
              GestureDetector(
                onTap: onSetupTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Set up',
                    style: TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // ── Dismiss ───────────────────────────────────────────────
              GestureDetector(
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.75),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
