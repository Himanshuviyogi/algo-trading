import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// ─────────────────────────────────────────────────────────────────────────────
// Admin Seed Screen
//
// Three sections:
//   1. Admin strategies  → algo_signals collection  (curated, plan-gated)
//   2. User templates    → algo_signals collection  (users can copy)
//   3. Temp user strategy → users/{uid}/strategies  (for dev/demo testing)
//
// All writes go straight to Firestore.
// ─────────────────────────────────────────────────────────────────────────────

// ── Admin strategy seeds ──────────────────────────────────────────────────────

const _adminStrategies = <_AdminSeed>[
  _AdminSeed(
    id:          'admin_reliance_breakout_2026',
    label:       'Reliance Industries — Resistance Breakout',
    badge:       'BREAKOUT',
    category:    'stocks',
    type:        'short_term',
    stockName:   'Reliance Industries',
    stockSymbol: 'RELIANCE',
    exchange:    'NSE',
    action:      'BUY',
    orderType:   'LIMIT',
    productType: 'CNC',
    validity:    'DAY',
    entryPrice:  2940.0,
    target:      3120.0,
    target2:     3280.0,
    stoploss:    2860.0,
    duration:    '2-3 weeks',
    confidence:  'high',
    planIds:     ['silver_algo', 'gold_algo'],
    tags:        ['breakout', 'momentum', 'technical'],
    description:
        'RELIANCE has been consolidating near ₹2940 for 3 weeks — a key '
        'horizontal resistance that held twice. A clean close above this '
        'level on volume >1.5× avg triggers the entry. T1 at ₹3120 (prev '
        'swing high), T2 at ₹3280 (ATH zone). SL below ₹2860 (pre-breakout '
        'base). R:R ≈ 2.3x at T1.',
  ),
  _AdminSeed(
    id:          'admin_nifty_fut_momentum_2026',
    label:       'NIFTY Sep Futures — Momentum Ride',
    badge:       'FUTURES',
    category:    'futures',
    type:        'intraday',
    stockName:   'NIFTY 50',
    stockSymbol: 'NIFTY',
    exchange:    'NFO',
    action:      'BUY',
    orderType:   'MARKET',
    productType: 'MIS',
    validity:    'DAY',
    entryPrice:  24680.0,
    target:      24900.0,
    target2:     0,
    stoploss:    24520.0,
    duration:    'Intraday',
    confidence:  'medium',
    planIds:     ['gold_algo'],
    lotSize:     25,
    tags:        ['momentum', 'intraday', 'technical'],
    description:
        'NIFTY has held above the 20-EMA on the 15-min chart after a '
        'morning gap-up. Entry at market after 09:30 confirmation candle '
        'close. Target at yesterday\'s high ₹24900. MIS (intraday), '
        'square-off by 3:15 PM if not hit.',
  ),
  _AdminSeed(
    id:          'admin_hdfc_bank_reversal_2026',
    label:       'HDFC Bank — Support Reversal',
    badge:       'REVERSAL',
    category:    'stocks',
    type:        'short_term',
    stockName:   'HDFC Bank',
    stockSymbol: 'HDFCBANK',
    exchange:    'NSE',
    action:      'BUY',
    orderType:   'LIMIT',
    productType: 'CNC',
    validity:    'DAY',
    entryPrice:  1680.0,
    target:      1780.0,
    target2:     1860.0,
    stoploss:    1630.0,
    duration:    '1-2 weeks',
    confidence:  'high',
    planIds:     ['silver_algo', 'gold_algo'],
    tags:        ['reversal', 'support-bounce', 'fundamental'],
    description:
        'HDFCBANK has pulled back to a strong weekly demand zone at ₹1680 '
        '(confluence of 200-DMA + prior breakout level). RSI at 42 — '
        'oversold on daily. SL below ₹1630 (demand zone invalidation). '
        'T1 ₹1780 / T2 ₹1860.',
  ),
  _AdminSeed(
    id:          'admin_gold_mcx_trend_2026',
    label:       'MCX Gold — Uptrend Continuation',
    badge:       'TREND',
    category:    'commodity',
    type:        'short_term',
    stockName:   'Gold (MCX)',
    stockSymbol: 'GOLDM',
    exchange:    'MCX',
    action:      'BUY',
    orderType:   'LIMIT',
    productType: 'NRML',
    validity:    'DAY',
    entryPrice:  72500.0,
    target:      74800.0,
    target2:     76500.0,
    stoploss:    71200.0,
    duration:    '5-7 days',
    confidence:  'high',
    planIds:     ['gold_algo'],
    tags:        ['momentum', 'sector-play', 'technical'],
    description:
        'MCX Gold broke above ₹72500 after a 2-week flag formation. Fed '
        'rate cut expectations and a weak dollar support bullish continuation. '
        'Target ₹74800 (measured move) then ₹76500 (all-time high extension). '
        'SL at ₹71200 below flag low.',
  ),
  _AdminSeed(
    id:          'admin_tcs_btst_2026',
    label:       'TCS — BTST Gap-Up Setup',
    badge:       'BTST',
    category:    'stocks',
    type:        'short_term',
    stockName:   'Tata Consultancy Services',
    stockSymbol: 'TCS',
    exchange:    'NSE',
    action:      'BUY',
    orderType:   'LIMIT',
    productType: 'CNC',
    validity:    'DAY',
    entryPrice:  4180.0,
    target:      4310.0,
    target2:     0,
    stoploss:    4100.0,
    duration:    '1-2 days',
    confidence:  'medium',
    planIds:     ['silver_algo', 'gold_algo'],
    tags:        ['BTST', 'gap-up', 'earnings-play'],
    description:
        'TCS reported strong Q2 results after market hours. Entry on '
        'tomorrow\'s open near ₹4180 (pre-open session range). Expected '
        'gap-up opens — ride intraday momentum with overnight position. '
        'SL at ₹4100 (results gap fill invalidation).',
  ),
  _AdminSeed(
    id:          'admin_banknifty_ce_2026',
    label:       'BANKNIFTY Weekly 50500 CE',
    badge:       'OPTIONS',
    category:    'options',
    type:        'short_term',
    stockName:   'Bank Nifty',
    stockSymbol: 'BANKNIFTY',
    exchange:    'NFO',
    action:      'BUY',
    orderType:   'LIMIT',
    productType: 'NRML',
    validity:    'DAY',
    entryPrice:  240.0,
    target:      420.0,
    target2:     600.0,
    stoploss:    120.0,
    duration:    '3-4 days',
    confidence:  'medium',
    planIds:     ['gold_algo'],
    lotSize:     15,
    optionType:  'CE',
    strikePrice: 50500.0,
    expiryDate:  'WEEKLY',
    tags:        ['breakout', 'momentum', 'technical'],
    description:
        'BANKNIFTY weekly CE 50500 — bullish breakout trade above '
        '50300 key resistance. Entry on LTP ₹240 with defined risk at ₹120 '
        '(50% premium loss SL). Target ₹420 at 75% gain, final target ₹600 '
        'if BANKNIFTY sustains above 50500.',
  ),
];

// ── User strategy templates ───────────────────────────────────────────────────

const _userTemplates = <_AdminSeed>[
  _AdminSeed(
    id:          'user_tpl_ema_crossover_2026',
    label:       'EMA 9/21 Crossover — Swing Template',
    badge:       'TEMPLATE',
    category:    'stocks',
    type:        'short_term',
    stockName:   'Your Stock',
    stockSymbol: 'SYMBOL',
    exchange:    'NSE',
    action:      'BUY',
    orderType:   'LIMIT',
    productType: 'CNC',
    validity:    'DAY',
    entryPrice:  0,
    target:      0,
    target2:     0,
    stoploss:    0,
    duration:    '1-2 weeks',
    confidence:  'medium',
    planIds:     ['silver_algo'],
    tags:        ['EMA-crossover', 'momentum', 'technical'],
    description:
        'Enter when 9-EMA crosses above 21-EMA on daily chart with RSI > 55. '
        'Set entry near crossover candle close, SL below 21-EMA, T1 at '
        'nearest resistance level. Replace SYMBOL with your chosen stock.',
  ),
  _AdminSeed(
    id:          'user_tpl_intraday_vwap_2026',
    label:       'Intraday VWAP Mean Reversion',
    badge:       'INTRADAY',
    category:    'stocks',
    type:        'intraday',
    stockName:   'Your Stock',
    stockSymbol: 'SYMBOL',
    exchange:    'NSE',
    action:      'BUY',
    orderType:   'MARKET',
    productType: 'MIS',
    validity:    'DAY',
    entryPrice:  0,
    target:      0,
    target2:     0,
    stoploss:    0,
    duration:    'Intraday',
    confidence:  'medium',
    planIds:     ['silver_algo'],
    tags:        ['intraday', 'momentum', 'technical'],
    description:
        'Enter long when stock dips 0.3% below VWAP and shows a reversal '
        'candle on 5-min chart. SL 0.5% below VWAP. Target VWAP + 0.6% '
        '(R:R 1.2x). MIS product — auto square-off at 3:20.',
  ),
  _AdminSeed(
    id:          'user_tpl_positional_breakout_2026',
    label:       'Volume Breakout — Positional Template',
    badge:       'POSITIONAL',
    category:    'stocks',
    type:        'medium_term',
    stockName:   'Your Stock',
    stockSymbol: 'SYMBOL',
    exchange:    'NSE',
    action:      'BUY',
    orderType:   'LIMIT',
    productType: 'CNC',
    validity:    'DAY',
    entryPrice:  0,
    target:      0,
    target2:     0,
    stoploss:    0,
    duration:    '4-8 weeks',
    confidence:  'high',
    planIds:     ['silver_algo'],
    tags:        ['breakout', 'momentum', 'fundamental'],
    description:
        'Enter on a weekly-chart breakout above multi-year resistance with '
        'volume > 2× avg. SL below breakout candle low. T1 at 10% gain, '
        'T2 at 20%. Trail SL to breakout level after T1 hit.',
  ),
];

