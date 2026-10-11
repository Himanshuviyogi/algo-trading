import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/cubits.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';
import '../widgets/activation_request_sheet.dart';
import '../utils/app_theme.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),

      body: Stack(
        children:[
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [
                    AuroraColors.violet.withOpacity(0.12),
                    AuroraColors.background,
                  ],
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.bottomRight,
                  radius: 1.2,
                  colors: [
                    AuroraColors.violet.withOpacity(0.12),
                    AuroraColors.background,
                  ],
                ),
              ),
            ),
          ),
          BlocBuilder<PlansCubit, PlansState>(
            builder: (context, plansState) {
              if (plansState is PlansLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (plansState is PlansError) {
                return Center(child: Text(plansState.message));
              }

              /// ✅ ONLY ONE PlansLoaded BLOCK
              if (plansState is PlansLoaded) {
                return BlocBuilder<SubscriptionCubit, SubscriptionState>(
                  builder: (context, subState) {
                    final activeSubs = subState is SubscriptionLoaded
                        ? subState.subscriptions
                        .where((s) => s.isEffectivelyActive)
                        .toList()
                        : <Subscription>[];

                    final pendingRequests = subState is SubscriptionLoaded
                        ? subState.pendingRequests
                        : <ActivationRequest>[];

                    // return SafeArea(
                    //   child: Column(
                    //     children: [
                    //       /// 🔥 YOUR ORIGINAL HEADER (UNCHANGED)
                    //       Padding(
                    //         padding:
                    //         const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    //         child: _buildHeader(),
                    //       ),
                    //
                    //       const SizedBox(height: 16),
                    //
                    //       /// 🔥 HORIZONTAL SWIPE
                    //       Container(
                    //         color:AuroraColors.violet.withOpacity(0.02),
                    //         child: SizedBox(
                    //           height: 420,
                    //           child: PageView.builder(
                    //
                    //             controller: _pageController,
                    //             itemCount: plansState.plans.length,
                    //             onPageChanged: (index) {
                    //               setState(() => _currentIndex = index);
                    //             },
                    //             itemBuilder: (context, index) {
                    //               final plan = plansState.plans[index];
                    //
                    //               final isSubscribed = activeSubs.any(
                    //                       (s) => s.planId == plan.id);
                    //               final activeSub = activeSubs.where(
                    //                       (s) => s.planId == plan.id)
                    //                   .firstOrNull;
                    //
                    //               return AnimatedBuilder(
                    //                 animation: _pageController,
                    //                 builder: (context, child) {
                    //                   double value = 1;
                    //
                    //                   if (_pageController.hasClients &&
                    //                       _pageController.position
                    //                           .haveDimensions) {
                    //                     value =
                    //                     (_pageController.page! - index);
                    //                     value = (1 - (value.abs() * 0.2))
                    //                         .clamp(0.85, 1.0);
                    //                   }
                    //
                    //                   return Transform.scale(
                    //                     scale: value,
                    //                     child: child,
                    //                   );
                    //                 },
                    //                 child: Padding(
                    //                   padding:
                    //                   const EdgeInsets.symmetric(
                    //                       horizontal: 8),
                    //                   child: _ModernPlanCard(
                    //                     plan: plan,
                    //                     isSubscribed: isSubscribed,
                    //                     subscription: activeSub,
                    //                   ),
                    //                 ),
                    //               );
                    //             },
                    //           ),
                    //         ),
                    //       ),
                    //
                    //       const SizedBox(height: 16),
                    //
                    //       /// 🔥 INDICATOR
                    //       Row(
                    //         mainAxisAlignment:
                    //         MainAxisAlignment.center,
                    //         children: List.generate(
                    //           plansState.plans.length,
                    //               (index) {
                    //             final isActive =
                    //                 _currentIndex == index;
                    //
                    //             return AnimatedContainer(
                    //               duration:
                    //               const Duration(milliseconds: 300),
                    //               margin:
                    //               const EdgeInsets.symmetric(
                    //                   horizontal: 4),
                    //               height: 8,
                    //               width: isActive ? 24 : 8,
                    //               decoration: BoxDecoration(
                    //                 color: isActive
                    //                     ? const Color(0xFF059669)
                    //                     : Colors.grey.shade300,
                    //                 borderRadius:
                    //                 BorderRadius.circular(20),
                    //               ),
                    //             );
                    //           },
                    //         ),
                    //       ),
                    //     ],
                    //   ),
                    // );



                    return SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                    child: _buildHeader(),
                                  ),

                                  const SizedBox(height: 16),

                                  Container(
                                    color: AuroraColors.violet.withOpacity(0.02),
                                    child: SizedBox(
                                      height: 460,
                                      child: PageView.builder(
                                        controller: _pageController,
                                        itemCount: plansState.plans.length,
                                        onPageChanged: (index) {
                                          setState(() => _currentIndex = index);
                                        },
                                        itemBuilder: (context, index) {
                                          final plan = plansState.plans[index];

                                          final isSubscribed =
                                          activeSubs.any((s) => s.planId == plan.id);

                                          final activeSub = activeSubs
                                              .where((s) => s.planId == plan.id)
                                              .firstOrNull;

                                          final pendingRequest = pendingRequests
                                              .where((r) => r.planId == plan.id)
                                              .firstOrNull;

                                          return AnimatedBuilder(
                                            animation: _pageController,
                                            builder: (context, child) {
                                              double value = 1;

                                              if (_pageController.hasClients &&
                                                  _pageController.position.haveDimensions) {
                                                value = (_pageController.page! - index);
                                                value = (1 - (value.abs() * 0.2))
                                                    .clamp(0.85, 1.0);
                                              }

                                              return Transform.scale(
                                                scale: value,
                                                child: child,
                                              );
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: _ModernPlanCard(
                                                plan: plan,
                                                isSubscribed: isSubscribed,
                                                subscription: activeSub,
                                                pendingRequest: pendingRequest,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(
                                      plansState.plans.length,
                                          (index) {
                                        final isActive = _currentIndex == index;

                                        return AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          margin: const EdgeInsets.symmetric(horizontal: 4),
                                          height: 8,
                                          width: isActive ? 24 : 8,
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? const Color(0xFF059669)
                                                : Colors.grey.shade300,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 24),
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

              return const SizedBox.shrink();
            },
          ),
        ]
      ),
    );
  }



  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,

      title: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            /// 🔥 LOGO BOX
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF1F3F7),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/small_logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),

            const SizedBox(width: 12),

            /// 🔥 TITLE BLOCK
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plans',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  'Choose your subscription',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      /// 🔥 OPTIONAL ACTION (premium feel)
      // actions: [
      //   Padding(
      //     padding: const EdgeInsets.only(right: 12),
      //     child: IconButton(
      //       onPressed: () {},
      //       icon: const Icon(
      //         Icons.help_outline_rounded,
      //         color: Colors.black54,
      //       ),
      //     ),
      //   ),
      // ],
    );
  }



  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A), // dark navy
            Color(0xFF1E293B), // slate
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 🔥 TOP TAG
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "🔥 PREMIUM ACCESS",
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 12),

          /// 🔥 TITLE
          const Text(
            "Available Plans",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 6),

          /// 🔥 SUBTITLE
          Text(
            "Choose a plan that fits your trading style",
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.7),
            ),
          ),

          // const SizedBox(height: 4),
          //
          // /// 🔥 STATS ROW (same but improved spacing)
          // Row(
          //   children: [
          //     _miniStat("Active Traders", "12K+"),
          //     const SizedBox(width: 20),
          //     _miniStat("Success Rate", "87%"),
          //   ],
          // ),
        ],
      ),
    );
  }


  Widget _miniStat(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// 🔥 VALUE
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 2),

        /// 🔥 LABEL
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.65),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// class _ModernPlanCard extends StatelessWidget {
//   const _ModernPlanCard({
//     required this.plan,
//     required this.isSubscribed,
//   });
//
//   final SubscriptionPlan plan;
//   final bool isSubscribed;
//
//   String _formatPrice(int paise) {
//     // final rupees = paise / 100;
//     // return '₹${rupees.toStringAsFixed(rupees.truncateToDouble() == rupees ? 0 : 2)}';
//     return '₹${paise}';
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final price = plan.pricing.oneMonth;
//
//     const primary = Color(0xFF059669); // 🔥 Emerald
//     const accent = Color(0xFF10B981);
//
//     return AnimatedContainer(
//       duration: const Duration(milliseconds: 300),
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(26),
//
//         /// 🔥 Glass + Gradient feel
//         gradient: LinearGradient(
//           colors: isSubscribed
//               ? [
//             AuroraColors.violet,
//             AuroraColors.violetLight,
//           ]
//               : [
//             Colors.white,
//             const Color(0xFFF6F7FF),
//           ],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//
//         boxShadow: [
//           BoxShadow(
//             color: isSubscribed
//                 ? AuroraColors.violet.withOpacity(0.35)
//                 : Colors.black.withOpacity(0.08),
//             blurRadius: 25,
//             offset: const Offset(0, 12),
//           ),
//         ],
//       ),
//
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           /// 🔥 HEADER
//           Row(
//             children: [
//               Expanded(
//                 child: Text(
//                   plan.name,
//                   style: const TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//               ),
//               if (isSubscribed)
//                 Container(
//                   padding:
//                   const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
//                   decoration: BoxDecoration(
//                     gradient: const LinearGradient(
//                       colors: [primary, accent],
//                     ),
//                     borderRadius: BorderRadius.circular(20),
//                   ),
//                   child: Row(
//                     mainAxisSize: MainAxisSize.min,
//                     children: const [
//                       Icon(
//                         Icons.verified_rounded,
//                         size: 14,
//                         color: Colors.white,
//                       ),
//                       SizedBox(width: 4),
//                       Text(
//                         "ACTIVE",
//                         style: TextStyle(
//                           fontSize: 11,
//                           fontWeight: FontWeight.w700,
//                           letterSpacing: 0.6,
//                           color: Colors.white,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//             ],
//           ),
//
//           const SizedBox(height: 14),
//
//           /// 🔥 PRICE
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.end,
//             children: [
//               Text(
//                 _formatPrice(price),
//                 style: const TextStyle(
//                   fontSize: 26,
//                   fontWeight: FontWeight.bold,
//                   color: primary,
//                 ),
//               ),
//               const SizedBox(width: 6),
//               const Text(
//                 "/month",
//                 style: TextStyle(
//                   fontSize: 13,
//                   color: Colors.black45,
//                 ),
//               ),
//             ],
//           ),
//
//           const SizedBox(height: 16),
//
//           /// 🔥 FEATURES
//           ...plan.features.map(
//                 (f) => Padding(
//               padding: const EdgeInsets.only(bottom: 10),
//               child: Row(
//                 children: [
//                   const Icon(
//                     Icons.check_circle,
//                     size: 18,
//                     color: primary,
//                   ),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       f,
//                       style: const TextStyle(fontSize: 14),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//
//           const SizedBox(height: 18),
//
//           /// 🔥 BUTTON
//           SizedBox(
//             width: double.infinity,
//             height: 48,
//             child: isSubscribed
//                 ? OutlinedButton(
//               style: OutlinedButton.styleFrom(
//                 side: const BorderSide(color: primary),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(14),
//                 ),
//               ),
//               onPressed: () => context
//                   .read<SubscriptionCubit>()
//                   .cancel(plan.id),
//               child: const Text(
//                 "Cancel Subscription",
//                 style: TextStyle(
//                   color: primary,
//                   fontWeight: FontWeight.w600,
//                 ),
//               ),
//             )
//                 : ElevatedButton(
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: primary,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(14),
//                 ),
//               ),
//               onPressed: () => context
//                   .read<SubscriptionCubit>()
//                   .subscribe(
//                 plan.id,
//                 DateTime.now()
//                     .add(const Duration(days: 30)),
//               ),
//               child: const Text(
//                 "Subscribe",
//                 style: TextStyle(
//                   fontWeight: FontWeight.w600,
//                   color: Colors.white,
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class _ModernPlanCard extends StatefulWidget {
  const _ModernPlanCard({
    required this.plan,
    required this.isSubscribed,
    this.subscription,
    this.pendingRequest,
  });

  final SubscriptionPlan plan;
  final bool isSubscribed;
  final Subscription? subscription;
  final ActivationRequest? pendingRequest;

  @override
  State<_ModernPlanCard> createState() => _ModernPlanCardState();
}

