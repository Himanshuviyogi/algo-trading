import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Displays a stock/instrument icon with automatic NSE logo fetch.
///
/// Priority:
/// 1. `logoUrl` from Firestore (manually set) — if present
/// 2. NSE archives logo URL for NSE equities
/// 3. Category-based icon (futures, options, commodity, forex)
/// 4. Letter avatar fallback (first 2 chars of symbol)
class StockIcon extends StatelessWidget {
  const StockIcon({
    super.key,
    required this.symbol,
    required this.category,
    this.logoUrl,
    this.size = 48,
    this.borderRadius = 12,
  });

  final String symbol;
  final String category;
  final String? logoUrl;
  final double size;
  final double borderRadius;

  /// NSE archives logo URL — works for most NSE-listed equities.
  /// Returns null for derivatives / F&O / MCX / Forex (no logo available).
  static String? _nseLogoUrl(String symbol, String category) {
    if (category == 'stocks') {
      // Strip any exchange prefix: NSE:RELIANCE → RELIANCE
      final clean = symbol.contains(':') ? symbol.split(':').last : symbol;
      return 'https://nsearchives.nseindia.com/content/equities/$clean.png';
    }
    return null;
  }

  /// Category-specific icon data and color.
  static ({IconData icon, Color color, Color bg}) _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'futures':
        return (
          icon: Icons.trending_up_rounded,
          color: const Color(0xFF7C3AED),
          bg:    const Color(0xFFEDE9FE),
        );
      case 'options':
        return (
          icon: Icons.candlestick_chart_rounded,
          color: const Color(0xFFD97706),
          bg:    const Color(0xFFFEF3C7),
        );
      case 'commodity':
        return (
          icon: Icons.local_fire_department_rounded,
          color: const Color(0xFFEA580C),
          bg:    const Color(0xFFFFF7ED),
        );
      case 'forex':
        return (
          icon: Icons.currency_exchange_rounded,
          color: const Color(0xFF0891B2),
          bg:    const Color(0xFFE0F2FE),
        );
      default: // stocks
        return (
          icon: Icons.show_chart_rounded,
          color: const Color(0xFF2563EB),
          bg:    const Color(0xFFEFF6FF),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _categoryIcon(category);

    // 1. Manual logo_url from Firestore
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return _logoImage(logoUrl!, cat);
    }

    // 2. NSE auto-fetch for equities
    final nseUrl = _nseLogoUrl(symbol, category);
    if (nseUrl != null) {
      return CachedNetworkImage(
        imageUrl: nseUrl,
        imageBuilder: (context, imageProvider) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.grey.shade100),
            image: DecorationImage(image: imageProvider, fit: BoxFit.contain),
          ),
        ),
        errorWidget: (_, __, ___) => _categoryFallback(cat),
        placeholder: (_, __) => _categoryFallback(cat),
        // Cache for 24h — logos don't change often
        cacheKey: 'nse_logo_$symbol',
      );
    }

    // 3. Category icon for derivatives / commodities / forex
    return _categoryFallback(cat);
  }

  Widget _logoImage(String url, ({IconData icon, Color color, Color bg}) cat) {
    // Handle base64 data URLs (e.g. data:image/png;base64,...)
    // CachedNetworkImage doesn't support data: URIs — decode manually.
    if (url.startsWith('data:')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex != -1) {
        try {
          final bytes = base64Decode(url.substring(commaIndex + 1));
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          );
        } catch (_) {
          return _categoryFallback(cat);
        }
      }
      return _categoryFallback(cat);
    }

    return CachedNetworkImage(
      imageUrl: url,
      imageBuilder: (context, imageProvider) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: Colors.grey.shade100),
          image: DecorationImage(image: imageProvider, fit: BoxFit.contain),
        ),
      ),
      errorWidget: (_, __, ___) => _categoryFallback(cat),
      placeholder: (_, __) => _categoryFallback(cat),
    );
  }

  Widget _categoryFallback(({IconData icon, Color color, Color bg}) cat) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cat.bg,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(cat.icon, color: cat.color, size: size * 0.5),
    );
  }
}
