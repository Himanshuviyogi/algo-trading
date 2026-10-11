import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'dart:ui';

import '../blocs/auth_bloc.dart';
import '../cubits/cubits.dart';
import '../cubits/order_cubit.dart';
import '../cubits/recommendation_detail_cubit.dart';
import '../models/order.dart';
import '../models/recommendation.dart';
import '../repositories/order_repository.dart';
import '../widgets/live_price_text.dart';
import '../widgets/stock_icon.dart';

// Strip exchange prefix: 'NSE:RELIANCE' → 'RELIANCE'
String _detailPriceSymbol(String raw) {
  final idx = raw.indexOf(':');
  return idx >= 0 ? raw.substring(idx + 1) : raw;
}

PreferredSizeWidget _buildStockAppBar(dynamic recommendation, BuildContext context) {
  final stock = recommendation.stock;
  final trade = recommendation.trade;

  final isPositive = (trade.action as String? ?? 'BUY').toUpperCase() == 'BUY'
      ? (trade.currentPrice - trade.entryPrice) >= 0
      : (trade.entryPrice - trade.currentPrice) >= 0;
  final accentColor = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);

  return AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    centerTitle: false,

    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1E293B)),
      onPressed: () => context.pop(),
    ),

    titleSpacing: 0,

    title: Row(
      children: [
        /// 📊 ICON
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.show_chart, color: accentColor, size: 20),
        ),

        const SizedBox(width: 10),

        /// 🔥 STOCK INFO
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stock.name ?? "Stock",
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            Row(
              children: [
                Text(
                  stock.symbol ?? "NSE",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 6),

                /// LIVE DOT
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    /// 💰 RIGHT SIDE PRICE
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "₹${trade.currentPrice}",
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            Text(
              "${(trade.currentPrice - trade.entryPrice).toStringAsFixed(2)}",
              style: TextStyle(
                fontSize: 34,
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      )
    ],
  );
}
class RecommendationDetailScreen extends StatefulWidget {
  const RecommendationDetailScreen({super.key, required this.id});
  final String id;




  @override
  State<RecommendationDetailScreen> createState() => _RecommendationDetailScreenState();
}



class _RecommendationDetailScreenState extends State<RecommendationDetailScreen> {

  @override
  void initState() {
    super.initState();
    context.read<RecommendationDetailCubit>().load(widget.id);
    // Connect live price service (idempotent — safe to call multiple times)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LivePriceCubit>().connect();
    });
  }
  String stockSymbol = '';
  String stockName = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final extra = GoRouterState.of(context).extra as Map?;

    stockName = extra?['name'] ?? '';
    stockSymbol = extra?['symbol'] ?? '';
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
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
                Text(
                  stockName.isEmpty ? 'Stock Details' :  'Stock Details',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: Color(0xFF111827)),
                ),
                Text(
                    stockSymbol.isEmpty ? "---" : stockSymbol,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            )
          ],
        ),
      ),
      body: Stack(
        children: [
          // Light Background Gradient
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9), // Light Slate
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
              ),
            ),
          ),

          // Subtle Ambient Glow (Light Mode)
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.08),
              ),
            ).animate().fadeIn(duration: 2.seconds),
          ),

          BlocBuilder<RecommendationDetailCubit, RecommendationDetailState>(
            builder: (context, state) {
              if (state is RecommendationDetailLoading) {
                return const Center(child: CircularProgressIndicator(color: Colors.blue));
              }
              if (state is RecommendationDetailLoaded) {
                // Subscribe to live price for this stock
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  context.read<LivePriceCubit>().subscribe([
                    _detailPriceSymbol(state.recommendation.stock.symbol),
                  ]);
                });
                return _LightDetailView(recommendation: state.recommendation);
              }
              if (state is RecommendationDetailAccessDenied) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'Access Restricted',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Subscribe to a plan to view this trade.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => context.push('/plans'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4C46E5),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('View Plans'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (state is RecommendationDetailError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 12),
                      const Text('Failed to load trade details'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context
                            .read<RecommendationDetailCubit>()
                            .load(widget.id),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator(color: Colors.blue));
            },
          ),
        ],
      ),
    );
  }
}

class _LightDetailView extends StatefulWidget {
  final dynamic recommendation;
  const _LightDetailView({required this.recommendation});

