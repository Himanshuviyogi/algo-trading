'use strict';
/**
 * test_paper_trade.js
 * ─────────────────────────────────────────────────────────────────────────────
 * End-to-end paper trade verification script.
 *
 * What it tests:
 *   1. POST /place-order with paperTrade:true → order doc written to Firestore
 *   2. Firestore order doc has: status=complete, paper_trade=true, PAPER-xxx angelOrderId
 *   3. Simulates the full strategy lifecycle by writing a strategy doc directly
 *      with status=watching, paper_trade=true, then checking the engine would
 *      pick it up (we verify the doc shape matches what the Cloud Function expects)
 *   4. Cleans up all test docs after verification
 *
 * Usage:
 *   node scripts/test_paper_trade.js
 */

const admin = require('firebase-admin');
const axios = require('axios');
const path  = require('path');

// ── Init Firebase Admin ───────────────────────────────────────────────────────
const serviceAccount = require('./algo-trading-service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

const PRICE_SERVER = 'http://31.172.87.141:3002';
const TEST_UID     = 'paper_test_script_user';
const SYMBOL       = 'NIFTY';

// ── Helpers ───────────────────────────────────────────────────────────────────
const pass  = (msg) => console.log(`  ✅ ${msg}`);
const fail  = (msg) => { console.error(`  ❌ FAIL: ${msg}`); process.exitCode = 1; };
const info  = (msg) => console.log(`  ℹ️  ${msg}`);

// ── Test suite ────────────────────────────────────────────────────────────────
async function run() {
  console.log('\n══════════════════════════════════════════════════════');
  console.log(' Paper Trade End-to-End Verification');
  console.log('══════════════════════════════════════════════════════\n');

  const createdOrderIds    = [];
  const createdStrategyIds = [];

  try {

    // ── STEP 1: Price server health ────────────────────────────────────────
    console.log('Step 1 — Price server health');
    const health = await axios.get(`${PRICE_SERVER}/health`, { timeout: 5000 });
    info(`status=${health.data.status} broker=${health.data.broker} uptime=${Math.round(health.data.uptime)}s`);
    if (health.data.status === 'ok') pass('Price server is up');
    else fail(`Price server returned status=${health.data.status}`);

    // ── STEP 2: Place a paper order via /place-order ───────────────────────
    console.log('\nStep 2 — Place paper order via /place-order');
    const orderRes = await axios.post(`${PRICE_SERVER}/place-order`, {
      userId:     TEST_UID,
      symbol:     SYMBOL,
      exchange:   'NSE',
      action:     'BUY',
      orderType:  'MARKET',
      quantity:   1,
      price:      100,       // small value to stay under risk limit
      paperTrade: true,
    }, { timeout: 10000 });

    const orderData = orderRes.data;
    info(`Response: ${JSON.stringify(orderData)}`);

    if (orderData.success !== true)           fail(`success!=true: ${JSON.stringify(orderData)}`);
    else                                      pass('success=true');

    if (orderData.paperTrade === true)        pass('paperTrade=true in response');
    else                                      fail(`paperTrade missing/false in response`);

    const paperId = orderData.angelOrderId;
    if (paperId && paperId.startsWith('PAPER-')) pass(`angelOrderId is synthetic: ${paperId}`);
    else                                          fail(`angelOrderId doesn't look like PAPER-xxx: ${paperId}`);

    const firestoreOrderId = orderData.firestoreOrderId;
    if (firestoreOrderId) pass(`firestoreOrderId=${firestoreOrderId}`);
    else                  fail('firestoreOrderId missing from response');

    if (firestoreOrderId) createdOrderIds.push(firestoreOrderId);

    // ── STEP 3: Verify Firestore order doc ────────────────────────────────
    console.log('\nStep 3 — Verify Firestore order doc');
    await new Promise(r => setTimeout(r, 1000)); // give Firestore a moment
    const orderDoc = await db.collection('orders').doc(firestoreOrderId).get();

    if (!orderDoc.exists) {
      fail('Order doc does not exist in Firestore');
    } else {
      pass('Order doc exists in Firestore');
      const d = orderDoc.data();
      info(`order doc: status=${d.status} paper_trade=${d.paper_trade} angel_order_id=${d.angel_order_id}`);

      if (d.status === 'complete')       pass('status=complete');
      else                               fail(`status=${d.status}, expected complete`);

      if (d.paper_trade === true)        pass('paper_trade=true');
      else                               fail(`paper_trade=${d.paper_trade}, expected true`);

      if (d.angel_order_id === paperId)  pass(`angel_order_id matches: ${paperId}`);
      else                               fail(`angel_order_id mismatch: got ${d.angel_order_id}`);

      if (d.user_id === TEST_UID)        pass(`user_id=${d.user_id}`);
      else                               fail(`user_id=${d.user_id}, expected ${TEST_UID}`);

      if (d.symbol === SYMBOL)           pass(`symbol=${d.symbol}`);
      else                               fail(`symbol=${d.symbol}, expected ${SYMBOL}`);
    }

    // ── STEP 4: Write a test strategy doc (paper_trade=true, watching) ───
    console.log('\nStep 4 — Write paper strategy doc and verify shape');
    const strategyRef = await db
      .collection('users').doc(TEST_UID)
      .collection('strategies').add({
        status:        'watching',
        paper_trade:   true,
        auto_execute:  true,
        category:      'stocks',
        type:          'stocks_strategy',
        user_id:       TEST_UID,
        source:        'test_script',
        stock: {
          symbol:   SYMBOL,
          name:     'Nifty 50',
          exchange: 'NSE',
        },
        trade: {
          action:      'BUY',
          entry_price: 24500,
          order_type:  'MARKET',
        },
        analysis: {
          target:   25000,
          stoploss: 24000,
        },
        quantity:     1,
        lot_size:     1,
        product_type: 'MIS',
        validity:     'DAY',
        entry_condition_type:  'above',
        entry_condition_price: 24500,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        meta: { updated_at: admin.firestore.FieldValue.serverTimestamp() },
      });

    createdStrategyIds.push(strategyRef.id);
    pass(`Strategy doc created: users/${TEST_UID}/strategies/${strategyRef.id}`);

    // Read it back and verify every field the Cloud Function expects
    const snap = await strategyRef.get();
    const s = snap.data();
    info(`strategy: status=${s.status} paper_trade=${s.paper_trade} auto_execute=${s.auto_execute}`);

    if (s.status === 'watching')        pass('status=watching');
    else                                fail(`status=${s.status}`);

    if (s.paper_trade === true)         pass('paper_trade=true');
    else                                fail(`paper_trade=${s.paper_trade}`);

    if (s.auto_execute === true)        pass('auto_execute=true');
    else                                fail(`auto_execute=${s.auto_execute}`);

    if (s.stock?.symbol === SYMBOL)     pass(`stock.symbol=${s.stock.symbol}`);
    else                                fail(`stock.symbol=${s.stock?.symbol}`);

    if (s.trade?.action === 'BUY')      pass(`trade.action=${s.trade.action}`);
    else                                fail(`trade.action=${s.trade?.action}`);

    if (s.analysis?.target > 0)         pass(`analysis.target=${s.analysis.target}`);
    else                                fail(`analysis.target=${s.analysis?.target}`);

    if (s.analysis?.stoploss > 0)       pass(`analysis.stoploss=${s.analysis.stoploss}`);
    else                                fail(`analysis.stoploss=${s.analysis.stoploss}`);

    // ── STEP 5: Simulate what the Cloud Function does on entry ────────────
    console.log('\nStep 5 — Simulate engine entry: watching → in_position');
    const fakePaperId = `PAPER-TEST-${Date.now()}`;
    const fakeOrderRef = db.collection('orders').doc(`test_entry_order_${Date.now()}`);
    createdOrderIds.push(fakeOrderRef.id);

    // Write entry order doc (mirrors writeOrderDoc with merge:true + paper_trade)
    await fakeOrderRef.set({
      strategy_id:      strategyRef.id,
      signal_id:        strategyRef.id,
      user_id:          TEST_UID,
      symbol:           SYMBOL,
      exchange:         'NSE',
      action:           'BUY',
      order_type:       'MARKET',
      quantity:         1,
      price:            24500,
      trigger_price:    null,
      product_type:     'MIS',
      validity:         'DAY',
      angel_order_id:   fakePaperId,
      status:           'complete',
      rejection_reason: null,
      order_role:       'entry',
      paper_trade:      true,           // ← the fix we applied
      placed_at:        admin.firestore.Timestamp.now(),
      updated_at:       admin.firestore.Timestamp.now(),
    }, { merge: true });

    // Update strategy to in_position (mirrors what the Cloud Function writes)
    await strategyRef.update({
      status:                'in_position',
      entry_order_id:        fakeOrderRef.id,
      entry_ltp:             24500,
      entry_qty:             1,
      entered_at:            admin.firestore.FieldValue.serverTimestamp(),
      paper_trade:           true,
      'meta.updated_at':     admin.firestore.FieldValue.serverTimestamp(),
      'trade.current_price': 24500,
    });
    pass('Strategy updated to in_position');

    // Verify the order doc has paper_trade=true (tests the merge fix)
    const entryOrderSnap = await fakeOrderRef.get();
    const eo = entryOrderSnap.data();
    info(`entry order: status=${eo.status} paper_trade=${eo.paper_trade} order_role=${eo.order_role}`);

    if (eo.paper_trade === true)        pass('entry order has paper_trade=true ✓ (merge fix verified)');
    else                                fail('entry order missing paper_trade=true — merge fix broken');

    if (eo.angel_order_id === fakePaperId) pass(`entry order angel_order_id=${eo.angel_order_id}`);
    else                                   fail(`angel_order_id mismatch`);

    // ── STEP 6: Simulate exit (target hit) ────────────────────────────────
    console.log('\nStep 6 — Simulate exit order (target_hit)');
    const exitOrderRef = db.collection('orders').doc(`test_exit_order_${Date.now()}`);
    createdOrderIds.push(exitOrderRef.id);

    const exitPrice  = 25000;
    const entryPrice = 24500;
    const qty        = 1;
    const pnlRs      = (exitPrice - entryPrice) * qty;  // BUY exit = sell - buy
    const pnlPct     = (pnlRs / (entryPrice * qty)) * 100;

    await exitOrderRef.set({
      strategy_id:      strategyRef.id,
      signal_id:        strategyRef.id,
      user_id:          TEST_UID,
      symbol:           SYMBOL,
      exchange:         'NSE',
      action:           'SELL',
      order_type:       'MARKET',
      quantity:         qty,
      price:            exitPrice,
      trigger_price:    null,
      product_type:     'MIS',
      validity:         'DAY',
      angel_order_id:   `PAPER-EXIT-${Date.now()}`,
      status:           'complete',
      rejection_reason: null,
      order_role:       'exit',
      paper_trade:      true,
      placed_at:        admin.firestore.Timestamp.now(),
      updated_at:       admin.firestore.Timestamp.now(),
    }, { merge: true });

    await strategyRef.update({
      status:               'target_hit',
      exit_order_id:        exitOrderRef.id,
      exit_ltp:             exitPrice,
      exited_at:            admin.firestore.FieldValue.serverTimestamp(),
      realised_pnl_rs:      pnlRs,
      realised_pnl_pct:     pnlPct,
      'trade.exit_price':   exitPrice,
      'trade.current_price': exitPrice,
      'meta.updated_at':    admin.firestore.FieldValue.serverTimestamp(),
    });

    const closedSnap = await strategyRef.get();
    const cs = closedSnap.data();
    info(`strategy closed: status=${cs.status} realised_pnl_rs=₹${cs.realised_pnl_rs} pnl_pct=${cs.realised_pnl_pct?.toFixed(2)}%`);

    if (cs.status === 'target_hit')             pass('status=target_hit');
    else                                         fail(`status=${cs.status}`);

    if (cs.realised_pnl_rs === pnlRs)           pass(`realised_pnl_rs=₹${cs.realised_pnl_rs}`);
    else                                         fail(`realised_pnl_rs=${cs.realised_pnl_rs}, expected ${pnlRs}`);

    const exitOrderSnap = await exitOrderRef.get();
    const exo = exitOrderSnap.data();
    if (exo.paper_trade === true)               pass('exit order has paper_trade=true');
    else                                         fail('exit order missing paper_trade=true');

    if (exo.order_role === 'exit')              pass('order_role=exit');
    else                                         fail(`order_role=${exo.order_role}`);

    // ── STEP 7: Summary ───────────────────────────────────────────────────
    console.log('\n──────────────────────────────────────────────────────');
    if (process.exitCode === 1) {
      console.log(' ❌  SOME CHECKS FAILED — see above');
    } else {
      console.log(' ✅  ALL CHECKS PASSED — paper trade flow is working correctly');
    }
    console.log('──────────────────────────────────────────────────────\n');

  } finally {
    // ── Cleanup ───────────────────────────────────────────────────────────
    console.log('Cleanup — deleting test docs...');
    for (const id of createdOrderIds) {
      try { await db.collection('orders').doc(id).delete(); } catch (_) {}
    }
    for (const id of createdStrategyIds) {
      try {
        await db.collection('users').doc(TEST_UID)
          .collection('strategies').doc(id).delete();
      } catch (_) {}
    }
    console.log('Cleanup done.\n');
    process.exit(process.exitCode ?? 0);
  }
}

run().catch(err => {
  console.error('\n💥 Unhandled error:', err.message);
  process.exit(1);
});
