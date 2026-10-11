# File Map — What Every File Does & What to Change

## Legend
- ✅ Copy as-is — zero changes needed
- 🔧 Minor rename/tweak — noted inline
- 🆕 Build from scratch — specs in WHAT_TO_BUILD.md

---

## price-server/src/

| File | Status | Notes |
|------|--------|-------|
| `broker/angelOne.js` | ✅ | Complete WS feed with TOTP login, binary tick parser, auto-reconnect. DO NOT touch. |
| `broker/instrumentTokens.js` | ✅ | NSE/BSE/MCX token↔symbol map loaded from Firestore. |
| `broker/optionChain.js` | ✅ | NSE option chain fetcher with session management. |
| `broker/screener.js` | ✅ | Breakout/screener computation using Angel One data. |
| `broker/scripMaster.js` | ✅ | Angel One ScripMaster for F&O contract lookup. |
| `cache/priceCache.js` | ✅ | In-memory price cache with disk persistence. |
| `auth/firebaseAuth.js` | ✅ | Firebase Admin SDK token verification. |
| `config.js` | ✅ | Reads env vars — update `.env` file only. |
| `server.js` | 🔧 | Keep all existing endpoints. ADD order endpoints (see WHAT_TO_BUILD.md). Change app title/branding strings only. |
| `broker/orderExecutor.js` | 🆕 | Angel One REST order placement — the core new file. |
| `broker/positionManager.js` | 🆕 | Fetches/syncs position book from Angel One. |
| `broker/riskManager.js` | 🆕 | Pre-order risk checks (sizing, daily loss limit, circuit breaker). |

---

## flutter_app/lib/models/

| File | Status | Notes |
|------|--------|-------|
| `recommendation.dart` | 🔧 | Rename class usages to `AlgoSignal` / `TradeSignal` if desired, or keep as-is. The schema is identical. Add `autoExecute` bool field. |
| `market_index.dart` | ✅ | |
| `market_quote.dart` | ✅ | |
| `option_chain.dart` | ✅ | |
| `subscription.dart` | ✅ | |
| `subscription_plan.dart` | ✅ | |
| `user_profile.dart` | ✅ | |
| `activation_request.dart` | ✅ | |
| `app_control_config.dart` | ✅ | |
| `order.dart` | 🆕 | Maps to `orders` Firestore collection. |
| `position.dart` | 🆕 | Maps to `positions` Firestore collection. |

---

## flutter_app/lib/services/

| File | Status | Notes |
|------|--------|-------|
| `live_price_service.dart` | ✅ | Singleton Socket.IO client. Change `_serverUrl` default value to your Railway URL. |
| `auth_service.dart` | ✅ | |
| `connectivity_service.dart` | ✅ | |
| `local_notification_service.dart` | 🔧 | Update `com.stock.stockyara` package name to your algo app package name. |
| `local_storage_service.dart` | ✅ | |
| `payment_service.dart` | ✅ | Razorpay — no changes needed. |
| `notification_service.dart` | ✅ | |
| `security_service.dart` | 🔧 | Update `com.stockara/security` channel name to match your package. |
| `app_control_service.dart` | ✅ | |
| `order_service.dart` | 🆕 | REST calls to price-server `/place-order`, `/cancel-order`, `/modify-order`. |

---

## flutter_app/lib/repositories/

| File | Status | Notes |
|------|--------|-------|
| `user_repository.dart` | ✅ | |
| `subscription_repository.dart` | ✅ | |
| `plan_repository.dart` | ✅ | |
| `market_data_repository.dart` | ✅ | |
| `signal_repository.dart` | 🔧 | Renamed from `recommendation_repository.dart`. Change collection name from `recommendations` → `algo_signals`. All query logic stays the same. |
| `option_chain_repository.dart` | ✅ | |
| `order_repository.dart` | 🆕 | CRUD for `orders` collection + stream for live status. |
| `position_repository.dart` | 🆕 | Stream `positions` collection for live P&L. |

---

## flutter_app/lib/blocs/ & cubits/