  @override
  State<_LightDetailView> createState() => _LightDetailViewState();
}

class _LightDetailViewState extends State<_LightDetailView> {
  int _quantity = 1;

  void _increment() => setState(() => _quantity++);
  void _decrement() {
    if (_quantity > 1) setState(() => _quantity--);
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = widget.recommendation as Recommendation;
    final symbol = recommendation.stock.symbol;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 110, 20, 40),
      child: Column(
        children: [
          _StockHeaderCard(recommendation: recommendation)
              .animate().fade(duration: 400.ms).slideY(begin: 0.1),

          const SizedBox(height: 12),

          _PriceInfoCard(recommendation: recommendation)
              .animate().fade(delay: 200.ms).slideY(begin: 0.1),

          // F&O specific card — only shown for options/futures
          if (recommendation.trade.isFno) ...[
            const SizedBox(height: 12),
            _FnoInfoCard(recommendation: recommendation)
                .animate().fade(delay: 250.ms).slideY(begin: 0.1),
          ],



          // const SizedBox(height: 16),

          // ── View Chart Button ──────────────────────────────────────────


          const SizedBox(height: 16),


          // GestureDetector(
          //   onTap: () => context.push('/chart/${recommendation.stock.symbol}'),
          //   child: Container(
          //     // width: 30,
          //     padding: const EdgeInsets.symmetric(vertical: 8,horizontal: 8),
          //     decoration: BoxDecoration(
          //       gradient: const LinearGradient(
          //         colors: [Color(0xFF4C46E5), Color(0xFF6366F1)],
          //         begin: Alignment.centerLeft,
          //         end: Alignment.centerRight,
          //       ),
          //       borderRadius: BorderRadius.circular(6),
          //       boxShadow: [
          //         BoxShadow(
          //           color: const Color(0xFF4C46E5).withOpacity(0.35),
          //           blurRadius: 16,
          //           offset: const Offset(0, 6),
          //         ),
          //       ],
          //     ),
          //     child: Row(
          //       mainAxisAlignment: MainAxisAlignment.center,
          //       children: [
          //         // const Icon(Icons.candlestick_chart_rounded,
          //         //     color: Colors.white, size: 20),
          //         // const SizedBox(width: 10),
          //         Text(
          //           'View Chart',
          //           style: const TextStyle(
          //             color: Colors.white,
          //             fontSize: 15,
          //             fontWeight: FontWeight.w700,
          //             letterSpacing: 0.3,
          //           ),
          //         ),
          //         const SizedBox(width: 2),
          //         const Icon(Icons.arrow_forward_ios_rounded,
          //             color: Colors.white70, size: 14),
          //       ],
          //     ),
          //   ),
          // ).animate().fade(delay: 150.ms).slideY(begin: 0.1),


          _PerformanceCard(recommendation: recommendation)
              .animate().fade(delay: 300.ms).slideY(begin: 0.1),

          const SizedBox(height: 16),

          _AnalysisCard(recommendation: recommendation)
              .animate().fade(delay: 400.ms).slideY(begin: 0.1),

         if (recommendation.notes != null )const SizedBox(height: 16),

          _AdditionalDetailsCard(recommendation: recommendation)
              .animate().fade(delay: 500.ms).slideY(begin: 0.1),

          const SizedBox(height: 16),

          GestureDetector(
            onTap: () => context.push('/chart/$symbol'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4C46E5), Color(0xFF6366F1)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4C46E5).withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.candlestick_chart_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'View Chart  ·  $symbol',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.white70, size: 14),
                  ],
                ),
              ),
            ),
          ).animate().fade(delay: 150.ms).slideY(begin: 0.1),
          const SizedBox(height: 20),
          // ── Order placement section ────────────────────────────────────
          _OrderSection(
            recommendation: recommendation,
            quantity: _quantity,
            onIncrement: _increment,
            onDecrement: _decrement,
          ).animate().fade(delay: 600.ms).slideY(begin: 0.1),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── _OrderSection ─────────────────────────────────────────────────────────────
//
// Shows:
//   • An existing order status card when an order already exists for this signal
//   • A quantity selector + Place Order button when no order exists yet
//
// Uses StreamBuilder on OrderRepository.getOrderForSignal so the existing-order
// check is live — if an order is placed from another device the UI updates.

