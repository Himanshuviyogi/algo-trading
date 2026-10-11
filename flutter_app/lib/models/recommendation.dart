import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class TradeStock extends Equatable {
  const TradeStock({
    required this.name,
    required this.symbol,
    this.logoUrl,
  });

  final String name;
  final String symbol;
  final String? logoUrl;

  factory TradeStock.fromMap(Map<String, dynamic> m) => TradeStock(
        name: m['name'] as String? ?? '',
        symbol: m['symbol'] as String? ?? '',
        logoUrl: m['logo_url'] as String?,
      );

  @override
  List<Object?> get props => [name, symbol, logoUrl];
}

class TradeInfo extends Equatable {
  const TradeInfo({
    required this.action,
    required this.entryPrice,
    required this.currentPrice,
    required this.rangeMin,
    required this.rangeMax,
    this.isInRange = false,
    this.exitPrice,
    this.exitDate,
    // F&O specific fields
    this.optionType,
    this.strikePrice,
    this.expiryDate,
    this.lotSize,
    this.premium,
    this.underlyingSymbol,
  });

  final String action;
  final double entryPrice;
  final double currentPrice;
  final double rangeMin;
  final double rangeMax;
  final bool isInRange;
  final double? exitPrice;
  final DateTime? exitDate;

  // F&O fields
  final String? optionType;       // 'CE' | 'PE' | null
  final double? strikePrice;      // e.g. 23500.0
  final String? expiryDate;       // e.g. "29MAY2025"
  final int? lotSize;             // e.g. 50
  final double? premium;          // option premium at entry
  final String? underlyingSymbol; // e.g. "NIFTY" for NIFTY23500CE

  bool get isFno => optionType != null || expiryDate != null;
  bool get isOption => optionType == 'CE' || optionType == 'PE';
  bool get isFuture => expiryDate != null && optionType == null;

  factory TradeInfo.fromMap(Map<String, dynamic> m) => TradeInfo(
        action: m['action'] as String? ?? 'BUY',
        entryPrice: (m['entry_price'] as num?)?.toDouble() ?? 0,
        currentPrice: (m['current_price'] as num?)?.toDouble() ?? 0,
        rangeMin: (m['range']?['min'] as num?)?.toDouble() ?? 0,
        rangeMax: (m['range']?['max'] as num?)?.toDouble() ?? 0,
        isInRange: m['is_in_range'] as bool? ?? false,
        exitPrice: (m['exit_price'] as num?)?.toDouble(),
        exitDate: m['exit_date'] is Timestamp
            ? (m['exit_date'] as Timestamp).toDate()
            : null,
        optionType:       m['option_type'] as String?,
        strikePrice:      (m['strike_price'] as num?)?.toDouble(),
        expiryDate:       m['expiry_date'] as String?,
        lotSize:          (m['lot_size'] as num?)?.toInt(),
        premium:          (m['premium'] as num?)?.toDouble(),
        underlyingSymbol: m['underlying_symbol'] as String?,
      );

  @override
  List<Object?> get props => [
        action, entryPrice, currentPrice, rangeMin, rangeMax, isInRange,
        exitPrice, exitDate, optionType, strikePrice, expiryDate, lotSize,
        premium, underlyingSymbol,
      ];
}

class TradeAnalysis extends Equatable {
  const TradeAnalysis({
    required this.target,
    this.stoploss,
    required this.duration,
  });

  final double target;
  final double? stoploss;
  final String duration;

  factory TradeAnalysis.fromMap(Map<String, dynamic> m) => TradeAnalysis(
        target: (m['target'] as num?)?.toDouble() ?? 0,
        stoploss: (m['stoploss'] as num?)?.toDouble(),
        duration: m['duration'] as String? ?? '',
      );

  @override
  List<Object?> get props => [target, stoploss, duration];
}

class TradePerformance extends Equatable {
  const TradePerformance({
    required this.gainSoFar,
    required this.potentialLeft,
  });

  final double gainSoFar;
  final double potentialLeft;

