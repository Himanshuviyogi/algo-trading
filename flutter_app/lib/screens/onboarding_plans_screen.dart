import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../blocs/auth_bloc.dart';
import '../cubits/cubits.dart';
import '../models/models.dart';
import '../repositories/user_repository.dart';
import '../services/local_storage_service.dart';
import '../widgets/activation_request_sheet.dart';
import '../utils/app_theme.dart';

/// Shown after profile setup (or on first login with no subscriptions)
/// to recommend plans before entering the main app.
class OnboardingPlansScreen extends StatefulWidget {
  const OnboardingPlansScreen({super.key, this.onSubscribed});

  final VoidCallback? onSubscribed;

  @override
  State<OnboardingPlansScreen> createState() =>
      _OnboardingPlansScreenState();
}

class _OnboardingPlansScreenState extends State<OnboardingPlansScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(
      viewportFraction: 0.85, // 🔥 side preview cards
    );
  }

  @override
  void dispose() {
    _pageController.dispose(); // ✅ important
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor:  AuroraColors.background,
      body: Stack(
        children: [
          // / 🔥 FULL BACKGROUND (FIXED)
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
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 🔥 HEADER
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AuroraColors.violet.withOpacity(0.08),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 54,
                            width: 54,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AuroraColors.violet,
                                  AuroraColors.violetLight
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: AuroraColors.violet
                                      .withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                )
                              ],
                            ),
                            child: const Icon(Icons.auto_awesome,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "Upgrade",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AuroraColors.violet,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        'Choose your plan',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Unlock premium features & better recommendations.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                /// 🔥 CONTENT
                Expanded(
                  child: BlocBuilder<PlansCubit, PlansState>(
                    builder: (context, state) {
                      if (state is PlansLoading) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (state is PlansError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(state.message),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => context
                                    .read<PlansCubit>()
                                    .loadPlans(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }

                      if (state is PlansLoaded) {
                        return Column(
                          children: [
                            /// 🔥 CAROUSEL
                            SizedBox(
                              height: 430,
                              child: PageView.builder(

                                controller: _pageController,
                                itemCount: state.plans.length,
                                onPageChanged: (index) {
                                  setState(
                                          () => _currentIndex = index);
                                },
                                itemBuilder: (context, index) {
                                  return AnimatedBuilder(
                                    animation: _pageController,
                                    builder: (context, child) {
                                      double value = 1.0;

                                      if (_pageController.hasClients &&
                                          _pageController.position
                                              .haveDimensions) {
                                        value =
                                        (_pageController.page! - index);
                                        value = (1 -
                                            (value.abs() * 0.2))
                                            .clamp(0.85, 1.0);

                                        value = Curves.easeOut
                                            .transform(value);
                                      }

                                      return Center(
                                        child: Transform.scale(
                                          scale: value,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: _OnboardingPlanCard(
                                      plan: state.plans[index],
                                      onSubscribed:
                                      widget.onSubscribed,
                                      isPopular: index == 1,
                                    ),
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 16),

                            /// 🔥 INDICATOR (IMPROVED)
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.center,
                              children: List.generate(
                                state.plans.length,
                                    (index) {
                                  final isActive =
                                      _currentIndex == index;

                                  return AnimatedContainer(
                                    duration: const Duration(
                                        milliseconds: 400),
                                    curve: Curves.easeOutBack,
                                    margin:
                                    const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    height: 8,
                                    width: isActive ? 26 : 8,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AuroraColors.violet
                                          : Colors.white
                                          .withOpacity(0.9),
                                      borderRadius:
                                      BorderRadius.circular(20),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ),

                /// 🔥 BOTTOM SECTION (FIXED DESIGN)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                        child: TextButton(
                          onPressed: () async {
                            final authState = context.read<AuthBloc>().state;
                            if (authState is AuthAuthenticated) {
                              // Write to local storage immediately — fast & offline-safe.
                              await context
                                  .read<LocalStorageService>()
                                  .setOnboardingSkipped(authState.uid);
                              // Also persist to Firestore in background.
                              try {
                                await context
                                    .read<UserRepository>()
                                    .markOnboardingSkipped(authState.uid);
                              } catch (_) {}
                            }
                            widget.onSubscribed?.call();
                            if (context.mounted) context.go('/home/dashboard');
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            "Skip for now",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPlanCard extends StatefulWidget {
  const _OnboardingPlanCard({
    required this.plan,
    this.onSubscribed,
    this.isPopular = false,
  });

  final SubscriptionPlan plan;
  final VoidCallback? onSubscribed;
  final bool isPopular;

  @override
  State<_OnboardingPlanCard> createState() => _OnboardingPlanCardState();
}

class _OnboardingPlanCardState extends State<_OnboardingPlanCard> {
  bool _subscribing = false;
  int _selectedDuration = 1; // 1, 6, or 12

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

  Future<void> _subscribe() async {
    await ActivationRequestSheet.show(
      context,
      plan:           widget.plan,
      durationMonths: _selectedDuration,
      amount:         _selectedPrice,
      onSubmitted: () {
        widget.onSubscribed?.call();
        if (mounted) context.go('/home/dashboard');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 420,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),

          /// 🔥 Glass + Gradient feel
          gradient: LinearGradient(
            colors: widget.isPopular
                ? [
              AuroraColors.violet,
              AuroraColors.violetLight,
            ]
                : [
              Colors.white,
              const Color(0xFFF6F7FF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),

          boxShadow: [
            BoxShadow(
              color: widget.isPopular
                  ? AuroraColors.violet.withOpacity(0.35)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔥 TOP BADGE
            if (widget.isPopular)
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "🔥 Most Popular",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            const SizedBox(height: 10),

            /// 🔥 TITLE
            Text(
              widget.plan.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: widget.isPopular ? Colors.white : Colors.black87,
              ),
            ),

            const SizedBox(height: 12),

            /// 🔥 DURATION SELECTOR
            Container(
              decoration: BoxDecoration(
                color: widget.isPopular
                    ? Colors.white.withOpacity(0.15)
                    : const Color(0xFFF1F3F7),
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
                                ? (widget.isPopular ? Colors.white : AuroraColors.violet)
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
                                  ? (widget.isPopular ? AuroraColors.violet : Colors.white)
                                  : (widget.isPopular ? Colors.white60 : Colors.black45),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            /// 🔥 PRICE
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatPrice(_selectedPrice),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: widget.isPopular ? Colors.white : AuroraColors.violet,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '/ $_durationLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isPopular ? Colors.white70 : Colors.black45,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            /// 🔥 FEATURES
            Expanded(

                child: Column(
                  children: widget.plan.features.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            height: 22,
                            width: 22,
                            decoration: BoxDecoration(
                              color: widget.isPopular
                                  ? Colors.white.withOpacity(0.2)
                                  : const Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: widget.isPopular
                                  ? Colors.white
                                  : AuroraColors.violet,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: widget.isPopular
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).take(widget.isPopular ? 5 :6).toList(),
                ),

            ),

            const SizedBox(height: 14),

            /// 🔥 BUTTON
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: widget.isPopular
                      ? Colors.white
                      : AuroraColors.violet,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _subscribing ? null : _subscribe,
                child: _subscribing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Get Started',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: widget.isPopular ? AuroraColors.violet : Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
