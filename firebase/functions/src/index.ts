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
          angelOrderId: result.angelOrderId, status: result.status,
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

      // Entry condition check
      const tol = ltp * 0.0005; // 0.05% tolerance
      let conditionMet = false;
      switch (w.conditionType) {
        case "above":     conditionMet = ltp >= w.conditionPrice - tol; break;
        case "below":     conditionMet = ltp <= w.conditionPrice + tol; break;
        case "at_market": conditionMet = true;                          break;
      }
      if (!conditionMet) { skippedCount++; continue; }

      console.log(
        `[EntryCheck] ✅ ${symbol} @ ₹${ltp} meets ${w.conditionType} ₹${w.conditionPrice} ` +
        `for user ${w.userId} (${w.docRef.path})`
      );

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
          angelOrderId: result.angelOrderId, status: result.status,
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
                status: slResult.status, orderRole: "bracket_sl",
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
                status: tgtResult.status, orderRole: "bracket_target",
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
              angelOrderId: misResult.angelOrderId, status: misResult.status,
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
          angelOrderId: result.angelOrderId, status: result.status,
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

  // Legacy / fallback: raw quantity field × lot_size
  const qty = (strategy.quantity ?? 1) * lotSize;
  console.log(`[Qty] Legacy fallback: quantity=${strategy.quantity} × lotSize=${lotSize} = ${qty}`);
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
