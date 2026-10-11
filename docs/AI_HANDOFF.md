# AI Handoff — Kiro Prompt Guide for Algo Trading App

This document is written specifically for use with **Kiro** (the AI coding agent).
Each section is a ready-to-paste spec prompt. Use Kiro's Spec mode for multi-file features,
or paste directly into Vibe mode for targeted tasks.

---

## How to use this folder with Kiro

1. Open `/Users/himanshukumar/algo-trading/` as your workspace in Kiro
2. Read `docs/ARCHITECTURE.md` first — gives Kiro the full system context
3. For each build task below, paste the relevant prompt into Kiro Spec mode
4. Always attach the relevant source files using `#File` context tags
5. The copied files in `flutter_app/` and `price-server/` are your reference implementations

---

## Prompt 1 — Angel One Order Executor (price-server)

```
I'm building an algo trading app on top of an existing price server (Node.js + Express + Socket.IO).
The existing codebase is in price-server/src/.

Read these files first:
#File price-server/src/broker/angelOne.js
#File price-server/src/config.js
#File price-server/src/auth/firebaseAuth.js
#File price-server/src/server.js
#File docs/ARCHITECTURE.md
#File docs/WHAT_TO_BUILD.md

Create price-server/src/broker/orderExecutor.js that:
1. Uses the existing angelOne.js auth token (call angelOne.getAuthToken())
2. Implements placeOrder(), modifyOrder(), cancelOrder(), getOrderStatus(), syncOrderBook()
3. Uses Angel One REST API endpoints (see WHAT_TO_BUILD.md section 1 for exact URLs)
4. Writes order results to Firestore `orders` collection using firebase-admin
5. Handles auth token expiry by calling angelOne.login() and retrying once

Then add the REST endpoints to server.js:
POST /place-order, POST /cancel-order, POST /modify-order, GET /order-book/:userId

Follow the exact coding style of angelOne.js (module.exports, async/await, console.log prefixes).
```

---

## Prompt 2 — Risk Manager (price-server)

```
I'm adding pre-order risk checks to an algo trading price server.

Read these files first:
#File price-server/src/broker/orderExecutor.js
#File price-server/src/config.js
#File docs/FIRESTORE_SCHEMA.md
#File docs/WHAT_TO_BUILD.md

Create price-server/src/broker/riskManager.js that:
1. Reads risk config from Firestore app_config/algo_risk (daily_loss_limit, max_open_positions, max_order_value, position_sizing_percent)
2. Caches the config for 5 minutes — avoid reading Firestore on every order
3. Implements checkOrderAllowed(userId, symbol, action, quantity, price) — returns { allowed: bool, reason: string|null }
4. Checks: max order value, max open positions, daily loss limit
5. Exports: checkOrderAllowed, loadRiskConfig

Call checkOrderAllowed() in orderExecutor.js BEFORE every placeOrder() call.
If not allowed, write the order to Firestore with status 'rejected' and return the reason.
```

---

## Prompt 3 — Flutter Order & Position Models

```
I'm building a Flutter algo trading app. I need two new Dart model classes.

Read these files first:
#File flutter_app/lib/models/recommendation.dart
#File flutter_app/lib/models/subscription.dart
#File docs/FIRESTORE_SCHEMA.md

Create:
1. flutter_app/lib/models/order.dart — class AlgoOrder (see FIRESTORE_SCHEMA.md orders collection)
2. flutter_app/lib/models/position.dart — class AlgoPosition (see FIRESTORE_SCHEMA.md positions collection)

Both classes must:
- Extend Equatable
- Have factory AlgoOrder.fromFirestore(DocumentSnapshot doc) constructor
- Have Map<String,dynamic> toFirestore() method
- Follow exact same patterns as recommendation.dart and subscription.dart

Do not add any extra fields beyond what's in the schema.
```

---

## Prompt 4 — Order Service (Flutter)

```
I'm building a Flutter algo trading app with an existing price server backend.

Read these files first:
#File flutter_app/lib/services/live_price_service.dart
#File flutter_app/lib/models/order.dart
#File price-server/src/server.js
#File docs/WHAT_TO_BUILD.md

Create flutter_app/lib/services/order_service.dart:
- Singleton class (like LivePriceService._())
- static const String _serverUrl = String.fromEnvironment('PRICE_SERVER_URL', defaultValue: 'http://31.172.87.141:3001')
- Methods: placeOrder(), cancelOrder(), modifyOrder()
- All methods use Firebase ID token for auth (copy the token fetch pattern from live_price_service.dart)
- Handle HTTP errors with proper exception types
- Use the http package (already in pubspec.yaml)
```

