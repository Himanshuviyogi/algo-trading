import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/option_chain.dart';

// ── Error types ───────────────────────────────────────────────────────────────

enum OptionChainErrorType {
  network,
  timeout,
  serverError,
  parsing,
  unknown,
}

class OptionChainException implements Exception {
  final String message;
  final OptionChainErrorType type;
  const OptionChainException(this.message, this.type);

  @override
  String toString() => 'OptionChainException: $message';
}

// ── Abstract interface ────────────────────────────────────────────────────────

abstract class OptionChainRepository {
  Future<OptionChainData> fetchChain(String symbol, {String? expiry});
}

// ── Implementation — calls NSE directly from the device ──────────────────────
//
// Uses dart:io HttpClient with a shared CookieJar so cookies are preserved
// across requests automatically. NSE blocks datacenter/VPS IPs but not
// real mobile/residential devices, so fetching from the app is reliable.

class OptionChainRepositoryImpl implements OptionChainRepository {
  OptionChainRepositoryImpl() {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent =
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36';
  }

  late final HttpClient _client;

  // dart:io HttpClient manages a cookie jar automatically per-instance,
  // but only if we read/write cookies explicitly between requests.
  final Map<String, String> _cookies = {};
  DateTime _cookieExpiry = DateTime.fromMillisecondsSinceEpoch(0);

  static const _kIndexSymbols = {
    'NIFTY', 'BANKNIFTY', 'FINNIFTY', 'MIDCPNIFTY', 'NIFTYNXT50', 'SENSEX',
  };

  static const _kUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36';

  // ── Session ───────────────────────────────────────────────────────────────

