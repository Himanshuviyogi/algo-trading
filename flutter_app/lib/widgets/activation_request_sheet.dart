import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../blocs/auth_bloc.dart';
import '../cubits/cubits.dart';
import '../models/models.dart';

/// Shows a bottom sheet with two payment options:
///   1. Request Activation  — admin manually reviews and activates
///   2. Pay via QR / Bank   — shows QR + bank details, then submits request
///
/// Supports three modes:
///   • Subscription plan  — pass [plan], [durationMonths], [amount]
///   • Renewal            — pass [plan], [durationMonths], [amount], [isRenewal] = true,
///                          [currentExpiryDate] for "extends until" display
///   • AI Boost (₹499)    — pass [isBoost] = true, [amount] = 499
///
/// Call with:
///   // Subscription
///   ActivationRequestSheet.show(context, plan: plan, durationMonths: 1, amount: 1999)
///
///   // Renewal
///   ActivationRequestSheet.show(context, plan: plan, durationMonths: 1, amount: 1999,
///       isRenewal: true, currentExpiryDate: subscription.expiryDate)
///
///   // AI Boost
///   ActivationRequestSheet.show(context, isBoost: true)
class ActivationRequestSheet extends StatefulWidget {
  const ActivationRequestSheet({
    super.key,
    this.plan,
    this.durationMonths = 1,
    this.amount = 499,
    this.isBoost = false,
    this.isRenewal = false,
    this.currentExpiryDate,
    this.onSubmitted,
  });

  final SubscriptionPlan? plan;
  final int durationMonths;
  final int amount;

  /// When true the sheet operates in AI Boost mode (₹499, no subscription plan needed).
  final bool isBoost;

  /// When true the sheet operates in Renewal mode — extends an existing subscription.
  final bool isRenewal;

  /// The current expiry date of the active subscription (used to compute
  /// "extends until" date in Renewal mode).
  final DateTime? currentExpiryDate;

  final VoidCallback? onSubmitted;

  // ── Subscription plan mode ─────────────────────────────────────────────────
  static Future<void> show(
    BuildContext context, {
    SubscriptionPlan? plan,
    int durationMonths = 1,
    int amount = 0,
    bool isBoost = false,
    bool isRenewal = false,
    DateTime? currentExpiryDate,
    VoidCallback? onSubmitted,
  }) {
    // Read cubits eagerly here — BEFORE entering the builder closure.
    // The builder's context is deactivated when the sheet closes, so any
    // context.read() inside it will throw "deactivated widget" errors.
    final subscriptionCubit = context.read<SubscriptionCubit>();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: subscriptionCubit,
        child: ActivationRequestSheet(
          plan: plan,
          durationMonths: durationMonths,
          amount: isBoost ? 499 : amount,
          isBoost: isBoost,
          isRenewal: isRenewal,
          currentExpiryDate: currentExpiryDate,
          onSubmitted: onSubmitted,
        ),
      ),
    );
  }

  @override
  State<ActivationRequestSheet> createState() => _ActivationRequestSheetState();
}

class _ActivationRequestSheetState extends State<ActivationRequestSheet> {
  String? _loadingMethod; // 'request' | 'qr_bank' | null
  String? _error;

  // ── Derived display helpers ────────────────────────────────────────────────

  String get _title {
    if (widget.isBoost) return 'AI Boost — 100 Coins';
    if (widget.isRenewal) return 'Renew ${widget.plan?.name ?? 'Plan'}';
    return widget.plan?.name ?? '';
  }

  String get _subtitle {
    if (widget.isBoost) return '₹${widget.amount} · Valid today until midnight';
    if (widget.isRenewal) return '₹${widget.amount} · $_durationLabel · Extends your plan';
    return '₹${widget.amount} · $_durationLabel';
  }

  String get _durationLabel {
    switch (widget.durationMonths) {
      case 6:  return '6 Months';
      case 12: return '1 Year';
      default: return '1 Month';
    }
  }

  /// The date the plan will extend TO if the renewal is approved.
  DateTime get _newExpiryDate {
    final base = widget.currentExpiryDate ?? DateTime.now();
    return DateTime(base.year, base.month + widget.durationMonths, base.day);
  }

  String get _type {
    if (widget.isBoost) return 'ai_boost';
    if (widget.isRenewal) return 'renewal';
    return 'subscription';
  }

