# Implementation Tracker — Algo Trading App

Last updated: August 2026 (audited against actual code)
Status legend: ✅ Done · ⚠️ Partial · ❌ Not started · 🔄 Needs update

---

## Architecture shift (key context)

The app started as a clone of the `recom` stock recommendation app where an
**admin manually published signals**. Redesigned to work like a real algo trading platform:

| Old (recom-style) | New (algo platform) |
|---|---|
| Admin writes `algo_signals` | Engine monitors user strategies |
| `is_published: true` triggers orders | `status: 'watching'` → engine places order |
| Users are passive subscribers | Users define their own entry conditions |
| `onAlgoSignalWritten` is the core | `onStrategyEntryCheck` is the core |

Admin `algo_signals` path is **kept** for curated signals to plan subscribers.
User self-service path flows through `users/{uid}/strategies`.

---

## 1. Firebase Functions (`firebase/functions/src/index.ts`)

| Function | Status | Notes |
|---|---|---|
| `onAlgoSignalWritten` | ✅ Done | Admin signal → auto-execute for plan subscribers. FCM via topic. |
| `onOrderStatusChanged` | ✅ Done | FCM push on order fill/reject, includes `order_role` (entry/exit) |
| `onStrategyEntryCheck` | ✅ Done | Core engine — scans `status=='watching'` every min, risk checks, places entry orders, updates strategy `in_position` |
| `onPositionMonitor` | ✅ Done | Scans `status=='in_position'` every min, checks SL/target, places exit orders, writes `realised_pnl_rs` |
| `getDailyLossRs()` helper | ✅ Done | Sums today's `sl_hit` strategy losses in ₹ for a user (IST midnight boundary) |
| Daily loss halt in entry check | ✅ Done | `onStrategyEntryCheck` calls `getDailyLossRs` and skips user if limit breached |
| Daily loss halt in position monitor | ✅ Done | `onPositionMonitor` defers target exits (not SL exits) when limit breached |
| Backward-compat for `drop_enabled` strategies | ✅ Done | Legacy strategies still handled in `onStrategyEntryCheck` |

---

## 2. Price Server (`price-server/src/`)

| File | Status | Notes |
|---|---|---|
| `broker/orderExecutor.js` | ✅ Done | `placeOrder`, `modifyOrder`, `cancelOrder`, `getOrderStatus`, `syncOrderBook`. **riskManager.checkOrderAllowed() IS wired at line 283** |
| `broker/riskManager.js` | ✅ Done | `checkOrderAllowed`, `isDailyLossLimitBreached`, `isMaxPositionsExceeded`, `loadRiskConfig` (5-min cache) |
| `broker/positionManager.js` | ✅ Done | `getPositionBook`, `syncPositions`, `closePosition` |
| `server.js` — `POST /place-order` | ✅ Done | Calls `orderExecutor.placeOrder` which calls `riskManager` internally |
| `server.js` — `POST /cancel-order` | ✅ Done | Verified in code |
| `server.js` — `POST /modify-order` | ✅ Done | Verified in code |
| `server.js` — `GET /order-book/:userId` | ✅ Done | Verified in code |
| `server.js` — `POST /sync-positions/:userId` | ✅ Done | Verified in code |
| `server.js` — `GET /positions/:userId` | ❌ Missing | **No GET endpoint for positions.** `PositionsScreen` and `PositionCubit` rely on Firestore stream (not this endpoint), so app functions — but the endpoint documented in WHAT_TO_BUILD.md does not exist |
| `angelOne.js` | ✅ Done | Auth, token refresh, WS price feed |
| `instrumentTokens.js` | ✅ Done | Symbol↔token mapping |

---

## 3. Flutter — Models

| File | Status | Notes |
|---|---|---|
| `models/order.dart` — `AlgoOrder` | ✅ Done | Full model, `OrderStatus` enum, `fromFirestore`, `toFirestore`, `copyWith` |
| `models/position.dart` — `AlgoPosition` | ✅ Done | Full model with `fromFirestore`, live P&L fields |
| `models/recommendation.dart` | ✅ Done | Kept for admin signal feed |
| `models/subscription.dart` | ✅ Done | |
| `models/broker_connection.dart` | ✅ Done | Angel One credentials model |
| `models/user_profile.dart` | ✅ Done | |

---

## 4. Flutter — Repositories

| File | Status | Notes |
|---|---|---|
| `repositories/order_repository.dart` | ✅ Done | `getUserOrders`, `getOrderForSignal`, `createOrder` |
| `repositories/position_repository.dart` | ✅ Done | `getOpenPositions`, `getClosedPositions` |
| `repositories/subscription_repository.dart` | ✅ Done | |
| `repositories/signal_repository.dart` | ✅ Done | |
| `repositories/broker_repository.dart` | ✅ Done | |
| `repositories/user_repository.dart` | ✅ Done | |