class _OrderSection extends StatelessWidget {
  const _OrderSection({
    required this.recommendation,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final Recommendation recommendation;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId =
        authState is AuthAuthenticated ? authState.uid : '';

    return StreamBuilder<AlgoOrder?>(
      stream: context
          .read<OrderRepository>()
          .getOrderForSignal(userId, recommendation.id),
      builder: (context, snapshot) {
        // While the stream is connecting show nothing — avoids a flash of
        // the Place Order UI before we know an order already exists.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _OrderSectionShimmer();
        }

        final existingOrder = snapshot.data;

        // ── Existing order — show status card ──────────────────────────
        if (existingOrder != null) {
          return _ExistingOrderCard(order: existingOrder);
        }

        // ── No order yet — show placement UI ──────────────────────────
        return _PlaceOrderPanel(
          recommendation: recommendation,
          quantity: quantity,
          onIncrement: onIncrement,
          onDecrement: onDecrement,
        );
      },
    );
  }
}

// ── _ExistingOrderCard ─────────────────────────────────────────────────────────

class _ExistingOrderCard extends StatelessWidget {
  const _ExistingOrderCard({required this.order});
  final AlgoOrder order;

  ({Color bg, Color border, Color text, IconData icon, String label})
      get _cfg {
    return switch (order.status) {
      OrderStatus.complete => (
          bg: const Color(0xFFDCFCE7),
          border: const Color(0xFF86EFAC),
          text: const Color(0xFF16A34A),
          icon: Icons.check_circle_rounded,
          label: 'ORDER FILLED',
        ),
      OrderStatus.open || OrderStatus.pending => (
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFFCD34D),
          text: const Color(0xFFD97706),
          icon: Icons.pending_actions_rounded,
          label: 'ORDER ACTIVE',
        ),
      OrderStatus.rejected => (
          bg: const Color(0xFFFEE2E2),
          border: const Color(0xFFFCA5A5),
          text: const Color(0xFFDC2626),
          icon: Icons.cancel_rounded,
          label: 'ORDER REJECTED',
        ),
      OrderStatus.cancelled => (
          bg: const Color(0xFFF3F4F6),
          border: const Color(0xFFD1D5DB),
          text: const Color(0xFF6B7280),
          icon: Icons.do_not_disturb_rounded,
          label: 'ORDER CANCELLED',
        ),
      _ => (
          bg: const Color(0xFFF3F4F6),
          border: const Color(0xFFD1D5DB),
          text: const Color(0xFF6B7280),
          icon: Icons.info_outline_rounded,
          label: 'ORDER STATUS',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    final isBuy = order.action.toUpperCase() == 'BUY';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cfg.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(cfg.icon, color: cfg.text, size: 20),
              const SizedBox(width: 8),
              Text(
                cfg.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cfg.text,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isBuy
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  order.action.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: isBuy
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Order details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _OrderDetailTile(label: 'QTY', value: '${order.quantity}'),
              _OrderDetailTile(
                  label: 'PRICE',
                  value: '₹${order.price.toStringAsFixed(2)}'),
              _OrderDetailTile(
                  label: 'TYPE', value: order.orderType),
            ],
          ),
          if (order.rejectionReason != null &&
              order.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.rejectionReason!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (order.angelOrderId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Order ID: ${order.angelOrderId}',
              style: TextStyle(
                fontSize: 11,
                color: cfg.text.withValues(alpha: 0.7),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderDetailTile extends StatelessWidget {
  const _OrderDetailTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.black38,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

// ── _PlaceOrderPanel ───────────────────────────────────────────────────────────

class _PlaceOrderPanel extends StatelessWidget {
  const _PlaceOrderPanel({
    required this.recommendation,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final Recommendation recommendation;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final isBuy =
        recommendation.trade.action.toUpperCase() == 'BUY';
    final accentColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final entryPrice = recommendation.trade.entryPrice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section label ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF4C46E5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'PLACE ORDER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),

        // ── Main panel card ────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    // ── Price summary row ────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryTile(
                            label: 'Action',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isBuy
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                recommendation.trade.action.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _SummaryTile(
                            label: 'Limit Price',
                            child: Text(
                              '₹${entryPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _SummaryTile(
                            label: 'Order Type',
                            child: const Text(
                              'LIMIT',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Divider(color: Colors.grey.shade100, height: 1),
                    const SizedBox(height: 16),

                    // ── Quantity selector ────────────────────────────
                    Row(
                      children: [
                        const Text(
                          'Quantity',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const Spacer(),
                        // Decrement
                        _QtyButton(
                          icon: Icons.remove_rounded,
                          onTap: onDecrement,
                          enabled: quantity > 1,
                        ),
                        Container(
                          width: 52,
                          alignment: Alignment.center,
                          child: Text(
                            '$quantity',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        // Increment
                        _QtyButton(
                          icon: Icons.add_rounded,
                          onTap: onIncrement,
                          enabled: true,
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Total value hint
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total: ₹${(entryPrice * quantity).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── BlocBuilder: place button + feedback ─────────
                    BlocBuilder<OrderCubit, OrderState>(
                      builder: (context, state) {
                        if (state is OrderPlacing) {
                          return _OrderLoadingWidget(isBuy: isBuy);
                        }
                        if (state is OrderPlaced) {
                          return _OrderSuccessWidget(order: state.order);
                        }
                        if (state is OrderFailed) {
                          return Column(
                            children: [
                              _OrderErrorWidget(message: state.message),
                              const SizedBox(height: 12),
                              _PlaceButton(
                                isBuy: isBuy,
                                label: 'Try Again',
                                onTap: () {
                                  context.read<OrderCubit>().reset();
                                },
                              ),
                            ],
                          );
                        }
                        // OrderInitial
                        return _PlaceButton(
                          isBuy: isBuy,
                          label:
                              '${isBuy ? 'BUY' : 'SELL'}  ·  $quantity × ₹${entryPrice.toStringAsFixed(2)}',
                          onTap: () =>
                              context.read<OrderCubit>().placeOrder(
                                    signal: recommendation,
                                    quantity: quantity,
                                  ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Small reusable pieces ──────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.black38,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.onTap,
    required this.enabled,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF4C46E5).withValues(alpha: 0.10)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? const Color(0xFF4C46E5) : Colors.grey.shade300,
        ),
      ),
    );
  }
}

class _PlaceButton extends StatelessWidget {
  const _PlaceButton({
    required this.isBuy,
    required this.label,
    required this.onTap,
  });
  final bool isBuy;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _OrderLoadingWidget extends StatelessWidget {
  const _OrderLoadingWidget({required this.isBuy});
  final bool isBuy;

  @override
  Widget build(BuildContext context) {
    final color =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Placing order…',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderSuccessWidget extends StatelessWidget {
  const _OrderSuccessWidget({required this.order});
  final AlgoOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Order placed successfully!',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _OrderDetailTile(label: 'QTY', value: '${order.quantity}'),
              _OrderDetailTile(
                  label: 'PRICE',
                  value: '₹${order.price.toStringAsFixed(2)}'),
              _OrderDetailTile(label: 'STATUS', value: 'PENDING'),
            ],
          ),
          if (order.id.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Order ID: ${order.id}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF15803D),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderErrorWidget extends StatelessWidget {
  const _OrderErrorWidget({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDC2626),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderSectionShimmer extends StatelessWidget {
  const _OrderSectionShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey.shade300,
          ),
        ),
      ),
    );
  }
}

class AnimatedPriceText extends StatefulWidget {
  final double value;
  final Color color;
  final String prefix;

  const AnimatedPriceText({
    super.key,
    required this.value,
    required this.color,
    this.prefix = "",
  });

  @override
  State<AnimatedPriceText> createState() => _AnimatedPriceTextState();
}

class _AnimatedPriceTextState extends State<AnimatedPriceText>
    with SingleTickerProviderStateMixin {
  double? previousValue;

  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _scaleAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _shakeAnim = Tween<double>(begin: 0, end: 6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticIn),
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedPriceText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.value != widget.value) {
      previousValue = oldWidget.value;
      _controller.forward(from: 0); // 🔥 trigger animation every update
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUp = previousValue != null && widget.value > previousValue!;
    final isDown = previousValue != null && widget.value < previousValue!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            sin(_shakeAnim.value) * 2, // 🔥 vibration
            0,
          ),
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isUp
                    ? Colors.green.withOpacity(0.08)
                    : isDown
                    ? Colors.red.withOpacity(0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "${widget.prefix}${widget.value.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.color,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
class ModernGlassCard extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  const ModernGlassCard({super.key, required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: borderColor ?? Colors.white.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _StockHeaderCard extends StatelessWidget {
  final dynamic recommendation;
  const _StockHeaderCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return ModernGlassCard(
      child: Row(
        children: [
          StockIcon(
            symbol:   recommendation.stock.symbol as String,
            category: recommendation.category    as String,
            logoUrl:  recommendation.stock.logoUrl,
            size:     56,
            borderRadius: 16,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recommendation.stock.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF1E293B), fontSize: 17, fontWeight: FontWeight.bold, height: 1.2)),
                const SizedBox(height: 4),
                Text(recommendation.stock.symbol,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black45, fontSize: 12, letterSpacing: 0.5)),
              ],
            ),
          ),
          // Container(
          //   padding: const EdgeInsets.all(8),
          //   decoration: BoxDecoration(color: Colors.black.withOpacity(0.03), shape: BoxShape.circle),
          //   child: const Icon(Icons.bookmark_border, color: Colors.black54),
          // )
        ],
      ),
    );
  }
}

class _TradeActionCard extends StatelessWidget {
  final dynamic recommendation;
  const _TradeActionCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final isBuy = recommendation.trade.action.toUpperCase() == 'BUY';
    final accentColor = isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return ModernGlassCard(
      borderColor: accentColor.withOpacity(0.2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(isBuy ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down, color: accentColor),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isBuy ? "BULLISH SIGNAL" : "BEARISH SIGNAL",
                  style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
              const Text("Execution Zone Active", style: TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.info_outline, color: Colors.black26),
        ],
      ),
    );
  }
}

class _PriceInfoCard extends StatelessWidget {
  final dynamic recommendation;
  const _PriceInfoCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final trade = recommendation.trade;
    final symbol = _detailPriceSymbol(recommendation.stock.symbol as String);

    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
          prev.prices[symbol]?.ltp != curr.prices[symbol]?.ltp,
      builder: (context, priceState) {
        final livePrice = priceState.ltp(symbol) ?? (trade.currentPrice as double);
        final isBuy = (trade.action as String).toUpperCase() == 'BUY';
        // BUY: profit when price is above entry; SELL: profit when price is below entry
        final isPositive = isBuy
            ? (livePrice - (trade.entryPrice as double)) >= 0
            : ((trade.entryPrice as double) - livePrice) >= 0;
        final accentColor = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);

        return ModernGlassCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Live Trend", style: TextStyle(color: Color(0xFF475569), fontSize: 16, fontWeight: FontWeight.bold)),
                  _StatusBadge(status: recommendation.status),
                ],
              ),
              const SizedBox(height: 15),
              SizedBox(height: 80, child: LivePriceChart(isPositive: isPositive)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatTile(label: "Entry", value: "₹${trade.entryPrice}", icon: Icons.login),
                  Container(width: 1, height: 35, color: Colors.black12),
                  // Column(
                  //   children: [
                  //     Row(
                  //       children: [
                  //         Icon(Icons.speed, size: 14, color: Colors.black38),
                  //         const SizedBox(width: 4),
                  //         const Text(
                  //           "Current",
                  //           style: TextStyle(color: Colors.black45, fontSize: 12),
                  //         ),
                  //       ],
                  //     ),
                  //     const SizedBox(height: 4),
                  //     LivePriceText(
                  //       symbol: symbol,
                  //       fallbackPrice: trade.currentPrice as double,
                  //       style: TextStyle(
                  //         fontSize: 13,
                  //         fontWeight: FontWeight.w700,
                  //         color: accentColor,
                  //       ),
                  //       showChange: true,
                  //     ),
                  //   ],
                  // )



                  BlocBuilder<LivePriceCubit, LivePriceState>(
                    builder: (context, liveState) {
                      final isMarketClosed = liveState.isMarketClosed;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.speed,
                                size: 14,
                                color: Colors.black38,
                              ),

                              const SizedBox(width: 4),

                              const Text(
                                "Current",
                                style: TextStyle(
                                  color: Colors.black45,
                                  fontSize: 12,
                                ),
                              ),

                              // const SizedBox(width: 8),
                              //
                              // Container(
                              //   padding: const EdgeInsets.symmetric(
                              //     horizontal: 8,
                              //     vertical: 4,
                              //   ),
                              //   decoration: BoxDecoration(
                              //     color: isMarketClosed
                              //         ? const Color(0xFFF3F4F6)
                              //         : const Color(0xFFDCFCE7),
                              //     borderRadius: BorderRadius.circular(30),
                              //   ),
                              //   child: Row(
                              //     mainAxisSize: MainAxisSize.min,
                              //     children: [
                              //       if (!isMarketClosed)
                              //         Container(
                              //           width: 6,
                              //           height: 6,
                              //           decoration: const BoxDecoration(
                              //             color: Color(0xFF16A34A),
                              //             shape: BoxShape.circle,
                              //           ),
                              //         ),
                              //
                              //       if (!isMarketClosed)
                              //         const SizedBox(width: 5),
                              //
                              //       Text(
                              //         isMarketClosed
                              //             ? 'MARKET CLOSED'
                              //             : 'LIVE',
                              //         style: TextStyle(
                              //           fontSize: 9,
                              //           fontWeight: FontWeight.w700,
                              //           letterSpacing: 0.4,
                              //           color: isMarketClosed
                              //               ? Colors.grey.shade700
                              //               : const Color(0xFF15803D),
                              //         ),
                              //       ),
                              //     ],
                              //   ),
                              // ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          LivePriceText(
                            symbol: symbol,
                            fallbackPrice: trade.currentPrice as double,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                            showChange: !isMarketClosed,
                          ),
                        ],
                      );
                    },
                  )
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color? color;
  const _StatTile({required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.black38),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color ?? const Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color = const Color(0xFF10B981);
    String label = status.toUpperCase();
    bool isLive = status.toLowerCase() == 'live';

    if (status.toLowerCase().contains('target')) color = Colors.blue;
    if (status.toLowerCase().contains('stoploss')) color = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            Container(
              margin: const EdgeInsets.only(right: 6),
              width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat()).fadeIn(duration: 600.ms).fadeOut(delay: 600.ms),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.1)),
        ],
      ),
    );
  }
}

