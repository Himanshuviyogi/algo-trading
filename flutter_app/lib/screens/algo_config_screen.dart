import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// AlgoConfigScreen — reads/writes `app_config/algo_risk` in Firestore.
///
/// Fields stored (aligned with Firebase Functions):
///   algo_enabled         — bool:   global auto-execute on/off
///   total_capital        — double: user's trading capital in ₹
///   position_size_pct    — double: % of capital per trade (0–100)
///   max_open_positions   — int:    max simultaneous open positions
///   max_order_value      — double: max single order value in ₹ (derived)
///   daily_loss_limit_pct — double: halt % of capital
///   daily_loss_limit     — double: halt in ₹ (derived = capital × pct / 100)
///
/// The Functions read `daily_loss_limit` (₹) and `max_order_value` (₹).
/// This screen writes both raw and percentage forms so both layers stay in sync.
class AlgoConfigScreen extends StatefulWidget {
  const AlgoConfigScreen({super.key});

  @override
  State<AlgoConfigScreen> createState() => _AlgoConfigScreenState();
}

class _AlgoConfigScreenState extends State<AlgoConfigScreen> {
  static const _doc = 'app_config/algo_risk';

  // ── Controllers / form state ─────────────────────────────────────────────
  final _formKey          = GlobalKey<FormState>();
  final _capitalCtrl      = TextEditingController();
  final _positionSizeCtrl = TextEditingController();
  final _maxPositionsCtrl = TextEditingController();
  final _maxOrderValueCtrl = TextEditingController();
  final _dailyLossCtrl    = TextEditingController();

  bool _algoEnabled = false;
  bool _loading     = true;
  bool _saving      = false;
  String? _error;

  // ── Derived preview values (shown below the fields) ──────────────────────
  double get _capital       => double.tryParse(_capitalCtrl.text.trim())      ?? 0;
  double get _positionSizePct => double.tryParse(_positionSizeCtrl.text.trim()) ?? 0;
  double get _dailyLossPct  => double.tryParse(_dailyLossCtrl.text.trim())    ?? 0;