---

## 5. Flutter — Services

| File | Status | Notes |
|---|---|---|
| `services/order_service.dart` | ✅ Done | REST client for price server order endpoints |
| `services/live_price_service.dart` | ✅ Done | Socket.IO + `fetchPrice` REST fallback, `-EQ` suffix handling |
| `services/auth_service.dart` | ✅ Done | |
| `services/local_notification_service.dart` | ✅ Done | |
| `services/payment_service.dart` | ✅ Done | Razorpay |

---

## 6. Flutter — Cubits / State

| File | Status | Notes |
|---|---|---|
| `cubits/order_cubit.dart` + `order_state.dart` | ✅ Done | `placeOrder`, `cancelOrder` |
| `cubits/position_cubit.dart` + `position_state.dart` | ✅ Done | Live P&L merged with `LivePriceCubit` |
| `cubits/live_price_cubit.dart` | ✅ Done | Wraps `LivePriceService` |
| `cubits/subscription_cubit.dart` | ✅ Done | |
| `cubits/feed_cubit.dart` | ✅ Done | Signal feed with pagination, filters |
| `cubits/broker_cubit.dart` | ✅ Done | Angel One connection state |

---

## 7. Flutter — Screens

| Screen | Status | Notes |
|---|---|---|
| `user_strategies_screen.dart` | ✅ Done | Performance header, status filter tabs, live P&L cards, price progress bar |
| `create_strategy_screen.dart` | ✅ Done | Instrument search, live price prefill, quantity+risk, confidence, tags, entry condition, drop trigger |
| `strategy_detail_screen.dart` | ✅ Done | Price ladder, live P&L hero, stats grid, watching/in_position banners, close action |
| `order_book_screen.dart` | ✅ Done | Grouped by Active/Completed/Rejected, shimmer, real-time stream |
| `positions_screen.dart` | ✅ Done | Live P&L, close position button, sync |
| `algo_config_screen.dart` | ✅ Done | Capital, position size, max positions, max order value, daily loss limit — all save both % and raw ₹ |
| `broker_setup_screen.dart` | ✅ Done | Angel One credential entry |
| `signal_feed_screen.dart` | ✅ Done | Admin signal feed with live prices |
| `signal_detail_screen.dart` | ✅ Done | Detail + order placement |
| `screeners_screen.dart` | ✅ Done | NSE EOD screeners + `+ Strategy` quick-add on each stock row |
| `home_dashboard_screen.dart` | ✅ Done | |
| `admin_seed_screen.dart` | ✅ Done | Seeds admin strategies into Firestore |
| Seed fake orders screen | ❌ Missing | No way to seed `orders` collection for visual testing yet |

---

## 8. Flutter — Router

| Route | Status | Notes |
|---|---|---|
| `/home/strategies` | ✅ Done | |
| `/create-strategy` | ✅ Done | Accepts prefill from screener |
| `/strategy-detail` | ✅ Done | Via GoRouter `extra` map |
| `/home/orders` | ✅ Done | |
| `/home/positions` | ✅ Done | |
| `/algo-config` | ✅ Done | |
| `/broker-setup` | ✅ Done | |
| All auth + onboarding routes | ✅ Done | |

---

## 9. Firestore

| Collection / Item | Status | Notes |
|---|---|---|
| `users/{uid}` | ✅ Done | |
| `users/{uid}/strategies` | ✅ Done | Full lifecycle: watching→in_position→target_hit/sl_hit/closed |
| `users/{uid}/broker_connections/angel_one` | ✅ Done | |
| `orders/{orderId}` | ✅ Done | Has `strategy_id`, `order_role` (entry/exit), all standard fields |
| `positions/{positionId}` | ✅ Done | |
| `algo_signals/{signalId}` | ✅ Done | Admin curated signals |
| `subscriptions/{id}` | ✅ Done | |
| `subscription_plans/{id}` | ✅ Done | |
| `instrument_tokens/{symbol}` | ✅ Done | 270 enabled instruments migrated from recom |
| `app_config/algo_risk` | ✅ Done | Now stores: `algo_enabled`, `total_capital`, `position_size_pct`, `max_open_positions`, `max_order_value`, `daily_loss_limit_pct`, `daily_loss_limit` (₹) |
| `screeners/{id}` | ✅ Done | NSE EOD screener data |
| **Security rules — `strategies` subcollection** | ✅ Fixed | Rule added in `firestore.rules` — owner read/create/update/delete; engine uses Admin SDK |
| **Security rules — `algo_signals` write** | ⚠️ Partial | Admin writes via `isAdmin()` check; `admin_seed_screen.dart` writes from Flutter — needs admin custom claim in production |
| **Firestore index — `strategies` collectionGroup by `status`** | ✅ Fixed | `status ASC` COLLECTION_GROUP index added to `firestore.indexes.json` |
| **Firestore index — `strategies` by `status + exited_at`** | ✅ Fixed | `status ASC + exited_at ASC` COLLECTION_GROUP index added — covers `getDailyLossRs()` |
| **Firestore index — `strategies` by `status + created_at`** | ✅ Fixed | Bonus index added for future filter queries |

