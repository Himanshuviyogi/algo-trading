import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../cubits/cubits.dart';
import '../models/broker_connection.dart';
import '../repositories/broker_repository.dart';
import '../utils/app_theme.dart';

// ── BrokerSetupScreen ─────────────────────────────────────────────────────────
//
// Entry point. Reads the current BrokerCubit state and shows either:
//   • The connected status card  (BrokerLoaded + connection exists)
//   • The setup form             (no connection, or user tapped "Reconfigure")

class BrokerSetupScreen extends StatelessWidget {
  const BrokerSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BrokerCubit, BrokerState>(
      listener: (context, state) {
        if (state is BrokerSaveSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Text('Broker connected successfully'),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        if (state is BrokerSaveFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(state.message)),
                ],
              ),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AuroraColors.background,
          appBar: _buildAppBar(context),
          body: _buildBody(context, state),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF111827), size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Broker Setup',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BrokerState state) {
    // Show spinner only on initial load (no data yet)
    if (state is BrokerLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Find Angel One connection if it exists
    BrokerConnection? existing;
    if (state is BrokerLoaded) {
      existing = state.connectionFor(BrokerType.angelOne);
    }

    final isSaving = state is BrokerSaving;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AuroraColors.background, Color(0xFFEFF2FB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BrokerSelectorHeader(selected: BrokerType.angelOne),
            const SizedBox(height: 24),
            if (existing != null && existing.isConnected)
              _ConnectedCard(
                connection: existing,
                isSaving: isSaving,
              )
            else
              _SetupForm(isSaving: isSaving),
            const SizedBox(height: 24),
            _HelpCard(),
          ],
        ),
      ),
    );
  }
}

// ── _BrokerSelectorHeader ─────────────────────────────────────────────────────
//
// Shows available brokers as selectable chips. Currently only Angel One.
// When a new BrokerType is added to the enum this list auto-populates.

class _BrokerSelectorHeader extends StatelessWidget {
  const _BrokerSelectorHeader({required this.selected});

  final BrokerType selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Broker',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: BrokerType.values.map((broker) {
            final isSelected = broker == selected;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [
                          AuroraColors.violet,
                          AuroraColors.violetLight
                        ],
                      )
                    : null,
                color: isSelected ? null : Colors.white,
                border: Border.all(
                  color: isSelected
                      ? AuroraColors.violet
                      : Colors.grey.shade200,
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AuroraColors.violet.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_rounded,
                    size: 16,
                    color:
                        isSelected ? Colors.white : AuroraColors.violet,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    broker.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── _ConnectedCard ────────────────────────────────────────────────────────────
//
// Shown when the user already has a verified Angel One connection.

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({
    required this.connection,
    required this.isSaving,
  });

  final BrokerConnection connection;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final lastVerified = connection.lastVerifiedAt;
    final verifiedText = lastVerified != null
        ? DateFormat('d MMM yyyy, h:mm a').format(lastVerified)
        : 'Not verified';

    return Column(
      children: [
        // ── Status card ──────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF059669),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connection.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Connected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Live indicator dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF10B981).withOpacity(0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),

              _detailRow(
                Icons.person_rounded,
                'Client ID',
                connection.clientId,
              ),
              const SizedBox(height: 10),
              _detailRow(
                Icons.access_time_rounded,
                'Last verified',
                verifiedText,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Action buttons ───────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _OutlineButton(
                label: 'Re-verify',
                icon: Icons.refresh_rounded,
                loading: isSaving,
                onTap: () => context
                    .read<BrokerCubit>()
                    .reverify(connection.brokerId),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OutlineButton(
                label: 'Reconfigure',
                icon: Icons.edit_rounded,
                loading: false,
                onTap: () => _showReconfigureSheet(context),
                color: AuroraColors.violet,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Disconnect ───────────────────────────────────────────────────────
        _DangerButton(
          label: 'Disconnect Broker',
          onTap: () => _confirmDisconnect(context),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: AuroraColors.violet),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showReconfigureSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<BrokerCubit>(),
        child: const _AngelOneFormSheet(),
      ),
    );
  }

  void _confirmDisconnect(BuildContext context) {
    final cubit = context.read<BrokerCubit>();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.link_off_rounded,
                    color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Disconnect Broker?',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Auto-trading will stop working until you reconnect.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        cubit.delete(connection.brokerId);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Disconnect'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SetupForm ────────────────────────────────────────────────────────────────
//
// Inline form shown when no broker is connected yet.

class _SetupForm extends StatelessWidget {
  const _SetupForm({required this.isSaving});
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AuroraColors.violet.withOpacity(0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AuroraColors.violet, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Connect your Angel One account to enable auto order execution '
                  'when trade signals are published.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Form card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Angel One Credentials',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Your credentials are encrypted and only used for order placement.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              _AngelOneForm(isSaving: isSaving),
            ],
          ),
        ),
      ],
    );
  }
}