// ── Temp user strategy seed ───────────────────────────────────────────────────
// Written to users/{uid}/strategies for dev/demo testing.
// Structure mirrors _buildDoc() in create_strategy_screen.dart exactly.

const _tempUserStrategies = <_TempUserSeed>[

  // ══════════════════════════════════════════════════════════════════════
  // OPTIONS strategies (6) — mirror the 6 template presets
  // ══════════════════════════════════════════════════════════════════════

  // 1. Bull Call Spread — NIFTY
  _TempUserSeed(
    id:              'seed_usr_bull_call_spread_nifty',
    label:           'NIFTY Bull Call Spread',
    strategyType:    'options',
    market:          'NSE F&O',
    category:        'options',
    type:            'options_strategy',
    stockName:       'NIFTY',
    stockSymbol:     'NIFTY',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'MARKET',
    productType:     'NRML',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      0,
    slPct:           50.0,
    targetPct:       100.0,
    expiry:          'Current Week',
    timeframe:       '15m',
    strategyStyle:   'Spread',
    lots:            1,
    lotSize:         50,
    confidence:      'high',
    tags:            ['bull-call-spread', 'spread', 'technical'],
    description:     'Buy ATM Call + Sell OTM Call (ATM+2). Capped profit & capped risk. RSI > 50 entry.',
    entryConds: [
      {'indicator': 'RSI', 'operator': '>', 'value_a': '50', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '20', 'param_b': '50', 'logic': 'AND'},
    ],
    legs: [
      {'side': 'Buy',  'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': 0,  'delta': 0.50, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Sell', 'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': 2,  'delta': 0.30, 'use_setup_expiry': true, 'expiry': 'Current Week'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 2. Bear Put Spread — BANKNIFTY
  _TempUserSeed(
    id:              'seed_usr_bear_put_spread_banknifty',
    label:           'BANKNIFTY Bear Put Spread',
    strategyType:    'options',
    market:          'NSE F&O',
    category:        'options',
    type:            'options_strategy',
    stockName:       'BANKNIFTY',
    stockSymbol:     'BANKNIFTY',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'MARKET',
    productType:     'NRML',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      0,
    slPct:           50.0,
    targetPct:       100.0,
    expiry:          'Current Week',
    timeframe:       '15m',
    strategyStyle:   'Spread',
    lots:            1,
    lotSize:         15,
    confidence:      'high',
    tags:            ['bear-put-spread', 'spread', 'bearish'],
    description:     'Buy ATM Put + Sell OTM Put (ATM-2). Bearish with capped risk. RSI < 45 entry.',
    entryConds: [
      {'indicator': 'RSI', 'operator': '<', 'value_a': '45', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'EMA', 'operator': '<', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '20', 'param_b': '50', 'logic': 'AND'},
    ],
    legs: [
      {'side': 'Buy',  'option_type': 'Put', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': 0,  'delta': 0.50, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Sell', 'option_type': 'Put', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': -2, 'delta': 0.30, 'use_setup_expiry': true, 'expiry': 'Current Week'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 3. Straddle — NIFTY
  _TempUserSeed(
    id:              'seed_usr_straddle_nifty',
    label:           'NIFTY ATM Straddle',
    strategyType:    'options',
    market:          'NSE F&O',
    category:        'options',
    type:            'options_strategy',
    stockName:       'NIFTY',
    stockSymbol:     'NIFTY',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'MARKET',
    productType:     'NRML',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      0,
    slPct:           40.0,
    targetPct:       80.0,
    expiry:          'Current Week',
    timeframe:       '15m',
    strategyStyle:   'Buying',
    lots:            1,
    lotSize:         50,
    confidence:      'medium',
    tags:            ['straddle', 'volatility', 'event-play'],
    description:     'Buy ATM Call + Buy ATM Put. Profits from large moves in either direction. Enter when IV 40–70.',
    entryConds: [
      {'indicator': 'IV / IV Rank', 'operator': '>', 'value_a': '40', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'IV / IV Rank', 'operator': '<', 'value_a': '70', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '', 'param_b': '', 'logic': 'AND'},
    ],
    legs: [
      {'side': 'Buy', 'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': 0, 'delta': 0.50, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Buy', 'option_type': 'Put',  'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': 0, 'delta': 0.50, 'use_setup_expiry': true, 'expiry': 'Current Week'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 4. Strangle — BANKNIFTY
  _TempUserSeed(
    id:              'seed_usr_strangle_banknifty',
    label:           'BANKNIFTY OTM Strangle',
    strategyType:    'options',
    market:          'NSE F&O',
    category:        'options',
    type:            'options_strategy',
    stockName:       'BANKNIFTY',
    stockSymbol:     'BANKNIFTY',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'MARKET',
    productType:     'NRML',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      0,
    slPct:           50.0,
    targetPct:       100.0,
    expiry:          'Current Week',
    timeframe:       '15m',
    strategyStyle:   'Buying',
    lots:            1,
    lotSize:         15,
    confidence:      'medium',
    tags:            ['strangle', 'volatility', 'technical'],
    description:     'Buy OTM Call (+2) + Buy OTM Put (-2). Cheaper than straddle; needs a bigger move. IV 35–65.',
    entryConds: [
      {'indicator': 'IV / IV Rank', 'operator': '>', 'value_a': '35', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'IV / IV Rank', 'operator': '<', 'value_a': '65', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '', 'param_b': '', 'logic': 'AND'},
    ],
    legs: [
      {'side': 'Buy', 'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n':  2, 'delta': 0.30, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Buy', 'option_type': 'Put',  'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': -2, 'delta': 0.30, 'use_setup_expiry': true, 'expiry': 'Current Week'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 5. Iron Condor — NIFTY
  _TempUserSeed(
    id:              'seed_usr_iron_condor_nifty',
    label:           'NIFTY Iron Condor',
    strategyType:    'options',
    market:          'NSE F&O',
    category:        'options',
    type:            'options_strategy',
    stockName:       'NIFTY',
    stockSymbol:     'NIFTY',
    exchange:        'NSE',
    action:          'SELL',
    orderType:       'MARKET',
    productType:     'NRML',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      0,
    slPct:           100.0,
    targetPct:       50.0,
    expiry:          'Current Week',
    timeframe:       '1H',
    strategyStyle:   'Selling',
    lots:            1,
    lotSize:         50,
    confidence:      'high',
    tags:            ['iron-condor', 'selling', 'sideways'],
    description:     'Sell OTM strangle + buy further OTM wings. Profits in low-volatility sideways market. IV > 50.',
    entryConds: [
      {'indicator': 'IV / IV Rank', 'operator': '>', 'value_a': '50', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '', 'param_b': '', 'logic': 'AND'},
    ],
    legs: [
      {'side': 'Buy',  'option_type': 'Put',  'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': -4, 'delta': 0.10, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Sell', 'option_type': 'Put',  'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': -2, 'delta': 0.20, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Sell', 'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n':  2, 'delta': 0.20, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Buy',  'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n':  4, 'delta': 0.10, 'use_setup_expiry': true, 'expiry': 'Current Week'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 6. Covered Call — NIFTY
  _TempUserSeed(
    id:              'seed_usr_covered_call_nifty',
    label:           'NIFTY Covered Call',
    strategyType:    'options',
    market:          'NSE F&O',
    category:        'options',
    type:            'options_strategy',
    stockName:       'NIFTY',
    stockSymbol:     'NIFTY',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'MARKET',
    productType:     'NRML',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      0,
    slPct:           30.0,
    targetPct:       60.0,
    expiry:          'Current Week',
    timeframe:       '1D',
    strategyStyle:   'Hedged',
    lots:            1,
    lotSize:         50,
    confidence:      'high',
    tags:            ['covered-call', 'hedged', 'income'],
    description:     'Long deep ITM call (≈underlying) + Sell OTM call. Income strategy in a confirmed uptrend.',
    entryConds: [
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '20', 'param_b': '50', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '<', 'value_a': '65', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    legs: [
      {'side': 'Buy',  'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n': -6, 'delta': 0.90, 'use_setup_expiry': true, 'expiry': 'Current Week'},
      {'side': 'Sell', 'option_type': 'Call', 'quantity': 1, 'strike_mode': 'ATM+N', 'strike_n':  2, 'delta': 0.30, 'use_setup_expiry': true, 'expiry': 'Current Week'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // ══════════════════════════════════════════════════════════════════════
  // STOCKS strategies (14) — various indicators + styles
  // ══════════════════════════════════════════════════════════════════════

  // 7. EMA Crossover Swing — RELIANCE
  _TempUserSeed(
    id:              'seed_usr_reliance_ema_cross_swing',
    label:           'RELIANCE EMA 20/50 Swing Long',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Reliance Industries',
    stockSymbol:     'RELIANCE',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       2940.0,
    entryPrice:      2940.0,
    slPct:           3.0,
    targetPct:       6.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          10,
    confidence:      'high',
    tags:            ['ema-crossover', 'swing', 'momentum'],
    description:     'Buy when RELIANCE LTP crosses above ₹2940 with EMA(20) > EMA(50) and RSI > 55.',
    entryConds: [
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '20', 'param_b': '50', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '>', 'value_a': '55', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      true,
    trailingSLMode:  'pct',
    trailingSLValue: 1.5,
    autoExecute:     true,
  ),

  // 8. VWAP Mean Reversion Intraday — HDFCBANK
  _TempUserSeed(
    id:              'seed_usr_hdfcbank_vwap_intraday',
    label:           'HDFCBANK VWAP Mean Reversion',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'HDFC Bank',
    stockSymbol:     'HDFCBANK',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'MARKET',
    productType:     'MIS',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      1680.0,
    slPct:           0.5,
    targetPct:       1.0,
    timeframe:       '5m',
    strategyStyle:   'Long',
    shares:          20,
    confidence:      'medium',
    tags:            ['vwap', 'intraday', 'mean-reversion'],
    description:     'Enter long when HDFCBANK dips 0.3% below VWAP with reversal candle on 5m. SL below VWAP.',
    entryConds: [
      {'indicator': 'VWAP', 'operator': '<', 'value_a': '', 'value_b': '', 'rhs_is_indicator': true, 'param_a': '', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'RSI',  'operator': '>', 'value_a': '45', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '9', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 9. RSI Oversold Reversal — ICICIBANK
  _TempUserSeed(
    id:              'seed_usr_icicibank_rsi_reversal',
    label:           'ICICIBANK RSI Oversold Reversal',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'ICICI Bank',
    stockSymbol:     'ICICIBANK',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       1200.0,
    entryPrice:      1200.0,
    slPct:           2.5,
    targetPct:       5.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          25,
    confidence:      'high',
    tags:            ['rsi', 'reversal', 'support-bounce'],
    description:     'RSI(14) < 35 on daily chart at strong support. Enter above ₹1200 on reversal confirmation.',
    entryConds: [
      {'indicator': 'RSI', 'operator': '<', 'value_a': '35', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '200', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 10. Momentum Breakout — INFOSYS
  _TempUserSeed(
    id:              'seed_usr_infy_volume_breakout',
    label:           'INFOSYS Volume Breakout Long',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Infosys',
    stockSymbol:     'INFY',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       1850.0,
    entryPrice:      1850.0,
    slPct:           2.0,
    targetPct:       7.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          15,
    confidence:      'high',
    tags:            ['breakout', 'momentum', 'volume'],
    description:     'Buy INFY on breakout above ₹1850 resistance with EMA(20) > EMA(50) and RSI > 60.',
    entryConds: [
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '20', 'param_b': '50', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '>', 'value_a': '60', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      true,
    trailingSLMode:  'pct',
    trailingSLValue: 1.5,
    autoExecute:     true,
  ),

  // 11. MACD Crossover — TCS
  _TempUserSeed(
    id:              'seed_usr_tcs_macd_swing',
    label:           'TCS MACD Crossover Swing',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Tata Consultancy Services',
    stockSymbol:     'TCS',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       4200.0,
    entryPrice:      4200.0,
    slPct:           2.5,
    targetPct:       8.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          5,
    confidence:      'medium',
    tags:            ['macd', 'swing', 'momentum'],
    description:     'MACD line crosses above signal line on daily chart. RSI between 50–70. Entry above ₹4200.',
    entryConds: [
      {'indicator': 'MACD', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': true, 'param_a': '12', 'param_b': '26', 'logic': 'AND'},
      {'indicator': 'RSI',  'operator': '>', 'value_a': '50', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 12. Bollinger Band Squeeze Breakout — WIPRO
  _TempUserSeed(
    id:              'seed_usr_wipro_bb_breakout',
    label:           'WIPRO Bollinger Band Breakout',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Wipro',
    stockSymbol:     'WIPRO',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       560.0,
    entryPrice:      560.0,
    slPct:           2.0,
    targetPct:       6.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          50,
    confidence:      'medium',
    tags:            ['bollinger-band', 'breakout', 'volatility'],
    description:     'Enter when WIPRO breaks above upper Bollinger Band with volume surge. RSI > 55 confirmation.',
    entryConds: [
      {'indicator': 'Bollinger Bands', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': true, 'param_a': '20', 'param_b': '2', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '>', 'value_a': '55', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      true,
    trailingSLMode:  'pct',
    trailingSLValue: 1.5,
    autoExecute:     true,
  ),

  // 13. Supertrend Long — BAJFINANCE
  _TempUserSeed(
    id:              'seed_usr_bajfinance_supertrend',
    label:           'BAJFINANCE Supertrend Momentum',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Bajaj Finance',
    stockSymbol:     'BAJFINANCE',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'MARKET',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'at_market',
    condPrice:       0,
    entryPrice:      7100.0,
    slPct:           2.0,
    targetPct:       5.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          5,
    confidence:      'high',
    tags:            ['supertrend', 'momentum', 'technical'],
    description:     'Supertrend flips bullish on daily chart. EMA(20) > EMA(50). Enter at market on signal candle close.',
    entryConds: [
      {'indicator': 'Supertrend', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': true, 'param_a': '7', 'param_b': '3', 'logic': 'AND'},
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '20', 'param_b': '50', 'logic': 'AND'},
    ],
    trailingSL:      true,
    trailingSLMode:  'pct',
    trailingSLValue: 2.0,
    autoExecute:     true,
  ),

  // 14. Short Sell RSI Overbought — AXISBANK
  _TempUserSeed(
    id:              'seed_usr_axisbank_rsi_short',
    label:           'AXISBANK RSI Overbought Short',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Axis Bank',
    stockSymbol:     'AXISBANK',
    exchange:        'NSE',
    action:          'SELL',
    orderType:       'LIMIT',
    productType:     'MIS',
    validity:        'DAY',
    condType:        'below',
    condPrice:       1150.0,
    entryPrice:      1150.0,
    slPct:           2.0,
    targetPct:       4.0,
    timeframe:       '15m',
    strategyStyle:   'Short',
    shares:          30,
    confidence:      'medium',
    tags:            ['rsi', 'overbought', 'short', 'intraday'],
    description:     'Short AXISBANK when RSI > 75 and price breaks below ₹1150 support. Intraday MIS.',
    entryConds: [
      {'indicator': 'RSI', 'operator': '>', 'value_a': '75', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'EMA', 'operator': '<', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '9',  'param_b': '21', 'logic': 'AND'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 15. Opening Range Breakout — SBIN
  _TempUserSeed(
    id:              'seed_usr_sbin_orb_intraday',
    label:           'SBIN Opening Range Breakout',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'State Bank of India',
    stockSymbol:     'SBIN',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'MIS',
    validity:        'DAY',
    condType:        'above',
    condPrice:       840.0,
    entryPrice:      840.0,
    slPct:           0.8,
    targetPct:       1.6,
    timeframe:       '15m',
    strategyStyle:   'Long',
    shares:          50,
    confidence:      'medium',
    tags:            ['orb', 'intraday', 'breakout'],
    description:     'Buy when SBIN breaks above first 15-min candle high (ORB) with EMA(9) > EMA(21). Intraday MIS.',
    entryConds: [
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '9', 'param_b': '21', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '>', 'value_a': '55', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 16. Positional Delivery — MARUTI
  _TempUserSeed(
    id:              'seed_usr_maruti_positional_delivery',
    label:           'MARUTI Positional Delivery',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Maruti Suzuki',
    stockSymbol:     'MARUTI',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       12500.0,
    entryPrice:      12500.0,
    slPct:           3.5,
    targetPct:       10.0,
    timeframe:       '1W',
    strategyStyle:   'Long',
    shares:          3,
    confidence:      'high',
    tags:            ['positional', 'delivery', 'weekly'],
    description:     'Buy MARUTI on weekly breakout above ₹12500. EMA(20) > EMA(50) on weekly. Hold 4–6 weeks.',
    entryConds: [
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '20', 'param_b': '50', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '>', 'value_a': '55', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      true,
    trailingSLMode:  'pct',
    trailingSLValue: 3.0,
    autoExecute:     true,
  ),

  // 17. EMA + RSI Dual Confirmation — TATAMOTORS
  _TempUserSeed(
    id:              'seed_usr_tatamotors_ema_rsi',
    label:           'TATAMOTORS EMA + RSI Long',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Tata Motors',
    stockSymbol:     'TATAMOTORS',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       880.0,
    entryPrice:      880.0,
    slPct:           3.0,
    targetPct:       9.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          30,
    confidence:      'high',
    tags:            ['ema', 'rsi', 'swing', 'auto'],
    description:     'Buy TATAMOTORS when 9-EMA crosses above 21-EMA on daily with RSI > 55. Swing 1–2 weeks.',
    entryConds: [
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '9',  'param_b': '21', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '>', 'value_a': '55', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      true,
    trailingSLMode:  'pct',
    trailingSLValue: 2.0,
    autoExecute:     true,
  ),

  // 18. Stochastic Oversold Bounce — SUNPHARMA
  _TempUserSeed(
    id:              'seed_usr_sunpharma_stoch_bounce',
    label:           'SUNPHARMA Stochastic Oversold Bounce',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Sun Pharmaceutical',
    stockSymbol:     'SUNPHARMA',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       1700.0,
    entryPrice:      1700.0,
    slPct:           2.5,
    targetPct:       6.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          15,
    confidence:      'medium',
    tags:            ['stochastic', 'oversold', 'reversal'],
    description:     'Stochastic %K < 20 (oversold) on daily, then crosses above %D. RSI < 40. Enter at ₹1700 bounce.',
    entryConds: [
      {'indicator': 'RSI', 'operator': '<', 'value_a': '40', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '200', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 19. Intraday Short — ULTRACEMCO
  _TempUserSeed(
    id:              'seed_usr_ultracemco_short_intraday',
    label:           'ULTRACEMCO Intraday Short Breakdown',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'UltraTech Cement',
    stockSymbol:     'ULTRACEMCO',
    exchange:        'NSE',
    action:          'SELL',
    orderType:       'LIMIT',
    productType:     'MIS',
    validity:        'DAY',
    condType:        'below',
    condPrice:       10800.0,
    entryPrice:      10800.0,
    slPct:           1.0,
    targetPct:       2.5,
    timeframe:       '15m',
    strategyStyle:   'Short',
    shares:          3,
    confidence:      'medium',
    tags:            ['short', 'breakdown', 'intraday'],
    description:     'Short ULTRACEMCO on breakdown below ₹10800 support. EMA(9) < EMA(21) on 15m. MIS intraday.',
    entryConds: [
      {'indicator': 'EMA', 'operator': '<', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '9',  'param_b': '21', 'logic': 'AND'},
      {'indicator': 'RSI', 'operator': '<', 'value_a': '45', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      false,
    autoExecute:     true,
  ),

  // 20. 200 DMA Positional Long — HINDUNILVR
  _TempUserSeed(
    id:              'seed_usr_hindunilvr_200dma_long',
    label:           'HINDUNILVR 200-DMA Bounce Long',
    strategyType:    'stocks',
    market:          'NSE Equity',
    category:        'stocks',
    type:            'stocks_strategy',
    stockName:       'Hindustan Unilever',
    stockSymbol:     'HINDUNILVR',
    exchange:        'NSE',
    action:          'BUY',
    orderType:       'LIMIT',
    productType:     'CNC',
    validity:        'DAY',
    condType:        'above',
    condPrice:       2650.0,
    entryPrice:      2650.0,
    slPct:           3.0,
    targetPct:       8.0,
    timeframe:       '1D',
    strategyStyle:   'Long',
    shares:          10,
    confidence:      'high',
    tags:            ['200dma', 'positional', 'delivery', 'FMCG'],
    description:     'Buy HINDUNILVR at 200-DMA bounce with price above EMA(200). RSI < 45 confirms oversold dip.',
    entryConds: [
      {'indicator': 'RSI', 'operator': '<', 'value_a': '45', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '14', 'param_b': '', 'logic': 'AND'},
      {'indicator': 'EMA', 'operator': '>', 'value_a': '', 'value_b': '', 'rhs_is_indicator': false, 'param_a': '200', 'param_b': '', 'logic': 'AND'},
    ],
    trailingSL:      true,
    trailingSLMode:  'pct',
    trailingSLValue: 2.5,
    autoExecute:     true,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _AdminSeed {
  const _AdminSeed({
    required this.id,
    required this.label,
    required this.badge,
    required this.category,
    required this.type,
    required this.stockName,
    required this.stockSymbol,
    required this.exchange,
    required this.action,
    required this.orderType,
    required this.productType,
    required this.validity,
    required this.entryPrice,
    required this.target,
    required this.target2,
    required this.stoploss,
    required this.duration,
    required this.confidence,
    required this.planIds,
    required this.tags,
    required this.description,
    this.lotSize,
    this.optionType,
    this.strikePrice,
    this.expiryDate,
  });

  final String id;
  final String label;
  final String badge;
  final String category;
  final String type;
  final String stockName;
  final String stockSymbol;
  final String exchange;
  final String action;
  final String orderType;    // LIMIT | MARKET | SL | SL-M
  final String productType;  // CNC | MIS | NRML
  final String validity;     // DAY | IOC | GTC
  final double entryPrice;
  final double target;
  final double target2;
  final double stoploss;
  final String duration;
  final String confidence;
  final List<String> planIds;
  final List<String> tags;
  final String description;
  final int?    lotSize;
  final String? optionType;
  final double? strikePrice;
  final String? expiryDate;

  String get _badge => badge;

  Map<String, dynamic> toFirestore({required bool isPublished}) => {
        'category':    category,
        'type':        type,
        'status':      'live',
        'plan_ids':    planIds,
        'is_published': isPublished,
        'source':      'admin',
        'auto_execute': false,
        'posted_at':   FieldValue.serverTimestamp(),
        'body':        description,
        'notes':       description,
        'tags':        tags,
        'confidence':  confidence,
        'stock': {
          'name':     stockName,
          'symbol':   stockSymbol,
          'exchange': exchange,
          'logo_url': null,
        },
        'trade': {
          'action':        action,
          'entry_price':   entryPrice,
          'current_price': entryPrice,
          'order_type':    orderType,
          'product_type':  productType,
          'validity':      validity,
          'range': {'min': entryPrice * 0.995, 'max': entryPrice * 1.005},
          'is_in_range': false,
          if (lotSize    != null) 'lot_size':          lotSize,
          if (optionType != null) 'option_type':       optionType,
          if (strikePrice != null) 'strike_price':     strikePrice,
          if (expiryDate != null && expiryDate!.isNotEmpty) 'expiry_date': expiryDate,
        },
        'analysis': {
          'target':   target,
          'target2':  target2 > 0 ? target2 : null,
          'stoploss': stoploss,
          'duration': duration,
        },
        'execution_mode':       'immediate',
        'entry_condition_type': null,
        'bracket_order':        false,
        'trailing_sl_enabled':  false,
        'product_type':         productType,
        'validity':             validity,
        'valid_till':           null,
        'performance': {
          'gain_so_far':    0.0,
          'potential_left': (entryPrice > 0 && target > 0)
              ? ((target - entryPrice) / entryPrice * 100).clamp(0.0, 500.0)
              : 0.0,
        },
        'meta': {
          'badge':      _badge,
          'posted_by':  'Admin',
          'updated_at': FieldValue.serverTimestamp(),
        },
        'seed_id': id,
      };
}

class _TempUserSeed {
  const _TempUserSeed({
    required this.id,
    required this.label,
    // ── strategy wizard fields (mirrors _buildDoc) ────────────────────────
    required this.strategyType,    // 'options' | 'stocks'
    required this.market,          // e.g. 'NSE F&O' | 'NSE Equity'
    required this.category,        // 'options' | 'stocks' | 'futures'
    required this.type,            // 'options_strategy' | 'stocks_strategy'
    required this.stockName,
    required this.stockSymbol,
    required this.exchange,
    required this.action,          // 'BUY' | 'SELL'
    required this.orderType,       // 'MARKET' | 'LIMIT'
    required this.productType,     // 'NRML' | 'MIS' | 'CNC'
    required this.validity,        // 'DAY'
    required this.condType,        // 'above' | 'below' | 'at_market' | null
    required this.condPrice,
    required this.entryPrice,
    required this.slPct,
    required this.targetPct,
    required this.confidence,
    required this.tags,
    required this.description,
    required this.entryConds,
    required this.trailingSL,
    required this.autoExecute,
    // options-specific
    this.expiry,
    this.lotSize   = 50,
    this.lots      = 1,
    this.legs      = const [],
    this.strategyStyle = 'Long',
    // stocks-specific
    this.shares    = 10,
    this.timeframe = '1D',
    // trailing SL
    this.trailingSLMode  = 'pct',
    this.trailingSLValue = 0.0,
  });

  final String  id;
  final String  label;
  final String  strategyType;
  final String  market;
  final String  category;
  final String  type;
  final String  stockName;
  final String  stockSymbol;
  final String  exchange;
  final String  action;
  final String  orderType;
  final String  productType;
  final String  validity;
  final String? condType;
  final double  condPrice;
  final double  entryPrice;
  final double  slPct;
  final double  targetPct;
  final String  confidence;
  final List<String>             tags;
  final String                   description;
  final List<Map<String, dynamic>> entryConds;
  final bool    trailingSL;
  final bool    autoExecute;
  // options
  final String? expiry;
  final int     lotSize;
  final int     lots;
  final List<Map<String, dynamic>> legs;
  final String  strategyStyle;
  // stocks
  final int     shares;
  final String  timeframe;
  // trailing
  final String  trailingSLMode;
  final double  trailingSLValue;

  bool get _isOpt => strategyType == 'options';

  // Compute ₹ SL / target from entry price + % values (mirrors _buildDoc)
  double get _slAbs     => entryPrice > 0 ? entryPrice * (1 - slPct / 100)    : 0;
  double get _targetAbs => entryPrice > 0 ? entryPrice * (1 + targetPct / 100) : 0;

  Map<String, dynamic> toFirestore(String uid) => {
        // ── top-level strategy wizard fields ────────────────────────────────
        'name':             label,
        'strategy_type':    strategyType,
        'market':           market,
        'instrument_type':  _isOpt ? 'Index Options' : 'Stocks',
        'underlying':       stockSymbol,
        'stock_name':       _isOpt ? '' : stockName,

        // ── stock map (read by engine + StrategyCard) ────────────────────────
        'stock': {
          'symbol':   stockSymbol,
          'name':     stockName,
          'exchange': exchange,
          'logo_url': null,
        },

        // ── trade map (read by engine + StrategyCard) ────────────────────────
        'trade': {
          'action':       action,
          'entry_price':  entryPrice,
          'order_type':   orderType,
          if (_isOpt) 'expiry': expiry ?? 'Current Week',
          if (!_isOpt) 'product_type': productType,
        },

        // ── analysis map (read by position monitor) ──────────────────────────
        'analysis': {
          if (_targetAbs > 0) 'target':   _targetAbs,
          if (_slAbs     > 0) 'stoploss': _slAbs,
          'duration': timeframe,
        },

        // ── engine entry condition ───────────────────────────────────────────
        'entry_condition_type':  condType ?? 'at_market',
        if (condPrice > 0) 'entry_condition_price': condPrice,
        'auto_execute': autoExecute,

        // ── position sizing ──────────────────────────────────────────────────
        'position_sizing':   _isOpt ? 'Fixed Lots' : 'Fixed Shares',
        if (_isOpt)  'lots':    lots,
        if (!_isOpt) 'shares':  shares,
        if (_isOpt)  'lot_size': lotSize,

        // ── order config ─────────────────────────────────────────────────────
        'order_type':   orderType,
        'product_type': productType,
        'validity':     validity,

        // ── trailing SL ──────────────────────────────────────────────────────
        'trailing_sl_enabled': trailingSL,
        'trailing_sl_mode':    trailingSL ? trailingSLMode : 'pct',
        'trailing_sl_value':   trailingSL ? trailingSLValue : 0,

        // ── risk / exit fields ───────────────────────────────────────────────
        if (_isOpt) 'expiry': expiry ?? 'Current Week',
        'strategy_style':    strategyStyle,
        'timeframe':         timeframe,
        'sl_pct':            slPct,
        'target_pct':        targetPct,
        'max_loss':          null,
        'locked_profit_at':  null,
        'locked_profit_min': null,
        'paper_trade':       false,
        'time_exit':         'Square off at 3:15 PM',
        'start_time':        '09:20 AM',
        'end_time':          '03:00 PM',
        'trading_days':      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        're_entry':          false,
        're_entry_mode':     'Time-based',
        're_entry_wait_min': 30,
        'backtest_range':    '3 Months',
        if (_isOpt) 'opt_underlying_type': 'Cash',

        // ── conditions ───────────────────────────────────────────────────────
        'entry_conditions':  entryConds,
        'exit_conditions':   [],
        'filter_conditions': [],
        'advanced_options':  _isOpt
            ? ['Open Interest (OI)', 'Put Call Ratio (PCR)', 'IV / IV Rank']
            : [],
        if (_isOpt)  'legs':       legs,
        if (!_isOpt) 'stock_side': action == 'BUY' ? 'Buy' : 'Sell',

        // ── metadata ─────────────────────────────────────────────────────────
        'created_at': FieldValue.serverTimestamp(),
        'user_id':    uid,
        'source':     'user',
        'status':     (condType != null && condType != 'at_market')
            ? 'watching'
            : 'active',
        'category':   category,
        'type':       type,
        'confidence': confidence,
        'tags':       List<String>.from(tags),
        'body':       description,
        'notes':      description,
        // runtime fields written by engine
        'entry_order_id':  null,
        'entry_ltp':       null,
        'entered_at':      null,
        'exit_order_id':   null,
        'exit_ltp':        null,
        'exited_at':       null,
        'realised_pnl_rs':  null,
        'realised_pnl_pct': null,
        'seed_id': id,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class AdminSeedScreen extends StatefulWidget {
  const AdminSeedScreen({super.key});

  @override
  State<AdminSeedScreen> createState() => _AdminSeedScreenState();
}

class _AdminSeedScreenState extends State<AdminSeedScreen> {
  final Map<String, bool?> _seeding   = {};
  final Set<String>        _existing  = {};
  bool _loadingExisting = true;

  // ── Firestore helpers ────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    setState(() => _loadingExisting = true);
    try {
      final allIds = [
        ..._adminStrategies.map((s) => s.id),
        ..._userTemplates.map((s) => s.id),
        ..._tempUserStrategies.map((s) => s.id),
      ];

      // algo_signals
      final sigSnap = await FirebaseFirestore.instance
          .collection('algo_signals')
          .where('seed_id', whereIn: allIds)
          .get();
      final found = sigSnap.docs
          .map((d) => d.get('seed_id') as String)
          .toSet();

      // user strategies (collectionGroup)
      final usrSnap = await FirebaseFirestore.instance
          .collectionGroup('strategies')
          .where('seed_id', whereIn: allIds)
          .get();
      found.addAll(
          usrSnap.docs.map((d) => d.get('seed_id') as String));

      // seeded orders
      final orderSnap = await FirebaseFirestore.instance
          .collection('orders')
          .where('seed_id', whereIn: _seedOrders.map((o) => o.id).toList())
          .get();
      found.addAll(
          orderSnap.docs.map((d) => d.get('seed_id') as String));

      if (mounted) setState(() { _existing
        ..clear()
        ..addAll(found); });
    } catch (e) {
      _snack('Check failed: $e', ok: false);
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  // ── Seed admin strategy ──────────────────────────────────────────────────

  Future<void> _seedAdmin(_AdminSeed s, {required bool isPublished}) async {
    if (_seeding[s.id] == true) return;
    setState(() => _seeding[s.id] = true);
    try {
      await FirebaseFirestore.instance
          .collection('algo_signals')
          .add(s.toFirestore(isPublished: isPublished));
      if (mounted) {
        setState(() { _seeding[s.id] = false; _existing.add(s.id); });
        _snack('✅  "${s.label}" seeded!', ok: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _seeding[s.id] = null);
        _snack('❌  Failed: $e', ok: false);
      }
    }
  }

  Future<void> _seedAllAdmin({required bool isPublished}) async {
    for (final s in [..._adminStrategies, ..._userTemplates]) {
      if (!_existing.contains(s.id)) {
        await _seedAdmin(s, isPublished: isPublished);
      }
    }
  }

  // ── Delete old seeded docs ───────────────────────────────────────────────

  Future<void> _deleteOldSeeds() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete all seeded docs?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
            'This will permanently delete all algo_signals documents '
            'that have a seed_id field, including any old seeds. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD1483F)),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('algo_signals')
          .where('seed_id', isNull: false)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) batch.delete(d.reference);
      await batch.commit();
      if (mounted) {
        setState(() => _existing.clear());
        _snack('🗑  Deleted ${snap.docs.length} seeded docs.', ok: true);
      }
    } catch (e) {
      _snack('Delete failed: $e', ok: false);
    }
  }

  // ── Seed temp user strategy ──────────────────────────────────────────────

  Future<void> _seedUserStrategy(_TempUserSeed s, String uid) async {
    if (_seeding[s.id] == true) return;
    setState(() => _seeding[s.id] = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('strategies')
          .add(s.toFirestore(uid));
      if (mounted) {
        setState(() { _seeding[s.id] = false; _existing.add(s.id); });
        _snack('✅  "${s.label}" seeded to user $uid!', ok: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _seeding[s.id] = null);
        _snack('❌  Failed: $e', ok: false);
      }
    }
  }

  Future<void> _deleteUserSeeds(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('strategies')
          .where('seed_id', isNull: false)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) batch.delete(d.reference);
      await batch.commit();
      if (mounted) {
        for (final s in _tempUserStrategies) _existing.remove(s.id);
        setState(() {});
        _snack('🗑  Deleted ${snap.docs.length} temp user strategies.', ok: true);
      }
    } catch (e) {
      _snack('Delete failed: $e', ok: false);
    }
  }

  // ── Seed fake orders ─────────────────────────────────────────────────────

  Future<void> _seedOrder(_SeedOrderData o, String uid) async {
    if (_seeding[o.id] == true) return;
    setState(() => _seeding[o.id] = true);
    try {
      final now = Timestamp.now();
      final placedAt = Timestamp.fromDate(
          DateTime.now().subtract(Duration(minutes: o.minutesAgo)));
      await FirebaseFirestore.instance.collection('orders').add({
        'user_id':          uid,
        'strategy_id':      'seed_strategy',
        'signal_id':        'seed_strategy',
        'symbol':           o.symbol,
        'exchange':         o.exchange,
        'action':           o.action,
        'order_type':       o.orderType,
        'quantity':         o.quantity,
        'price':            o.price,
        'trigger_price':    null,
        'product_type':     o.productType,
        'validity':         'DAY',
        'angel_order_id':   o.angelOrderId,
        'status':           o.status,
        'rejection_reason': o.rejectionReason,
        'order_role':       o.orderRole,
        'placed_at':        placedAt,
        'updated_at':       now,
        'seed_id':          o.id,
      });
      if (mounted) {
        setState(() { _seeding[o.id] = false; _existing.add(o.id); });
        _snack('✅  Order "${o.symbol} ${o.action}" seeded!', ok: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _seeding[o.id] = null);
        _snack('❌  Failed: $e', ok: false);
      }
    }
  }

  Future<void> _seedAllOrders(String uid) async {
    for (final o in _seedOrders) {
      if (!_existing.contains(o.id)) await _seedOrder(o, uid);
    }
  }

  Future<void> _deleteOrderSeeds(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('user_id', isEqualTo: uid)
          .where('seed_id', isNull: false)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) batch.delete(d.reference);
      await batch.commit();
      if (mounted) {
        for (final o in _seedOrders) _existing.remove(o.id);
        setState(() {});
        _snack('🗑  Deleted ${snap.docs.length} seed orders.', ok: true);
      }
    } catch (e) {
      _snack('Delete failed: $e', ok: false);
    }
  }

  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? const Color(0xFF0E7C6B) : const Color(0xFFD1483F),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seed Strategies',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xFF14161D))),
            Text('Admin · Firestore seeder',
                style: TextStyle(fontSize: 11, color: Color(0xFF9C9DA6))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF3548C7)),
            tooltip: 'Refresh',
            onPressed: _checkExisting,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded,
                color: Color(0xFFD1483F)),
            tooltip: 'Delete all seeded admin docs',
            onPressed: _deleteOldSeeds,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loadingExisting
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3548C7)))
          : RefreshIndicator(
              onRefresh: _checkExisting,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Info banner ──────────────────────────────────────
                    _InfoBanner(
                      icon:  Icons.admin_panel_settings_rounded,
                      color: const Color(0xFF3548C7),
                      text:  'Seed real-world strategies into Firestore. '
                          '"Draft" saves with is_published:false — no push '
                          'notifications sent. "Live" publishes immediately.',
                    ),
                    const SizedBox(height: 24),

                    // ── Admin strategies ─────────────────────────────────
                    _SectionHeader(
                      title:     'Admin Algo Signals',
                      subtitle:  '${_adminStrategies.length} curated strategies',
                      allSeeded: _adminStrategies.every((s) => _existing.contains(s.id)),
                      onSeedAll: () => _seedAllAdmin(isPublished: false),
                    ),
                    const SizedBox(height: 12),
                    ..._adminStrategies.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AdminCard(
                        seed:          s,
                        alreadySeeded: _existing.contains(s.id),
                        loading:       _seeding[s.id] == true,
                        onDraft:       () => _seedAdmin(s, isPublished: false),
                        onLive:        () => _seedAdmin(s, isPublished: true),
                      ),
                    )),

                    const SizedBox(height: 28),

                    // ── User templates ───────────────────────────────────
                    _SectionHeader(
                      title:     'User Strategy Templates',
                      subtitle:  '${_userTemplates.length} templates · users can copy',
                      allSeeded: _userTemplates.every((s) => _existing.contains(s.id)),
                      onSeedAll: () => _seedAllAdmin(isPublished: false),
                    ),
                    const SizedBox(height: 12),
                    ..._userTemplates.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AdminCard(
                        seed:          s,
                        alreadySeeded: _existing.contains(s.id),
                        loading:       _seeding[s.id] == true,
                        onDraft:       () => _seedAdmin(s, isPublished: false),
                        onLive:        () => _seedAdmin(s, isPublished: true),
                      ),
                    )),

                    const SizedBox(height: 28),

                    // ── Temp user strategies ─────────────────────────────
                    _TempUserSection(
                      seeds:      _tempUserStrategies,
                      existing:   _existing,
                      seeding:    _seeding,
                      onSeed:     _seedUserStrategy,
                      onDeleteAll: _deleteUserSeeds,
                    ),

                    const SizedBox(height: 28),

                    // ── Seed orders ──────────────────────────────────────
                    _SeedOrdersSection(
                      orders:     _seedOrders,
                      existing:   _existing,
                      seeding:    _seeding,
                      onSeed:     _seedOrder,
                      onSeedAll:  _seedAllOrders,
                      onDeleteAll: _deleteOrderSeeds,
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TempUserSection — requires a UID input
// ─────────────────────────────────────────────────────────────────────────────

class _TempUserSection extends StatefulWidget {
  const _TempUserSection({
    required this.seeds,
    required this.existing,
    required this.seeding,
    required this.onSeed,
    required this.onDeleteAll,
  });

  final List<_TempUserSeed> seeds;
  final Set<String> existing;
  final Map<String, bool?> seeding;
  final Future<void> Function(_TempUserSeed s, String uid) onSeed;
  final Future<void> Function(String uid) onDeleteAll;

  @override
  State<_TempUserSection> createState() => _TempUserSectionState();
}

class _TempUserSectionState extends State<_TempUserSection> {
  final _uidCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      _uidCtrl.text = currentUid;
    }
  }

  @override
  void dispose() {
    _uidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uidCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Temp User Strategies',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF14161D))),
                  SizedBox(height: 2),
                  Text(
                    'Written to users/{uid}/strategies for dev/demo testing',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9C9DA6)),
                  ),
                ],
              ),
            ),
            if (uid.isNotEmpty)
              TextButton.icon(
                onPressed: () => widget.onDeleteAll(uid),
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                label: const Text('Delete All'),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD1483F),
                    textStyle: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // UID input
        // UID label + reset button
        Row(children: [
          const Icon(Icons.person_pin_rounded, size: 13, color: Color(0xFF9C9DA6)),
          const SizedBox(width: 5),
          const Text('Target UID',
              style: TextStyle(fontSize: 11, color: Color(0xFF9C9DA6))),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3548C7).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('editable',
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: Color(0xFF3548C7))),
          ),
          const Spacer(),
          if (FirebaseAuth.instance.currentUser?.uid != null)
            GestureDetector(
              onTap: () => setState(() {
                _uidCtrl.text =
                    FirebaseAuth.instance.currentUser!.uid;
              }),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.refresh_rounded,
                    size: 12, color: Color(0xFF3548C7)),
                const SizedBox(width: 3),
                const Text('Reset to me',
                    style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF3548C7),
                        fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE7E4DA)),
          ),
          child: Row(children: [
            const Icon(Icons.person_outline_rounded,
                size: 18, color: Color(0xFF3548C7)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _uidCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF14161D)),
                decoration: const InputDecoration(
                  hintText: 'Paste user UID here',
                  hintStyle: TextStyle(
                      fontSize: 13, color: Color(0xFF9C9DA6)),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ]),
        ),

        if (uid.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Enter a UID above to enable seeding',
              style: TextStyle(
                  fontSize: 11, color: Colors.orange.shade700),
            ),
          ),

        const SizedBox(height: 12),

        ...widget.seeds.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TempUserCard(
            seed:          s,
            alreadySeeded: widget.existing.contains(s.id),
            loading:       widget.seeding[s.id] == true,
            uidReady:      uid.isNotEmpty,
            onSeed:        uid.isNotEmpty
                ? () => widget.onSeed(s, uid)
                : null,
          ),
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards
// ─────────────────────────────────────────────────────────────────────────────

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.seed,
    required this.alreadySeeded,
    required this.loading,
    required this.onDraft,
    required this.onLive,
  });

  final _AdminSeed seed;
  final bool alreadySeeded;
  final bool loading;
  final VoidCallback onDraft;
  final VoidCallback onLive;

  static Color _catColor(String cat) {
    switch (cat) {
      case 'options':   return const Color(0xFF7C3AED);
      case 'futures':   return const Color(0xFF2563EB);
      case 'commodity': return const Color(0xFFD97706);
      case 'forex':     return const Color(0xFF059669);
      default:          return const Color(0xFF3548C7);
    }
  }

  String _fmtPrice(double v) {
    if (v <= 0) return '—';
    if (v >= 1000) {
      return '₹${v.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    }
    return '₹${v.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final cat = _catColor(seed.category);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alreadySeeded
              ? const Color(0xFF0E7C6B).withOpacity(0.35)
              : const Color(0xFFE7E4DA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: category chip + badge + order type + product type
          Row(children: [
            _Chip(seed.category.toUpperCase(), cat),
            const SizedBox(width: 6),
            _Chip(seed.action, seed.action == 'BUY'
                ? const Color(0xFF0E7C6B)
                : const Color(0xFFD1483F)),
            const SizedBox(width: 6),
            _Chip(seed.orderType, const Color(0xFF5B5D66)),
            const SizedBox(width: 6),
            _Chip(seed.productType,
                seed.productType == 'MIS'
                    ? const Color(0xFFBF7A16)
                    : seed.productType == 'NRML'
                        ? const Color(0xFF2C6FB0)
                        : const Color(0xFF0E7C6B)),
            const Spacer(),
            if (alreadySeeded)
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF0E7C6B), size: 18),
          ]),

          const SizedBox(height: 10),

          // Title
          Text(seed.label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF14161D))),
          const SizedBox(height: 2),
          Text('${seed.stockSymbol}  ·  ${seed.exchange}  ·  ${seed.type.replaceAll('_', ' ')}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9C9DA6))),

          const SizedBox(height: 8),

          // Description
          Text(seed.description,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF5B5D66), height: 1.45),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),

          const SizedBox(height: 10),

          // Price chips
          if (seed.entryPrice > 0)
            Wrap(spacing: 6, runSpacing: 6, children: [
              _PChip('Entry',  _fmtPrice(seed.entryPrice), const Color(0xFF3548C7)),
              _PChip('T1',     _fmtPrice(seed.target),     const Color(0xFF0E7C6B)),
              if (seed.target2 > 0)
                _PChip('T2',   _fmtPrice(seed.target2),    const Color(0xFF0A916B)),
              _PChip('SL',     _fmtPrice(seed.stoploss),   const Color(0xFFD1483F)),
              _PChip('Dur',    seed.duration,               const Color(0xFF9C9DA6)),
              _PChip('Valid',  seed.validity,               const Color(0xFF9C9DA6)),
            ]),

          const SizedBox(height: 10),

          // Tags
          if (seed.tags.isNotEmpty)
            Wrap(spacing: 4, runSpacing: 4,
              children: seed.tags.take(4).map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF3548C7).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('#$t',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF3548C7),
                        fontWeight: FontWeight.w600)),
              )).toList(),
            ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEFEDE8)),
          const SizedBox(height: 12),

          // Actions
          if (loading)
            const Center(child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF3548C7)))
          else if (alreadySeeded)
            Row(children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF0E7C6B), size: 16),
              const SizedBox(width: 6),
              const Text('Already seeded',
                  style: TextStyle(fontSize: 12, color: Color(0xFF0E7C6B))),
              const Spacer(),
              TextButton(
                onPressed: onLive,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF3548C7),
                    textStyle: const TextStyle(fontSize: 12)),
                child: const Text('Reseed Live'),
              ),
            ])
          else
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: onDraft,
                icon: const Icon(Icons.drafts_rounded, size: 14),
                label: const Text('Draft'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF3548C7),
                  side: const BorderSide(color: Color(0xFF3548C7)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: onLive,
                icon: const Icon(Icons.rocket_launch_rounded, size: 14),
                label: const Text('Seed Live'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3548C7),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                ),
              )),
            ]),
        ],
      ),
    );
  }
}