| File | Status | Notes |
|------|--------|-------|
| `auth_bloc.dart` | ✅ | |
| `auth_event.dart` | ✅ | |
| `auth_state.dart` | ✅ | |
| `feed_bloc.dart` | 🔧 | References `RecommendationRepository` — update import to `SignalRepository`. |
| `feed_event.dart` | ✅ | |
| `feed_state.dart` | ✅ | |
| `subscription_cubit.dart` | ✅ | |
| `subscription_state.dart` | ✅ | |
| `live_price_cubit.dart` | ✅ | |
| `market_data_cubit.dart` | ✅ | |
| `market_data_state.dart` | ✅ | |
| `option_chain_cubit.dart` | ✅ | |
| `plans_cubit.dart` | ✅ | |
| `plans_state.dart` | ✅ | |
| `feed_cubit.dart` | 🔧 | Same as feed_bloc note — update SignalRepository import. |
| `feed_state.dart` | ✅ | |
| `notification_cubit.dart` | ✅ | |
| `notification_state.dart` | ✅ | |
| `signal_detail_cubit.dart` | 🔧 | Renamed from `recommendation_detail_cubit`. Update collection reference. |
| `signal_detail_state.dart` | ✅ | |
| `order_cubit.dart` | 🆕 | Manages order placement UX (loading, success, failure states). |
| `position_cubit.dart` | 🆕 | Streams open positions with live P&L from LivePriceCubit. |

---

## flutter_app/lib/screens/

| File | Status | Notes |
|------|--------|-------|
| `splash_screen.dart` | 🔧 | Update branding text ("Stockara" → your app name). |
| `phone_entry_screen.dart` | 🔧 | Update branding text. |
| `otp_verification_screen.dart` | ✅ | |
| `profile_setup_screen.dart` | ✅ | |
| `plans_screen.dart` | ✅ | |
| `onboarding_plans_screen.dart` | ✅ | |
| `home_dashboard_screen.dart` | 🔧 | Replace "Live Calls" KPI with "Open Positions". Add "Today's P&L" stat card. |
| `home_screen.dart` | 🔧 | Update bottom nav tabs: Dashboard / Signals / Orders / Market / Profile. |
| `market_screen.dart` | ✅ | |
| `stock_chart_screen.dart` | ✅ | |
| `option_chain_screen.dart` | ✅ | |
| `breakouts_screen.dart` | ✅ | |
| `screeners_screen.dart` | ✅ | |
| `notification_history_screen.dart` | ✅ | |
| `profile_screen.dart` | ✅ | |
| `news_updates_screen.dart` | ✅ | |
| `force_update_screen.dart` | ✅ | |
| `maintenance_screen.dart` | ✅ | |
| `signal_feed_screen.dart` | 🔧 | Renamed from recommendation_feed. Add "Execute" button on each signal card. |
| `signal_detail_screen.dart` | 🔧 | Add order placement section at bottom. Show order status if already placed. |
| `order_book_screen.dart` | 🆕 | List all orders with status, timestamps, angel order ID. |
| `positions_screen.dart` | 🆕 | Open positions with live P&L powered by LivePriceCubit. |
| `algo_config_screen.dart` | 🆕 | Toggle auto-execute on/off, set position size, view risk parameters. |

---

## flutter_app/lib/config/

| File | Status | Notes |
|------|--------|-------|
| `finnhub_config.dart` | ✅ | |
| `payment_config.dart` | ✅ | |
| `notification_config.dart` | 🔧 | Update sound file names and channel IDs to match your package. Add `order_filled` and `order_rejected` notification types. |

---

## flutter_app/lib/router/

| File | Status | Notes |
|------|--------|-------|
| `app_router.dart` | 🔧 | Add routes: `/orders`, `/positions`, `/algo-config`. Auth guard + subscription guard stay identical. |

---

## firebase/

| File | Status | Notes |
|------|--------|-------|
| `firestore.rules` | 🔧 | Add rules for `algo_signals`, `orders`, `positions` collections. See WHAT_TO_BUILD.md. |
| `firestore.indexes.json` | 🔧 | Add indexes for `orders` (user_id + placed_at), `positions` (user_id + status). |