// ── _AngelOneForm ─────────────────────────────────────────────────────────────
//
// The actual form fields + submit button, reused in both the inline view
// and the reconfigure bottom sheet.

class _AngelOneForm extends StatefulWidget {
  const _AngelOneForm({this.isSaving = false});
  final bool isSaving;

  @override
  State<_AngelOneForm> createState() => _AngelOneFormState();
}

class _AngelOneFormState extends State<_AngelOneForm> {
  final _formKey = GlobalKey<FormState>();
  final _clientIdCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _totpCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  bool _obscureApiKey = true;
  bool _obscureTotp = true;
  bool _obscurePin = true;

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    _totpCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final input = BrokerConnectionInput(
      broker: BrokerType.angelOne,
      clientId: _clientIdCtrl.text.trim().toUpperCase(),
      apiKey: _apiKeyCtrl.text.trim(),
      totpSecret: _totpCtrl.text.trim(),
      pin: _pinCtrl.text.trim(),
    );

    context.read<BrokerCubit>().save(input);
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.isSaving ||
        context.watch<BrokerCubit>().state is BrokerSaving;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          _FormField(
            controller: _clientIdCtrl,
            label: 'Client ID',
            hint: 'e.g. A123456',
            icon: Icons.person_outline_rounded,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(10),
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Client ID is required';
              if (v.trim().length < 3) return 'Enter a valid client ID';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _FormField(
            controller: _apiKeyCtrl,
            label: 'API Key',
            hint: 'Your Angel One API key',
            icon: Icons.vpn_key_outlined,
            obscureText: _obscureApiKey,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureApiKey
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _obscureApiKey = !_obscureApiKey),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'API key is required';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _FormField(
            controller: _totpCtrl,
            label: 'TOTP Secret',
            hint: 'Base-32 encoded secret key',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscureTotp,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureTotp
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _obscureTotp = !_obscureTotp),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'TOTP secret is required';
              }
              // Loose base-32 check (chars A-Z, 2-7, optional = padding)
              final clean = v.trim().replaceAll(' ', '').toUpperCase();
              if (!RegExp(r'^[A-Z2-7=]+$').hasMatch(clean)) {
                return 'Enter a valid base-32 TOTP secret';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _FormField(
            controller: _pinCtrl,
            label: 'MPIN (4-digit login PIN)',
            hint: 'Your Angel One login PIN',
            icon: Icons.pin_outlined,
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePin
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _obscurePin = !_obscurePin),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'MPIN is required';
              if (v.trim().length != 4) return 'MPIN must be exactly 4 digits';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AuroraColors.violet,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Connect & Verify',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _AngelOneFormSheet ────────────────────────────────────────────────────────
//
// Reconfigure bottom sheet — wraps _AngelOneForm in a modal sheet.

class _AngelOneFormSheet extends StatelessWidget {
  const _AngelOneFormSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding:
          EdgeInsets.fromLTRB(20, 24, 20, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Reconfigure Angel One',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter new credentials to replace the existing ones.',
            style:
                TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          BlocConsumer<BrokerCubit, BrokerState>(
            listener: (context, state) {
              if (state is BrokerSaveSuccess) {
                Navigator.of(context).pop();
              }
            },
            builder: (context, state) {
              return _AngelOneForm(isSaving: state is BrokerSaving);
            },
          ),
        ],
      ),
    );
  }
}

// ── _HelpCard ─────────────────────────────────────────────────────────────────

class _HelpCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded,
                  color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                'Where to find these?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _helpItem('Client ID',
              'Your Angel One login ID (e.g. A123456).'),
          _helpItem('API Key',
              'Generate from Angel One SmartAPI portal → My Profile → API Key.'),
          _helpItem('TOTP Secret',
              'Shown once when you enable TOTP in Angel One → Settings → Security. Copy the base-32 secret before closing.'),
          _helpItem('MPIN',
              'Your 4-digit Angel One login PIN (same one you use to log in to the Angel One app).'),
        ],
      ),
    );
  }

  Widget _helpItem(String label, String description) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 12, color: Color(0xFF374151)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: description),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.inputFormatters,
    this.validator,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          inputFormatters: inputFormatters,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(color: Colors.grey.shade400, fontSize: 13),
            prefixIcon: Icon(icon, size: 18, color: AuroraColors.violet),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF8F9FF),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AuroraColors.violet, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFFEF4444), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF374151);
    return OutlinedButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c,
              ),
            )
          : Icon(icon, size: 16, color: c),
      label: Text(
        label,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(color: c.withOpacity(0.4)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.link_off_rounded,
            size: 16, color: Color(0xFFEF4444)),
        label: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFEF4444),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFEF4444)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ── Shared card decoration ────────────────────────────────────────────────────

BoxDecoration _cardDecoration() => BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        colors: [
          Colors.white.withOpacity(0.95),
          Colors.white.withOpacity(0.80),
        ],
      ),
      border: Border.all(color: Colors.white.withOpacity(0.6)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