---

## 10. Risk Management — Current Status (all fixed)

| Component | Status | Notes |
|---|---|---|
| `AlgoConfigScreen` UI | ✅ Done | Capital, %, max positions, max order value, daily loss limit. Saves both % and raw ₹ |
| `riskManager.js` on price server | ✅ Done | All checks wired. Called inside `orderExecutor.placeOrder` |
| Risk checks in `onStrategyEntryCheck` | ✅ Done | `algo_enabled`, `max_open_positions`, `max_order_value`, daily loss limit |
| Risk checks in `onPositionMonitor` | ✅ Done | `algo_enabled` gate + defers target exits when daily limit hit (SL exits always proceed) |
| `getDailyLossRs()` helper | ✅ Done | Sums today's SL-hit strategy losses per user using IST midnight |
| `position_size_pct` → auto-compute quantity | ❌ Missing | Engine still reads raw `quantity` from strategy doc. Should compute `quantity = (capital × position_size_pct / 100) / ltp` but this is complex (requires knowing user's capital at order time) |

---

## 11. What's Actually Missing (verified against code)

Priority order — fix these before going live:

### 🔴 Critical (will break in production)

| # | Item | File to fix | What to do |
|---|---|---|---|
| ~~1~~ | ~~`strategies` subcollection missing from Firestore rules~~ | ✅ Fixed | Done |
| ~~2~~ | ~~Missing Firestore index: `strategies` collectionGroup by `status`~~ | ✅ Fixed | Done |
| ~~3~~ | ~~Missing Firestore index: `strategies` by `status + exited_at`~~ | ✅ Fixed | Done |

### 🟡 Important (degraded functionality)

| # | Item | File to fix | What to do |
|---|---|---|---|
| 4 | **No seed data for orders** — `OrderBookScreen` shows empty for all users | `admin_seed_screen.dart` | Add "Seed Orders" section with fake orders for current user |
| 5 | **`GET /positions/:userId` missing from price server** | `price-server/src/server.js` | Add endpoint (app works without it via Firestore stream, but sync button on PositionsScreen may be broken) |
| 6 | **`position_size_pct` not used by engine** | `firebase/functions/src/index.ts` | `onStrategyEntryCheck` reads `quantity` from strategy doc; should optionally auto-compute from capital × pct ÷ LTP |
| 7 | **Cancel order button not wired in `OrderBookScreen`** | `order_book_screen.dart` | UI shows cards but no tap action for cancellation on active orders |

### 🟢 Low priority (nice to have)

| # | Item | Notes |
|---|---|---|
| 8 | `admin_seed_screen.dart` writes `algo_signals` directly — needs `isAdmin` Firebase custom claim | Fine for development; set custom claim before production |
| 9 | `IMPLEMENTATION_TRACKER.md` needs update after each session | This document |

---

## 12. Firestore Indexes — Current State

| Index | Status |
|---|---|
| `strategies` collectionGroup: `drop_enabled + is_published` | ✅ Exists |
| `strategies` collectionGroup: `status` | ✅ Added this session |
| `strategies` collectionGroup: `status + exited_at` | ✅ Added this session |
| `strategies` collectionGroup: `status + created_at` | ✅ Added this session |
| `orders`: `user_id + placed_at` | ✅ Exists |
| `orders`: `user_id + signal_id + placed_at` | ✅ Exists |
| `positions`: `user_id + status` | ✅ Exists |
| `algo_signals`: `is_published + status + posted_at` | ✅ Exists |
| `algo_signals`: `source + is_published + status + posted_at` | ✅ Exists |

---

## 13. Summary

| Category | ✅ Done | ⚠️ Partial | ❌ Missing |
|---|---|---|---|
| Firebase Functions | 8 | 0 | 0 |
| Price Server files | 10 | 0 | 1 endpoint |
| Flutter Models | 6 | 0 | 0 |
| Flutter Repositories | 6 | 0 | 0 |
| Flutter Services | 5 | 0 | 0 |
| Flutter Cubits | 6 | 0 | 0 |
| Flutter Screens | 12 | 0 | 1 (seed orders) |
| Flutter Routes | 8 | 0 | 0 |
| Risk Management | 5 | 0 | 1 (position sizing) |
| Firestore Rules | 11 rules | 1 partial | 0 |
| Firestore Indexes | 11 | 0 | 0 |
