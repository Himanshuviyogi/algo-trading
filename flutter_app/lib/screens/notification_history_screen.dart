import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../cubits/cubits.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends State<NotificationHistoryScreen> {
  final _firestore = FirebaseFirestore.instance;

  List<_NotifItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Returns the list of plan IDs the current user is actively subscribed to.
  List<String> _activePlanIds() {
    final subState = context.read<SubscriptionCubit>().state;
    if (subState is SubscriptionLoaded) {
      return subState.subscriptions
          .where((s) => s.isEffectivelyActive)
          .map((s) => s.planId)
          .toList();
    }
    return [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final planIds = _activePlanIds();

      // No active subscription — show empty list, not all notifications
      if (planIds.isEmpty) {
        if (mounted) setState(() => _items = []);
        return;
      }

      // Firestore `whereIn` supports up to 30 values; chunk if needed
      final List<_NotifItem> all = [];

      for (var i = 0; i < planIds.length; i += 30) {
        final chunk = planIds.sublist(
          i,
          (i + 30).clamp(0, planIds.length),
        );

        final snap = await _firestore
            .collection('notifications')
            .where('plan_id', whereIn: chunk)
            .orderBy('sent_at', descending: true)
            .limit(50)
            .get();

        all.addAll(snap.docs.map((doc) {
          final d = doc.data();
          return _NotifItem(
            id: doc.id,
            title: d['title'] ?? '',
            body: d['body'] ?? '',
            type: d['type'] ?? 'general',
            recommendationId: d['recommendation_id'],
            gain: d['gain'],
            sentAt: d['sent_at'],
          );
        }));
      }

      // Sort merged results by sent_at desc and cap at 50
      all.sort((a, b) {
        final aTs = a.sentAt;
        final bTs = b.sentAt;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });

      if (mounted) setState(() => _items = all.take(50).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      // appBar: AppBar(
      //   backgroundColor: Colors.white,
      //   elevation: 0,
      //   leading: IconButton(
      //     icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      //     onPressed: () => context.pop(),
      //   ),
      //   title: const Text(
      //     'Notifications',
      //     style: TextStyle(
      //       fontWeight: FontWeight.w800,
      //       fontSize: 18,
      //       color: Color(0xFF111827),
      //     ),
      //   ),
      //   actions: [
      //     IconButton(
      //       icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4C46E5)),
      //       onPressed: _load,
      //     ),
      //   ],
      // ),

      appBar : AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4C46E5)),
            onPressed: _load,
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
                  'Notifications',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: Color(0xFF111827)),
                ),
                Text(
                  'View recent updates',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            )
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: 8,
        itemBuilder: (_, __) => const _ShimmerCard(),
      );
    }

    if (_error != null) {
      return Center(
        child: Text("Error: $_error"),
      );
    }

    if (_items.isEmpty) {
      final hasNoSub = _activePlanIds().isEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasNoSub
                    ? Icons.lock_outline_rounded
                    : Icons.notifications_none_rounded,
                size: 56,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                hasNoSub
                    ? 'No active subscription'
                    : 'No notifications yet',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasNoSub
                    ? 'Subscribe to a plan to receive trade alerts and updates.'
                    : 'Trade alerts will appear here once published.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
              if (hasNoSub) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => context.push('/plans'),
                  child: const Text('View Plans',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];

          return TweenAnimationBuilder(
            duration: Duration(milliseconds: 300 + (i * 50)),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: _NotifCard(
              item: item,
              onTap: item.recommendationId != null
                  ? () => context.push(
                  '/recommendation/${item.recommendationId}')
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _NotifItem {
  const _NotifItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.recommendationId,
    this.gain,
    this.sentAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String? recommendationId;
  final String? gain;
  final Timestamp? sentAt;
}
class _NotifCard extends StatefulWidget {
  const _NotifCard({required this.item, this.onTap});

  final _NotifItem item;
  final VoidCallback? onTap;

  @override
  State<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends State<_NotifCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  static const _typeConfig = {
    'trade': (
    icon: Icons.show_chart_rounded,
    color: Color(0xFF10B981),
    label: 'Trade',
    ),
    'target_hit': (
    icon: Icons.emoji_events_rounded,
    color: Color(0xFF22C55E),
    label: 'Target Hit',
    ),
    'stoploss_hit': (
    icon: Icons.warning_rounded,
    color: Color(0xFFEF4444),
    label: 'Stoploss',
    ),
    'alert': (
    icon: Icons.notifications_active_rounded,
    color: Color(0xFFF59E0B),
    label: 'Alert',
    ),
    'recommendation': (
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF6366F1),
    label: 'Update',
    ),
  };

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97).animate(_controller);
  }

  void _down(_) => _controller.forward();
  void _up(_) => _controller.reverse();

  String _time(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final diff = DateTime.now().difference(d);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cfg = _typeConfig[item.type];

    final color = cfg?.color ?? Colors.grey;
    final icon = cfg?.icon ?? Icons.notifications;
    final label = cfg?.label ?? 'Notification';

    final gainVal =
    item.gain != null ? double.tryParse(item.gain!) : null;
    final isProfit = gainVal != null && gainVal >= 0;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Stack(
            children: [

              /// 🌈 BACK GLOW (like feed)
              // Positioned.fill(
              //   child: Container(
              //     decoration: BoxDecoration(
              //       borderRadius: BorderRadius.circular(24),
              //       gradient: RadialGradient(
              //         colors: [
              //           color.withValues(alpha: 0.15),
              //           Colors.transparent,
              //         ],
              //         radius: 1.2,
              //         center: Alignment.topRight,
              //       ),
              //     ),
              //   ),
              // ),

              /// 💎 MAIN GLASS CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),

                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.75),
                      Colors.white.withValues(alpha: 0.55),
                    ],
                  ),

                  border: Border.all(color: Colors.white.withValues(alpha: 0.6)),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 5,
                      offset: const Offset(0, 12),
                    ),
                    // BoxShadow(
                    //   color: color.withValues(alpha: 0.2),
                    //   blurRadius: 6,
                    //   spreadRadius: 2,
                    // ),
                  ],
                ),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    /// 🔥 ICON
                    Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.6),
                            color,
                          ],
                        ),
                      ),
                      child: Icon(icon, color: Colors.white),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          /// 🔹 HEADER
                          Row(
                            children: [
                              Text(
                                label.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _time(item.sentAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          /// 🔥 TITLE
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: Color(0xFF111827),
                            ),
                          ),

                          if (item.body.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.body,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                          ],

                          /// 📈 PROGRESS BAR (NEW 🔥)
                          if (gainVal != null) ...[
                            const SizedBox(height: 10),

                            Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: (gainVal.abs() / 10)
                                    .clamp(0.1, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: LinearGradient(
                                      colors: isProfit
                                          ? [
                                        Color(0xFF22C55E),
                                        Color(0xFF16A34A)
                                      ]
                                          : [
                                        Color(0xFFEF4444),
                                        Color(0xFFDC2626)
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            /// 💰 PROFIT CHIP
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isProfit
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${isProfit ? '+' : ''}${gainVal.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: isProfit
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (widget.onTap != null)
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade300),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// class _NotifCard extends StatefulWidget {
//   const _NotifCard({required this.item, this.onTap});
//
//   final _NotifItem item;
//   final VoidCallback? onTap;
//
//   @override
//   State<_NotifCard> createState() => _NotifCardState();
// }
//
// class _NotifCardState extends State<_NotifCard>
//     with SingleTickerProviderStateMixin {
//   late AnimationController _controller;
//   late Animation<double> _scale;
//
//   static const _typeConfig = {
//     'trade': (
//     icon: Icons.trending_up_rounded,
//     color: Color(0xFF10B981),
//     label: 'New Trade',
//     ),
//     'target_hit': (
//     icon: Icons.emoji_events_rounded,
//     color: Color(0xFF22C55E),
//     label: 'Target Hit',
//     ),
//     'stoploss_hit': (
//     icon: Icons.warning_rounded,
//     color: Color(0xFFEF4444),
//     label: 'Stoploss',
//     ),
//     'alert': (
//     icon: Icons.notifications_active_rounded,
//     color: Color(0xFFF59E0B),
//     label: 'Alert',
//     ),
//     'recommendation': (
//     icon: Icons.auto_awesome_rounded,
//     color: Color(0xFF6366F1),
//     label: 'Update',
//     ),
//   };
//
//   @override
//   void initState() {
//     super.initState();
//
//     _controller = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 120),
//     );
//
//     _scale = Tween(begin: 1.0, end: 0.97).animate(_controller);
//   }
//
//   void _tapDown(_) => _controller.forward();
//   void _tapUp(_) => _controller.reverse();
//
//   String _time(Timestamp? ts) {
//     if (ts == null) return '';
//     final d = ts.toDate();
//     final diff = DateTime.now().difference(d);
//
//     if (diff.inMinutes < 1) return 'now';
//     if (diff.inMinutes < 60) return '${diff.inMinutes}m';
//     if (diff.inHours < 24) return '${diff.inHours}h';
//     return '${diff.inDays}d';
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final item = widget.item;
//     final cfg = _typeConfig[item.type];
//
//     final color = cfg?.color ?? Colors.grey;
//     final icon = cfg?.icon ?? Icons.notifications;
//     final label = cfg?.label ?? 'Notification';
//
//     final gainVal =
//     item.gain != null ? double.tryParse(item.gain!) : null;
//     final isProfit = gainVal != null && gainVal >= 0;
//
//     return GestureDetector(
//       onTap: widget.onTap,
//       onTapDown: _tapDown,
//       onTapUp: _tapUp,
//       onTapCancel: () => _controller.reverse(),
//       child: ScaleTransition(
//         scale: _scale,
//         child: Container(
//           margin: const EdgeInsets.only(bottom: 14),
//           decoration: BoxDecoration(
//             borderRadius: BorderRadius.circular(20),
//             boxShadow: [
//               BoxShadow(
//                 color: color.withValues(alpha: 0.08),
//                 blurRadius: 2,
//                 offset: const Offset(0, 8),
//               ),
//             ],
//           ),
//           child: Stack(
//             children: [
//               // 🌈 Gradient Accent Strip
//               // Positioned(
//               //   left: 0,
//               //   top: 0,
//               //   bottom: 0,
//               //   child: Container(
//               //     width: 4,
//               //     decoration: BoxDecoration(
//               //       borderRadius: const BorderRadius.horizontal(
//               //           left: Radius.circular(20)),
//               //       gradient: LinearGradient(
//               //         colors: [color, color.withValues(alpha: 0.5)],
//               //         begin: Alignment.topCenter,
//               //         end: Alignment.bottomCenter,
//               //       ),
//               //     ),
//               //   ),
//               // ),
//
//               // 💎 Main Card
//               Container(
//                 margin: const EdgeInsets.only(left: 4),
//                 padding: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: Colors.white.withValues(alpha: 0.9),
//                   borderRadius: BorderRadius.circular(20),
//                   border: Border.all(
//                       color: Colors.grey.withValues(alpha: 0.05)),
//                 ),
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Icon
//                     Container(
//                       width: 44,
//                       height: 44,
//                       decoration: BoxDecoration(
//                         gradient: LinearGradient(
//                           colors: [
//                             color.withValues(alpha: 0.15),
//                             color.withValues(alpha: 0.05)
//                           ],
//                         ),
//                         borderRadius: BorderRadius.circular(14),
//                       ),
//                       child: Icon(icon, color: color),
//                     ),
//
//                     const SizedBox(width: 14),
//
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment:
//                         CrossAxisAlignment.start,
//                         children: [
//                           // Header row
//                           Row(
//                             children: [
//                               Text(
//                                 label.toUpperCase(),
//                                 style: TextStyle(
//                                   fontSize: 10,
//                                   fontWeight: FontWeight.w800,
//                                   color: color,
//                                   letterSpacing: 0.5,
//                                 ),
//                               ),
//                               const Spacer(),
//                               Text(
//                                 _time(item.sentAt),
//                                 style: TextStyle(
//                                   fontSize: 11,
//                                   color: Colors.grey.shade400,
//                                 ),
//                               ),
//                             ],
//                           ),
//
//                           const SizedBox(height: 6),
//
//                           Text(
//                             item.title,
//                             style: const TextStyle(
//                               fontSize: 14,
//                               fontWeight: FontWeight.w700,
//                               color: Color(0xFF111827),
//                             ),
//                           ),
//
//                           if (item.body.isNotEmpty) ...[
//                             const SizedBox(height: 4),
//                             Text(
//                               item.body,
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 color: Colors.grey.shade600,
//                                 height: 1.4,
//                               ),
//                             ),
//                           ],
//
//                           // 💰 Profit badge
//                           if (gainVal != null) ...[
//                             const SizedBox(height: 10),
//                             AnimatedContainer(
//                               duration:
//                               const Duration(milliseconds: 300),
//                               padding: const EdgeInsets.symmetric(
//                                   horizontal: 10, vertical: 4),
//                               decoration: BoxDecoration(
//                                 color: isProfit
//                                     ? const Color(0xFFDCFCE7)
//                                     : const Color(0xFFFEE2E2),
//                                 borderRadius:
//                                 BorderRadius.circular(999),
//                               ),
//                               child: Text(
//                                 '${isProfit ? '+' : ''}${gainVal.toStringAsFixed(2)}%',
//                                 style: TextStyle(
//                                   fontWeight: FontWeight.w800,
//                                   fontSize: 12,
//                                   color: isProfit
//                                       ? const Color(0xFF16A34A)
//                                       : const Color(0xFFDC2626),
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ],
//                       ),
//                     ),
//
//                     if (widget.onTap != null)
//                       Icon(Icons.chevron_right_rounded,
//                           color: Colors.grey.shade300),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              color: Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  Container(height: 12, color: Colors.grey),
                  const SizedBox(height: 8),
                  Container(height: 10, color: Colors.grey),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}