  Future<void> _ensureSession() async {
    if (_cookies.isNotEmpty && DateTime.now().isBefore(_cookieExpiry)) return;

    debugPrint('[OptionChain] Refreshing NSE session…');

    // Step 1 — homepage
    await _get(
      'https://www.nseindia.com',
      headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      },
      storeCookies: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 700));

    // Step 2 — option-chain page
    await _get(
      'https://www.nseindia.com/option-chain',
      headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Referer': 'https://www.nseindia.com',
      },
      storeCookies: true,
    );

    _cookieExpiry = DateTime.now().add(const Duration(minutes: 12));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    debugPrint('[OptionChain] Session ready. Cookies: ${_cookies.keys.join(', ')}');
  }

  /// Low-level GET using dart:io HttpClient so we get individual Set-Cookie
  /// headers (the http package merges them into one comma-joined string which
  /// is impossible to parse reliably when cookie values contain commas).
  Future<({int statusCode, String body})> _get(
    String url, {
    Map<String, String> headers = const {},
    bool storeCookies = false,
  }) async {
    final uri = Uri.parse(url);
    final req = await _client.getUrl(uri);

    req.headers
      ..set(HttpHeaders.userAgentHeader, _kUa)
      ..set('Accept-Encoding', 'gzip, deflate, br');

    for (final e in headers.entries) {
      req.headers.set(e.key, e.value);
    }

    if (_cookies.isNotEmpty) {
      req.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    }

    final resp = await req.close().timeout(const Duration(seconds: 20));

    if (storeCookies) {
      resp.headers.forEach((name, values) {
        if (name.toLowerCase() == 'set-cookie') {
          for (final v in values) {
            // Each value is one cookie directive, e.g. "nsit=abc123; Path=/"
            final kv = v.split(';').first.trim();
            final idx = kv.indexOf('=');
            if (idx > 0) {
              _cookies[kv.substring(0, idx)] = kv.substring(idx + 1);
            }
          }
        }
      });
    }

    final bytes = await resp.expand((b) => b).toList();
    final body = utf8.decode(bytes, allowMalformed: true);
    return (statusCode: resp.statusCode, body: body);
  }

  // ── Main fetch ────────────────────────────────────────────────────────────

  @override
  Future<OptionChainData> fetchChain(String symbol, {String? expiry}) async {
    try {
      await _ensureSession();

      final sym = symbol.toUpperCase().replaceAll(' ', '');
      final isIndex = _kIndexSymbols.contains(sym);
      final endpoint = isIndex
          ? 'https://www.nseindia.com/api/option-chain-indices'
          : 'https://www.nseindia.com/api/option-chain-equities';

      final uri = Uri.parse(endpoint)
          .replace(queryParameters: {'symbol': sym});

      debugPrint('[OptionChain] GET $uri');

      final result = await _get(
        uri.toString(),
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'en-US,en;q=0.5',
          'Referer': 'https://www.nseindia.com/option-chain',
          'X-Requested-With': 'XMLHttpRequest',
        },
      );

      debugPrint('[OptionChain] Response status: ${result.statusCode}');

      if (result.statusCode == 401 || result.statusCode == 404) {
        // Session expired — reset so next call refreshes
        _cookies.clear();
        _cookieExpiry = DateTime.fromMillisecondsSinceEpoch(0);
        throw OptionChainException(
          'Session expired (${result.statusCode}). Please retry.',
          OptionChainErrorType.serverError,
        );
      }

      if (result.statusCode != 200) {
        _cookies.clear();
        throw OptionChainException(
          'NSE returned ${result.statusCode}. Please retry.',
          OptionChainErrorType.serverError,
        );
      }

      dynamic body;
      try {
        body = jsonDecode(result.body);
      } on FormatException {
        // NSE sometimes returns an HTML block page
        _cookies.clear();
        throw const OptionChainException(
          'NSE returned non-JSON response. Please retry.',
          OptionChainErrorType.serverError,
        );
      }

      if (body is! Map || body['records'] == null) {
        _cookies.clear();
        throw const OptionChainException(
          'NSE response missing data. Please retry.',
          OptionChainErrorType.serverError,
        );
      }

      return _parse(body as Map<String, dynamic>, symbol, expiry);
    } on OptionChainException {
      rethrow;
    } on SocketException catch (e) {
      throw OptionChainException(
          'No network: ${e.message}', OptionChainErrorType.network);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        throw const OptionChainException(
            'Request timed out.', OptionChainErrorType.timeout);
      }
      throw OptionChainException(msg, OptionChainErrorType.unknown);
    }
  }

  // ── Parse ─────────────────────────────────────────────────────────────────

  OptionChainData _parse(
      Map<String, dynamic> raw, String symbol, String? expiry) {
    final records = (raw['filtered']?['data'] as List?) ??
        (raw['records']?['data'] as List?) ??
        [];

    final underlyingValue =
        (raw['records']?['underlyingValue'] as num?)?.toDouble() ?? 0.0;

    final allExpiries = (raw['records']?['expiryDates'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final targetExpiry =
        (expiry != null && expiry.isNotEmpty) ? expiry : allExpiries.firstOrNull;

    final filtered = targetExpiry != null
        ? records.where((r) => r['expiryDate'] == targetExpiry).toList()
        : records;

    final rowMap = <double, Map<String, dynamic>>{};
    for (final record in filtered) {
      final strike = (record['strikePrice'] as num?)?.toDouble() ?? 0;
      if (strike == 0) continue;
      rowMap.putIfAbsent(
          strike, () => {'strike': strike, 'ce': null, 'pe': null});
      if (record['CE'] != null) {
        rowMap[strike]!['ce'] = _leg(record['CE'] as Map<String, dynamic>);
      }
      if (record['PE'] != null) {
        rowMap[strike]!['pe'] = _leg(record['PE'] as Map<String, dynamic>);
      }
    }

    var rows = rowMap.values.map(OptionStrike.fromMap).toList()
      ..sort((a, b) => b.strike.compareTo(a.strike));

    // Mark ATM
    if (underlyingValue > 0 && rows.isNotEmpty) {
      int atmIdx = 0;
      double minDist = double.infinity;
      for (int i = 0; i < rows.length; i++) {
        final d = (rows[i].strike - underlyingValue).abs();
        if (d < minDist) {
          minDist = d;
          atmIdx = i;
        }
      }
      rows = [
        for (int i = 0; i < rows.length; i++)
          rows[i].copyWith(isAtm: i == atmIdx),
      ];
    }

    return OptionChainData(
      symbol: symbol.toUpperCase(),
      underlyingValue: underlyingValue,
      expiry: targetExpiry,
      allExpiries: allExpiries,
      rows: rows,
      source: 'nse',
      fetchedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> _leg(Map<String, dynamic> m) => {
        'oi':        (m['openInterest']         as num?)?.toInt()    ?? 0,
        'oiChange':  (m['changeinOpenInterest']  as num?)?.toInt()    ?? 0,
        'ltp':       (m['lastPrice']             as num?)?.toDouble() ?? 0.0,
        'ltpChange': (m['change']                as num?)?.toDouble() ?? 0.0,
        'volume':    (m['totalTradedVolume']      as num?)?.toInt()    ?? 0,
        'iv':        (m['impliedVolatility']      as num?)?.toDouble() ?? 0.0,
        'bidQty':    (m['bidQty']                as num?)?.toInt()    ?? 0,
        'askQty':    (m['askQty']                as num?)?.toInt()    ?? 0,
        'bidPrice':  (m['bidprice']              as num?)?.toDouble() ?? 0.0,
        'askPrice':  (m['askPrice']              as num?)?.toDouble() ?? 0.0,
      };
}