class _TempUserCard extends StatelessWidget {
  const _TempUserCard({
    required this.seed,
    required this.alreadySeeded,
    required this.loading,
    required this.uidReady,
    this.onSeed,
  });

  final _TempUserSeed seed;
  final bool alreadySeeded;
  final bool loading;
  final bool uidReady;
  final VoidCallback? onSeed;

  @override
  Widget build(BuildContext context) {
    final isConditional = seed.condType != null && seed.condType != 'at_market';
    final execColor = isConditional
        ? const Color(0xFFBF7A16)
        : seed.strategyType == 'options'
            ? const Color(0xFF7C3AED)
            : const Color(0xFF0E7C6B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alreadySeeded
              ? const Color(0xFF0E7C6B).withOpacity(0.35)
              : const Color(0xFFE7E4DA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _Chip(seed.strategyType.toUpperCase(),
                seed.strategyType == 'options'
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF3548C7)),
            const SizedBox(width: 6),
            _Chip(isConditional ? 'CONDITIONAL' : 'MARKET', execColor),
            const SizedBox(width: 6),
            _Chip(seed.productType,
                seed.productType == 'MIS'
                    ? const Color(0xFFBF7A16)
                    : seed.productType == 'NRML'
                        ? const Color(0xFF2C6FB0)
                        : const Color(0xFF0E7C6B)),
            if (seed.trailingSL) ...[
              const SizedBox(width: 6),
              _Chip('TRAIL SL', const Color(0xFFBF7A16)),
            ],
            const Spacer(),
            if (alreadySeeded)
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF0E7C6B), size: 18),
          ]),

          const SizedBox(height: 10),

          Text(seed.label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: Color(0xFF14161D))),
          const SizedBox(height: 2),
          Text('${seed.stockSymbol}  ·  ${seed.strategyType == 'options' ? '${seed.lots} lot(s) × ${seed.lotSize}' : '${seed.shares} shares'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9C9DA6))),

          const SizedBox(height: 8),

          Text(seed.description,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF5B5D66), height: 1.4),
              maxLines: 2, overflow: TextOverflow.ellipsis),

          if (isConditional) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.radio_button_checked_rounded,
                  size: 13, color: Color(0xFFBF7A16)),
              const SizedBox(width: 6),
              Text(
                'Enter when LTP ${seed.condType == 'above' ? '≥' : '≤'} ₹${seed.condPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 11.5, color: Color(0xFFBF7A16),
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEFEDE8)),
          const SizedBox(height: 12),

          if (loading)
            const Center(child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF3548C7)))
          else if (alreadySeeded)
            Row(children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF0E7C6B), size: 16),
              const SizedBox(width: 6),
              const Text('Already seeded to user',
                  style: TextStyle(fontSize: 12, color: Color(0xFF0E7C6B))),
              const Spacer(),
              TextButton(
                onPressed: uidReady ? onSeed : null,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF3548C7),
                    textStyle: const TextStyle(fontSize: 12)),
                child: const Text('Reseed'),
              ),
            ])
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: uidReady ? onSeed : null,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: Text(uidReady
                    ? 'Seed to User'
                    : 'Enter UID above first'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: uidReady
                      ? execColor
                      : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.grey.shade500,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(
      {required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: color.withOpacity(0.9),
                      height: 1.5)),
            ),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.allSeeded,
    required this.onSeedAll,
  });

  final String title, subtitle;
  final bool allSeeded;
  final VoidCallback onSeedAll;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: Color(0xFF14161D))),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9C9DA6))),
            ],
          )),
          if (!allSeeded)
            TextButton.icon(
              onPressed: onSeedAll,
              icon: const Icon(Icons.cloud_upload_rounded, size: 15),
              label: const Text('Seed All (draft)'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3548C7),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0E7C6B).withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded,
                    size: 13, color: Color(0xFF0E7C6B)),
                SizedBox(width: 5),
                Text('All seeded',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF0E7C6B))),
              ]),
            ),
        ],
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: color)),
      );
}

