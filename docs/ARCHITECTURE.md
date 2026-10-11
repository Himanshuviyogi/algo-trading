# Algo Trading App — Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App (User)                    │
│  Auth → Subscription → Signal Feed → Order Placement   │
└──────────────────────────┬──────────────────────────────┘
                           │ Socket.IO (prices)
                           │ REST (orders, positions)
┌──────────────────────────▼──────────────────────────────┐
│               Price Server (Node.js)                    │
│  Angel One WS feed → Price Cache → Socket.IO broadcast  │
│  + NEW: Order Executor (REST → Angel One SmartAPI)      │
└──────────┬──────────────────────────┬───────────────────┘
           │ Token/symbol data        │ Admin writes
┌──────────▼──────────┐   ┌──────────▼───────────────────┐
│  Angel One          │   │   Firebase (Firestore)        │
│  SmartAPI           │   │   - users                    │
│  - WS price feed    │   │   - subscriptions            │
│  - REST orders      │   │   - algo_signals             │
│  - Position book    │   │   - orders                   │
│  - Trade book       │   │   - positions                │
└─────────────────────┘   │   - subscription_plans       │
                          │   - instrument_tokens        │
                          └──────────────────────────────┘
```

## Key Layers

### 1. Flutter App
- **Auth**: Firebase Phone Auth (OTP) — `AuthBloc`
- **Subscriptions**: Firestore `subscriptions` + `subscription_plans` — `SubscriptionCubit`
- **Live Prices**: Socket.IO → `LivePriceService` → `LivePriceCubit`
- **Signals**: Firestore `algo_signals` collection — `SignalRepository` (renamed from RecommendationRepository)
- **Orders** (NEW): REST calls to price server `/place-order` → Angel One SmartAPI
- **Positions** (NEW): Firestore `positions` + live P&L from price feed

### 2. Price Server (Node.js + Express + Socket.IO)
- Connects to Angel One SmartAPI WebSocket for live NSE/BSE/MCX tick data
- Broadcasts price changes to subscribed Flutter clients every 1s
- **NEW**: Exposes REST endpoints for order placement, modification, cancellation
- Verifies Firebase ID tokens on connection

### 3. Firebase
- **Firestore**: single source of truth for users, subscriptions, signals, orders, positions
- **Functions**: subscription expiry checks, order status sync, notifications
- **Auth**: phone auth (shared with `recom` project — same Firebase project or separate)

---

## Data Flow: Signal → Auto Order

```
Admin publishes algo_signal (Firestore)
         │
         ▼
Firebase Function: onAlgoSignalWritten
         │ checks plan_ids, is_published
         ▼
Calls price-server POST /place-order
         │
         ▼
orderExecutor.js → Angel One REST API
         │
         ▼
Writes order result to Firestore `orders/{orderId}`
         │
         ▼
Flutter app streams orders collection → shows order status
```

---

## Firestore Collections

| Collection           | Purpose                                           |
|----------------------|---------------------------------------------------|
| `users`              | User profiles (name, phone, FCM token)            |
| `subscriptions`      | Active user subscriptions with expiry dates       |
| `subscription_plans` | Plan definitions (name, price, features, topic)   |
| `algo_signals`       | Trade signals published by admin                  |
| `orders`             | Order records (placed, pending, filled, rejected) |
| `positions`          | Open positions with live P&L                      |
| `instrument_tokens`  | Angel One token↔symbol map                       |
| `app_config`         | Maintenance, banners, security, payment config    |

---

## Tech Stack

| Layer        | Technology                                        |
|--------------|---------------------------------------------------|
| Mobile       | Flutter (Dart) — BLoC/Cubit state management      |
| Backend      | Node.js + Express + Socket.IO                     |
| Broker       | Angel One SmartAPI (WebSocket + REST)             |
| Database     | Firebase Firestore                                |
| Auth         | Firebase Phone Auth                               |
| Payments     | Razorpay                                          |
| Notifications| FCM + flutter_local_notifications                 |
| Charts       | TradingView widget (WebView)                      |
| Hosting      | Railway (price server) + Firebase (functions)     |
