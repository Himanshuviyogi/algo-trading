# Algo Trading App — Scaffold

This folder is a complete scaffold for a standalone algo trading Flutter app,
built on top of the infrastructure from the `recom` (Stockara) project.

## Folder Structure

```
algo-trading/
├── flutter_app/              Flutter app (copied + renamed from recom)
│   ├── lib/
│   │   ├── models/           Data models (recommendation=AlgoSignal, order, position)
│   │   ├── services/         Auth, LivePrice, Payment, Notification, OrderService(NEW)
│   │   ├── repositories/     Firestore data layer (signal, order, position repos)
│   │   ├── blocs/            AuthBloc, FeedBloc
│   │   ├── cubits/           Subscription, LivePrice, MarketData, Order(NEW), Position(NEW)
│   │   ├── screens/          All UI screens (auth, plans, signals, orders, positions)
│   │   ├── widgets/          LivePriceText, MarketStrip, NotificationBanner, etc.
│   │   ├── config/           Finnhub, Payment, Notification config
│   │   ├── router/           GoRouter with auth + subscription guards
│   │   └── main.dart         App entry point
│   └── pubspec.yaml          All dependencies pre-filled
│
├── price-server/             Node.js backend (copied from recom + order endpoints needed)
│   └── src/
│       ├── broker/           AngelOne WS feed + NEW: orderExecutor, riskManager, positionManager
│       ├── cache/            In-memory price cache with disk persistence
│       ├── auth/             Firebase token verification
│       ├── config.js         Env var loader
│       └── server.js         Express + Socket.IO server
│
├── firebase/                 Firestore rules + indexes
│   ├── firestore.rules       Add rules for algo_signals, orders, positions
│   └── firestore.indexes.json
│
└── docs/                     Complete documentation for AI-assisted development
    ├── ARCHITECTURE.md       Full system design, data flows, tech stack
    ├── FIRESTORE_SCHEMA.md   All collection schemas with field types
    ├── FILE_MAP.md           Every file: status (copy/tweak/build), what to change
    ├── WHAT_TO_BUILD.md      New files with full function signatures and specs
    └── AI_HANDOFF.md         Kiro-ready prompts for every build task (START HERE)
```

## Quick Start

### Step 1 — Read the docs
Open `docs/AI_HANDOFF.md` first. It has numbered prompts for every task.

### Step 2 — Setup price server
```bash
cd price-server
cp .env.example .env
# Fill in your Angel One credentials
npm install
npm start
```

### Step 3 — Setup Flutter app
```bash
cd flutter_app
flutter pub get
# Copy google-services.json into android/app/
# Copy GoogleService-Info.plist into ios/Runner/
flutter run
```

### Step 4 — Build new files
Use the prompts in `docs/AI_HANDOFF.md` with Kiro in this order:
1. Prompt 1 — Order Executor (price-server)
2. Prompt 2 — Risk Manager (price-server)
3. Prompt 3 — Order & Position Models (Flutter)
4. Prompt 4 — Order Service (Flutter)
5. Prompt 5 — Repositories (Flutter)
6. Prompt 6 — Cubits (Flutter)
7. Prompt 7 — Order Book Screen
8. Prompt 8 — Positions Screen
9. Prompt 9 — Signal Detail with Order Placement
10. Prompt 10 — Router updates
11. Prompt 11 — Firebase Function

## What's already working (copied directly)

- Firebase Phone Auth (OTP login)
- Subscription system with Razorpay payments
- Real-time price feed (Socket.IO → Angel One SmartAPI)
- Signal feed (same as recommendation feed, rename collection)
- Market data (NSE movers, screeners, option chain)
- TradingView charts
- FCM push notifications
- Maintenance mode, force update, security controls

## What needs to be built

- Angel One REST order placement
- Risk management engine
- Flutter order book + positions screens
- Auto-execution Firebase Function

Estimated build time with Kiro: **2–3 weeks**

## Files NOT to modify

- `price-server/src/broker/angelOne.js` — WS feed, battle-tested
- `price-server/src/cache/priceCache.js` — disk persistence logic
- `flutter_app/lib/services/live_price_service.dart` — Socket.IO singleton
- `flutter_app/lib/services/auth_service.dart` — Firebase auth

---

Source project: `/Users/himanshukumar/recom` (Stockara)
Scaffold created: July 2026