  String get _planName => widget.isBoost ? 'AI Boost' : (widget.plan?.name ?? '');

  String get _planId => widget.isBoost ? '' : (widget.plan?.id ?? '');

  int get _durationMonths => widget.isBoost ? 0 : widget.durationMonths;

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit(String paymentMethod) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    setState(() {
      _loadingMethod = paymentMethod;
      _error = null;
    });

    try {
      if (paymentMethod == 'qr_bank') {
        setState(() => _loadingMethod = null);
        await _showQrDialog();
        return;
      }

      await context.read<SubscriptionCubit>().submitActivationRequest(
        type:           _type,
        planId:         _planId,
        planName:       _planName,
        durationMonths: _durationMonths,
        amount:         widget.amount,
        paymentMethod:  paymentMethod,
        userName:       authState.phoneNumber,
        userPhone:      authState.phoneNumber,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSubmitted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isBoost
                  ? '✅ AI Boost request submitted! Admin will activate shortly.'
                  : widget.isRenewal
                      ? '✅ Renewal request submitted! Admin will extend your plan shortly.'
                      : '✅ Request submitted! Admin will activate your plan shortly.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMethod = null;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _showQrDialog() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _QrPaymentDialog(
        title:     _title,
        subtitle:  _subtitle,
        amount:    widget.amount,
        userPhone: authState.phoneNumber,
        onConfirm: () async {
          Navigator.of(ctx).pop();
          setState(() => _loadingMethod = 'qr_bank');
          try {
            await context.read<SubscriptionCubit>().submitActivationRequest(
              type:           _type,
              planId:         _planId,
              planName:       _planName,
              durationMonths: _durationMonths,
              amount:         widget.amount,
              paymentMethod:  'qr_bank',
              userName:       authState.phoneNumber,
              userPhone:      authState.phoneNumber,
              note:           widget.isBoost
                  ? 'User confirmed AI Boost payment via QR/Bank transfer'
                  : widget.isRenewal
                      ? 'User confirmed renewal payment via QR/Bank transfer'
                      : 'User confirmed payment via QR/Bank transfer',
            );
            if (mounted) {
              Navigator.of(context).pop();
              widget.onSubmitted?.call();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    widget.isBoost
                        ? '✅ Payment sent! Admin will verify and activate AI Boost shortly.'
                        : widget.isRenewal
                            ? '✅ Payment sent! Admin will verify and extend your plan shortly.'
                            : '✅ Payment confirmation sent! Admin will verify and activate shortly.',
                  ),
                  backgroundColor: const Color(0xFF16A34A),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _loadingMethod = null;
                _error = e.toString();
              });
            }
          }
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + bottomPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ───────────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: widget.isBoost
                                  ? const [Color(0xFF7C3AED), Color(0xFF4C46E5)]
                                  : widget.isRenewal
                                      ? const [Color(0xFF059669), Color(0xFF047857)]
                                      : const [Color(0xFF4F46E5), Color(0xFF6D5DFC)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4F46E5).withOpacity(.20),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.isBoost
                                ? Icons.bolt_rounded
                                : widget.isRenewal
                                    ? Icons.autorenew_rounded
                                    : Icons.workspace_premium_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: widget.isBoost
                                          ? const Color(0xFF7C3AED).withOpacity(.12)
                                          : widget.isRenewal
                                              ? const Color(0xFF059669).withOpacity(.12)
                                              : const Color(0xFFF59E0B).withOpacity(.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          widget.isBoost
                                              ? Icons.bolt_rounded
                                              : widget.isRenewal
                                                  ? Icons.autorenew_rounded
                                                  : Icons.star_rounded,
                                          size: 10,
                                          color: widget.isBoost
                                              ? const Color(0xFF7C3AED)
                                              : widget.isRenewal
                                                  ? const Color(0xFF059669)
                                                  : const Color(0xFFF59E0B),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          widget.isBoost ? 'BOOST' : widget.isRenewal ? 'RENEW' : 'PRO',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: widget.isBoost
                                                ? const Color(0xFF7C3AED)
                                                : widget.isRenewal
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFFF59E0B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 5),