class _ModernPlanCardState extends State<_ModernPlanCard> {
  bool _loading = false;
  int _selectedDuration = 1; // 1, 6, or 12 months

  String _formatPrice(int p) => '₹${p.toStringAsFixed(0)}';

  int get _selectedPrice {
    switch (_selectedDuration) {
      case 6:  return widget.plan.pricing.sixMonth;
      case 12: return widget.plan.pricing.oneYear;
      default: return widget.plan.pricing.oneMonth;
    }
  }

  String get _durationLabel {
    switch (_selectedDuration) {
      case 6:  return '6 months';
      case 12: return '1 year';
      default: return '1 month';
    }
  }

  Future<void> _handleAction() async {
    if (widget.isSubscribed) {
      setState(() => _loading = true);
      try {
        await context.read<SubscriptionCubit>().cancel(widget.plan.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
          );
        }
      }
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Show the activation request sheet
    await ActivationRequestSheet.show(
      context,
      plan:           widget.plan,
      durationMonths: _selectedDuration,
      amount:         _selectedPrice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const primary = AuroraColors.violet;
    const secondary = AuroraColors.violetLight;

    final isActive = widget.isSubscribed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),

          /// 🔥 GRADIENT BASED ON SUBSCRIPTION
          gradient: LinearGradient(
            colors: isActive
                ? [primary, secondary]
                : [Colors.white, const Color(0xFFF6F7FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),

          boxShadow: [
            BoxShadow(
              color: isActive
                  ? primary.withOpacity(0.35)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔥 ACTIVE BADGE
            if (isActive)
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "✨ ACTIVE PLAN",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            /// 🔥 TITLE
            Text(
              widget.plan.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : Colors.black87,
              ),
            ),

            const SizedBox(height: 12),

            /// 🔥 DURATION SELECTOR
            Container(
              decoration: BoxDecoration(
                color: isActive ? Colors.white.withOpacity(0.15) : const Color(0xFFF1F3F7),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  for (final entry in const [(1, '1M'), (6, '6M'), (12, '1Y')])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedDuration = entry.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _selectedDuration == entry.$1
                                ? (isActive ? Colors.white : AuroraColors.violet)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            entry.$2,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _selectedDuration == entry.$1
                                  ? (isActive ? AuroraColors.violet : Colors.white)
                                  : (isActive ? Colors.white60 : Colors.black45),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            /// 🔥 PRICE
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatPrice(_selectedPrice),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : AuroraColors.violet,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '/ $_durationLabel',
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive ? Colors.white70 : Colors.black45,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            /// 🔥 FEATURES
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: widget.plan.features.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 22,
                            width: 22,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.white.withOpacity(0.2)
                                  : const Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: isActive ? Colors.white : primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: isActive ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 14),

            /// 🔥 BUTTON
            SizedBox(
              width: double.infinity,
              child: isActive
                  // Active — show expiry + renew button
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Expiry info row
                        Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 13,
                                color: Colors.white.withOpacity(0.75),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Active until  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.75),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                widget.subscription != null
                                    ? DateFormat('dd MMM yyyy').format(widget.subscription!.expiryDate)
                                    : '—',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Renew button — only if no pending renewal request
                        widget.pendingRequest != null
                            ? Container(
                                height: 46,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 14,
                                      color: Color(0xFFB45309),
                                    ),
                                    const SizedBox(width: 7),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Renewal Pending Approval',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFB45309),
                                          ),
                                        ),
                                        Text(
                                          'Submitted ${DateFormat('dd MMM').format(widget.pendingRequest!.createdAt)}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFFD97706),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : SizedBox(
                                height: 46,
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: Colors.white.withOpacity(0.22),
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withOpacity(0.45)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: _loading
                                      ? null
                                      : () => ActivationRequestSheet.show(
                                            context,
                                            plan: widget.plan,
                                            durationMonths: _selectedDuration,
                                            amount: _selectedPrice,
                                            isRenewal: true,
                                            currentExpiryDate: widget.subscription?.expiryDate,
                                          ),
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.autorenew_rounded, size: 16),
                                  label: const Text(
                                    'Renew Plan',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    )
                  // Pending request — block further requests
                  : widget.pendingRequest != null
                      ? Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 16,
                                color: Color(0xFFB45309),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Awaiting Admin Approval',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                  Text(
                                    'Submitted ${DateFormat('dd MMM').format(widget.pendingRequest!.createdAt)}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                  // Not subscribed — Request / Pay button
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AuroraColors.violet,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _loading ? null : _handleAction,
                      child: _loading
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Get Started',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
