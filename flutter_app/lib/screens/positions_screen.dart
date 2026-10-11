import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';

import '../blocs/auth_bloc.dart';
import '../cubits/live_price_cubit.dart';
import '../cubits/order_cubit.dart';
import '../cubits/position_cubit.dart';
import '../models/order.dart';
import '../models/position.dart';
import '../repositories/order_repository.dart';
import '../repositories/position_repository.dart';
import '../services/order_service.dart';
import '../utils/app_theme.dart';

// ── PositionsScreen ────────────────────────────────────────────────────────────
//
// Provides its own PositionCubit scoped to this screen so the cubit's
// Firestore + price streams are created/destroyed with the screen itself.

class PositionsScreen extends StatelessWidget {
  const PositionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return const Scaffold(
        body: Center(child: Text('Not authenticated')),
      );
    }

    return BlocProvider<PositionCubit>(
      create: (ctx) => PositionCubit(
        positionRepository: ctx.read<PositionRepository>(),
        livePriceCubit: ctx.read<LivePriceCubit>(),
        userId: authState.uid,
      )..loadPositions(),
      child: const _PositionsView(),
    );
  }
}

// ── _PositionsView ─────────────────────────────────────────────────────────────

class _PositionsView extends StatefulWidget {
  const _PositionsView();

  @override
  State<_PositionsView> createState() => _PositionsViewState();
}

class _PositionsViewState extends State<_PositionsView> {
  bool _syncing = false;

  // Pull-to-refresh: calls POST /sync-positions/:userId on the price server,
  // then reloads positions from Firestore via the cubit.
  Future<void> _syncPositions() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) return;

      const serverUrl = String.fromEnvironment(
        'PRICE_SERVER_URL',
        defaultValue: 'http://31.172.87.141:3002',
      );

      final user = FirebaseAuth.instance.currentUser;
      final token = user != null ? await user.getIdToken(true) : null;

      await http
          .post(
            Uri.parse('$serverUrl/sync-positions/${authState.uid}'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Silent — Firestore stream will surface any real errors.
    } finally {
      if (mounted) {
        context.read<PositionCubit>().loadPositions();
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuroraColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AuroraColors.violet,
                    ),
                  )
                : const Icon(Icons.sync_rounded, color: AuroraColors.violet),
            onPressed: _syncing ? null : _syncPositions,
          ),
        ],
        title: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFFF1F3F7),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/images/small_logo.png'),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Positions',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  'Live P&L',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
      body: BlocBuilder<PositionCubit, PositionState>(
        builder: (context, state) {
          if (state is PositionLoading) return _buildShimmer();
          if (state is PositionError)   return _buildError(state.message);
          if (state is PositionLoaded)  return _buildLoaded(context, state);
          return const SizedBox.shrink();
        },
      ),
    );
  }

  // ── States ───────────────────────────────────────────────────────────────────

  Widget _buildLoaded(BuildContext context, PositionLoaded state) {
    return RefreshIndicator(
      color: AuroraColors.violet,
      onRefresh: _syncPositions,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Portfolio P&L header ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: _PortfolioPnlHeader(
              totalPnl: state.totalPnl,
              totalPnlPercent: state.totalPnlPercent,
              positionCount: state.positions.length,
            ),
          ),

          // ── Empty state ───────────────────────────────────────────────────
          if (state.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(),
            )
          else ...[
            // ── Section label ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'OPEN POSITIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),

            // ── Position cards ────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final pos = state.positions[i];
                    final authState = context.read<AuthBloc>().state as AuthAuthenticated;

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 250 + i * 50),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (_, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, 18 * (1 - v)),
                          child: child,
                        ),
                      ),
                      child: BlocProvider<OrderCubit>(
                        key: ValueKey(pos.id),
                        create: (ctx) => OrderCubit(
                          orderRepository: ctx.read<OrderRepository>(),
                          orderService: OrderService.instance,
                          userId: authState.uid,
                        ),
                        child: _PositionCard(position: pos),
                      ),
                    );
                  },
                  childCount: state.positions.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AuroraColors.violet.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.candlestick_chart_rounded,
              size: 36,
              color: AuroraColors.violet,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No open positions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Positions will appear here once orders\nare filled by the broker.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _syncPositions,
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text('Sync from broker'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AuroraColors.violet,
              side: const BorderSide(color: AuroraColors.violet),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            const Text(
              'Failed to load positions',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151)),
            ),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AuroraColors.violet,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.read<PositionCubit>().loadPositions(),
              child: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 5,
      itemBuilder: (_, __) => const _ShimmerCard(),
    );
  }
}