  double get _derivedPositionSize => _capital > 0 ? _capital * _positionSizePct / 100 : 0;
  double get _derivedDailyLoss    => _capital > 0 ? _capital * _dailyLossPct / 100    : 0;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    // Rebuild derived previews whenever any field changes
    _capitalCtrl.addListener(() => setState(() {}));
    _positionSizeCtrl.addListener(() => setState(() {}));
    _dailyLossCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _capitalCtrl.dispose();
    _positionSizeCtrl.dispose();
    _maxPositionsCtrl.dispose();
    _maxOrderValueCtrl.dispose();
    _dailyLossCtrl.dispose();
    super.dispose();
  }

  // ── Firestore ────────────────────────────────────────────────────────────

  Future<void> _loadConfig() async {
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await FirebaseFirestore.instance.doc(_doc).get();
      final d    = snap.data() ?? {};
      _algoEnabled           = d['algo_enabled']         as bool?   ?? false;
      _capitalCtrl.text      = ((d['total_capital']      as num?)?.toDouble() ?? 100_000.0).toStringAsFixed(0);
      _positionSizeCtrl.text = ((d['position_size_pct']  as num?)?.toDouble() ?? 2.0).toStringAsFixed(1);
      _maxPositionsCtrl.text = ((d['max_open_positions'] as num?)?.toInt()    ?? 5).toString();
      _maxOrderValueCtrl.text= ((d['max_order_value']    as num?)?.toDouble() ?? 50_000.0).toStringAsFixed(0);
      _dailyLossCtrl.text    = ((d['daily_loss_limit_pct'] as num?)?.toDouble() ?? 3.0).toStringAsFixed(1);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final capital         = double.parse(_capitalCtrl.text.trim());
      final positionSizePct = double.parse(_positionSizeCtrl.text.trim());
      final maxPositions    = int.parse(_maxPositionsCtrl.text.trim());
      final maxOrderValue   = double.parse(_maxOrderValueCtrl.text.trim());
      final dailyLossPct    = double.parse(_dailyLossCtrl.text.trim());

      // Derived ₹ values — what the Firebase Functions actually read
      final dailyLossLimit  = capital * dailyLossPct / 100;

      await FirebaseFirestore.instance.doc(_doc).set(
        {
          'algo_enabled':         _algoEnabled,
          'total_capital':        capital,
          'position_size_pct':    positionSizePct,
          'max_open_positions':   maxPositions,
          'max_order_value':      maxOrderValue,
          // Both forms written — percentage for display, raw ₹ for Functions
          'daily_loss_limit_pct': dailyLossPct,
          'daily_loss_limit':     dailyLossLimit,
          'updated_at':           FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Config saved'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AuroraColors.violet),
            onPressed: _loading ? null : _loadConfig,
          ),
        ],
        title: Row(
          children: [
            Container(
              height: 36, width: 36,
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
                const Text('Algo Config',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF111827))),
                Text('Risk & execution settings',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AuroraColors.violet))
          : _error != null
              ? _buildError()
              : _buildForm(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            const Text('Failed to load config',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AuroraColors.violet, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              onPressed: _loadConfig,
              child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [

          // ── Master toggle ──────────────────────────────────────────────
          _SectionCard(
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _algoEnabled
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFFEF4444).withValues(alpha: 0.10),
                  ),
                  child: Icon(
                    _algoEnabled ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded,
                    color: _algoEnabled ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Auto-Execute',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                      const SizedBox(height: 2),
                      Text(
                        _algoEnabled ? 'Orders placed automatically on condition' : 'Manual only — engine paused',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _algoEnabled,
                  onChanged: (v) => setState(() => _algoEnabled = v),
                  activeColor: AuroraColors.violet,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _SectionHeader(label: 'CAPITAL'),
          const SizedBox(height: 8),

          // ── Capital ───────────────────────────────────────────────────
          _SectionCard(
            child: _ConfigField(
              controller: _capitalCtrl,
              label: 'Total Trading Capital',
              hint: '100000',
              prefix: '₹',
              icon: Icons.account_balance_wallet_outlined,
              validator: _validatePositiveNumber,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
            ),
          ),

          const SizedBox(height: 20),
          _SectionHeader(label: 'POSITION & ORDER LIMITS'),
          const SizedBox(height: 8),

          _SectionCard(
            child: Column(
              children: [
                _ConfigField(
                  controller: _positionSizeCtrl,
                  label: 'Position Size per Trade',
                  hint: '2.0',
                  suffix: '% of capital',
                  icon: Icons.pie_chart_outline_rounded,
                  validator: _validatePercent,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  previewValue: _derivedPositionSize > 0
                      ? '= ₹${_derivedPositionSize.toStringAsFixed(0)} per trade'
                      : null,
                ),
                _Divider(),
                _ConfigField(
                  controller: _maxPositionsCtrl,
                  label: 'Max Open Positions',
                  hint: '5',
                  suffix: 'positions',
                  icon: Icons.grid_view_rounded,
                  validator: _validatePositiveInt,
                  keyboardType: TextInputType.number,
                ),
                _Divider(),
                _ConfigField(
                  controller: _maxOrderValueCtrl,
                  label: 'Max Single Order Value',
                  hint: '50000',
                  prefix: '₹',
                  icon: Icons.price_check_rounded,
                  validator: _validatePositiveNumber,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _SectionHeader(label: 'DAILY LOSS PROTECTION'),
          const SizedBox(height: 8),

          _SectionCard(
            child: _ConfigField(
              controller: _dailyLossCtrl,
              label: 'Daily Loss Limit',
              hint: '3.0',
              suffix: '% of capital',
              icon: Icons.shield_outlined,
              validator: _validatePercent,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              accentColor: const Color(0xFFEF4444),
              previewValue: _derivedDailyLoss > 0
                  ? '= ₹${_derivedDailyLoss.toStringAsFixed(0)} max daily loss'
                  : null,
              previewColor: const Color(0xFFEF4444),
            ),
          ),

          // ── Info banner ───────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AuroraColors.infoBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AuroraColors.info.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AuroraColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'When today\'s total realised loss reaches the daily limit, '
                    'the engine automatically stops placing new entry orders until midnight.',
                    style: TextStyle(
                        fontSize: 12, height: 1.5,
                        color: AuroraColors.info.withValues(alpha: 0.85)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Save button ───────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save Config',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AuroraColors.violet,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Validators ────────────────────────────────────────────────────────────

  String? _validatePercent(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a number';
    if (n <= 0 || n > 100) return 'Must be between 0 and 100';
    return null;
  }

  String? _validatePositiveInt(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = int.tryParse(v.trim());
    if (n == null) return 'Enter a whole number';
    if (n < 1) return 'Must be at least 1';
    return null;
  }

  String? _validatePositiveNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a number';
    if (n <= 0) return 'Must be greater than 0';
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: Colors.grey.shade500, letterSpacing: 0.8)),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 24, color: Colors.grey.shade100);
}

class _ConfigField extends StatelessWidget {
  const _ConfigField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validator,
    required this.keyboardType,
    this.suffix,
    this.prefix,
    this.accentColor = AuroraColors.violet,
    this.previewValue,
    this.previewColor,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? suffix;
  final String? prefix;
  final IconData icon;
  final FormFieldValidator<String> validator;
  final TextInputType keyboardType;
  final Color accentColor;
  final String? previewValue;
  final Color? previewColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: accentColor.withValues(alpha: 0.10),
          ),
          child: Icon(icon, size: 18, color: accentColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
              const SizedBox(height: 6),
              TextFormField(
                controller: controller,
                keyboardType: keyboardType,
                validator: validator,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                decoration: InputDecoration(
                  hintText: hint,
                  prefixText: prefix,
                  suffixText: suffix,
                  suffixStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor, width: 1.5)),
                  errorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                  focusedErrorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                ),
              ),
              if (previewValue != null) ...[
                const SizedBox(height: 4),
                Text(previewValue!,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: (previewColor ?? AuroraColors.violet).withValues(alpha: 0.7))),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