// ── F&O Info Card ─────────────────────────────────────────────────────────────

class _FnoInfoCard extends StatelessWidget {
  final dynamic recommendation;
  const _FnoInfoCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final trade = recommendation.trade;
    final isOption = trade.isOption;
    final isFuture = trade.isFuture;

    final Color accentColor = isOption
        ? (trade.optionType == 'CE'
            ? const Color(0xFF10B981)  // green for CE (bullish)
            : const Color(0xFFEF4444)) // red for PE (bearish)
        : const Color(0xFF6366F1);     // indigo for futures

    return ModernGlassCard(
      borderColor: accentColor.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withOpacity(0.3)),
                ),
                child: Text(
                  isOption
                      ? '${trade.optionType} OPTION'
                      : 'FUTURES',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              if (trade.expiryDate != null)
                Text(
                  'Expiry: ${trade.expiryDate}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (trade.underlyingSymbol != null)
                _FnoTile(label: 'Underlying', value: trade.underlyingSymbol!),
              if (isOption && trade.strikePrice != null)
                _FnoTile(label: 'Strike', value: '₹${trade.strikePrice!.toStringAsFixed(0)}'),
              if (trade.lotSize != null)
                _FnoTile(label: 'Lot Size', value: '${trade.lotSize}'),
              if (isOption && trade.premium != null)
                _FnoTile(label: 'Premium', value: '₹${trade.premium!.toStringAsFixed(2)}'),
            ],
          ),
          if (isOption && trade.premium != null && trade.lotSize != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Max Risk (1 lot)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    '₹${(trade.premium! * trade.lotSize!).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FnoTile extends StatelessWidget {
  final String label;
  final String value;
  const _FnoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PerformanceCard extends StatelessWidget {  final dynamic recommendation;
  const _PerformanceCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final symbol = _detailPriceSymbol(recommendation.stock.symbol as String);

    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
          prev.prices[symbol]?.ltp != curr.prices[symbol]?.ltp,
      builder: (context, priceState) {
        final livePrice = priceState.ltp(symbol) ??
            (recommendation.trade.currentPrice as double);
        final entryPrice = recommendation.trade.entryPrice as double;
        final target = recommendation.analysis.target as double;
        final isBuy = (recommendation.trade.action as String).toUpperCase() == 'BUY';

        // BUY:  gain = (live - entry) / entry
        // SELL: gain = (entry - live) / entry  (short profits when price falls)
        final gainPct = entryPrice > 0
            ? isBuy
                ? ((livePrice - entryPrice) / entryPrice) * 100
                : ((entryPrice - livePrice) / entryPrice) * 100
            : recommendation.performance.gainSoFar as double;

        // Potential left to reach target
        // BUY:  target is above current — (target - live) / live
        // SELL: target is below current — (live - target) / live
        final potentialPct = target > 0 && livePrice > 0
            ? isBuy
                ? ((target - livePrice) / livePrice) * 100
                : ((livePrice - target) / livePrice) * 100
            : recommendation.performance.potentialLeft as double;

        final gainColor = gainPct >= 0 ? Colors.green : Colors.red;

        return ModernGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PERFORMANCE',
                  style: TextStyle(
                      color: Colors.black38,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _MetricTile(
                          label: 'Gain',
                          value: '${gainPct >= 0 ? '+' : ''}${gainPct.toStringAsFixed(2)}%',
                          color: gainColor)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _MetricTile(
                          label: 'Potential',
                          value: '${potentialPct.toStringAsFixed(2)}%',
                          color: Colors.blue)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MetricTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text(label, style: const TextStyle(color: Colors.black45, fontSize: 11)),
        ],
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  final dynamic recommendation;
  const _AnalysisCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final analysis = recommendation.analysis;
    return ModernGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('STRATEGY', style: TextStyle(color: Colors.black38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TargetCol(label: "Target", value: "₹${analysis.target}", color: Colors.blue),
              _TargetCol(label: "Stop Loss", value: "₹${analysis.stoploss ?? 'N/A'}", color: Colors.red),
            ],
          ),
          const SizedBox(height: 20),
          _ConfidenceBar(confidence: recommendation.confidence ?? 'Medium'),
        ],
      ),
    );
  }
}

