import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';

import '../blocs/auth_bloc.dart';
import '../cubits/order_cubit.dart';
import '../models/order.dart';
import '../repositories/order_repository.dart';
import '../services/order_service.dart';
import '../utils/app_theme.dart';

class OrderBookScreen extends StatefulWidget {
  const OrderBookScreen({super.key});

  @override
  State<OrderBookScreen> createState() => _OrderBookScreenState();
}

class _OrderBookScreenState extends State<OrderBookScreen> {
  StreamSubscription<List<AlgoOrder>>? _sub;

  List<AlgoOrder> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    _sub?.cancel();
    _sub = context
        .read<OrderRepository>()
        .getUserOrders(authState.uid)
        .listen(
          (orders) {
            if (mounted) {
              setState(() {
                _orders = orders;
                _loading = false;
              });
            }
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _error = e.toString();
                _loading = false;
              });
            }
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Order detail / cancel sheet ───────────────────────────────────────────

  void _showOrderDetail(AlgoOrder order) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider(
        create: (_) => OrderCubit(
          orderRepository: context.read<OrderRepository>(),
          orderService:    OrderService.instance,
          userId:          authState.uid,
        ),
        child: _OrderDetailSheet(order: order),
      ),
    );
  }

  List<AlgoOrder> get _active =>
      _orders.where((o) => o.status.isActive).toList();

  List<AlgoOrder> get _completed =>
      _orders.where((o) => o.status == OrderStatus.complete).toList();

  List<AlgoOrder> get _closedNegative => _orders
      .where((o) =>
          o.status == OrderStatus.rejected ||
          o.status == OrderStatus.cancelled)
      .toList();

  // ── Build ──────────────────────────────────────────────────────────────────

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
            icon: const Icon(Icons.refresh_rounded, color: AuroraColors.violet),
            onPressed: _subscribe,
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
                  'Order Book',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  'Your trade history',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildShimmer();

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Failed to load orders',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AuroraColors.violet,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                ),
                onPressed: _subscribe,
                child: const Text('Retry',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => _subscribe(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Icon(Icons.receipt_long_rounded,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No orders yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Orders placed from trade signals will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500, height: 1.5),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AuroraColors.violet,
      onRefresh: () async => _subscribe(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _OrderGroup(
            label: 'Active',
            sublabel: 'Pending & Open — tap to cancel',
            icon: Icons.pending_actions_rounded,
            color: const Color(0xFFF59E0B),
            orders: _active,
            emptyMessage: 'No active orders right now.',
            onTap: _showOrderDetail,
          ),
          const SizedBox(height: 8),
          _OrderGroup(
            label: 'Completed',
            sublabel: 'Filled orders',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF10B981),
            orders: _completed,
            emptyMessage: 'No completed orders yet.',
          ),
          const SizedBox(height: 8),
          _OrderGroup(
            label: 'Rejected / Cancelled',
            sublabel: 'Closed without fill',
            icon: Icons.cancel_outlined,
            color: const Color(0xFFEF4444),
            orders: _closedNegative,
            emptyMessage: 'No rejected or cancelled orders.',
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 6,
      itemBuilder: (_, __) => const _ShimmerCard(),
    );
  }
}

// ── Order Group ────────────────────────────────────────────────────────────────

class _OrderGroup extends StatefulWidget {
  const _OrderGroup({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.orders,
    required this.emptyMessage,
    this.onTap,
  });

  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final List<AlgoOrder> orders;
  final String emptyMessage;
  final void Function(AlgoOrder)? onTap;

  @override
  State<_OrderGroup> createState() => _OrderGroupState();
}

class _OrderGroupState extends State<_OrderGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: widget.color.withValues(alpha: 0.12),
                  ),
                  child: Icon(widget.icon, size: 18, color: widget.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      Text(
                        widget.sublabel,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${widget.orders.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: widget.color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded,
                      color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ),

        // ── Cards ─────────────────────────────────────────────────────────
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeIn,
          crossFadeState:
              _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: widget.orders.isEmpty
              ? _EmptyGroup(message: widget.emptyMessage, color: widget.color)
              : Column(
                  children: [
                    for (var i = 0; i < widget.orders.length; i++)
                      TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 250 + i * 40),
                        tween: Tween(begin: 0.0, end: 1.0),
                        builder: (context, v, child) => Opacity(
                          opacity: v,
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - v)),
                            child: child,
                          ),
                        ),
                        child: _OrderCard(
                          order: widget.orders[i],
                          onTap: widget.onTap != null
                              ? () => widget.onTap!(widget.orders[i])
                              : null,
                        ),
                      ),
                  ],
                ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Empty Group ────────────────────────────────────────────────────────────────

