import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class NewsUpdatesScreen extends StatelessWidget {
  const NewsUpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
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
                  'Daily Insights',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: Color(0xFF111827)),
                ),
                Text(
                  'Recent updates & alerts',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            )
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('daily_updates')
            .where('is_active', isEqualTo: true)
            .orderBy('created_at', descending: true)
            .limit(30)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: 6,
              itemBuilder: (_, __) => const _ShimmerCard(),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No updates yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final item = _UpdateItem.fromMap(data);

              return TweenAnimationBuilder(
                duration: Duration(milliseconds: 300 + (i * 50)),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                ),
                child: _UpdateCard(item: item),
              );
            },
          );
        },
      ),
    );
  }
}

class _UpdateItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime? createdAt;

  const _UpdateItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.createdAt,
  });

  factory _UpdateItem.fromMap(Map<String, dynamic> m) => _UpdateItem(
        id:        m['id'] as String? ?? '',
        title:     m['title'] as String? ?? '',
        body:      m['body'] as String? ?? '',
        type:      m['type'] as String? ?? 'update',
        createdAt: m['created_at'] is Timestamp
            ? (m['created_at'] as Timestamp).toDate()
            : null,
      );
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.item});
  final _UpdateItem item;

  String _time(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'alert':  return const Color(0xFFEF4444);
      case 'market': return const Color(0xFF10B981);
      case 'tip':    return const Color(0xFFF59E0B);
      default:       return const Color(0xFF6366F1);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'alert':  return Icons.warning_amber_rounded;
      case 'market': return Icons.show_chart_rounded;
      case 'tip':    return Icons.lightbulb_outline_rounded;
      default:       return Icons.campaign_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'alert':  return 'ALERT';
      case 'market': return 'MARKET';
      case 'tip':    return 'TIP';
      default:       return 'UPDATE';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(item.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.85),
            Colors.white.withOpacity(0.65),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: color.withOpacity(0.12),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Icon(_typeIcon(item.type), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _typeLabel(item.type),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _time(item.createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF111827),
                  ),
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
            Container(width: 44, height: 44, decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(14),
            )),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 10, width: 60, color: Colors.grey),
                  const SizedBox(height: 8),
                  Container(height: 12, color: Colors.grey),
                  const SizedBox(height: 6),
                  Container(height: 10, width: double.infinity, color: Colors.grey),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