  factory TradePerformance.fromMap(Map<String, dynamic> m) => TradePerformance(
        gainSoFar: (m['gain_so_far'] as num?)?.toDouble() ?? 0,
        potentialLeft: (m['potential_left'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [gainSoFar, potentialLeft];
}

class Recommendation extends Equatable {
  const Recommendation({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.type,
    required this.status,
    required this.planIds,
    required this.postedBy,
    required this.postedAt,
    required this.isPublished,
    required this.stock,
    required this.trade,
    required this.analysis,
    required this.performance,
    required this.badge,
    this.riskRewardRatio,
    this.confidence,
    this.notes,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final String type;
  final String status;
  final List<String> planIds;
  final String postedBy;
  final DateTime postedAt;
  final bool isPublished;
  final TradeStock stock;
  final TradeInfo trade;
  final TradeAnalysis analysis;
  final TradePerformance performance;
  final String badge;
  final double? riskRewardRatio;
  final String? confidence; // low | medium | high
  final String? notes;
  final List<String> tags;

  bool get isLive => status == 'live';
  bool get isClosed =>
      status == 'hit_target' || status == 'stoploss_hit' || status == 'closed';

  factory Recommendation.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final badgeRaw = d['meta']?['badge'];
    final postedByRaw = d['meta']?['posted_by'];
    final confidenceRaw = d['confidence'];

    final notesRaw = d['notes'];


    // print("------ DOC ------");
    // print("ID: ${doc.id}");
    //
    //
    //
    // d.forEach((key, value) {
    //   print("$key → ${value.runtimeType} → $value");
    // });

    return Recommendation(
      id: doc.id,
      title: d['stock']?['name'] as String? ?? d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      category: d['category'] as String? ?? '',
      type: d['type'] as String? ?? '',
      status: d['status'] as String? ?? 'live',
      planIds: List<String>.from(d['plan_ids'] as List? ?? []),
      // postedBy: d['meta']?['posted_by'] as String? ??
      //     d['posted_by'] as String? ?? '',
      postedAt: d['posted_at'] is Timestamp
          ? (d['posted_at'] as Timestamp).toDate()
          : DateTime.now(),
      isPublished: d['is_published'] as bool? ?? false,
      stock: TradeStock.fromMap(
          (d['stock'] as Map<String, dynamic>?) ?? {}),
      trade: TradeInfo.fromMap(
          (d['trade'] as Map<String, dynamic>?) ?? {}),
      analysis: TradeAnalysis.fromMap(
          (d['analysis'] as Map<String, dynamic>?) ?? {}),
      performance: TradePerformance.fromMap(
          (d['performance'] as Map<String, dynamic>?) ?? {}),
      // badge: badgeRaw is String
      //     ? badgeRaw
      //     : badgeRaw is List
      //     ? badgeRaw.join(', ')
      //     : '',
      riskRewardRatio:
          (d['risk_reward_ratio'] as num?)?.toDouble(),
      // confidence: d['confidence'] as String?,
      // notes: d['notes'] as String?,

      notes: notesRaw is String
          ? notesRaw
          : notesRaw is List
          ? notesRaw.join(' ')
          : null,
      tags: List<String>.from(d['tags'] as List? ?? []),


      badge: badgeRaw is String
          ? badgeRaw
          : badgeRaw is List
          ? badgeRaw.join(', ')
          : '',

      postedBy: postedByRaw is String
          ? postedByRaw
          : postedByRaw is List
          ? postedByRaw.first.toString()
          : '',

      confidence: confidenceRaw is String
          ? confidenceRaw
          : confidenceRaw is List
          ? confidenceRaw.first.toString()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'category': category,
        'type': type,
        'status': status,
        'plan_ids': planIds,
        'posted_at': Timestamp.fromDate(postedAt),
        'is_published': isPublished,
        'stock': {
          'name': stock.name,
          'symbol': stock.symbol,
          'logo_url': stock.logoUrl,
        },
        'trade': {
          'action': trade.action,
          'entry_price': trade.entryPrice,
          'current_price': trade.currentPrice,
          'range': {'min': trade.rangeMin, 'max': trade.rangeMax},
          'is_in_range': trade.isInRange,
          if (trade.exitPrice != null) 'exit_price': trade.exitPrice,
          if (trade.exitDate != null)
            'exit_date': Timestamp.fromDate(trade.exitDate!),
          if (trade.optionType != null) 'option_type': trade.optionType,
          if (trade.strikePrice != null) 'strike_price': trade.strikePrice,
          if (trade.expiryDate != null) 'expiry_date': trade.expiryDate,
          if (trade.lotSize != null) 'lot_size': trade.lotSize,
          if (trade.premium != null) 'premium': trade.premium,
          if (trade.underlyingSymbol != null) 'underlying_symbol': trade.underlyingSymbol,
        },
        'analysis': {
          'target': analysis.target,
          'stoploss': analysis.stoploss,
          'duration': analysis.duration,
        },
        'performance': {
          'gain_so_far': performance.gainSoFar,
          'potential_left': performance.potentialLeft,
        },
        'meta': {
          'badge': badge,
          'posted_by': postedBy,
          'updated_at': Timestamp.now(),
        },
        if (riskRewardRatio != null) 'risk_reward_ratio': riskRewardRatio,
        if (confidence != null) 'confidence': confidence,
        if (notes != null) 'notes': notes,
        'tags': tags,
      };

  @override
  List<Object?> get props => [
        id, title, category, type, status, planIds,
        postedAt, isPublished, stock, trade, analysis, performance, badge,
        riskRewardRatio, confidence, notes, tags,
      ];
}
