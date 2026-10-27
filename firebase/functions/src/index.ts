import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getMessaging, Message } from "firebase-admin/messaging";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import axios from "axios";

initializeApp();

// ── Environment ───────────────────────────────────────────────────────────────

const PRICE_SERVER_URL =
  process.env.PRICE_SERVER_URL || "http://31.172.87.141:3002";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

/**
 * User strategy status lifecycle (new architecture):
 *
 *   watching    → entry condition not yet met, engine is polling price
 *   in_position → entry order placed, waiting for target or SL
 *   target_hit  → exit order placed because price reached target
 *   sl_hit      → exit order placed because price hit stop-loss
 *   closed      → manually closed by user from the app
 *   live        → legacy value (admin algo_signals only)
 */
type StrategyStatus =
  | "watching"
  | "in_position"
  | "target_hit"
  | "sl_hit"
  | "closed"
  | "live";

interface UserStrategy {
  status: StrategyStatus;
  stock?: { symbol?: string; name?: string; exchange?: string };
  trade?: {
    action?: string;
    entry_price?: number;
    order_type?: string;         // LIMIT | MARKET | SL | SL-M
    trigger_price?: number;      // Required for SL / SL-M order types
  };
  analysis?: { target?: number; target2?: number; stoploss?: number };
  quantity?: number;
  lot_size?: number;
  // Execution mode: immediate | conditional | bracket
  execution_mode?: "immediate" | "conditional" | "bracket";
  // Entry condition fields
  entry_condition_type?: "above" | "below" | "at_market";
  entry_condition_price?: number;
  // Bracket order fields
  bracket_order?: boolean;
  bracket_sl?: number;
  bracket_target?: number;
  // Trailing stop-loss
  trailing_sl_enabled?: boolean;
  trailing_sl_mode?: "points" | "pct";
  trailing_sl_value?: number;
  trailing_sl_current?: number;  // runtime: current trailing SL level
  // Position sizing
  position_size_mode?: "qty" | "capitalPct" | "fixedRs";
  // New fields written by the Flutter strategy wizard (create_strategy_screen.dart)
  // position_sizing: 'Fixed Lots' | '% of Capital'
  position_sizing?: string;
  lots?: number;            // number of lots (Fixed Lots mode)
  capital_pct?: number;     // % of capital per trade (% of Capital mode)
  capital_amount?: number;  // user-entered total capital (% of Capital mode)
  // Per-strategy paper trading — user sets this at strategy creation time
  paper_trade?: boolean;    // true = simulate only, no real order sent to Angel One
  // Auto-execute flag (user-controlled — false = manual tracking only)
  auto_execute?: boolean;
  // Product type: CNC (delivery) | MIS (intraday margin) | NRML (carry-forward F&O)
  product_type?: "CNC" | "MIS" | "NRML";
  // Order validity: DAY | IOC | GTC
  validity?: "DAY" | "IOC" | "GTC";
  // Conditional strategy expiry — engine auto-cancels watching strategies after this date
  valid_till?: FirebaseFirestore.Timestamp;
  // Runtime — written by the engine when an order is placed
  entry_order_id?: string;
  entry_ltp?: number;
  entry_qty?: number;       // actual filled quantity — written at entry, read at exit
  entered_at?: FirebaseFirestore.Timestamp;
  // User identifier — stored on the doc for easy access inside collectionGroup
  user_id?: string;

  // ── Fields written by create_strategy_screen.dart ───────────────────────────

  // Indicator-based entry/exit conditions arrays (Section 2 of the wizard)
  entry_conditions?: StrategyCondition[];
  exit_conditions?:  StrategyCondition[];

  // Custom trading schedule (Section 4 of the wizard)
  // start_time / end_time: "09:30 AM" or "15:00 PM" in IST
  start_time?:    string;
  end_time?:      string;
  // trading_days: list of 0-indexed weekdays (0=Mon…6=Sun in Flutter, 1=Mon…5=Fri typical)
  // Stored as List<int> in Firestore — 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri
  trading_days?:  number[];

  // Per-strategy maximum loss cap — engine exits the position if floating P&L
  // drops below -max_loss_rs (₹) regardless of the static SL level.
  max_loss_rs?:   number;

  // Locked profit floor — once floating profit reaches locked_profit_trigger_rs,
  // the engine will not exit below a locked_profit_floor_rs profit.
  // Implemented by dynamically raising the effective SL to floor.
  locked_profit_trigger_rs?: number;   // P&L ₹ threshold to activate the lock
  locked_profit_floor_rs?:   number;   // minimum ₹ profit to protect once locked
  locked_profit_active?:     boolean;  // runtime flag — written by engine when triggered

  // Re-entry after SL/target hit
  re_entry?:          boolean;    // true = engine should re-arm the strategy
  re_entry_mode?:     "time" | "signal";  // 'time' = wait N min, 'signal' = immediate
  re_entry_wait_min?: number;     // minutes to wait before re-arming (mode='time')
  re_entry_count?:    number;     // max number of re-entries (0 = unlimited)
  re_entry_used?:     number;     // runtime: how many re-entries have fired so far
  re_entry_not_before?: FirebaseFirestore.Timestamp; // runtime: earliest re-entry time

  // Shares field (stocks strategies) — set by Flutter as 'shares' not 'quantity'
  shares?: number;
}

// ── Condition object shape saved by create_strategy_screen.dart ──────────────
interface StrategyCondition {
  // snake_case fields (from Dart toMap())
  lhs_type?:          string;    // 'Indicator' | 'Price'
  indicator?:         string;    // 'EMA' | 'RSI' | 'MACD' | etc.
  lhs_price?:         string;    // 'Close' | 'Open' | 'High' | 'Low' | 'Volume' | 'LTP'
  param_a?:           string;    // primary period (e.g. '14')
  param_b?:           string;    // secondary period (e.g. '26' for MACD slow)
  param_c?:           string;    // signal period  (e.g. '9' for MACD signal)
  operator?:          string;    // '>' | '<' | '>=' | '<=' | '==' | 'Crosses Above' | 'Crosses Below'
  rhs_none?:          boolean;   // true = compare to zero/direction only
  rhs_is_indicator?:  boolean;   // true = RHS is another indicator
  value_a?:           string;    // numeric threshold (RHS when rhs_is_indicator=false)
  value_b?:           string;    // RHS indicator name (when rhs_is_indicator=true)
  rhs_period?:        string;    // period for RHS indicator
  logic?:             string;    // 'AND' | 'OR' (gates with the NEXT condition)
  candle_src?:        string;    // 'Current Candle' | 'Previous Candle'
  // camelCase aliases (kept for forward compat)
  lhsType?:           string;
  lhsPrice?:          string;
  paramA?:            string;
  paramB?:            string;
  paramC?:            string;
  rhsNone?:           boolean;
  rhsIsInd?:          boolean;
  valueA?:            string;
  valueB?:            string;
  rhsPeriod?:         string;
  candleSrc?:         string;
}

interface AlgoSignal {
  is_published: boolean;
  auto_execute: boolean;
  plan_ids: string[];
  title: string;
  stock?: { name?: string; symbol?: string; logo_url?: string | null };
  trade?: {
    action?: string;
    entry_price?: number;
    order_type?: string;
    lot_size?: number | null;
  };
  analysis?: { target?: number; stoploss?: number };
}

interface UserDoc {
  uid?: string;
  name?: string | null;
  fcm_token?: string | null;
  algo_fcm_token?: string | null;
}

interface BrokerCredentials {
  broker_id: string;
  client_id: string;
  api_key: string;
  totp_secret: string;
  is_connected: boolean;
}

interface PlaceOrderPayload {
  userId:       string;
  strategyId:   string;   // was signalId — now the strategy doc ID
  symbol:       string;
  exchange:     string;
  action:       string;
  orderType:    string;
  quantity:     number;
  price:        number;
  triggerPrice?: number;  // required for SL / SL-M order types
  productType?:  string;   // CNC | MIS | NRML
  validity?:     string;   // DAY | IOC | GTC
  paperTrade?:   boolean;  // when true, price server skips Angel One
}

interface PlaceOrderResult {
  firestoreOrderId: string;
  angelOrderId: string | null;
  status: "pending" | "open" | "complete" | "rejected" | "cancelled";
}

interface ActiveSubscription {
  user_id: string;
  plan_id: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// FCM helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Send a high-priority data+alert message to a specific device token. */
async function sendToDevice(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  const message: Message = {
    token,
    data: { ...data, title, body },
    android: { priority: "high" },
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: {
          contentAvailable: true,
          sound: "default",
          badge: 1,
          alert: { title, body },
        },
      },
    },
  };
  try {
    await getMessaging().send(message);
  } catch (err) {
    console.error("[FCM] sendToDevice failed:", err instanceof Error ? err.message : err);
  }
}

