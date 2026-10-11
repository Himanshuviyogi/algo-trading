import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'screeners_screen.dart';

// ── Breakout category definition ──────────────────────────────────────────────

class _BreakoutCategory {
  final String screenerId;
  final String emoji;
  final String title;
  final String subtitle;
  final Color  accentColor;
  final Color  bgColor;
  final bool   requiresHistory;  // Phase 2 screeners

  const _BreakoutCategory({
    required this.screenerId,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.bgColor,
    this.requiresHistory = false,
  });
}

const _kCategories = [
  _BreakoutCategory(
    screenerId:  'daily_breakout',
    emoji:       '🔥',
    title:       'Daily Fresh Breakout',
    subtitle:    'Stocks hitting 52-week highs today with positive momentum',
    accentColor: Color(0xFF6366F1),
    bgColor:     Color(0xFFEEF2FF),
  ),
  _BreakoutCategory(
    screenerId:  'nearing_breakout',
    emoji:       '🎯',
    title:       'Nearing Breakout',
    subtitle:    'Within 3% of 52-week high — coiled and ready',
    accentColor: Color(0xFF7C3AED),
    bgColor:     Color(0xFFF5F3FF),
  ),
  _BreakoutCategory(
    screenerId:       'weekly_breakout',
    emoji:            '📅',
    title:            'Weekly Breakout',
    subtitle:         'Stocks crossing last week\'s high today',
    accentColor:      Color(0xFF0891B2),
    bgColor:          Color(0xFFECFEFF),
    requiresHistory:  true,
  ),
  _BreakoutCategory(
    screenerId:       'oversold_rsi',
    emoji:            '📉',
    title:            'Oversold (RSI < 30)',
    subtitle:         'Deeply oversold stocks — potential reversal candidates',
    accentColor:      Color(0xFFDC2626),
    bgColor:          Color(0xFFFFF1F2),
    requiresHistory:  true,
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class BreakoutsScreen extends StatelessWidget {
  const BreakoutsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Breakouts',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xFF111827))),
            Text('NSE EOD · Updated daily after market close',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ),
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).padding.bottom + 80),
        itemCount: _kCategories.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _BreakoutCard(category: _kCategories[i]),
        ),
      ),
    );
  }
}

// ── Breakout card ─────────────────────────────────────────────────────────────

class _BreakoutCard extends StatelessWidget {
  final _BreakoutCategory category;
  const _BreakoutCard({required this.category});

  @override
  Widget build(BuildContext context) {
    if (category.requiresHistory) {
      return _buildLockedCard(context);
    }
    return _buildLiveCard(context);
  }

  // ── Live card — reads from Firestore ─────────────────────────────────────────
  Widget _buildLiveCard(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('screeners')
          .doc(category.screenerId)
          .get(),
      builder: (context, snap) {
        int?    count;
        String? date;
        bool    available = false;

        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>? ?? {};
          if (d['status'] == 'ok') {
            count     = (d['count'] as num?)?.toInt();
            date      = d['date'] as String?;
            available = true;
          }
        }

        return _CardShell(
          category:  category,
          count:     count,
          date:      date,
          available: available,
          loading:   snap.connectionState == ConnectionState.waiting,
          onTap: available
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenerDetailScreen(
                        screenerId: category.screenerId,
                        meta: ScreenerMeta(
                          id:     category.screenerId,
                          label:  category.title,
                          emoji:  category.emoji,
                          color:  _colorName(category.accentColor),
                          count:  count ?? 0,
                          date:   date ?? '',
                          status: 'ok',
                        ),
                      ),
                    ),
                  )
              : null,
        );
      },
    );
  }

  // ── Locked card (Phase 2) ─────────────────────────────────────────────────────
  Widget _buildLockedCard(BuildContext context) {
    return _CardShell(
      category:  category,
      count:     null,
      date:      null,
      available: false,
      loading:   false,
      locked:    true,
      onTap:     null,
    );
  }

  String _colorName(Color c) {
    if (c == const Color(0xFF6366F1)) return 'indigo';
    if (c == const Color(0xFF7C3AED)) return 'purple';
    if (c == const Color(0xFF0891B2)) return 'teal';
    if (c == const Color(0xFFDC2626)) return 'red';
    return 'blue';
  }
}

// ── Card shell ────────────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  final _BreakoutCategory category;
  final int?              count;
  final String?           date;
  final bool              available;
  final bool              loading;
  final bool              locked;
  final VoidCallback?     onTap;

  const _CardShell({
    required this.category,
    required this.count,
    required this.date,
    required this.available,
    required this.loading,
    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !available || locked;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity:  dimmed ? 0.65 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(18),
            border:       Border.all(color: Colors.grey.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color:  Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // ── Emoji badge ─────────────────────────────────────────────────
              Container(
                width:  52,
                height: 52,
                decoration: BoxDecoration(
                  color:        category.bgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(category.emoji,
                    style: const TextStyle(fontSize: 26)),
              ),

              const SizedBox(width: 14),

              // ── Text content ────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.title,
                            style: const TextStyle(
                              fontSize:   14,
                              fontWeight: FontWeight.w800,
                              color:      Color(0xFF111827),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (locked)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:        Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline_rounded,
                                    size: 10, color: Colors.grey.shade400),
                                const SizedBox(width: 3),
                                Text('Coming soon',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade400)),
                              ],
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 3),

                    Text(
                      category.subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8),

                    // ── Bottom row ───────────────────────────────────────────
                    Row(
                      children: [
                        if (loading) ...[
                          SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: category.accentColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('Loading…',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade400)),
                        ] else if (locked) ...[
                          Text('Requires 14 days of price history',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade400)),
                        ] else if (available && count != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:        category.accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$count stocks',
                              style: TextStyle(
                                fontSize:   11,
                                fontWeight: FontWeight.w700,
                                color:      category.accentColor,
                              ),
                            ),
                          ),
                          if (date != null && date!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(date!,
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade400)),
                          ],
                        ] else ...[
                          Text('Updated after market close',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade400)),
                        ],

                        const Spacer(),

                        if (available && !locked)
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: Colors.grey.shade400),
                      ],
                    ),
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