class _TargetCol extends StatelessWidget {
  final String label, value;
  final Color color;
  const _TargetCol({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black45, fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final String confidence;
  const _ConfidenceBar({required this.confidence});

  @override
  Widget build(BuildContext context) {
    double value = 0.5; Color color = Colors.orange;
    if (confidence.toLowerCase() == 'high') { value = 0.9; color = Colors.green; }
    if (confidence.toLowerCase() == 'low') { value = 0.2; color = Colors.red; }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Confidence", style: TextStyle(color: Colors.black45, fontSize: 12)),
            Text(confidence.toUpperCase(), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(value: value, backgroundColor: Colors.black12, color: color, minHeight: 6),
        ).animate().shimmer(duration: 2.seconds),
      ],
    );
  }
}

class _AdditionalDetailsCard extends StatelessWidget {
  final dynamic recommendation;
  const _AdditionalDetailsCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return ModernGlassCard(
      child: Container(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (recommendation.notes != null) ...[
              const Text('NOTES', style: TextStyle(color: Colors.black38, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                recommendation.notes!,
                style: const TextStyle(color: Color(0xFF475569), fontSize: 14, height: 1.6),
              ),
            ],
            if (recommendation.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: recommendation.tags.map<Widget>((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.1))),
                  child: Text("#$tag", style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
                )).toList(),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class LivePriceChart extends StatelessWidget {
  final bool isPositive;
  const LivePriceChart({super.key, required this.isPositive});

  @override
  Widget build(BuildContext context) {
    final accentColor = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final List<FlSpot> spots = [
      const FlSpot(0, 10), const FlSpot(2, 14), const FlSpot(4, 12), const FlSpot(6, 18),
      const FlSpot(8, 16), const FlSpot(10, 22), const FlSpot(12, 19), const FlSpot(14, 25),
    ];

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: accentColor,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accentColor.withOpacity(0.2), accentColor.withOpacity(0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}