/** Send to a Firestore topic and persist to notifications collection. */
async function sendToTopic(
  topic: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  const messaging = getMessaging();
  const db = getFirestore();

  const message: Message = {
    topic,
    data: { ...data, title, body },
    android: { priority: "high" },
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: {
          contentAvailable: true,
          sound: "default",
          badge: 1,
          alert: { title, body },
        },
      },
    },
  };

  await messaging.send(message);

  await db.collection("notifications").add({
    title,
    body,
    type: data.type ?? "order_placed",
    topic,
    signal_id: data.signal_id ?? null,
    plan_id:   data.plan_id   ?? null,
    sent_at:   Timestamp.now(),
    created_at: Timestamp.now(),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Firestore helpers
// ─────────────────────────────────────────────────────────────────────────────

async function getBrokerCredentials(uid: string): Promise<BrokerCredentials | null> {
  const snap = await getFirestore()
    .collection("users").doc(uid)
    .collection("broker_connections").doc("angel_one")
    .get();
  if (!snap.exists) return null;
  const d = snap.data() as Partial<BrokerCredentials>;
  if (!d.api_key || !d.totp_secret || !d.client_id) return null;
  return {
    broker_id:    d.broker_id    ?? "angel_one",
    client_id:    d.client_id,
    api_key:      d.api_key,
    totp_secret:  d.totp_secret,
    is_connected: d.is_connected ?? false,
  };
}

async function getUserFcmToken(uid: string): Promise<string | null> {
  try {
    const snap = await getFirestore().collection("users").doc(uid).get();
    return (snap.data()?.algo_fcm_token as string | null) ?? null;
  } catch {
    return null;
  }
}

async function callPlaceOrder(payload: PlaceOrderPayload): Promise<PlaceOrderResult> {
  const response = await axios.post<PlaceOrderResult>(
    `${PRICE_SERVER_URL}/place-order`,
    payload,  // paperTrade is forwarded in the body if present
    { headers: { "Content-Type": "application/json" }, timeout: 15_000 }
  );
  return response.data;
}

async function writeOrderDoc(
  orderId: string,
  params: {
    strategyId: string;
    userId: string;
    symbol: string;
    exchange: string;
    action: string;
    orderType: string;
    quantity: number;
    price: number;
    angelOrderId: string | null;
    status: "pending" | "open" | "complete" | "rejected" | "cancelled";
    rejectionReason?: string;
    orderRole?: "entry" | "exit" | "bracket_sl" | "bracket_target";
    triggerPrice?: number;
    productType?: string;
    validity?: string;
    paperTrade?: boolean;
  }
): Promise<void> {
  const db = getFirestore();
  const now = Timestamp.now();
  // Use merge:true so we don't wipe the paper_trade:true field that
  // orderExecutor.js already wrote via update() on the same doc.
  await db.collection("orders").doc(orderId).set({
    // strategy_id replaces signal_id for user-created orders
    strategy_id:      params.strategyId,
    signal_id:        params.strategyId, // keep for backward-compat with OrderBookScreen
    user_id:          params.userId,
    symbol:           params.symbol,
    exchange:         params.exchange,
    action:           params.action,
    order_type:       params.orderType,
    quantity:         params.quantity,
    price:            params.price,
    trigger_price:    params.triggerPrice ?? null,
    product_type:     params.productType  ?? "CNC",
    validity:         params.validity     ?? "DAY",
    angel_order_id:   params.angelOrderId,
    status:           params.status,
    rejection_reason: params.rejectionReason ?? null,
    order_role:       params.orderRole ?? "entry",
    paper_trade:      params.paperTrade ?? false,
    placed_at:        now,
    updated_at:       now,
  }, { merge: true });
}

async function getRiskConfig(): Promise<{
  algo_enabled:        boolean;
  max_open_positions:  number;
  max_order_value:     number;
  daily_loss_limit:    number;       // raw ₹ — written by AlgoConfigScreen
  daily_loss_limit_pct: number;      // % of capital — for display only
  total_capital:       number;
  paper_trading:       boolean;      // when true, no real orders hit Angel One
}> {
  const snap = await getFirestore().collection("app_config").doc("algo_risk").get();
  const d = snap.data() ?? {};
  const capital          = (d.total_capital        as number) ?? 100_000;
  const dailyLossPct     = (d.daily_loss_limit_pct as number) ?? 3;
  // Prefer the pre-computed ₹ value if present; fall back to deriving it
  const dailyLossLimit   = (d.daily_loss_limit     as number) ?? (capital * dailyLossPct / 100);
  return {
    algo_enabled:         (d.algo_enabled       as boolean) ?? true,
    max_open_positions:   (d.max_open_positions  as number)  ?? 5,
    max_order_value:      (d.max_order_value     as number)  ?? 50_000,
    daily_loss_limit:     dailyLossLimit,
    daily_loss_limit_pct: dailyLossPct,
    total_capital:        capital,
    paper_trading:        (d.paper_trading       as boolean) ?? false,
  };
}

// ── Helper: compute today's total realised loss for a user ────────────────────
//
// Queries users/{uid}/strategies where:
//   - status is 'sl_hit' or 'stoploss_hit'
//   - exited_at >= today midnight IST
//   - realised_pnl_rs < 0
//
// Returns the absolute sum of losses in ₹ (positive number).
// Returns 0 on any error so a query failure never blocks trading.

async function getDailyLossRs(uid: string): Promise<number> {
  try {
    const db = getFirestore();

    // Midnight IST = midnight UTC+5:30
    const now     = new Date();
    const istMs   = now.getTime() + 5.5 * 60 * 60 * 1000;
    const istDate = new Date(istMs);
    istDate.setUTCHours(0, 0, 0, 0);
    const midnightIST = new Date(istDate.getTime() - 5.5 * 60 * 60 * 1000); // back to UTC

    const snap = await db
      .collection("users").doc(uid)
      .collection("strategies")
      .where("status", "in", ["sl_hit", "stoploss_hit"])
      .where("exited_at", ">=", Timestamp.fromDate(midnightIST))
      .get();

    let totalLoss = 0;
    for (const doc of snap.docs) {
      const pnl = (doc.data().realised_pnl_rs as number | undefined) ?? 0;
      if (pnl < 0) totalLoss += Math.abs(pnl);
    }

    return totalLoss;
  } catch (err) {
    console.error(`[RiskMgr] getDailyLossRs for ${uid} failed — defaulting to 0:`, err instanceof Error ? err.message : err);
    return 0;
  }
}

// ── Fetch LTP from price server ───────────────────────────────────────────────
// Tries plain symbol first, then with -EQ suffix (NSE equities).
async function fetchLtp(symbol: string): Promise<number | null> {
  const candidates = [symbol];
  if (!symbol.endsWith("-EQ")) candidates.push(`${symbol}-EQ`);
  for (const candidate of candidates) {
    try {
      const url = `${PRICE_SERVER_URL}/price/${encodeURIComponent(candidate)}`;
      const res = await axios.get<{ ltp?: number }>(url, { timeout: 8_000 });
      if (res.status === 200 && typeof res.data?.ltp === "number") {
        return res.data.ltp;
      }
    } catch { /* try next */ }
  }
  return null;
}

// ── Persist a notification to Firestore notifications collection ──────────────
// Called alongside sendToDevice so personal trade alerts appear in the
// notification history screen (which reads from this collection).

async function _persistNotification(params: {
  userId:     string;
  title:      string;
  body:       string;
  type:       string;
  strategyId?: string;
  symbol?:    string;
  pnl?:       number;
}): Promise<void> {
  try {
    await getFirestore().collection("notifications").add({
      user_id:     params.userId,
      title:       params.title,
      body:        params.body,
      type:        params.type,
      strategy_id: params.strategyId ?? null,
      symbol:      params.symbol     ?? null,
      pnl:         params.pnl        ?? null,
      plan_id:     null,   // null for personal trade alerts (not plan-broadcast)
      signal_id:   null,
      sent_at:     Timestamp.now(),
      created_at:  Timestamp.now(),
    });
  } catch (err) {
    // Non-fatal — don't let a Firestore write failure block the trade flow
    console.warn("[Notify] Failed to persist notification:", err instanceof Error ? err.message : err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriber helpers (kept for onAlgoSignalWritten — admin signal path)
// ─────────────────────────────────────────────────────────────────────────────

async function getTopicsForPlanIds(
  planIds: string[]
): Promise<{ planId: string; topic: string }[]> {
  const db = getFirestore();
  const results: { planId: string; topic: string }[] = [];
  for (const planId of planIds) {
    const snap = await db.collection("subscription_plans").doc(planId).get();
    if (!snap.exists) continue;
    const topic: string | undefined = snap.data()?.fcm_topic;
    if (!topic) continue;
    results.push({ planId, topic });
  }
  return results;
}

async function getActiveSubscribersForPlans(
  planIds: string[]
): Promise<ActiveSubscription[]> {
  const db = getFirestore();
  const results: ActiveSubscription[] = [];
  for (let i = 0; i < planIds.length; i += 10) {
    const chunk = planIds.slice(i, i + 10);
    const snap = await db
      .collection("subscriptions")
      .where("plan_id", "in", chunk)
      .where("is_active", "==", true)
      .get();
    for (const doc of snap.docs) {
      const data = doc.data();
      const expiry = data.expiry_date as Timestamp | undefined;
      if (expiry && expiry.toMillis() < Date.now()) continue;
      results.push({ user_id: data.user_id as string, plan_id: data.plan_id as string });
    }
  }
  const seen = new Set<string>();
  return results.filter((s) => { if (seen.has(s.user_id)) return false; seen.add(s.user_id); return true; });
}

// ─────────────────────────────────────────────────────────────────────────────
// onAlgoSignalWritten
//
// KEPT for admin-created algo_signals (the curated recommendation path).
// This path is still valid — admins can still publish signals that auto-execute
// for all subscribers of a plan.
//
// The NEW user self-service path goes through onStrategyEntryCheck instead.
// ─────────────────────────────────────────────────────────────────────────────

export const onAlgoSignalWritten = onDocumentWritten(
  { document: "algo_signals/{docId}", region: "us-central1", timeoutSeconds: 540 },
  async (event) => {
    const before = event.data?.before?.data() as AlgoSignal | undefined;
    const after  = event.data?.after?.data()  as AlgoSignal | undefined;
    if (!after) return;

    const docId       = event.params.docId;
    const wasPublished = before?.is_published === true;
    const isPublished  = after.is_published   === true;

    if (!isPublished || wasPublished) return;

    if (!after.auto_execute) {
      await _sendPublishNotification(docId, after);
      return;
    }

    const planIds: string[] = after.plan_ids ?? [];
    if (planIds.length === 0) return;

    const symbol    = after.stock?.symbol ?? "";
    const exchange  = "NSE";
    const action    = (after.trade?.action    ?? "BUY").toUpperCase();
    const orderType = (after.trade?.order_type ?? "LIMIT").toUpperCase();
    const entryPrice = after.trade?.entry_price ?? 0;
    const lotSize    = after.trade?.lot_size    ?? 1;

    if (!symbol) { console.error(`[AlgoSignal] ${docId}: no symbol`); return; }

    const subscribers = await getActiveSubscribersForPlans(planIds);
    if (subscribers.length === 0) { await _sendPublishNotification(docId, after); return; }

    const risk = await getRiskConfig();
    if (!risk.algo_enabled) { await _sendPublishNotification(docId, after); return; }

    const db = getFirestore();
    let successCount = 0;
    let failCount = 0;

    for (const sub of subscribers) {
      const userId = sub.user_id;
      try {
        const brokerCreds = await getBrokerCredentials(userId);
        if (!brokerCreds?.is_connected) { failCount++; continue; }

        const openCount = (await db.collection("positions")
          .where("user_id", "==", userId).where("status", "==", "open")
          .count().get()).data().count ?? 0;
        if (openCount >= risk.max_open_positions) { failCount++; continue; }

        let result: PlaceOrderResult;
        try {
          result = await callPlaceOrder({ userId, strategyId: docId, symbol, exchange, action, orderType, quantity: lotSize, price: entryPrice });
        } catch (err) {
          const reason = err instanceof Error ? err.message : String(err);
          await writeOrderDoc(`${docId}_${userId}_${Date.now()}`, {
            strategyId: docId, userId, symbol, exchange, action, orderType,
            quantity: lotSize, price: entryPrice, angelOrderId: null,
            status: "rejected", rejectionReason: `Auto-execute failed: ${reason}`,
          });
          failCount++;
          continue;
        }

        await writeOrderDoc(result.firestoreOrderId, {
          strategyId: docId, userId, symbol, exchange, action, orderType,
          quantity: lotSize, price: entryPrice,
          angelOrderId: result.angelOrderId, status: result.status ?? "complete",
        });

        const token = await getUserFcmToken(userId);
        if (token) {
          await sendToDevice(token,
            `📈 Order Placed: ${action} ${symbol}`,
            `${lotSize} × ${symbol} @ ₹${entryPrice} — order ${result.status}`,
            { type: "order_placed", strategy_id: docId, symbol }
          );
        }
        successCount++;
      } catch (err) {
        console.error(`[AlgoSignal] ${docId}: user ${userId} error:`, err instanceof Error ? err.message : err);
        failCount++;
      }
    }

    console.log(`[AlgoSignal] ${docId}: ${successCount} succeeded, ${failCount} failed.`);
    await _sendPublishNotification(docId, after);
  }
);

async function _sendPublishNotification(docId: string, signal: AlgoSignal): Promise<void> {
  const planIds = signal.plan_ids ?? [];
  if (!planIds.length) return;
  const topics = await getTopicsForPlanIds(planIds);
  if (!topics.length) return;
  const stockName  = signal.stock?.name ?? signal.title ?? signal.stock?.symbol ?? "Trade";
  const action     = (signal.trade?.action ?? "BUY").toUpperCase();
  const entryPrice = signal.trade?.entry_price ?? 0;
  const title = `📈 New ${action} Call: ${stockName}`;
  const body  = signal.auto_execute
    ? `Order placed @ ₹${entryPrice} · Tap to view details`
    : `Entry ₹${entryPrice} · Tap to view details`;
  for (const { planId, topic } of topics) {
    try {
      await sendToTopic(topic, title, body, { type: "trade", signal_id: docId, plan_id: planId });
    } catch (err) {
      console.error(`[AlgoSignal] FCM failed for plan ${planId}:`, err instanceof Error ? err.message : err);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// onOrderStatusChanged
//
// Fires when an order transitions to 'complete' or 'rejected'.
// Sends a device-targeted push notification to the user.
// ─────────────────────────────────────────────────────────────────────────────

export const onOrderStatusChanged = onDocumentWritten(
  { document: "orders/{orderId}", region: "us-central1" },
  async (event) => {
    const before = event.data?.before?.data() as Record<string, unknown> | undefined;
    const after  = event.data?.after?.data()  as Record<string, unknown> | undefined;
    if (!after) return;

    const newStatus  = after.status  as string | undefined;
    const prevStatus = before?.status as string | undefined;
    if (newStatus === prevStatus) return;
    if (newStatus !== "complete" && newStatus !== "rejected") return;

    const orderId = event.params.orderId;
    const userId  = after.user_id as string | undefined;
    const symbol  = (after.symbol  as string | undefined) ?? "Trade";
    const action  = ((after.action as string | undefined) ?? "BUY").toUpperCase();
    const qty     = (after.quantity as number | undefined) ?? 0;
    const price   = (after.price   as number | undefined) ?? 0;
    const role    = (after.order_role as string | undefined) ?? "entry";

    if (!userId) return;

    const token = await getUserFcmToken(userId);
    if (!token) return;

    const isFilled = newStatus === "complete";
    const isExit   = role === "exit";

    const title = isFilled
      ? (isExit
          ? `🏁 Position Closed: ${symbol}`
          : `✅ Order Filled: ${action} ${symbol}`)
      : `❌ Order Rejected: ${action} ${symbol}`;

    const body = isFilled
      ? (isExit
          ? `${qty} × ${symbol} sold @ ₹${price.toFixed(2)}`
          : `${qty} × ${symbol} ${action === "BUY" ? "bought" : "sold"} @ ₹${price.toFixed(2)}`)
      : `Your ${action} order for ${qty} ${symbol} was rejected. ${(after.rejection_reason as string | undefined) ?? ""}`.trim();

    await sendToDevice(token, title, body, {
      type:     isFilled ? (isExit ? "position_closed" : "order_filled") : "order_rejected",
      order_id: orderId,
      symbol,
      action,
    });
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// onStrategyEntryCheck  (was: onDropTriggerCheck)
//
// THE CORE ALGO ENGINE — runs every minute during market hours.
//
// Scans all user strategies with status == 'watching'.
// For each strategy:
//   1. Fetch current LTP for the strategy's symbol.
//   2. Evaluate entry condition:
//        'above'     → ltp >= entry_condition_price
//        'below'     → ltp <= entry_condition_price
//        'at_market' → always true (place immediately at market price)
//   3. On condition met:
//        a. Risk checks (algo enabled, max positions, max order value)
//        b. Broker credentials check
//        c. Call price-server POST /place-order
//        d. Write order to orders/{id}
//        e. Update strategy status: 'watching' → 'in_position'
//        f. Write entered_at, entry_ltp, entry_order_id onto the strategy
//        g. Send FCM push notification to user
//
// ALSO handles old drop_trigger format (drop_enabled: true, is_published: false)
// for backward-compatibility with any strategies created before this update.
// ─────────────────────────────────────────────────────────────────────────────

export const onStrategyEntryCheck = onSchedule(
  {
    schedule:       "every 1 minutes",
    region:         "us-central1",
    timeoutSeconds: 540,
  },
  async (_context) => {
    // ── Market hours gate (UTC) ───────────────────────────────────────────
    const now       = new Date();
    const dayOfWeek = now.getUTCDay();
    if (dayOfWeek === 0 || dayOfWeek === 6) {
      console.log("[EntryCheck] Weekend — skipping.");
      return;
    }
    const utcMins = now.getUTCHours() * 60 + now.getUTCMinutes();
    const MARKET_OPEN  = 3 * 60 + 40;  // 09:10 IST → 03:40 UTC
    const MARKET_CLOSE = 10 * 60 + 5;  // 15:35 IST → 10:05 UTC
    if (utcMins < MARKET_OPEN || utcMins > MARKET_CLOSE) {
      console.log(`[EntryCheck] Outside market hours — skipping.`);
      return;
    }

    const db   = getFirestore();
    const risk = await getRiskConfig();
    if (!risk.algo_enabled) {
      console.log("[EntryCheck] algo_enabled=false — skipping.");
      return;
    }

    // ── 1. Collect all watching strategies ───────────────────────────────
    // collectionGroup query across all users/{uid}/strategies
    // Requires Firestore composite index: (status ASC, stock.symbol ASC)
    interface WatchingStrategy {
      docRef:    FirebaseFirestore.DocumentReference;
      userId:    string;
      strategy:  UserStrategy;
      conditionType: "above" | "below" | "at_market";
      conditionPrice: number;
    }

    const watching: WatchingStrategy[] = [];

    try {
      // New architecture: status == 'watching'
      const newSnap = await db
        .collectionGroup("strategies")
        .where("status", "==", "watching")
        .get();

      for (const doc of newSnap.docs) {
        const d    = doc.data() as UserStrategy;
        const uid  = _extractUidFromPath(doc.ref.path);
        if (!uid) continue;
        const symbol = d.stock?.symbol ?? "";
        if (!symbol) continue;
        const condType  = d.entry_condition_type  ?? "above";
        const condPrice = d.entry_condition_price ?? d.trade?.entry_price ?? 0;
        watching.push({
          docRef:         doc.ref,
          userId:         uid,
          strategy:       d,
          conditionType:  condType,
          conditionPrice: condPrice,
        });
      }

      console.log(`[EntryCheck] Found ${watching.length} watching strategy/ies.`);
    } catch (err) {
      console.error("[EntryCheck] Failed to query strategies:", err instanceof Error ? err.message : err);
      return;
    }

    // Backward-compat: also handle old drop_enabled strategies
    try {
      const oldSnap = await db
        .collectionGroup("strategies")
        .where("drop_enabled", "==", true)
        .where("is_published", "==", false)
        .get();

      for (const doc of oldSnap.docs) {
        const d   = doc.data() as UserStrategy & {
          drop_enabled?: boolean;
          drop_trigger_type?: "above" | "below" | "in_range";
          drop_trigger_price?: number;
        };
        const uid = _extractUidFromPath(doc.ref.path);
        if (!uid) continue;
        const symbol = d.stock?.symbol ?? "";
        if (!symbol) continue;
        // Map old drop_trigger fields to new entry_condition fields
        const condType: "above" | "below" | "at_market" =
          d.drop_trigger_type === "below" ? "below" : "above";
        const condPrice = (d as any).drop_trigger_price ?? d.trade?.entry_price ?? 0;
        watching.push({
          docRef: doc.ref, userId: uid, strategy: d,
          conditionType: condType, conditionPrice: condPrice,
        });
      }
    } catch (err) {
      console.error("[EntryCheck] Failed to query legacy drop strategies:", err instanceof Error ? err.message : err);
    }

    if (watching.length === 0) {
      console.log("[EntryCheck] No strategies to check — done.");
      return;
    }

    // ── 2. Deduplicate symbols → fetch each LTP once ──────────────────────
    const symbolSet = new Set(watching.map((w) => w.strategy.stock?.symbol ?? ""));
    symbolSet.delete("");
    const ltpMap = new Map<string, number>();
    await Promise.all(
      Array.from(symbolSet).map(async (sym) => {
        const ltp = await fetchLtp(sym);
        if (ltp !== null) ltpMap.set(sym, ltp);
        else console.warn(`[EntryCheck] ${sym}: price unavailable.`);
      })
    );

    // ── 3. Evaluate & place orders ────────────────────────────────────────
    let enteredCount = 0;
    let skippedCount = 0;

    for (const w of watching) {
      const symbol = w.strategy.stock?.symbol ?? "";
      const ltp    = ltpMap.get(symbol);
      if (ltp == null) { skippedCount++; continue; }

      // ── Valid-till expiry check ───────────────────────────────────────────
      // ── Expiry check ─────────────────────────────────────────────────────────
      // Auto-expire watching strategies whose valid_till date has passed.
      const validTill = w.strategy.valid_till;
      if (validTill && validTill.toMillis() < Date.now()) {
        console.log(
          `[EntryCheck] ⏰ ${w.docRef.path}: valid_till expired (${validTill.toDate().toISOString()}) — expiring strategy.`
        );
        await w.docRef.update({
          status:            "closed",
          "meta.updated_at": FieldValue.serverTimestamp(),
          expired_at:        FieldValue.serverTimestamp(),
          expiry_reason:     "valid_till_exceeded",
        });
        // Notify the user
        const expToken = await getUserFcmToken(w.userId);
        if (expToken) {
          const expSym = w.strategy.stock?.name ?? w.strategy.stock?.symbol ?? "Strategy";
          await sendToDevice(expToken,
            `⏰ Strategy Expired: ${expSym}`,
            "Entry condition was not triggered before the expiry date you set.",
            { type: "strategy_expired", strategy_id: w.docRef.id }
          );
        }
        skippedCount++;
        continue;
      }

      // ── Re-entry wait check ───────────────────────────────────────────────
      // If this strategy was re-armed after a previous exit, it may have a
      // re_entry_not_before timestamp. Skip until that time has passed.
      const reEntryNotBefore = (w.strategy as any).re_entry_not_before as FirebaseFirestore.Timestamp | undefined;
      if (reEntryNotBefore && reEntryNotBefore.toMillis() > Date.now()) {
        console.log(
          `[EntryCheck] ${w.docRef.id}: re-entry wait active until ` +
          `${reEntryNotBefore.toDate().toISOString()} — skipping.`
        );
        skippedCount++;
        continue;
      }

      // ── Custom trading schedule check ─────────────────────────────────────
      // Honour the user's start_time, end_time, and trading_days settings.
      // If the current time is outside the configured window, skip this tick.
      if (!_isWithinTradingSchedule(w.strategy, utcMins, now.getUTCDay())) {
        console.log(
          `[EntryCheck] ${w.docRef.id}: outside trading schedule ` +
          `(start=${w.strategy.start_time ?? "default"} end=${w.strategy.end_time ?? "default"} ` +
          `days=${JSON.stringify(w.strategy.trading_days ?? [])}) — skipping.`
        );
        skippedCount++;
        continue;
      }

      // ── Entry condition check ─────────────────────────────────────────────
      // Step 1: Price-level trigger (above / below / at_market)
      const tol = ltp * 0.0005; // 0.05% tolerance
      let conditionMet = false;
      switch (w.conditionType) {
        case "above":     conditionMet = ltp >= w.conditionPrice - tol; break;
        case "below":     conditionMet = ltp <= w.conditionPrice + tol; break;
        case "at_market": conditionMet = true;                          break;
      }
      if (!conditionMet) { skippedCount++; continue; }

      // Step 2: Indicator-based entry conditions (Section 2 of the wizard).
      // Update the rolling state for this strategy, then evaluate all conditions.
      const indState = _getIndState(w.docRef.id);
      const prevLtp  = indState.prevClose;
      _pushPrice(indState, ltp);

      const entryConds = w.strategy.entry_conditions ?? [];
      if (entryConds.length > 0) {
        const indicatorsMet = _evalConditionsLive(entryConds, indState, ltp, prevLtp);
        if (!indicatorsMet) {
          console.log(
            `[EntryCheck] ${w.docRef.id}: price trigger met but indicator conditions not satisfied at ₹${ltp} — waiting.`
          );
          skippedCount++;
          continue;
        }
        console.log(`[EntryCheck] ${w.docRef.id}: price trigger AND indicator conditions met at ₹${ltp} ✅`);
      } else {
        console.log(
          `[EntryCheck] ✅ ${symbol} @ ₹${ltp} meets ${w.conditionType} ₹${w.conditionPrice} ` +
          `for user ${w.userId} (${w.docRef.path})`
        );
      }

      // ── Risk checks ──────────────────────────────────────────────────────
      try {
        // Check max open positions for this user
        const openCount = (await db.collection("positions")
          .where("user_id", "==", w.userId)
          .where("status", "==", "open")
          .count().get()).data().count ?? 0;
        if (openCount >= risk.max_open_positions) {
          console.warn(`[EntryCheck] ${w.userId}: max positions (${openCount}/${risk.max_open_positions}) — skip.`);
          skippedCount++;
          continue;
        }

        // ── Compute quantity from position sizing mode ──────────────────────
        // Resolves 'Fixed Lots', '% of Capital', or legacy quantity × lot_size.
        // Must be called AFTER we have the current LTP so % of Capital can
        // compute how many lots fit within the allocated capital.
        const finalQtyCheck = await _computeQuantity(w.strategy, ltp, risk);

        // Check max order value
        const orderVal = ltp * finalQtyCheck;
        if (orderVal > risk.max_order_value) {
          console.warn(`[EntryCheck] ${w.userId}: order value ₹${orderVal.toFixed(0)} > max ₹${risk.max_order_value} — skip.`);
          skippedCount++;
          continue;
        }

        // Check daily loss limit — halt new entries if today's loss already exceeded
        const dailyLoss = await getDailyLossRs(w.userId);
        if (dailyLoss >= risk.daily_loss_limit && risk.daily_loss_limit > 0) {
          console.warn(
            `[EntryCheck] ${w.userId}: daily loss ₹${dailyLoss.toFixed(0)} >= limit ₹${risk.daily_loss_limit.toFixed(0)} — halting new entries.`
          );
          skippedCount++;
          continue;
        }

        // ── MIS entry cutoff — no new intraday positions after 15:00 IST ──
        // 15:00 IST = 09:30 UTC. Opening MIS past this point risks broker
        // auto-squareoff before the user's target/SL is reached.
        const MIS_ENTRY_CUTOFF_UTC = 9 * 60 + 30; // 15:00 IST
        const isMISEntry = (w.strategy.product_type ?? "CNC").toUpperCase() === "MIS";
        if (isMISEntry && utcMins >= MIS_ENTRY_CUTOFF_UTC) {
          console.log(
            `[EntryCheck] ${w.userId}/${w.docRef.id}: MIS strategy — past 15:00 IST entry cutoff. ` +
            `Strategy will not enter today; resetting to watching for tomorrow.`
          );
          skippedCount++;
          continue;
        }

        // Check broker credentials
        // In paper trading mode, skip broker credential check entirely —
        // the price server will simulate the order without needing a session.
        // Paper mode is active when EITHER the global flag OR the per-strategy flag is set.
        const isStrategyPaper = risk.paper_trading || (w.strategy.paper_trade === true);
        if (!isStrategyPaper) {
          const creds = await getBrokerCredentials(w.userId);
          if (!creds) {
            console.warn(`[EntryCheck] ${w.userId}: no broker credentials — skip.`);
            skippedCount++;
            continue;
          }
          if (!creds.is_connected) {
            console.warn(`[EntryCheck] ${w.userId}: broker not connected — skip.`);
            skippedCount++;
            continue;
          }
        } else {
          console.log(`[EntryCheck] 📄 Paper trading ON — skipping broker credential check for ${w.userId}`);
        }

        // ── Place the entry order ────────────────────────────────────────

        // ── Place the entry order ────────────────────────────────────────
        const strategyDocId  = w.docRef.id;
        const action         = (w.strategy.trade?.action ?? "BUY").toUpperCase();
        const rawOrderType   = (w.strategy.trade?.order_type ?? "LIMIT").toUpperCase();
        const exchange       = w.strategy.stock?.exchange ?? "NSE";
        const isBracket      = w.strategy.bracket_order === true;
        const autoExecute    = w.strategy.auto_execute !== false; // default true

        // If auto_execute is disabled, just arm the strategy as watched but
        // skip actual order placement — it's a manual-tracking strategy.
        if (!autoExecute) {
          console.log(
            `[EntryCheck] ${w.userId}/${strategyDocId}: auto_execute=false — condition met, marking for manual entry.`
          );
          await w.docRef.update({
            status:           "in_position",
            entry_ltp:        ltp,
            entered_at:       FieldValue.serverTimestamp(),
            drop_enabled:     false,
            is_published:     true,
            "meta.updated_at": FieldValue.serverTimestamp(),
            "trade.current_price": ltp,
            manual_entry_required: true,
          });
          const token = await getUserFcmToken(w.userId);
          if (token) {
            const stockName = w.strategy.stock?.name ?? symbol;
            await sendToDevice(token,
              `📋 Entry Condition Met: ${symbol}`,
              `${stockName} has crossed your entry level at ₹${ltp.toFixed(2)} — manual order required`,
              { type: "manual_entry_required", strategy_id: strategyDocId, symbol }
            );
          }
          enteredCount++;
          continue;
        }

        // Determine effective entry price and order type
        // MARKET orders always execute at LTP; LIMIT uses the condition price.
        const isMarketOrder = rawOrderType === "MARKET";
        const isSLOrder     = rawOrderType === "SL" || rawOrderType === "SL-M";
        const entryPrice    = (isMarketOrder || w.conditionType === "at_market")
            ? ltp
            : w.conditionPrice;

        // For SL / SL-M orders the trigger_price is used as the stop-trigger.
        const triggerPrice = isSLOrder
            ? (w.strategy.trade?.trigger_price ?? entryPrice)
            : undefined;

        // Product type and validity — forwarded to the broker via price-server
        const productType = (w.strategy.product_type ?? "CNC").toUpperCase();
        const validity    = (w.strategy.validity     ?? "DAY").toUpperCase();

        // qty is already computed above as finalQtyCheck — reuse it
        const finalQty = finalQtyCheck;

        let result: PlaceOrderResult;
        try {
          result = await callPlaceOrder({
            userId:       w.userId,
            strategyId:   strategyDocId,
            symbol,
            exchange,
            action,
            orderType:    rawOrderType,
            quantity:     finalQty,
            price:        entryPrice,
            productType,
            validity,
            paperTrade:   isStrategyPaper,
            ...(triggerPrice !== undefined && { triggerPrice }),
          });
        } catch (orderErr) {
          const reason = orderErr instanceof Error ? orderErr.message : String(orderErr);
          console.error(`[EntryCheck] Price-server error for ${w.userId}/${strategyDocId}: ${reason}`);
          await writeOrderDoc(`${strategyDocId}_${w.userId}_${Date.now()}`, {
            strategyId: strategyDocId, userId: w.userId, symbol, exchange,
            action, orderType: rawOrderType, quantity: finalQty, price: entryPrice,
            angelOrderId: null, status: "rejected",
            rejectionReason: `Entry order failed: ${reason}`,
            orderRole: "entry",
            productType,
            validity,
          });
          skippedCount++;
          continue;
        }

        // Write the entry order doc
        await writeOrderDoc(result.firestoreOrderId, {
          strategyId: strategyDocId, userId: w.userId, symbol, exchange,
          action, orderType: rawOrderType, quantity: finalQty, price: entryPrice,
          angelOrderId: result.angelOrderId, status: result.status ?? "complete",
          orderRole: "entry",
          productType,
          validity,
          paperTrade: isStrategyPaper,
          ...(triggerPrice !== undefined && { triggerPrice }),
        });

        // For bracket orders: also place the linked SL and target orders
        if (isBracket) {
          const slPrice     = w.strategy.bracket_sl     ?? w.strategy.analysis?.stoploss     ?? 0;
          const targetPrice = w.strategy.bracket_target ?? w.strategy.analysis?.target ?? 0;
          const exitAction  = action === "BUY" ? "SELL" : "BUY";

          if (slPrice > 0) {
            try {
              const slResult = await callPlaceOrder({
                userId: w.userId, strategyId: strategyDocId, symbol, exchange,
                action: exitAction, orderType: "SL-M",
                quantity: finalQty, price: slPrice, triggerPrice: slPrice,
                productType, validity,
              });
              await writeOrderDoc(slResult.firestoreOrderId, {
                strategyId: strategyDocId, userId: w.userId, symbol, exchange,
                action: exitAction, orderType: "SL-M", quantity: finalQty,
                price: slPrice, angelOrderId: slResult.angelOrderId,
                status: slResult.status ?? "complete", orderRole: "bracket_sl",
                productType, validity,
              });
              console.log(`[EntryCheck] Bracket SL order placed for ${strategyDocId}: ${slResult.firestoreOrderId}`);
            } catch (err) {
              console.error(`[EntryCheck] Bracket SL order failed for ${strategyDocId}:`, err instanceof Error ? err.message : err);
            }
          }

          if (targetPrice > 0) {
            try {
              const tgtResult = await callPlaceOrder({
                userId: w.userId, strategyId: strategyDocId, symbol, exchange,
                action: exitAction, orderType: "LIMIT",
                quantity: finalQty, price: targetPrice,
                productType, validity,
              });
              await writeOrderDoc(tgtResult.firestoreOrderId, {
                strategyId: strategyDocId, userId: w.userId, symbol, exchange,
                action: exitAction, orderType: "LIMIT", quantity: finalQty,
                price: targetPrice, angelOrderId: tgtResult.angelOrderId,
                status: tgtResult.status ?? "complete", orderRole: "bracket_target",
                productType, validity,
              });
              console.log(`[EntryCheck] Bracket target order placed for ${strategyDocId}: ${tgtResult.firestoreOrderId}`);
            } catch (err) {
              console.error(`[EntryCheck] Bracket target order failed for ${strategyDocId}:`, err instanceof Error ? err.message : err);
            }
          }
        }

        // For trailing SL: seed the initial trailing_sl_current value
        const trailEnabled = w.strategy.trailing_sl_enabled === true;
        const trailValue   = w.strategy.trailing_sl_value ?? 0;
        const trailMode    = w.strategy.trailing_sl_mode ?? "points";
        let trailSlCurrent: number | null = null;
        if (trailEnabled && trailValue > 0) {
          const sl = w.strategy.analysis?.stoploss ?? 0;
          trailSlCurrent = sl > 0 ? sl : (
            trailMode === "pct"
              ? entryPrice * (1 - trailValue / 100)
              : entryPrice - trailValue
          );
        }

        // Update strategy: watching → in_position
        // entry_qty is stamped here so the position monitor can read the
        // exact quantity to use for the exit order — critical when the
        // entry quantity was computed from % of Capital at runtime.
        await w.docRef.update({
          status:                "in_position",
          entry_order_id:        result.firestoreOrderId,
          entry_ltp:             ltp,
          entry_qty:             finalQty,
          entered_at:            FieldValue.serverTimestamp(),
          drop_enabled:          false,
          is_published:          true,
          dropped_at:            FieldValue.serverTimestamp(),
          "meta.updated_at":     FieldValue.serverTimestamp(),
          "trade.current_price": ltp,
          ...(trailSlCurrent !== null && { trailing_sl_current: trailSlCurrent }),
        });

        // Clean up in-memory indicator state — no longer needed after entry
        _indStateMap.delete(w.docRef.id);

        enteredCount++;
        console.log(
          `[EntryCheck] Order placed for ${w.userId}/${strategyDocId}: ` +
          `${action} ${finalQty}×${symbol} @ ₹${entryPrice} → orderId=${result.firestoreOrderId}`
        );

        // Send push notification + persist to notifications collection
        const isPaper     = isStrategyPaper;
        const entryTitle  = isPaper
          ? `📄 Paper Trade: ${action} ${symbol}`
          : `🚀 Order Placed: ${action} ${symbol}`;
        const entryBody   = isPaper
          ? `Paper trade entry at ₹${ltp.toFixed(2)} · ${finalQty} × ${(w.strategy.stock?.name ?? symbol)} · no real money moved`
          : `Entry at ₹${ltp.toFixed(2)} · ${finalQty} × ${(w.strategy.stock?.name ?? symbol)} · monitoring started`;

        const token = await getUserFcmToken(w.userId);
        if (token) {
          const stockName = w.strategy.stock?.name ?? symbol;
          await sendToDevice(token,
            entryTitle,
            isPaper
              ? `Paper trade entry at ₹${ltp.toFixed(2)} · ${finalQty} × ${stockName} · no real money moved`
              : `Entry at ₹${ltp.toFixed(2)} · ${finalQty} × ${stockName} · Target & SL are being monitored`,
            { type: isPaper ? "paper_order_placed" : "order_placed", strategy_id: strategyDocId, symbol }
          );
        }
        // Persist to notifications collection regardless of FCM token presence
        await _persistNotification({
          userId:     w.userId,
          title:      entryTitle,
          body:       entryBody,
          type:       isPaper ? "paper_order_placed" : "order_placed",
          strategyId: strategyDocId,
          symbol,
        });
      } catch (err) {
        console.error(
          `[EntryCheck] Unexpected error for ${w.userId}/${w.docRef.id}:`,
          err instanceof Error ? err.message : err
        );
        skippedCount++;
      }
    }

    console.log(
      `[EntryCheck] Done — ${enteredCount} entered, ${skippedCount} skipped out of ${watching.length} strategies.`
    );
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// onPositionMonitor
//
// NEW — runs every minute during market hours.
//
// Scans all user strategies with status == 'in_position'.
// For each:
//   1. Fetch current LTP.
//   2. Check if LTP >= target (for BUY) or <= target (for SELL).
//      → Place exit (SELL/BUY) order, update strategy status: 'target_hit'
//   3. Check if LTP <= stoploss (for BUY) or >= stoploss (for SELL).
//      → Place exit order, update strategy status: 'sl_hit'
//   4. Calculate realised P&L and write to the strategy doc.
//   5. Send FCM push notification to user.
// ─────────────────────────────────────────────────────────────────────────────

export const onPositionMonitor = onSchedule(
  {
    schedule:       "every 1 minutes",
    region:         "us-central1",
    timeoutSeconds: 540,
  },
  async (_context) => {
    // ── Market hours gate ─────────────────────────────────────────────────
    const now       = new Date();
    const dayOfWeek = now.getUTCDay();
    if (dayOfWeek === 0 || dayOfWeek === 6) return;
    const utcMins = now.getUTCHours() * 60 + now.getUTCMinutes();
    if (utcMins < 3 * 60 + 40 || utcMins > 10 * 60 + 5) return;

    const db   = getFirestore();
    const risk = await getRiskConfig();
    if (!risk.algo_enabled) return;

    // ── 1. Collect all in_position strategies ─────────────────────────────
    interface ActivePosition {
      docRef:  FirebaseFirestore.DocumentReference;
      userId:  string;
      data:    UserStrategy;
    }

    const positions: ActivePosition[] = [];

    try {
      const snap = await db
        .collectionGroup("strategies")
        .where("status", "==", "in_position")
        .get();

      for (const doc of snap.docs) {
        const d   = doc.data() as UserStrategy;
        const uid = _extractUidFromPath(doc.ref.path);
        if (!uid) continue;
        positions.push({ docRef: doc.ref, userId: uid, data: d });
      }

      console.log(`[PositionMonitor] Monitoring ${positions.length} active position(s).`);
    } catch (err) {
      console.error("[PositionMonitor] Query failed:", err instanceof Error ? err.message : err);
      return;
    }

    if (positions.length === 0) return;

    // ── 2. Deduplicate symbols → fetch each LTP once ──────────────────────
    const symbolSet = new Set(positions.map((p) => p.data.stock?.symbol ?? ""));
    symbolSet.delete("");
    const ltpMap = new Map<string, number>();
    await Promise.all(
      Array.from(symbolSet).map(async (sym) => {
        const ltp = await fetchLtp(sym);
        if (ltp !== null) ltpMap.set(sym, ltp);
      })
    );

    // ── 3. Check each position ────────────────────────────────────────────
    let closedCount  = 0;
    let monitorCount = 0;

    for (const pos of positions) {
      const symbol = pos.data.stock?.symbol ?? "";
      const ltp    = ltpMap.get(symbol);
      if (ltp == null) { monitorCount++; continue; }

      const target   = pos.data.analysis?.target   ?? 0;
      const stoploss = pos.data.analysis?.stoploss  ?? 0;
      const isBuy    = (pos.data.trade?.action ?? "BUY").toUpperCase() === "BUY";
      // Use entry_qty (stamped by onStrategyEntryCheck) so the exit quantity
      // exactly matches what was entered — critical for % of Capital strategies
      // where the lot count was computed from LTP at entry time, not from a
      // fixed field. Fall back to legacy quantity field for older strategies.
      const qty      = pos.data.entry_qty ?? pos.data.quantity ?? 1;
      const entryLtp = pos.data.entry_ltp ?? pos.data.trade?.entry_price ?? ltp;

      // ── Trailing SL: ratchet up the SL as price moves in favour ─────────
      let effectiveSL = stoploss;
      const trailEnabled = pos.data.trailing_sl_enabled === true;
      const trailValue   = pos.data.trailing_sl_value ?? 0;
      const trailMode    = pos.data.trailing_sl_mode ?? "points";
      const currentTrailSL = pos.data.trailing_sl_current ?? stoploss;

      if (trailEnabled && trailValue > 0) {
        // Compute where the trailing SL should be based on current LTP
        let newTrailSL: number;
        if (trailMode === "pct") {
          newTrailSL = isBuy
            ? ltp * (1 - trailValue / 100)
            : ltp * (1 + trailValue / 100);
        } else {
          newTrailSL = isBuy
            ? ltp - trailValue
            : ltp + trailValue;
        }

        // Only ratchet in the favourable direction (never loosen the SL)
        if (isBuy && newTrailSL > currentTrailSL) {
          await pos.docRef.update({ trailing_sl_current: newTrailSL });
          effectiveSL = newTrailSL;
        } else if (!isBuy && newTrailSL < currentTrailSL) {
          await pos.docRef.update({ trailing_sl_current: newTrailSL });
          effectiveSL = newTrailSL;
        } else {
          effectiveSL = currentTrailSL;
        }
      }

      // ── Locked Profit Floor ───────────────────────────────────────────────
      // Once floating profit reaches locked_profit_trigger_rs, we dynamically
      // raise the effective SL so the position cannot close below
      // locked_profit_floor_rs profit.
      const lockedTrigger = pos.data.locked_profit_trigger_rs ?? 0;
      const lockedFloor   = pos.data.locked_profit_floor_rs   ?? 0;
      const lockedAlready = pos.data.locked_profit_active     === true;

      if (lockedTrigger > 0 && lockedFloor >= 0) {
        const floatingPnl = isBuy
          ? (ltp - entryLtp) * qty
          : (entryLtp - ltp) * qty;

        if (floatingPnl >= lockedTrigger || lockedAlready) {
          // Compute the SL price that corresponds to locking in lockedFloor ₹
          // For BUY:  SL_price = entryLtp + lockedFloor / qty
          // For SELL: SL_price = entryLtp - lockedFloor / qty
          const lockSlPrice = qty > 0
            ? (isBuy
                ? entryLtp + lockedFloor / qty
                : entryLtp - lockedFloor / qty)
            : effectiveSL;

          // Raise the effective SL to lock the floor (never lower it)
          if (isBuy  && lockSlPrice > effectiveSL) effectiveSL = lockSlPrice;
          if (!isBuy && lockSlPrice < effectiveSL) effectiveSL = lockSlPrice;

          if (!lockedAlready) {
            // First time locking — write the flag to Firestore
            await pos.docRef.update({ locked_profit_active: true });
            console.log(
              `[PositionMonitor] 🔒 Locked profit for ${pos.userId}/${pos.docRef.id}: ` +
              `floatingPnl=₹${floatingPnl.toFixed(0)} >= trigger=₹${lockedTrigger} → lockSL=₹${lockSlPrice.toFixed(2)}`
            );
          }
        }
      }

      // ── MIS auto-squareoff check ──────────────────────────────────────
      // Angel One auto-squares MIS positions at ~15:20 IST (09:50 UTC).
      // We proactively exit at 15:15 IST (09:45 UTC) to avoid broker
      // auto-squareoff at potentially worse slippage.
      // MIS_SQUAREOFF_UTC = 9h 45m = 585 minutes
      const MIS_SQUAREOFF_UTC = 9 * 60 + 45;
      const isMIS = (pos.data.product_type ?? "CNC").toUpperCase() === "MIS";
      if (isMIS && utcMins >= MIS_SQUAREOFF_UTC) {
        console.log(
          `[PositionMonitor] MIS squareoff triggered for ${pos.userId}/${pos.docRef.id} ` +
          `(${symbol} @ ₹${ltp}) — past 15:15 IST cutoff.`
        );

        try {
          const isPosStrategyPaper = risk.paper_trading || (pos.data.paper_trade === true);
          let brokerReady = isPosStrategyPaper;
          if (!brokerReady) {
            const creds = await getBrokerCredentials(pos.userId);
            brokerReady = !!(creds?.is_connected);
          }

          const exitAction      = isBuy ? "SELL" : "BUY";
          const exchange        = pos.data.stock?.exchange ?? "NSE";
          const strategyId      = pos.docRef.id;
          const qty             = pos.data.entry_qty ?? pos.data.quantity ?? 1;
          const entryLtp        = pos.data.entry_ltp ?? pos.data.trade?.entry_price ?? ltp;

          if (brokerReady) {
            const misResult = await callPlaceOrder({
              userId:      pos.userId,
              strategyId,
              symbol,
              exchange,
              action:      exitAction,
              orderType:   "MARKET",
              quantity:    qty,
              price:       ltp,
              productType: "MIS",
              validity:    "DAY",
              paperTrade:  isPosStrategyPaper,
            });

            await writeOrderDoc(misResult.firestoreOrderId, {
              strategyId, userId: pos.userId, symbol, exchange,
              action: exitAction, orderType: "MARKET", quantity: qty, price: ltp,
              angelOrderId: misResult.angelOrderId, status: misResult.status ?? "complete",
              orderRole:   "exit",
              productType: "MIS",
              validity:    "DAY",
              paperTrade:  isPosStrategyPaper,
            });
          }

          // P&L calculation
          const pnlRs  = isBuy
            ? (ltp - entryLtp) * qty
            : (entryLtp - ltp) * qty;
          const pnlPct = entryLtp > 0 ? (pnlRs / (entryLtp * qty)) * 100 : 0;

          await pos.docRef.update({
            status:                "closed",
            exit_reason:           "mis_squareoff",
            exit_ltp:              ltp,
            exited_at:             FieldValue.serverTimestamp(),
            realised_pnl_rs:       pnlRs,
            realised_pnl_pct:      pnlPct,
            "trade.exit_price":    ltp,
            "trade.current_price": ltp,
            "meta.updated_at":     FieldValue.serverTimestamp(),
          });

          // FCM notification
          const stockName = pos.data.stock?.name ?? symbol;
          const isProfit  = pnlRs >= 0;
          const sqTitle   = `${isPosStrategyPaper ? "📄 Paper " : "🕐 "}Intraday Closed: ${symbol}`;
          const sqBody    = `MIS position squared off before market close · ${qty} × ${stockName} @ ₹${ltp.toFixed(2)} · P&L: ${isProfit ? "+" : ""}₹${pnlRs.toFixed(2)} (${pnlPct.toFixed(2)}%)`;

          const token = await getUserFcmToken(pos.userId);
          if (token) {
            await sendToDevice(token, sqTitle, sqBody, {
              type:        "mis_squareoff",
              strategy_id: strategyId,
              symbol,
              pnl:         pnlRs.toFixed(2),
            });
          }
          await _persistNotification({
            userId:     pos.userId,
            title:      sqTitle,
            body:       sqBody,
            type:       "mis_squareoff",
            strategyId,
            symbol,
            pnl:        pnlRs,
          });

          closedCount++;
        } catch (err) {
          console.error(
            `[PositionMonitor] MIS squareoff error for ${pos.userId}/${pos.docRef.id}:`,
            err instanceof Error ? err.message : err
          );
          // Mark closed anyway — broker will auto-squareoff, don't keep retrying
          await pos.docRef.update({
            status:            "closed",
            exit_reason:       "mis_squareoff",
            exit_ltp:          ltp,
            exited_at:         FieldValue.serverTimestamp(),
            "meta.updated_at": FieldValue.serverTimestamp(),
          });
          closedCount++;
        }
        continue;
      }

      // Determine exit condition
      let exitReason: "target_hit" | "sl_hit" | null = null;
      if (target > 0) {
        const targetHit = isBuy ? ltp >= target : ltp <= target;
        if (targetHit) exitReason = "target_hit";
      }
      if (!exitReason && effectiveSL > 0) {
        const slHit = isBuy ? ltp <= effectiveSL : ltp >= effectiveSL;
        if (slHit) exitReason = "sl_hit";
      }

      // ── Per-strategy Max Loss cap ─────────────────────────────────────────
      // Exit immediately if the per-strategy max_loss_rs threshold is breached.
      // This fires regardless of the static SL level — a safety hard-stop.
      if (!exitReason) {
        const maxLossRs = pos.data.max_loss_rs ?? 0;
        if (maxLossRs > 0) {
          const floatingPnl = isBuy
            ? (ltp - entryLtp) * qty
            : (entryLtp - ltp) * qty;
          if (floatingPnl <= -maxLossRs) {
            console.log(
              `[PositionMonitor] 🛑 Max loss hit for ${pos.userId}/${pos.docRef.id}: ` +
              `floatingPnl=₹${floatingPnl.toFixed(0)} <= -maxLoss=₹${maxLossRs} — force exit as sl_hit.`
            );
            exitReason = "sl_hit";
          }
        }
      }

      // ── Indicator-based exit conditions (Section 2, Exit tab) ────────────
      // Evaluate exit_conditions array — if any condition is met, exit as
      // target_hit (graceful exit when user's exit signal fires).
      if (!exitReason) {
        const exitConds = pos.data.exit_conditions ?? [];
        if (exitConds.length > 0) {
          const posIndState = _getIndState(`${pos.docRef.id}_exit`);
          const prevLtp     = posIndState.prevClose;
          _pushPrice(posIndState, ltp);
          const exitSignal = _evalConditionsLive(exitConds, posIndState, ltp, prevLtp);
          if (exitSignal) {
            console.log(
              `[PositionMonitor] 📊 Exit conditions met for ${pos.userId}/${pos.docRef.id} ` +
              `at ₹${ltp} — closing as target_hit.`
            );
            exitReason = "target_hit";
          }
        }
      }

      if (!exitReason) { monitorCount++; continue; }

      console.log(
        `[PositionMonitor] ${symbol} @ ₹${ltp}: ${exitReason} for user ${pos.userId} ` +
        `(target=${target}, sl=${stoploss})`
      );

      // ── Place exit order ──────────────────────────────────────────────
      // Note: we ALWAYS exit on SL hit regardless of daily loss limit.
      // We skip target exits when daily loss limit is breached so the
      // user is still protected, but not locked out of closing losing trades.
      if (exitReason === "target_hit" && risk.daily_loss_limit > 0) {
        const dailyLoss = await getDailyLossRs(pos.userId);
        if (dailyLoss >= risk.daily_loss_limit) {
          console.log(
            `[PositionMonitor] ${pos.userId}: daily loss ₹${dailyLoss.toFixed(0)} >= limit — ` +
            `target exit deferred (SL exits still active).`
          );
          monitorCount++;
          continue;
        }
      }

      try {
        // In paper trading mode, skip broker credentials — the price server
        // will simulate the exit order with no real Angel One call.
        // Check BOTH the global flag and the per-strategy flag.
        const isPosStrategyPaper = risk.paper_trading || (pos.data.paper_trade === true);
        let brokerReady = isPosStrategyPaper;
        if (!brokerReady) {
          const creds = await getBrokerCredentials(pos.userId);
          brokerReady = !!(creds?.is_connected);
        }

        if (!brokerReady) {
          // Broker not connected in live mode — update status anyway so we don't keep retrying
          console.warn(`[PositionMonitor] ${pos.userId}: no broker — marking ${exitReason} without exit order.`);
          await pos.docRef.update({
            status:              exitReason,
            exit_ltp:            ltp,
            exited_at:           FieldValue.serverTimestamp(),
            "meta.updated_at":   FieldValue.serverTimestamp(),
            "trade.current_price": ltp,
            "trade.exit_price":  ltp,
          });
          closedCount++;
          continue;
        }

        const exitAction       = isBuy ? "SELL" : "BUY";
        const exchange         = pos.data.stock?.exchange ?? "NSE";
        const strategyId       = pos.docRef.id;
        const orderType        = "MARKET"; // exit orders are always market
        // Mirror the product type from the original strategy so the broker
        // routes the exit correctly (MIS exits must stay MIS, NRML → NRML, etc.)
        const exitProductType  = (pos.data.product_type ?? "CNC").toUpperCase();
        const exitValidity     = "DAY";

        let result: PlaceOrderResult;
        try {
          result = await callPlaceOrder({
            userId:      pos.userId,
            strategyId,
            symbol,
            exchange,
            action:      exitAction,
            orderType,
            quantity:    qty,
            price:       ltp,
            productType: exitProductType,
            validity:    exitValidity,
            paperTrade:  isPosStrategyPaper,
          });
        } catch (orderErr) {
          const reason = orderErr instanceof Error ? orderErr.message : String(orderErr);
          console.error(`[PositionMonitor] Exit order failed for ${pos.userId}/${strategyId}: ${reason}`);
          // Still update strategy status so we don't re-trigger next minute
          await pos.docRef.update({
            status:            exitReason,
            exit_ltp:          ltp,
            exited_at:         FieldValue.serverTimestamp(),
            "meta.updated_at": FieldValue.serverTimestamp(),
          });
          closedCount++;
          continue;
        }

        // Write exit order doc
        await writeOrderDoc(result.firestoreOrderId, {
          strategyId, userId: pos.userId, symbol, exchange,
          action: exitAction, orderType, quantity: qty, price: ltp,
          angelOrderId: result.angelOrderId, status: result.status ?? "complete",
          orderRole: "exit",
          productType: exitProductType,
          validity:    exitValidity,
          paperTrade:  isPosStrategyPaper,
        });

        // Calculate realised P&L
        const pnlRs  = isBuy
          ? (ltp - entryLtp) * qty
          : (entryLtp - ltp) * qty;
        const pnlPct = entryLtp > 0 ? (pnlRs / (entryLtp * qty)) * 100 : 0;

        // Update strategy doc
        await pos.docRef.update({
          status:              exitReason,
          exit_order_id:       result.firestoreOrderId,
          exit_ltp:            ltp,
          exited_at:           FieldValue.serverTimestamp(),
          realised_pnl_rs:     pnlRs,
          realised_pnl_pct:    pnlPct,
          "trade.exit_price":  ltp,
          "trade.current_price": ltp,
          "meta.updated_at":   FieldValue.serverTimestamp(),
        });

        closedCount++;
        console.log(
          `[PositionMonitor] ${exitReason} for ${pos.userId}/${strategyId}: ` +
          `exit @ ₹${ltp}, P&L = ₹${pnlRs.toFixed(2)} (${pnlPct.toFixed(2)}%)`
        );

        // Send push notification + persist to notifications collection
        const isPaperExit = isPosStrategyPaper;
        const stockName   = pos.data.stock?.name ?? symbol;
        const isProfit    = pnlRs >= 0;
        const exitTitle   = exitReason === "target_hit"
          ? `${isPaperExit ? "📄 Paper " : "🎯 "}Target Hit: ${symbol} +₹${Math.abs(pnlRs).toFixed(0)}`
          : `${isPaperExit ? "📄 Paper " : "🛡 "}Stop-Loss Hit: ${symbol} -₹${Math.abs(pnlRs).toFixed(0)}`;
        const exitBody    = `${qty} × ${stockName} closed @ ₹${ltp.toFixed(2)} · P&L: ${isProfit ? "+" : ""}₹${pnlRs.toFixed(2)} (${pnlPct.toFixed(2)}%)${isPaperExit ? " · paper trade" : ""}`;

        const token = await getUserFcmToken(pos.userId);
        if (token) {
          await sendToDevice(token, exitTitle, exitBody, {
            type:        exitReason,
            strategy_id: strategyId,
            symbol,
            pnl:         pnlRs.toFixed(2),
          });
        }
        // Persist trade result to notifications collection
        await _persistNotification({
          userId:     pos.userId,
          title:      exitTitle,
          body:       exitBody,
          type:       exitReason,
          strategyId,
          symbol,
          pnl:        pnlRs,
        });

        // ── Re-entry logic ─────────────────────────────────────────────────
        // If the user enabled re-entry and hasn't exceeded max re-entries,
        // reset the strategy back to 'watching' after the configured delay.
        // The delay is implemented via a simple timestamp on the strategy doc —
        // the entry check engine respects re_entry_not_before and skips the
        // strategy until the time has passed.
        const reEntryEnabled = pos.data.re_entry === true;
        const reEntryCount   = pos.data.re_entry_count  ?? 0;  // 0 = unlimited
        const reEntryUsed    = pos.data.re_entry_used   ?? 0;
        const reEntryMode    = pos.data.re_entry_mode   ?? "time";
        const reEntryWaitMin = pos.data.re_entry_wait_min ?? 5;

        const withinReEntryLimit = reEntryCount === 0 || reEntryUsed < reEntryCount;

        if (reEntryEnabled && withinReEntryLimit) {
          const waitMs     = reEntryMode === "time" ? reEntryWaitMin * 60 * 1000 : 0;
          const notBefore  = new Date(Date.now() + waitMs);

          // Reset strategy to 'watching' — engine will re-enter when conditions are met again
          await pos.docRef.update({
            status:                 "watching",
            re_entry_used:          reEntryUsed + 1,
            re_entry_not_before:    Timestamp.fromDate(notBefore),
            // Clear runtime entry fields so the next entry is fresh
            entry_order_id:         FieldValue.delete(),
            entry_ltp:              FieldValue.delete(),
            entry_qty:              FieldValue.delete(),
            entered_at:             FieldValue.delete(),
            exit_ltp:               FieldValue.delete(),
            exit_order_id:          FieldValue.delete(),
            exited_at:              FieldValue.delete(),
            realised_pnl_rs:        FieldValue.delete(),
            realised_pnl_pct:       FieldValue.delete(),
            trailing_sl_current:    FieldValue.delete(),
            locked_profit_active:   FieldValue.delete(),
            "meta.updated_at":      FieldValue.serverTimestamp(),
          });

          console.log(
            `[PositionMonitor] 🔁 Re-entry armed for ${pos.userId}/${strategyId}: ` +
            `used=${reEntryUsed + 1}/${reEntryCount === 0 ? "∞" : reEntryCount} ` +
            `mode=${reEntryMode} notBefore=${notBefore.toISOString()}`
          );
        }

        // Clean up exit indicator state for this position
        _indStateMap.delete(`${pos.docRef.id}_exit`);
      } catch (err) {
        console.error(
          `[PositionMonitor] Unexpected error for ${pos.userId}/${pos.docRef.id}:`,
          err instanceof Error ? err.message : err
        );
        monitorCount++;
      }
    }

    console.log(
      `[PositionMonitor] Done — ${closedCount} closed, ${monitorCount} still open out of ${positions.length}.`
    );
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// _normCond
//
// Normalise a condition object — handle both snake_case (from Dart toMap())
// and camelCase field names so both work transparently.
// ─────────────────────────────────────────────────────────────────────────────

interface NormCond {
  lhsType:   string;
  indicator: string;
  lhsPrice:  string;
  paramA:    string;
  paramB:    string;
  paramC:    string;
  candleSrc: string;
  op:        string;
  rhsNone:   boolean;
  rhsIsInd:  boolean;
  valueA:    string;
  valueB:    string;
  rhsPeriod: string;
  logic:     string;
}

function _normCond(c: StrategyCondition): NormCond {
  return {
    lhsType:   c.lhs_type        ?? c.lhsType   ?? "Indicator",
    indicator: c.indicator       ?? "",
    lhsPrice:  c.lhs_price       ?? c.lhsPrice  ?? "Close",
    paramA:    c.param_a         ?? c.paramA    ?? "14",
    paramB:    c.param_b         ?? c.paramB    ?? "14",
    paramC:    c.param_c         ?? c.paramC    ?? "9",
    candleSrc: c.candle_src      ?? c.candleSrc ?? "Current Candle",
    op:        c.operator        ?? ">" ,
    rhsNone:   c.rhs_none        ?? c.rhsNone   ?? false,
    rhsIsInd:  c.rhs_is_indicator ?? c.rhsIsInd ?? false,
    valueA:    c.value_a         ?? c.valueA    ?? "0",
    valueB:    c.value_b         ?? c.valueB    ?? "",
    rhsPeriod: c.rhs_period      ?? c.rhsPeriod ?? "14",
    logic:     c.logic           ?? "AND",
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// _emaStep
//
// Incremental single-step EMA calculation using Wilder smoothing factor.
// k = 2 / (period + 1)
// ─────────────────────────────────────────────────────────────────────────────

function _emaStep(prev: number, current: number, period: number): number {
  const k = 2 / (period + 1);
  return current * k + prev * (1 - k);
}

// ─────────────────────────────────────────────────────────────────────────────
// _IndicatorState
//
// Holds rolling state for incremental indicator calculation at runtime.
// Instead of fetching full OHLCV history from Angel One in every tick, we
// maintain a sliding window of the last N LTP values and compute indicator
// values incrementally.
//
// State is stored in memory per strategy, keyed by strategyId.
// It is flushed when a strategy enters a position (no longer needed for entry).
// ─────────────────────────────────────────────────────────────────────────────

interface IndicatorState {
  // Sliding window of recent close prices (up to maxWindow)
  closes:        number[];
  // Incremental EMA state: keyed by period
  emas:          Record<number, number>;
  // Incremental RSI state: keyed by period
  rsiAvgGain:    Record<number, number>;
  rsiAvgLoss:    Record<number, number>;
  rsiCount:      Record<number, number>;
  // Previous close for RSI diff
  prevClose:     number | null;
  // Candle count pushed (for warm-up tracking)
  count:         number;
}

// In-memory state store — reset on cold start, that's fine for a 1-min engine
const _indStateMap = new Map<string, IndicatorState>();

function _getIndState(stratId: string): IndicatorState {
  if (!_indStateMap.has(stratId)) {
    _indStateMap.set(stratId, {
      closes: [], emas: {}, rsiAvgGain: {}, rsiAvgLoss: {}, rsiCount: {},
      prevClose: null, count: 0,
    });
  }
  return _indStateMap.get(stratId)!;
}

function _pushPrice(state: IndicatorState, price: number, maxWindow = 200): void {
  state.closes.push(price);
  if (state.closes.length > maxWindow) state.closes.shift();

  // ── Update RSI states ──────────────────────────────────────────────────────
  if (state.prevClose !== null) {
    const diff = price - state.prevClose;
    const gain = diff > 0 ? diff : 0;
    const loss = diff < 0 ? Math.abs(diff) : 0;

    for (const pStr of Object.keys(state.rsiAvgGain)) {
      const p = parseInt(pStr);
      if (state.rsiCount[p] < p) {
        // Accumulation phase: simple average
        state.rsiAvgGain[p] = (state.rsiAvgGain[p] * state.rsiCount[p] + gain) / (state.rsiCount[p] + 1);
        state.rsiAvgLoss[p] = (state.rsiAvgLoss[p] * state.rsiCount[p] + loss) / (state.rsiCount[p] + 1);
        state.rsiCount[p]++;
      } else {
        // Wilder smooth
        state.rsiAvgGain[p] = (state.rsiAvgGain[p] * (p - 1) + gain) / p;
        state.rsiAvgLoss[p] = (state.rsiAvgLoss[p] * (p - 1) + loss) / p;
      }
    }

    // ── Update EMA states ────────────────────────────────────────────────────
    for (const pStr of Object.keys(state.emas)) {
      const p = parseInt(pStr);
      if (state.closes.length >= p) {
        state.emas[p] = _emaStep(state.emas[p], price, p);
      }
    }
  }

  state.prevClose = price;
  state.count++;
}

/** Seed RSI state for period p if not already present. */
function _ensureRsi(state: IndicatorState, period: number): void {
  if (!(period in state.rsiAvgGain)) {
    state.rsiAvgGain[period] = 0;
    state.rsiAvgLoss[period] = 0;
    state.rsiCount[period]   = 0;
  }
}

/** Seed EMA state for period p if not already present. */
function _ensureEma(state: IndicatorState, period: number, initPrice: number): void {
  if (!(period in state.emas)) {
    // Seed with SMA of available closes or just the current price
    if (state.closes.length >= period) {
      const slice = state.closes.slice(-period);
      state.emas[period] = slice.reduce((a, b) => a + b, 0) / period;
    } else {
      state.emas[period] = initPrice;
    }
  }
}

// ── Compute a single indicator value from current rolling state ───────────────

function _indValueFromState(
  indicator: string,
  paramA: string,
  state: IndicatorState,
  currentPrice: number
): number | null {
  const period = parseInt(paramA) || 14;
  const closes = state.closes;
  const n = closes.length;

  switch (indicator) {
    case "EMA": {
      _ensureEma(state, period, currentPrice);
      if (n < Math.min(period, 3)) return null; // not enough data yet
      return state.emas[period] ?? null;
    }
    case "SMA": {
      if (n < period) return null;
      const slice = closes.slice(-period);
      return slice.reduce((a, b) => a + b, 0) / period;
    }
    case "RSI": {
      _ensureRsi(state, period);
      if (state.rsiCount[period] < period) return null; // still warming up
      const avgGain = state.rsiAvgGain[period];
      const avgLoss = state.rsiAvgLoss[period];
      if (avgLoss === 0) return 100;
      const rs = avgGain / avgLoss;
      return 100 - 100 / (1 + rs);
    }
    case "MACD": {
      // MACD line = EMA(fast=paramA) - EMA(slow=26)
      const fast = period;
      const slow = 26;
      _ensureEma(state, fast, currentPrice);
      _ensureEma(state, slow, currentPrice);
      if (n < Math.min(fast, 3)) return null;
      const emaFast = state.emas[fast];
      const emaSlow = state.emas[slow];
      if (emaFast == null || emaSlow == null) return null;
      return emaFast - emaSlow;
    }
    case "ATR": {
      if (n < 2) return null;
      // Simplified ATR using close-to-close as true-range proxy (no OHLC available)
      const diffs: number[] = [];
      for (let i = Math.max(1, n - period); i < n; i++) {
        diffs.push(Math.abs(closes[i] - closes[i - 1]));
      }
      if (diffs.length === 0) return null;
      return diffs.reduce((a, b) => a + b, 0) / diffs.length;
    }
    case "Bollinger Bands": {
      if (n < period) return null;
      const slice = closes.slice(-period);
      const mean  = slice.reduce((a, b) => a + b, 0) / period;
      const std   = Math.sqrt(slice.reduce((s, v) => s + (v - mean) ** 2, 0) / period);
      return mean + 2 * std; // upper band
    }
    case "Volume":
      // No volume data in the LTP-only feed — return neutral
      return 0;
    case "VWAP":
      // Requires tick volume — approximate with SMA of recent prices
      return closes.length >= 5
        ? closes.slice(-5).reduce((a, b) => a + b, 0) / 5
        : currentPrice;
    case "OI":
    case "PCR":
    case "IV / IV Rank":
    case "Option Premium":
      // Not available via LTP feed — return neutral value (50)
      // so these conditions never block entry unintentionally
      return 50;
    default:
      return null;
  }
}

// ── Get LHS value from a condition ────────────────────────────────────────────

function _lhsValueFromState(
  cond: NormCond,
  state: IndicatorState,
  currentPrice: number
): number | null {
  if (cond.lhsType === "Price") {
    // In a tick-only feed, Open/High/Low are all approximated by close
    return currentPrice;
  }
  return _indValueFromState(cond.indicator, cond.paramA, state, currentPrice);
}

// ─────────────────────────────────────────────────────────────────────────────
// _evalConditionsLive
//
// Evaluate a list of StrategyCondition objects against the current LTP and
// rolling indicator state.
//
// Returns true if all/any (AND/OR chain) conditions are met.
// Returns true (pass-through) if the conditions array is empty.
// ─────────────────────────────────────────────────────────────────────────────

function _evalConditionsLive(
  conds: StrategyCondition[],
  state: IndicatorState,
  currentPrice: number,
  prevPrice: number | null
): boolean {
  if (!conds || conds.length === 0) return true;

  let result = _evalSingleCondLive(_normCond(conds[0]), state, currentPrice, prevPrice);

  for (let c = 1; c < conds.length; c++) {
    const gate   = (conds[c - 1].logic ?? conds[c - 1].logic ?? "AND").toUpperCase();
    const thisOk = _evalSingleCondLive(_normCond(conds[c]), state, currentPrice, prevPrice);
    result = gate === "OR" ? (result || thisOk) : (result && thisOk);
  }

  return result;
}

function _evalSingleCondLive(
  cond: NormCond,
  state: IndicatorState,
  currentPrice: number,
  prevPrice: number | null
): boolean {
  const lhs = _lhsValueFromState(cond, state, currentPrice);
  if (lhs === null) return false; // still warming up

  // rhsNone: direction-only check
  if (cond.rhsNone) {
    switch (cond.indicator) {
      case "MACD":  return lhs > 0;
      case "ADX":   return lhs > 25;
      default:      return lhs > 0;
    }
  }

  let rhs: number;
  if (cond.rhsIsInd) {
    const rhsVal = _indValueFromState(cond.valueB, cond.rhsPeriod, state, currentPrice);
    if (rhsVal === null) return false;
    rhs = rhsVal;
  } else {
    rhs = parseFloat(cond.valueA) || 0;
  }

  // For crossover operators we need the previous value of LHS
  if (cond.op === "Crosses Above" || cond.op === "Crosses Below") {
    if (prevPrice === null) return false;
    // Approximate "previous LHS" by evaluating with prevPrice
    // We do this by temporarily cloning the state window minus the last entry
    const prevLhs = ((): number | null => {
      const prevCloses = state.closes.slice(0, -1);
      if (prevCloses.length === 0) return null;
      // Approximate: use second-to-last SMA/EMA as prev value
      if (cond.lhsType === "Price") return prevPrice;
      if (cond.indicator === "EMA") {
        const p = parseInt(cond.paramA) || 14;
        const s = prevCloses.slice(-p);
        return s.length >= 1 ? s.reduce((a, b) => a + b, 0) / s.length : null;
      }
      if (cond.indicator === "SMA") {
        const p = parseInt(cond.paramA) || 14;
        const s = prevCloses.slice(-p);
        return s.length === p ? s.reduce((a, b) => a + b, 0) / p : null;
      }
      return prevPrice; // fallback
    })();

    if (prevLhs === null) return false;
    const prevRhs = cond.rhsIsInd
      ? (prevLhs) // approximate — same RHS value
      : rhs;

    if (cond.op === "Crosses Above") return prevLhs <= prevRhs && lhs > rhs;
    if (cond.op === "Crosses Below") return prevLhs >= prevRhs && lhs < rhs;
  }

  switch (cond.op) {
    case ">":  return lhs >  rhs;
    case "<":  return lhs <  rhs;
    case ">=": return lhs >= rhs;
    case "<=": return lhs <= rhs;
    case "==": return Math.abs(lhs - rhs) < Math.max(0.001, Math.abs(rhs) * 0.001);
    default:   return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _isWithinTradingSchedule
//
// Returns true if the current IST time falls within the user-configured
// trading window for the strategy.
//
// Fields read from strategy:
//   start_time:   "09:15 AM"  — defaults to market open (09:15 IST)
//   end_time:     "15:00 PM"  — defaults to market close (15:00 IST)
//   trading_days: [1,2,3,4,5] — 1=Mon … 5=Fri (Flutter convention)
//
// utcMins: current time expressed as minutes since midnight UTC.
// ─────────────────────────────────────────────────────────────────────────────

function _parseIstTimeToUtcMins(timeStr: string): number | null {
  // Expected format: "09:15 AM" or "03:30 PM" or "15:30 PM"
  // Also tolerates "9:15 AM", "15:00" (no AM/PM)
  if (!timeStr) return null;
  const m = timeStr.trim().match(/^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?$/i);
  if (!m) return null;
  let hours   = parseInt(m[1]);
  const mins  = parseInt(m[2]);
  const ampm  = (m[3] ?? "").toUpperCase();
  if (ampm === "PM" && hours !== 12) hours += 12;
  if (ampm === "AM" && hours === 12) hours = 0;
  // Convert IST (UTC+5:30) to UTC: subtract 5h 30m
  const istMins = hours * 60 + mins;
  return ((istMins - 330) + 1440) % 1440; // keep positive
}

function _isWithinTradingSchedule(
  strategy: UserStrategy,
  utcMins: number,
  utcDayOfWeek: number  // 0=Sun,1=Mon...6=Sat
): boolean {
  // ── Day-of-week check ─────────────────────────────────────────────────────
  const tradingDays = strategy.trading_days;
  if (tradingDays && tradingDays.length > 0) {
    // Flutter stores 1=Mon…5=Fri. JS getUTCDay() gives 0=Sun,1=Mon…6=Sat.
    // utcDayOfWeek 1=Mon matches Flutter 1=Mon → direct comparison works.
    if (!tradingDays.includes(utcDayOfWeek)) {
      return false;
    }
  }

  // ── Time-of-day check ──────────────────────────────────────────────────────
  const startUtc = _parseIstTimeToUtcMins(strategy.start_time ?? "");
  const endUtc   = _parseIstTimeToUtcMins(strategy.end_time   ?? "");

  if (startUtc !== null && utcMins < startUtc) return false;
  if (endUtc   !== null && utcMins > endUtc)   return false;

  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// _computeQuantity
//
// Resolves the final order quantity from a strategy doc at execution time.
//
// Three modes (driven by strategy.position_sizing):
//
//   'Fixed Lots'   — quantity = lots × lotSize
//                    Fallback: strategy.quantity × strategy.lot_size (legacy)
//
//   '% of Capital' — quantity = floor((capital × pct/100) / (ltp × lotSize))
//                    rounded down to nearest whole lot, minimum 1 lot.
//                    Capital source priority:
//                      1. strategy.capital_amount  (user entered it in the wizard)
//                      2. app_config/algo_risk.total_capital (global setting)
//
//   Any other / missing → fall back to strategy.quantity × strategy.lot_size
//
// Returns at minimum 1 (never 0 or negative).
// ─────────────────────────────────────────────────────────────────────────────

async function _computeQuantity(
  strategy:   UserStrategy,
  ltp:        number,
  riskConfig: { total_capital: number }
): Promise<number> {
  const lotSize = strategy.lot_size ?? 1;

  const mode = strategy.position_sizing ?? "";

  if (mode === "% of Capital") {
    const pct     = strategy.capital_pct ?? 5;              // default 5% if not set
    const capital = strategy.capital_amount               // user's own capital entry
                 ?? riskConfig.total_capital;              // global AlgoConfig fallback

    if (capital > 0 && ltp > 0 && lotSize > 0) {
      // How much ₹ to allocate to this trade
      const allocated = capital * (pct / 100);
      // Cost of one lot at current LTP
      const costPerLot = ltp * lotSize;
      // Floor to whole lots, minimum 1
      const lots = Math.max(1, Math.floor(allocated / costPerLot));
      console.log(
        `[Qty] % of Capital: capital=₹${capital} pct=${pct}% ` +
        `→ allocated=₹${allocated.toFixed(0)} / lotCost=₹${costPerLot.toFixed(0)} ` +
        `= ${lots} lot(s) (qty=${lots * lotSize})`
      );
      return lots * lotSize;
    }
    // Fall through to legacy if values are missing/zero
  }

  if (mode === "Fixed Lots") {
    const lots = strategy.lots ?? strategy.quantity ?? 1;
    const qty  = lots * lotSize;
    console.log(`[Qty] Fixed Lots: ${lots} lot(s) × ${lotSize} = ${qty}`);
    return Math.max(1, qty);
  }

  // Stocks "Fixed Shares" — Flutter writes the field as 'shares', not 'quantity'
  if (mode === "Fixed Shares") {
    const shares = strategy.shares ?? strategy.quantity ?? 1;
    console.log(`[Qty] Fixed Shares: ${shares}`);
    return Math.max(1, shares);
  }

  // Legacy / fallback: raw quantity field × lot_size
  // Also covers stocks where position_sizing is absent/blank
  const rawQty = strategy.shares ?? strategy.quantity ?? 1;
  const qty    = rawQty * lotSize;
  console.log(`[Qty] Legacy fallback: qty=${rawQty} × lotSize=${lotSize} = ${qty}`);
  return Math.max(1, qty);
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility: extract uid from a Firestore document path
//
// Path format: "users/{uid}/strategies/{strategyId}"
// ─────────────────────────────────────────────────────────────────────────────

function _extractUidFromPath(path: string): string | null {
  // e.g. "users/abc123/strategies/xyz456"
  const parts = path.split("/");
  const usersIdx = parts.indexOf("users");
  if (usersIdx === -1 || usersIdx + 1 >= parts.length) return null;
  return parts[usersIdx + 1] ?? null;
}

// ─────────────────────────────────────────────────────────────────────────────
// onAlgoStatsUpdate
//
// Runs every 5 minutes. Aggregates key trading stats across all users and
// writes them to app_config/algo_stats so the HomeDashboardScreen can show
// live metrics without per-user queries.
//
// Fields written to app_config/algo_stats:
//   deployed_strategies  — count of strategies with status != 'closed'
//   active_bots          — count of strategies currently 'in_position'
//   watching_bots        — count of strategies 'watching'
//   today_pnl            — sum of realised_pnl_rs for strategies exited today (IST)
//   overall_pnl          — sum of all realised_pnl_rs ever
//   total_trades_today   — count of trades exited today
//   win_rate_today       — winning trades today / total trades today (0-100)
//   updated_at           — server timestamp
// ─────────────────────────────────────────────────────────────────────────────

export const onAlgoStatsUpdate = onSchedule(
  {
    schedule:       "every 5 minutes",
    region:         "us-central1",
    timeoutSeconds: 120,
  },
  async (_context) => {
    const db = getFirestore();

    // Today midnight IST
    const now     = new Date();
    const istMs   = now.getTime() + 5.5 * 60 * 60 * 1000;
    const istDate = new Date(istMs);
    istDate.setUTCHours(0, 0, 0, 0);
    const midnightIST = new Date(istDate.getTime() - 5.5 * 60 * 60 * 1000);

    try {
      // ── 1. Count deployed (non-closed) and in_position strategies ─────────
      const [deployedSnap, inPositionSnap, watchingSnap] = await Promise.all([
        db.collectionGroup("strategies")
          .where("status", "not-in", ["closed", "target_hit", "sl_hit", "stoploss_hit", "hit_target"])
          .count().get(),
        db.collectionGroup("strategies")
          .where("status", "==", "in_position")
          .count().get(),
        db.collectionGroup("strategies")
          .where("status", "==", "watching")
          .count().get(),
      ]);

      const deployedStrategies = deployedSnap.data().count ?? 0;
      const activeBots         = inPositionSnap.data().count ?? 0;
      const watchingBots       = watchingSnap.data().count ?? 0;

      // ── 2. Today's P&L and overall P&L ────────────────────────────────────
      // Scan all strategies with realised_pnl_rs set (exited trades).
      const exitedTodaySnap = await db
        .collectionGroup("strategies")
        .where("exited_at", ">=", Timestamp.fromDate(midnightIST))
        .get();

      let todayPnl          = 0;
      let totalTradesToday  = 0;
      let winsTodayCount    = 0;

      for (const doc of exitedTodaySnap.docs) {
        const pnl = (doc.data().realised_pnl_rs as number | undefined) ?? 0;
        if (pnl !== 0) {
          todayPnl += pnl;
          totalTradesToday++;
          if (pnl > 0) winsTodayCount++;
        }
      }

      // Overall P&L — scan all strategies that have realised_pnl_rs set.
      // We limit to 500 docs to avoid timeout; for large deployments a
      // running total maintained per trade would be more scalable.
      const allExitedSnap = await db
        .collectionGroup("strategies")
        .where("realised_pnl_rs", "!=", null)
        .limit(500)
        .get();

      let overallPnl = 0;
      for (const doc of allExitedSnap.docs) {
        const pnl = (doc.data().realised_pnl_rs as number | undefined) ?? 0;
        overallPnl += pnl;
      }

      const winRateToday = totalTradesToday > 0
        ? Math.round((winsTodayCount / totalTradesToday) * 100)
        : 0;

      // ── 3. Write to app_config/algo_stats ─────────────────────────────────
      await db.collection("app_config").doc("algo_stats").set({
        deployed_strategies:  deployedStrategies,
        active_bots:          activeBots,
        watching_bots:        watchingBots,
        today_pnl:            parseFloat(todayPnl.toFixed(2)),
        overall_pnl:          parseFloat(overallPnl.toFixed(2)),
        total_trades_today:   totalTradesToday,
        win_rate_today:       winRateToday,
        updated_at:           Timestamp.now(),
      }, { merge: false }); // full overwrite so stale fields don't linger

      console.log(
        `[AlgoStats] deployed=${deployedStrategies} active=${activeBots} ` +
        `watching=${watchingBots} todayPnl=₹${todayPnl.toFixed(0)} ` +
        `overallPnl=₹${overallPnl.toFixed(0)} trades=${totalTradesToday} wr=${winRateToday}%`
      );
    } catch (err) {
      console.error("[AlgoStats] Failed:", err instanceof Error ? err.message : err);
    }
  }
);
