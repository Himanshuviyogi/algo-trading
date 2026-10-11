import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class ResearchExpert {
  final String name;
  final String designation;
  final int    yearsExp;
  final String imageUrl;

  const ResearchExpert({
    required this.name,
    required this.designation,
    required this.yearsExp,
    required this.imageUrl,
  });

  factory ResearchExpert.fromMap(Map<String, dynamic> m) => ResearchExpert(
        name:        m['name']        as String? ?? '',
        designation: m['designation'] as String? ?? '',
        yearsExp:    (m['years_exp']  as num?)?.toInt() ?? 0,
        imageUrl:    m['image_url']   as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name':        name,
        'designation': designation,
        'years_exp':   yearsExp,
        'image_url':   imageUrl,
      };
}

// ── Widget ────────────────────────────────────────────────────────────────────
// Reads from Firestore `app_config/experts` → field `experts: [...]`
// Updated via admin panel (AppUtilities page).
//
// NOTE: Converted to StatefulWidget so the stream is stored as a field.
// A StatelessWidget creates a new stream object on every build(), which causes
// StreamBuilder to resubscribe and charge an extra Firestore read each time.

class ResearchExpertsSection extends StatefulWidget {
  const ResearchExpertsSection({super.key});

  @override
  State<ResearchExpertsSection> createState() => _ResearchExpertsSectionState();
}

class _ResearchExpertsSectionState extends State<ResearchExpertsSection> {
  final Stream<DocumentSnapshot> _stream = FirebaseFirestore.instance
      .collection('app_config')
      .doc('experts')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();

        final raw = (snap.data!.data() as Map<String, dynamic>?)?['experts'];
        if (raw == null || raw is! List || raw.isEmpty) {
          return const SizedBox.shrink();
        }

        final experts = raw
            .map((e) => ResearchExpert.fromMap(e as Map<String, dynamic>))
            .where((e) => e.name.isNotEmpty)
            .toList();

        if (experts.isEmpty) return const SizedBox.shrink();

        return Container(
          // color: Colors.red,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Container(
                      // height: 28,
                      // width: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                      ),
                      child: const Icon(Icons.people_rounded,
                          size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Meet our Research Experts',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              // ── Grid ────────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = (constraints.maxWidth - 12) / 2;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: experts.map((expert) {
                        return SizedBox(
                          width: cardWidth,
                          child: _ExpertCard(expert: expert),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),

              // ── Bottom header ──────────────────────────────────────────────
              // Padding(
              //   padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              //   child: Row(
              //     children: [
              //       Container(
              //         // height: 28,
              //         // width: 28,
              //         decoration: BoxDecoration(
              //           borderRadius: BorderRadius.circular(8),
              //           gradient: const LinearGradient(
              //             colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              //           ),
              //         ),
              //         child: const Icon(Icons.people_rounded,
              //             size: 15, color: Colors.white),
              //       ),
              //       const SizedBox(width: 10),
              //       const Text(
              //         'Meet our Research Experts',
              //         style: TextStyle(
              //           fontSize: 15,
              //           fontWeight: FontWeight.w800,
              //           color: Color(0xFF111827),
              //           letterSpacing: -0.2,
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _ExpertCard extends StatelessWidget {
  final ResearchExpert expert;
  const _ExpertCard({required this.expert});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),

          // ── Avatar ──────────────────────────────────────────────────────
          Container(
            width:  72,
            height: 72,
            decoration: BoxDecoration(
              shape:  BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              ),
              border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.2),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: expert.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl:   expert.imageUrl,
                      fit:        BoxFit.cover,
                      placeholder: (_, __) => _avatarFallback(expert.name),
                      errorWidget: (_, __, ___) => _avatarFallback(expert.name),
                    )
                  : _avatarFallback(expert.name),
            ),
          ),

          const SizedBox(height: 12),

          // ── Name ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              expert.name,
              style: const TextStyle(
                fontSize:   13,
                fontWeight: FontWeight.w800,
                color:      Color(0xFF111827),
                letterSpacing: -0.2,
              ),
              textAlign:  TextAlign.center,
              maxLines:   2,
              overflow:   TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 4),

          // ── Designation ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              expert.designation,
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w500,
                color:      Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 10),

          // ── Experience badge ─────────────────────────────────────────────
          if (expert.yearsExp > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        const Color(0xFF6366F1).withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${expert.yearsExp}+ yrs experience',
                style: const TextStyle(
                  fontSize:   10,
                  fontWeight: FontWeight.w700,
                  color:      Color(0xFF6366F1),
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    return Container(
      color: const Color(0xFFEEF2FF),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize:   22,
            fontWeight: FontWeight.w800,
            color:      Color(0xFF6366F1),
          ),
        ),
      ),
    );
  }
}