---

## Prompt 5 — Order & Position Repositories (Flutter)

```
I'm building a Flutter algo trading app using Firebase Firestore.

Read these files first:
#File flutter_app/lib/repositories/subscription_repository.dart
#File flutter_app/lib/repositories/signal_repository.dart
#File flutter_app/lib/models/order.dart
#File flutter_app/lib/models/position.dart
#File docs/FIRESTORE_SCHEMA.md

Create:
1. flutter_app/lib/repositories/order_repository.dart
   - Abstract class + Impl
   - getUserOrders(userId) → Stream<List<AlgoOrder>> (real-time)
   - getOrderForSignal(userId, signalId) → Stream<AlgoOrder?>
   - createOrder(AlgoOrder) → Future<void>

2. flutter_app/lib/repositories/position_repository.dart
   - Abstract class + Impl
   - getOpenPositions(userId) → Stream<List<AlgoPosition>>
   - getClosedPositions(userId, {int limit}) → Future<List<AlgoPosition>>

Follow the exact same abstract+impl pattern as subscription_repository.dart.
```

---

## Prompt 6 — Order & Position Cubits (Flutter)

```
I'm building Flutter BLoC cubits for an algo trading app.

Read these files first:
#File flutter_app/lib/cubits/subscription_cubit.dart
#File flutter_app/lib/cubits/live_price_cubit.dart
#File flutter_app/lib/repositories/order_repository.dart
#File flutter_app/lib/repositories/position_repository.dart
#File flutter_app/lib/services/order_service.dart
#File flutter_app/lib/models/order.dart
#File flutter_app/lib/models/position.dart

Create:
1. flutter_app/lib/cubits/order_cubit.dart + order_state.dart
   States: OrderInitial, OrderPlacing, OrderPlaced(order), OrderFailed(message)
   Methods: placeOrder(signal, quantity), cancelOrder(orderId)

2. flutter_app/lib/cubits/position_cubit.dart + position_state.dart
   States: PositionLoading, PositionLoaded(positions, totalPnl, totalPnlPercent), PositionError
   - Merges PositionRepository stream with LivePriceCubit prices to compute live P&L
   - Updates P&L in real-time without fetching from server on every tick

Follow the same coding patterns as subscription_cubit.dart and live_price_cubit.dart.
Use part/part-of for state files.
```

---

## Prompt 7 — Order Book Screen (Flutter)

```
I'm building a Flutter screen showing all trading orders in an algo trading app.

Read these files first:
#File flutter_app/lib/screens/notification_history_screen.dart
#File flutter_app/lib/cubits/order_cubit.dart
#File flutter_app/lib/models/order.dart
#File flutter_app/lib/router/app_router.dart

Create flutter_app/lib/screens/order_book_screen.dart:
- Shows orders grouped by status: Active (pending/open) / Completed / Rejected/Cancelled
- Each order card shows: symbol, action (BUY/SELL badge), quantity, price, status chip, timestamp
- Status chips: green (complete), orange (open/pending), red (rejected), grey (cancelled)
- Pull to refresh
- Empty state for each group
- Match the visual design language of the existing screens (white cards, rounded corners, Color(0xFF4C46E5) accent)
```

---

## Prompt 8 — Positions Screen (Flutter)

```
I'm building a Flutter positions screen for an algo trading app with live P&L.

Read these files first:
#File flutter_app/lib/screens/home_dashboard_screen.dart
#File flutter_app/lib/cubits/position_cubit.dart
#File flutter_app/lib/cubits/live_price_cubit.dart
#File flutter_app/lib/widgets/live_price_text.dart
#File flutter_app/lib/models/position.dart

Create flutter_app/lib/screens/positions_screen.dart:
- Header: total portfolio P&L (green/red, bold)
- List of open position cards, each showing:
  - Stock name + symbol
  - Avg buy price vs current live price (use LivePriceCubit, same as LivePriceText)
  - P&L in ₹ and %
  - Close Position button → calls OrderCubit.placeOrder() with opposite action
- Pull to refresh → calls price-server POST /sync-positions/:userId
- Empty state when no open positions
- Match existing app visual style
```

---

## Prompt 9 — Signal Detail Screen with Order Placement (Flutter)