class _PChip extends StatelessWidget {
  const _PChip(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.20)),
        ),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                  fontSize: 9.5,
                  color: color.withOpacity(0.7),
                  fontWeight: FontWeight.w500),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: 11.5,
                  color: color,
                  fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Seed Orders — data model + list
// ─────────────────────────────────────────────────────────────────────────────

class _SeedOrderData {
  const _SeedOrderData({
    required this.id,
    required this.symbol,
    required this.exchange,
    required this.action,
    required this.orderType,
    required this.quantity,
    required this.price,
    required this.productType,
    required this.status,
    required this.orderRole,
    required this.minutesAgo,
    this.angelOrderId,
    this.rejectionReason,
  });

  final String  id;
  final String  symbol;
  final String  exchange;
  final String  action;
  final String  orderType;
  final int     quantity;
  final double  price;
  final String  productType;
  final String  status;       // pending | open | complete | rejected | cancelled
  final String  orderRole;    // entry | exit | bracket_sl | bracket_target
  final int     minutesAgo;   // how far in the past to back-date placed_at
  final String? angelOrderId;
  final String? rejectionReason;
}

const _seedOrders = <_SeedOrderData>[
  // ── Completed (filled) orders
  _SeedOrderData(
    id:          'seed_order_reliance_buy_complete',
    symbol:      'RELIANCE',       exchange:    'NSE',
    action:      'BUY',            orderType:   'LIMIT',
    quantity:    10,               price:       2942.50,
    productType: 'CNC',            status:      'complete',
    orderRole:   'entry',          minutesAgo:  240,
    angelOrderId: '230914000001',
  ),
  _SeedOrderData(
    id:          'seed_order_reliance_sell_complete',
    symbol:      'RELIANCE',       exchange:    'NSE',
    action:      'SELL',           orderType:   'MARKET',
    quantity:    10,               price:       3048.00,
    productType: 'CNC',            status:      'complete',
    orderRole:   'exit',           minutesAgo:  60,
    angelOrderId: '230914000002',
  ),
  _SeedOrderData(
    id:          'seed_order_hdfcbank_buy_complete',
    symbol:      'HDFCBANK',       exchange:    'NSE',
    action:      'BUY',            orderType:   'LIMIT',
    quantity:    15,               price:       1682.00,
    productType: 'CNC',            status:      'complete',
    orderRole:   'entry',          minutesAgo:  360,
    angelOrderId: '230914000003',
  ),
  // ── Active (open/pending) orders
  _SeedOrderData(
    id:          'seed_order_tcs_buy_open',
    symbol:      'TCS',            exchange:    'NSE',
    action:      'BUY',            orderType:   'LIMIT',
    quantity:    5,                price:       4182.00,
    productType: 'CNC',            status:      'open',
    orderRole:   'entry',          minutesAgo:  8,
    angelOrderId: '230914000004',
  ),
  _SeedOrderData(
    id:          'seed_order_nifty_buy_pending',
    symbol:      'NIFTY',          exchange:    'NFO',
    action:      'BUY',            orderType:   'MARKET',
    quantity:    50,               price:       24688.00,
    productType: 'MIS',            status:      'pending',
    orderRole:   'entry',          minutesAgo:  2,
    angelOrderId: null,
  ),
  // ── Bracket SL order
  _SeedOrderData(
    id:          'seed_order_nifty_bracket_sl',
    symbol:      'NIFTY',          exchange:    'NFO',
    action:      'SELL',           orderType:   'SL-M',
    quantity:    50,               price:       24520.00,
    productType: 'MIS',            status:      'open',
    orderRole:   'bracket_sl',     minutesAgo:  3,
    angelOrderId: '230914000005',
  ),
  // ── Rejected orders
  _SeedOrderData(
    id:          'seed_order_banknifty_rejected',
    symbol:      'BANKNIFTY',      exchange:    'NFO',
    action:      'BUY',            orderType:   'LIMIT',
    quantity:    15,               price:       240.00,
    productType: 'NRML',           status:      'rejected',
    orderRole:   'entry',          minutesAgo:  480,
    angelOrderId: null,
    rejectionReason: 'Insufficient funds in trading account',
  ),
  // ── Cancelled orders
  _SeedOrderData(
    id:          'seed_order_goldm_cancelled',
    symbol:      'GOLDM',          exchange:    'MCX',
    action:      'BUY',            orderType:   'LIMIT',
    quantity:    1,                price:       72510.00,
    productType: 'NRML',           status:      'cancelled',
    orderRole:   'entry',          minutesAgo:  720,
    angelOrderId: '230914000006',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// _SeedOrdersSection
// ─────────────────────────────────────────────────────────────────────────────

class _SeedOrdersSection extends StatefulWidget {
  const _SeedOrdersSection({
    required this.orders,
    required this.existing,
    required this.seeding,
    required this.onSeed,
    required this.onSeedAll,
    required this.onDeleteAll,
  });

  final List<_SeedOrderData> orders;
  final Set<String>         existing;
  final Map<String, bool?>  seeding;
  final Future<void> Function(_SeedOrderData, String) onSeed;
  final Future<void> Function(String) onSeedAll;
  final Future<void> Function(String) onDeleteAll;

  @override
  State<_SeedOrdersSection> createState() => _SeedOrdersSectionState();
}

class _SeedOrdersSectionState extends State<_SeedOrdersSection> {
  final _uidCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      _uidCtrl.text = currentUid;
    }
  }

  @override
  void dispose() {
    _uidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uidCtrl.text.trim();
    final allSeeded = widget.orders.every((o) => widget.existing.contains(o.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Seed Orders',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF14161D))),
            const SizedBox(height: 2),
            Text('${widget.orders.length} fake orders → orders collection',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9C9DA6))),
          ])),
          if (uid.isNotEmpty && !allSeeded)
            TextButton.icon(
              onPressed: () => widget.onSeedAll(uid),
              icon: const Icon(Icons.cloud_upload_rounded, size: 15),
              label: const Text('Seed All'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3548C7),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          if (uid.isNotEmpty)
            TextButton.icon(
              onPressed: () => widget.onDeleteAll(uid),
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: const Text('Delete All'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD1483F),
                  textStyle: const TextStyle(fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 12),

        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF3548C7).withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3548C7).withOpacity(0.18)),
          ),
          child: const Row(children: [
            Icon(Icons.receipt_long_rounded, size: 15, color: Color(0xFF3548C7)),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Writes fake orders to the global orders collection so OrderBookScreen '
              'shows all three groups (Active · Completed · Rejected).',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF3548C7), height: 1.45),
            )),
          ]),
        ),
        const SizedBox(height: 12),

        // UID label + reset button
        Row(children: [
          const Icon(Icons.person_pin_rounded, size: 13, color: Color(0xFF9C9DA6)),
          const SizedBox(width: 5),
          const Text('Target UID',
              style: TextStyle(fontSize: 11, color: Color(0xFF9C9DA6))),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3548C7).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('editable',
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: Color(0xFF3548C7))),
          ),
          const Spacer(),
          if (FirebaseAuth.instance.currentUser?.uid != null)
            GestureDetector(
              onTap: () => setState(() {
                _uidCtrl.text =
                    FirebaseAuth.instance.currentUser!.uid;
              }),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded,
                    size: 12, color: Color(0xFF3548C7)),
                SizedBox(width: 3),
                Text('Reset to me',
                    style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF3548C7),
                        fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
        const SizedBox(height: 6),

        // UID input — same pattern as _TempUserSection
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE7E4DA)),
          ),
          child: Row(children: [
            const Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF3548C7)),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _uidCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF14161D)),
              decoration: const InputDecoration(
                hintText: 'Paste user UID here',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9C9DA6)),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            )),
          ]),
        ),

        if (uid.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text('Enter a UID above to enable seeding',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
          ),

        const SizedBox(height: 12),

        // Order cards
        ...widget.orders.map((o) {
          final seeded  = widget.existing.contains(o.id);
          final loading = widget.seeding[o.id] == true;

          final statusColor = switch (o.status) {
            'complete'  => const Color(0xFF16A34A),
            'open'      => const Color(0xFFD97706),
            'pending'   => const Color(0xFFD97706),
            'rejected'  => const Color(0xFFDC2626),
            'cancelled' => const Color(0xFF9CA3AF),
            _           => const Color(0xFF9CA3AF),
          };

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: seeded
                    ? const Color(0xFF0E7C6B).withOpacity(0.35)
                    : const Color(0xFFE7E4DA),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Row 1: symbol + action + status + role
              Row(children: [
                _Chip(o.symbol, const Color(0xFF3548C7)),
                const SizedBox(width: 6),
                _Chip(o.action,
                    o.action == 'BUY' ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
                const SizedBox(width: 6),
                _Chip(o.orderRole.toUpperCase().replaceAll('_', ' '), const Color(0xFF5B5D66)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(o.status.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9.5, fontWeight: FontWeight.w800, color: statusColor)),
                ),
                if (seeded) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF0E7C6B), size: 16),
                ],
              ]),
              const SizedBox(height: 8),
              // Row 2: qty + price + exchange
              Row(children: [
                _PChip('QTY',   '${o.quantity}',           const Color(0xFF374151)),
                const SizedBox(width: 6),
                _PChip('₹',    o.price.toStringAsFixed(2), const Color(0xFF3548C7)),
                const SizedBox(width: 6),
                _PChip('MKT',  o.exchange,                 const Color(0xFF9CA3AF)),
                const SizedBox(width: 6),
                _PChip('TYPE', o.orderType,                const Color(0xFF9CA3AF)),
                const Spacer(),
                Text('${o.minutesAgo}m ago',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
              ]),
              if (o.rejectionReason != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(o.rejectionReason!,
                      style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)))),
                ]),
              ],
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFEFEDE8)),
              const SizedBox(height: 10),
              // Seed button
              if (loading)
                const Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3548C7))))
              else if (seeded)
                Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF0E7C6B), size: 15),
                  const SizedBox(width: 6),
                  const Text('Seeded', style: TextStyle(fontSize: 12, color: Color(0xFF0E7C6B))),
                  const Spacer(),
                  TextButton(
                    onPressed: uid.isNotEmpty ? () => widget.onSeed(o, uid) : null,
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF3548C7),
                        textStyle: const TextStyle(fontSize: 12)),
                    child: const Text('Reseed'),
                  ),
                ])
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: uid.isNotEmpty ? () => widget.onSeed(o, uid) : null,
                    icon: const Icon(Icons.receipt_long_rounded, size: 15),
                    label: Text(uid.isNotEmpty ? 'Seed Order' : 'Enter UID above first'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uid.isNotEmpty
                          ? statusColor
                          : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.grey.shade500,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
            ]),
          );
        }),
      ],
    );
  }
}