class _EmptyGroup extends StatelessWidget {
  const _EmptyGroup({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 2),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.12),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_rounded, size: 20, color: Colors.grey.shade300),
          const SizedBox(width: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade400,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Order Card ─────────────────────────────────────────────────────────────────

class _OrderCard extends StatefulWidget {
  const _OrderCard({required this.order, this.onTap});

  final AlgoOrder order;
  final VoidCallback? onTap;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.97).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(_) => _controller.forward();
  void _up(_) => _controller.reverse();

  // ── Status chip config ─────────────────────────────────────────────────────

  ({Color bg, Color text, String label}) get _statusConfig {
    return switch (widget.order.status) {
      OrderStatus.complete  => (
          bg: const Color(0xFFDCFCE7),
          text: const Color(0xFF16A34A),
          label: 'COMPLETE',
        ),
      OrderStatus.open      => (
          bg: const Color(0xFFFFF7ED),
          text: const Color(0xFFD97706),
          label: 'OPEN',
        ),
      OrderStatus.pending   => (
          bg: const Color(0xFFFFF7ED),
          text: const Color(0xFFD97706),
          label: 'PENDING',
        ),
      OrderStatus.rejected  => (
          bg: const Color(0xFFFEE2E2),
          text: const Color(0xFFDC2626),
          label: 'REJECTED',
        ),
      OrderStatus.cancelled => (
          bg: const Color(0xFFF3F4F6),
          text: const Color(0xFF9CA3AF),
          label: 'CANCELLED',
        ),
      OrderStatus.unknown   => (
          bg: const Color(0xFFF3F4F6),
          text: const Color(0xFF9CA3AF),
          label: 'UNKNOWN',
        ),
    };
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final d = dt;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final sc = _statusConfig;
    final isBuy = order.isBuy;

    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.9),
                  Colors.white.withValues(alpha: 0.75),
                ],
              ),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: symbol + action badge + status chip ──────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Symbol icon placeholder
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        gradient: LinearGradient(
                          colors: [
                            AuroraColors.violet.withValues(alpha: 0.15),
                            AuroraColors.violet.withValues(alpha: 0.07),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          order.symbol.length >= 2
                              ? order.symbol.substring(0, 2)
                              : order.symbol,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: AuroraColors.violet,
                            letterSpacing: 0.5,
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
                                order.symbol,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // BUY / SELL badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
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
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${order.exchange} · ${order.orderType}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),

                    // Status chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sc.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        sc.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: sc.text,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(color: Colors.grey.shade100, height: 1),
                const SizedBox(height: 12),

                // ── Bottom row: qty, price, time ──────────────────────────
                Row(
                  children: [
                    _InfoPill(
                      icon: Icons.format_list_numbered_rounded,
                      label: 'QTY',
                      value: '${order.quantity}',
                    ),
                    const SizedBox(width: 10),
                    _InfoPill(
                      icon: Icons.currency_rupee_rounded,
                      label: 'PRICE',
                      value: order.price.toStringAsFixed(2),
                      accent: true,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(order.placedAt),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Rejection reason (if any) ─────────────────────────────
                if (order.rejectionReason != null &&
                    order.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 14, color: Color(0xFFDC2626)),
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
                // ── "Tap to manage" hint for active orders ────────────────
                if (order.isActive && widget.onTap != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Tap to manage →',
                        style: TextStyle(
                          fontSize: 11,
                          color: AuroraColors.violet.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Info Pill ──────────────────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? AuroraColors.violet : const Color(0xFF374151);
    final bg = accent
        ? AuroraColors.violet.withValues(alpha: 0.07)
        : const Color(0xFFF3F4F6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg.withValues(alpha: 0.7)),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: fg.withValues(alpha: 0.5),
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Order Detail / Cancel Sheet ───────────────────────────────────────────────
//
// Shown when user taps an active (pending/open) order.
// Displays full order details + a Cancel button that calls OrderCubit.cancelOrder().

class _OrderDetailSheet extends StatelessWidget {
  const _OrderDetailSheet({required this.order});

  final AlgoOrder order;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OrderCubit, OrderState>(
      listener: (ctx, state) {
        if (state is OrderInitial) {
          // Cancel succeeded — close sheet
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('Cancel request sent to broker'),
              ]),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          );
        } else if (state is OrderFailed) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(state.message)),
              ]),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          );
        }
      },
      builder: (ctx, state) {
        final isCancelling = state is OrderPlacing;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Header
              Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: AuroraColors.violet.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      order.symbol.length >= 2
                          ? order.symbol.substring(0, 2)
                          : order.symbol,
                      style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900,
                        color: AuroraColors.violet,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.symbol,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                    Text('${order.exchange} · ${order.orderType}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: order.isBuy
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.action.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: order.isBuy
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              // Detail rows
              _DetailRow(label: 'Status',
                  value: order.status.value.toUpperCase()),
              _DetailRow(label: 'Quantity',
                  value: '${order.quantity}'),
              _DetailRow(label: 'Price',
                  value: '₹${order.price.toStringAsFixed(2)}'),
              if (order.angelOrderId != null && order.angelOrderId!.isNotEmpty)
                _DetailRow(label: 'Angel Order ID',
                    value: order.angelOrderId!),
              _DetailRow(label: 'Placed at',
                  value: _formatDt(order.placedAt)),
              const SizedBox(height: 8),
              // Angel Order ID note
              if (order.angelOrderId == null || order.angelOrderId!.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'No Angel One order ID yet — order may still be pending.',
                      style: TextStyle(fontSize: 12,
                          color: Color(0xFFD97706)),
                    )),
                  ]),
                ),
              const SizedBox(height: 4),
              // Cancel button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isCancelling
                        ? const Color(0xFFDC2626).withValues(alpha: 0.5)
                        : const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: isCancelling
                      ? null
                      : () {
                          if (order.angelOrderId == null ||
                              order.angelOrderId!.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Cannot cancel — no Angel One order ID yet. '
                                    'Try again in a moment.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          ctx.read<OrderCubit>()
                              .cancelOrder(order.angelOrderId!);
                        },
                  icon: isCancelling
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(
                    isCancelling ? 'Cancelling…' : 'Cancel Order',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDt(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade500)),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ],
    ),
  );
}

// ── Shimmer placeholder ────────────────────────────────────────────────────────

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
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 13,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 72,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