```
I'm adding order placement to an existing trade signal detail screen in a Flutter algo trading app.

Read these files first:
#File flutter_app/lib/screens/signal_detail_screen.dart
#File flutter_app/lib/cubits/order_cubit.dart
#File flutter_app/lib/cubits/live_price_cubit.dart
#File flutter_app/lib/models/order.dart

Modify flutter_app/lib/screens/signal_detail_screen.dart to add at the bottom of the screen:
1. A quantity selector (default 1, increment/decrement buttons)
2. A "Place Order" primary button — triggers OrderCubit.placeOrder()
3. A BlocBuilder on OrderCubit showing:
   - Loading spinner while placing
   - Success card (green) with order ID when placed
   - Error message (red) on failure
4. If an order already exists for this signal (check OrderRepository.getOrderForSignal),
   show the existing order status instead of the Place Order button

Keep all existing UI intact — only append the order section at the bottom.
```

---

## Prompt 10 — Router updates (Flutter)

```
I'm adding new routes to an existing GoRouter setup in a Flutter app.

Read these files first:
#File flutter_app/lib/router/app_router.dart
#File flutter_app/lib/screens/order_book_screen.dart
#File flutter_app/lib/screens/positions_screen.dart
#File flutter_app/lib/screens/algo_config_screen.dart

Add these routes to app_router.dart:
- /orders → OrderBookScreen
- /positions → PositionsScreen
- /algo-config → AlgoConfigScreen

Also update the StatefulShellRoute branches to add:
- index 5: /home/orders → OrderBookScreen (in bottom nav)
- index 6: /home/positions → PositionsScreen (in bottom nav)

Update HomeScreen's bottom navigation bar accordingly.
Keep all existing routes and auth guards unchanged.
```

---

## Prompt 11 — Firebase Function: onAlgoSignalWritten

```
I'm adding a Firebase Cloud Function that triggers automated order placement when an algo signal is published.

Read these files first:
#File functions/src/index.ts (the existing functions file from recom project — use as pattern reference)
#File docs/ARCHITECTURE.md
#File docs/FIRESTORE_SCHEMA.md
#File docs/WHAT_TO_BUILD.md section 16

Create the onAlgoSignalWritten Cloud Function in firebase/functions/index.ts:
- Trigger: onDocumentWritten('algo_signals/{docId}')
- Only fires when: is_published transitions false→true AND auto_execute === true
- For each active subscriber in the signal's plan_ids:
  1. Fetch user from Firestore `users` collection
  2. Call price-server POST /place-order (use the server URL from env var PRICE_SERVER_URL)
  3. Send FCM notification via existing sendToTopic helper pattern
- On error: write error to Firestore order doc, log it, do NOT crash the function

Follow the exact same TypeScript patterns as the existing onRecommendationWritten function.
```

---

## Quick Reference: Key Angel One API Endpoints

```
Base URL: https://apiconnect.angelone.in

Auth:
  POST /rest/auth/angelbroking/user/v1/loginByPassword

Orders:
  POST /rest/secure/angelbroking/order/v1/placeOrder
  POST /rest/secure/angelbroking/order/v1/modifyOrder
  POST /rest/secure/angelbroking/order/v1/cancelOrder
  GET  /rest/secure/angelbroking/order/v1/getOrderBook
  GET  /rest/secure/angelbroking/order/v1/getTradeBook

Portfolio:
  GET  /rest/secure/angelbroking/order/v1/getPosition
  GET  /rest/secure/angelbroking/portfolio/v1/getHolding

Market Data:
  GET  /rest/secure/angelbroking/market/v1/quote
  POST /rest/secure/angelbroking/market/v1/optionGreeks

Required headers for all secure endpoints:
  Authorization: Bearer <jwtToken>
  X-PrivateKey: <apiKey>
  X-UserType: USER
  X-SourceID: WEB
  X-ClientLocalIP: 127.0.0.1
  X-ClientPublicIP: 127.0.0.1
  X-MACAddress: 00:00:00:00:00:00
  Content-Type: application/json
```

---

## Important Kiro Tips for this project

1. **Always read the source files first.** The copied files in `flutter_app/` and `price-server/` are the reference implementations. Every new file should match their patterns exactly.

2. **State management pattern:** All new cubits use `part`/`part of` for state files, extend `Equatable`, and follow the same `sealed class` state hierarchy as `subscription_cubit.dart`.

3. **Repository pattern:** Every new repository has an abstract class + `Impl` class, identical to `subscription_repository.dart`.

4. **Error handling:** Price server files silently ignore errors in broadcast paths (try/catch with console.error). Flutter services throw typed exceptions.

5. **Don't touch these files:** `angelOne.js`, `instrumentTokens.js`, `priceCache.js`, `auth_service.dart`, `live_price_service.dart`. They work perfectly and have complex logic.

6. **Package name:** Update `com.stock.stockyara` → your app's package name in `local_notification_service.dart` and `security_service.dart` before building.