                              Row(
                                children: [
                                  Text(
                                    '₹${widget.amount}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF16A34A),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: Container(
                                      width: 3,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    widget.isBoost
                                        ? 'Valid today'
                                        : _durationLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // AI Boost — feature summary
                    if (widget.isBoost) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color(0xFF7C3AED).withOpacity(.15)),
                        ),
                        child: Column(
                          children: [
                            _boostFeatureRow(
                                '🪙 100 AI messages today',
                                '10× more than standard plan'),
                            const SizedBox(height: 8),
                            _boostFeatureRow(
                                '📊 All market analysis tools',
                                'Full access unlocked'),
                            const SizedBox(height: 8),
                            _boostFeatureRow(
                                '🔄 Resets tomorrow at midnight',
                                'One-time daily purchase'),
                          ],
                        ),
                      ),
                    ],

                    // Renewal — "extends until" summary
                    if (widget.isRenewal) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color(0xFF059669).withOpacity(.20)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withOpacity(.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.calendar_month_rounded,
                                size: 20,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'New expiry after approval',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF047857),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDate(_newExpiryDate),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF065F46),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    Text(
                      'Choose how to pay',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800),
                    ),

                    const SizedBox(height: 14),

                    // Option 1 — Request Activation
                    _OptionCard(
                      icon: Icons.support_agent_rounded,
                      iconColor: const Color(0xFF4C46E5),
                      iconBg: const Color(0xFFEEF2FF),
                      title: widget.isRenewal ? 'Request Renewal' : 'Request Activation',
                      subtitle: widget.isBoost
                          ? 'Ask admin to manually activate your AI Boost. No payment needed upfront.'
                          : widget.isRenewal
                              ? 'Ask admin to extend your plan. No payment needed upfront.'
                              : 'Ask admin to manually activate your plan. No payment needed upfront.',
                      badge: 'Free to request',
                      badgeColor: const Color(0xFF16A34A),
                      loading: _loadingMethod == 'request',
                      disabled: _loadingMethod != null,
                      onTap: () => _submit('request'),
                    ),

                    const SizedBox(height: 12),

                    // Option 2 — Pay via QR / Bank
                    _OptionCard(
                      icon: Icons.qr_code_2_rounded,
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFEF3C7),
                      title: 'Pay via QR / Bank Transfer',
                      subtitle: widget.isBoost
                          ? 'Scan QR or transfer ₹${widget.amount} to our bank, then notify admin to activate your boost.'
                          : widget.isRenewal
                              ? 'Scan QR or transfer ₹${widget.amount} to our bank, then notify admin to extend your plan.'
                              : 'Scan QR or transfer to our bank account, then notify admin for activation.',
                      badge: 'Instant confirmation',
                      badgeColor: const Color(0xFFD97706),
                      loading: _loadingMethod == 'qr_bank',
                      disabled: _loadingMethod != null,
                      onTap: () => _submit('qr_bank'),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 16, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFDC2626)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  Widget _boostFeatureRow(String main, String sub) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(main,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
              Text(sub,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Option card ───────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.loading,
    required this.onTap,
    this.disabled = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final String badge;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: (loading || disabled) ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: disabled && !loading ? .45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFFCFCFD)],
            ),
            border: Border.all(color: const Color(0xFFEEF2F7)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10)),
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  spreadRadius: -2,
                  offset: const Offset(0, 3)),
              const BoxShadow(
                  color: Colors.white,
                  blurRadius: 1,
                  offset: Offset(0, -1)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827))),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(.12),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(badge,
                              style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 22,
                height: 22,
                child: loading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Icon(Icons.arrow_forward_ios_rounded,
                        size: 16, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── QR / Bank Details Dialog ──────────────────────────────────────────────────

class _QrPaymentDialog extends StatelessWidget {
  const _QrPaymentDialog({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.userPhone,
    required this.onConfirm,
  });

  final String title;
  final String subtitle;
  final int amount;
  final String userPhone;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pay via QR / Bank Transfer',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // QR Code image
              Center(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFFE5E7EB), width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/payment_qr.jpeg',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_2_rounded,
                                size: 80, color: Color(0xFF4C46E5)),
                            const SizedBox(height: 8),
                            Text(
                              'Place your QR + bank details image at\nassets/images/payment_qr.jpeg',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Phone reminder
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add your phone number ($userPhone) in the payment remarks so we can verify easily.',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF92400E),
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Amount to pay
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF4C46E5), Color(0xFF6D5DFC)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Amount to Pay',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    Text('₹$amount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: onConfirm,
                  child: const Text(
                    "I've Paid — Notify Admin",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