// ── Portfolio P&L Header ───────────────────────────────────────────────────────

class _PortfolioPnlHeader extends StatelessWidget {
  const _PortfolioPnlHeader({
    required this.totalPnl,
    required this.totalPnlPercent,
    required this.positionCount,
  });

  final double totalPnl;
  final double totalPnlPercent;
  final int positionCount;

  @override
  Widget build(BuildContext context) {
    final isProfit = totalPnl >= 0;
    final sign = isProfit ? '+' : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isProfit
              ? [const Color(0xFF059669), const Color(0xFF10B981)]
              : [const Color(0xFFDC2626), const Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (isProfit
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444))
                .withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Unrealised P&L',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0, end: totalPnl),
                  builder: (_, val, __) => Text(
                    '${val >= 0 ? '+' : ''}₹${val.abs().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$sign${totalPnlPercent.toStringAsFixed(2)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$positionCount position${positionCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isProfit
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _PositionCard ──────────────────────────────────────────────────────────────

class _PositionCard extends StatefulWidget {
  const _PositionCard({required this.position});

  final AlgoPosition position;

  @override
  State<_PositionCard> createState() => _PositionCardState();
}

class _PositionCardState extends State<_PositionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(_scaleCtrl);
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _tapDown(_) => _scaleCtrl.forward();
  void _tapUp(_) => _scaleCtrl.reverse();

  // ── Close-position confirmation ────────────────────────────────────────────

  Future<void> _confirmClose(BuildContext context) async {
    final pos = widget.position;
    final ltp = context.read<LivePriceCubit>().state.ltp(pos.symbol);
    final closePrice = ltp ?? pos.currentPrice;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CloseConfirmSheet(
        position: pos,
        closePrice: closePrice,
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Opposite action: BUY position → SELL to close; SELL → BUY
    final closeAction =
        pos.action.toUpperCase() == 'BUY' ? 'SELL' : 'BUY';

    // OrderCubit.placeOrder requires a Recommendation — for close orders
    // we build a minimal synthetic signal object directly via OrderService.
    // Instead, we access the cubit and call the lower-level service method.
    //
    // The closest canonical path is to call OrderCubit.placeOrder with a
    // minimal Recommendation. However, because closing a position doesn't
    // originate from a signal, we call OrderService directly and emit state
    // through the cubit via the pattern already established in OrderCubit.
    final authState = context.read<AuthBloc>().state as AuthAuthenticated;

    try {
      final result = await OrderService.instance.placeOrder(
        userId:    authState.uid,
        signalId:  pos.signalId,       // link back to the original signal
        symbol:    pos.symbol,
        exchange:  pos.exchange,
        action:    closeAction,
        orderType: 'MARKET',
        quantity:  pos.quantity,
        price:     closePrice,
      );

      // Write to Firestore via the repository
      final now = DateTime.now();
      await context.read<OrderRepository>().createOrder(
        AlgoOrder(
          id:           result.firestoreOrderId,
          signalId:     pos.signalId,
          userId:       authState.uid,
          symbol:       pos.symbol,
          exchange:     pos.exchange,
          action:       closeAction,
          orderType:    'MARKET',
          quantity:     pos.quantity,
          price:        closePrice,
          angelOrderId: result.angelOrderId,
          status:       OrderStatus.pending,
          placedAt:     now,
          updatedAt:    now,
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Close order placed for ${pos.symbol} (${pos.quantity} qty)'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } on OrderBlockedException catch (e) {
      _showError(context, e.reason);
    } on OrderServerException catch (e) {
      _showError(context, e.message);
    } catch (e) {
      _showError(context, e.toString());
    }
  }

  void _showError(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the price for this symbol changes.
    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
          prev.prices[widget.position.symbol]?.ltp !=
          curr.prices[widget.position.symbol]?.ltp,
      builder: (context, priceState) {
        final pos = widget.position;
        final ltp = priceState.ltp(pos.symbol) ?? pos.currentPrice;

        // Recompute P&L live from the latest LTP
        final isBuy = pos.action.toUpperCase() == 'BUY';
        final livePnl = isBuy
            ? (ltp - pos.avgPrice) * pos.quantity
            : (pos.avgPrice - ltp) * pos.quantity;
        final costBasis = pos.avgPrice * pos.quantity;
        final livePnlPct = costBasis > 0 ? (livePnl / costBasis) * 100 : 0.0;

        final isProfit = livePnl >= 0;
        final pnlColor =
            isProfit ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
        final pnlBg =
            isProfit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
        final sign = isProfit ? '+' : '';

        return GestureDetector(
          onTapDown: _tapDown,
          onTapUp: _tapUp,
          onTapCancel: () => _scaleCtrl.reverse(),
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.92),
                      Colors.white.withValues(alpha: 0.78),
                    ],
                  ),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top row: avatar + name + action badge ──────────
                    Row(
                      children: [
                        // Symbol avatar
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [
                                AuroraColors.violet
                                    .withValues(alpha: 0.15),
                                AuroraColors.violet
                                    .withValues(alpha: 0.06),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              pos.symbol.length >= 2
                                  ? pos.symbol.substring(0, 2)
                                  : pos.symbol,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AuroraColors.violet,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    pos.symbol,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _ActionBadge(action: pos.action),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${pos.exchange} · ${pos.quantity} qty',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        ),
                        // P&L chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: pnlBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$sign${livePnlPct.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: pnlColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Divider(color: Colors.grey.shade100, height: 1),
                    const SizedBox(height: 12),

                    // ── Price row: avg buy vs live ─────────────────────
                    Row(
                      children: [
                        _PriceColumn(
                          label: 'AVG BUY',
                          value: '₹${pos.avgPrice.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF374151),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: Colors.grey.shade100,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        _LivePriceColumn(
                          symbol: pos.symbol,
                          fallback: pos.currentPrice,
                          avgPrice: pos.avgPrice,
                        ),
                        const Spacer(),
                        // Absolute P&L
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'P&L',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade400,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$sign₹${livePnl.abs().toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: pnlColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Close position button ──────────────────────────
                    BlocBuilder<OrderCubit, OrderState>(
                      builder: (ctx, orderState) {
                        final isPlacing = orderState is OrderPlacing;
                        final isPlaced  = orderState is OrderPlaced;

                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (isPlacing || isPlaced)
                                ? null
                                : () => _confirmClose(ctx),
                            icon: isPlacing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    isPlaced
                                        ? Icons.check_rounded
                                        : Icons.close_rounded,
                                    size: 16,
                                  ),
                            label: Text(
                              isPlacing
                                  ? 'Placing order…'
                                  : isPlaced
                                      ? 'Order placed'
                                      : 'Close Position',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPlaced
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: isPlaced
                                  ? const Color(0xFF10B981)
                                  : Colors.grey.shade300,
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── _ActionBadge ───────────────────────────────────────────────────────────────

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.action});
  final String action;

  @override
  Widget build(BuildContext context) {
    final isBuy = action.toUpperCase() == 'BUY';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isBuy ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        action.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: isBuy ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── _PriceColumn ───────────────────────────────────────────────────────────────

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade400,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ── _LivePriceColumn ───────────────────────────────────────────────────────────
//
// Shows the live LTP for [symbol] with the same flash animation used by
// LivePriceText, and a directional indicator (up/down arrow + change colour).

class _LivePriceColumn extends StatefulWidget {
  const _LivePriceColumn({
    required this.symbol,
    required this.fallback,
    required this.avgPrice,
  });
  final String symbol;
  final double fallback;
  final double avgPrice;

  @override
  State<_LivePriceColumn> createState() => _LivePriceColumnState();
}

class _LivePriceColumnState extends State<_LivePriceColumn>
    with SingleTickerProviderStateMixin {
  late AnimationController _flash;
  late Animation<Color?> _flashColor;
  double? _prevLtp;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashColor =
        ColorTween(begin: Colors.transparent, end: Colors.transparent)
            .animate(_flash);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _triggerFlash(double ltp) {
    if (_prevLtp == null) { _prevLtp = ltp; return; }
    final up = ltp > _prevLtp!;
    _prevLtp = ltp;
    _flashColor = ColorTween(
      begin: up
          ? Colors.green.withValues(alpha: 0.25)
          : Colors.red.withValues(alpha: 0.25),
      end: Colors.transparent,
    ).animate(CurvedAnimation(parent: _flash, curve: Curves.easeOut));
    _flash.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
          prev.prices[widget.symbol]?.ltp != curr.prices[widget.symbol]?.ltp,
      builder: (context, state) {
        final tick = state.prices[widget.symbol];
        final ltp  = tick?.ltp ?? widget.fallback;
        if (tick != null) _triggerFlash(ltp);

        final isUp = ltp >= widget.avgPrice;
        final dirColor =
            isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

        return AnimatedBuilder(
          animation: _flash,
          builder: (_, child) => Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _flashColor.value,
              borderRadius: BorderRadius.circular(6),
            ),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LIVE PRICE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade400,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹${ltp.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: dirColor,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    isUp
                        ? Icons.arrow_drop_up_rounded
                        : Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: dirColor,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── _CloseConfirmSheet ─────────────────────────────────────────────────────────

class _CloseConfirmSheet extends StatelessWidget {
  const _CloseConfirmSheet({
    required this.position,
    required this.closePrice,
  });

  final AlgoPosition position;
  final double closePrice;

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final isBuy = pos.action.toUpperCase() == 'BUY';
    final closeAction = isBuy ? 'SELL' : 'BUY';
    final estPnl = isBuy
        ? (closePrice - pos.avgPrice) * pos.quantity
        : (pos.avgPrice - closePrice) * pos.quantity;
    final isProfit = estPnl >= 0;
    final pnlColor =
        isProfit ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final sign = isProfit ? '+' : '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.close_rounded,
                color: Color(0xFFDC2626), size: 28),
          ),
          const SizedBox(height: 16),

          Text(
            'Close ${pos.symbol} Position?',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This will place a $closeAction MARKET order for ${pos.quantity} shares.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),

          // Summary row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AuroraColors.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryItem(
                    label: 'Avg Buy',
                    value: '₹${pos.avgPrice.toStringAsFixed(2)}'),
                _SummaryItem(
                    label: 'Close @ (est.)',
                    value: '₹${closePrice.toStringAsFixed(2)}'),
                _SummaryItem(
                  label: 'Est. P&L',
                  value: '$sign₹${estPnl.abs().toStringAsFixed(2)}',
                  valueColor: pnlColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Confirm Close',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: valueColor ?? const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

// ── _ShimmerCard ───────────────────────────────────────────────────────────────

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 13,
                          width: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(6),
                          )),
                      const SizedBox(height: 6),
                      Container(
                          height: 10,
                          width: 70,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(6),
                          )),
                    ],
                  ),
                ),
                Container(
                    width: 60,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(999),
                    )),
              ],
            ),
            const SizedBox(height: 14),
            Container(
                height: 1,
                color: Colors.grey.shade200),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                    width: 70,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(8),
                    )),
                const SizedBox(width: 32),
                Container(
                    width: 70,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(8),
                    )),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
