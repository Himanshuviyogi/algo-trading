# What To Build — New Files Required

This document lists every file that needs to be created from scratch.
Each entry has the file path, its purpose, key functions/classes, and dependencies.

---

## 1. price-server/src/broker/orderExecutor.js

**Purpose:** Places, modifies, and cancels orders on Angel One SmartAPI REST.
Writes results to Firestore `orders` collection.

**Key functions:**
```js
// Place a new order
async function placeOrder({ symbol, exchange, action, orderType, quantity, price, triggerPrice, userId, signalId })
// Returns: { success, angelOrderId, firestoreOrderId }

// Modify an existing order
async function modifyOrder({ angelOrderId, orderType, quantity, price, triggerPrice })

// Cancel an order
async function cancelOrder({ angelOrderId })

// Get order status from Angel One
async function getOrderStatus(angelOrderId)

// Sync order book from Angel One → Firestore
async function syncOrderBook(userId)
```

**Angel One REST endpoints used:**
- `POST /rest/secure/angelbroking/order/v1/placeOrder`
- `POST /rest/secure/angelbroking/order/v1/modifyOrder`
- `POST /rest/secure/angelbroking/order/v1/cancelOrder`
- `GET  /rest/secure/angelbroking/order/v1/getOrderBook`

**Dependencies:** `angelOne.js` (for auth token), `firebaseAuth.js`, `config.js`, `firebase-admin`

---

## 2. price-server/src/broker/riskManager.js

**Purpose:** Pre-order checks. Every order placement must pass all checks before executing.

**Key functions:**
```js
// Main gate — call before every order
async function checkOrderAllowed({ userId, symbol, action, quantity, price })
// Returns: { allowed: bool, reason: string | null }

// Check if daily loss limit is breached
async function isDailyLossLimitBreached(userId)

// Check if max open positions exceeded
async function isMaxPositionsExceeded(userId)

// Check if single order value exceeds limit
function isOrderValueExceeded(quantity, price, maxOrderValue)

// Load risk config from Firestore app_config/algo_risk
async function loadRiskConfig()
```

**Dependencies:** `firebase-admin` (reads `app_config/algo_risk`, `positions`, `orders` collections)

---

## 3. price-server/src/broker/positionManager.js

**Purpose:** Fetches position book from Angel One and syncs to Firestore `positions`.

**Key functions:**
```js
// Fetch all open positions from Angel One
async function getPositionBook()

// Sync positions to Firestore for a user
async function syncPositions(userId)

// Close a position (place opposite order)
async function closePosition({ positionId, userId })
```

**Angel One endpoint:** `GET /rest/secure/angelbroking/order/v1/getPosition`

---

## 4. New REST endpoints to add to server.js

Add these to `price-server/src/server.js` after the existing endpoints:

```js
// POST /place-order — place a new order
// Body: { userId, signalId, symbol, exchange, action, orderType, quantity, price, triggerPrice }
app.post('/place-order', async (req, res) => { ... })

// POST /cancel-order
// Body: { angelOrderId, userId }
app.post('/cancel-order', async (req, res) => { ... })

// POST /modify-order
// Body: { angelOrderId, orderType, quantity, price, triggerPrice }
app.post('/modify-order', async (req, res) => { ... })

// GET /order-book/:userId
app.get('/order-book/:userId', async (req, res) => { ... })

// GET /positions/:userId
app.get('/positions/:userId', async (req, res) => { ... })

// POST /sync-positions/:userId — force sync from Angel One
app.post('/sync-positions/:userId', async (req, res) => { ... })
```

---

## 5. flutter_app/lib/models/order.dart

```dart
class AlgoOrder extends Equatable {
  final String id;             // Firestore doc ID
  final String signalId;
  final String userId;
  final String symbol;
  final String exchange;
  final String action;         // BUY | SELL
  final String orderType;      // LIMIT | MARKET | SL | SL-M
  final int quantity;
  final double price;
  final double? triggerPrice;
  final String? angelOrderId;
  final String status;         // pending | open | complete | rejected | cancelled
  final String? rejectionReason;
  final DateTime placedAt;
  final DateTime updatedAt;

  // factory AlgoOrder.fromFirestore(DocumentSnapshot doc)
  // Map<String, dynamic> toFirestore()
}
```

---

## 6. flutter_app/lib/models/position.dart

```dart
class AlgoPosition extends Equatable {
  final String id;
  final String userId;
  final String signalId;
  final String orderId;
  final String symbol;
  final String exchange;
  final String action;
  final int quantity;
  final double avgPrice;
  final double currentPrice;   // updated from LivePriceCubit
  final double pnl;
  final double pnlPercent;
  final String status;         // open | closed
  final DateTime openedAt;
  final DateTime? closedAt;

  // factory AlgoPosition.fromFirestore(DocumentSnapshot doc)
}
```

---

## 7. flutter_app/lib/services/order_service.dart

REST client for the price-server order endpoints.

```dart
class OrderService {
  // Place a new order. Returns the Firestore order ID.
  Future<String> placeOrder({
    required String userId,
    required String signalId,
    required String symbol,
    required String exchange,
    required String action,
    required String orderType,
    required int quantity,
    required double price,
    double? triggerPrice,
  });

  // Cancel an existing order
  Future<void> cancelOrder({ required String angelOrderId, required String userId });

  // Modify an existing order
  Future<void> modifyOrder({ required String angelOrderId, required double price, required int quantity });
}
```

---

## 8. flutter_app/lib/repositories/order_repository.dart

```dart
abstract class OrderRepository {
  // Stream all orders for a user (real-time)
  Stream<List<AlgoOrder>> getUserOrders(String userId);

  // Stream orders for a specific signal
  Stream<AlgoOrder?> getOrderForSignal(String userId, String signalId);

  // Write a new order doc (called after price-server confirms placement)
  Future<void> createOrder(AlgoOrder order);
}
```

---

## 9. flutter_app/lib/repositories/position_repository.dart

```dart
abstract class PositionRepository {
  // Stream all open positions for a user (real-time)
  Stream<List<AlgoPosition>> getOpenPositions(String userId);

  // Get closed positions (paginated)
  Future<List<AlgoPosition>> getClosedPositions(String userId, { int limit = 20 });
}
```

---

## 10. flutter_app/lib/cubits/order_cubit.dart

```dart
// States: OrderInitial, OrderPlacing, OrderPlaced, OrderFailed
class OrderCubit extends Cubit<OrderState> {
  Future<void> placeOrder({ required AlgoSignal signal, required int quantity });
  Future<void> cancelOrder(String orderId);
}
```

---

## 11. flutter_app/lib/cubits/position_cubit.dart

```dart
// States: PositionLoading, PositionLoaded(positions, totalPnl), PositionError
class PositionCubit extends Cubit<PositionState> {
  // Combines PositionRepository stream + LivePriceCubit prices to compute live P&L
  void loadPositions(String userId);
}
```

---

## 12. flutter_app/lib/screens/order_book_screen.dart

Show all orders grouped by status (active / completed / rejected).
Each order card shows: symbol, action, qty, price, status chip, angel order ID, timestamp.
Tap → detail sheet with cancel/modify options (for open orders).

---

## 13. flutter_app/lib/screens/positions_screen.dart

Show open positions with:
- Live LTP from `LivePriceCubit` (auto-updates without rebuild)
- P&L displayed in green/red
- Close position button → triggers a SELL/BUY order
- Swipe to refresh → calls `sync-positions/:userId`

---

## 14. flutter_app/lib/screens/algo_config_screen.dart

Admin/user config screen:
- Global algo on/off toggle (writes to `app_config/algo_risk`)
- Position size (% of capital per trade)
- Max open positions
- Daily loss limit
- Per-plan auto-execute toggle

---

## 15. Firebase Firestore Rules additions

Add to `firebase/firestore.rules`:

```
match /algo_signals/{signalId} {
  allow read: if isSignedIn() && hasActiveSub();
  allow write: if false; // admin only via Firebase Functions / Admin SDK
}

match /orders/{orderId} {
  allow read: if isSignedIn() && resource.data.user_id == request.auth.uid;
  allow create: if isSignedIn() && request.resource.data.user_id == request.auth.uid;
  allow update: if false; // price-server updates via Admin SDK only
}

match /positions/{positionId} {
  allow read: if isSignedIn() && resource.data.user_id == request.auth.uid;
  allow write: if false; // price-server writes via Admin SDK only
}
```

---

## 16. Firebase Function: onAlgoSignalWritten

Add to `firebase/functions/index.ts` — triggers when `algo_signals/{id}` is written.
When `is_published` transitions `false → true` AND `auto_execute == true`:
1. Fetch all active subscribers for the signal's `plan_ids`
2. For each subscriber, call price-server `POST /place-order`
3. Send FCM notification of order placement

```typescript
export const onAlgoSignalWritten = onDocumentWritten(
  'algo_signals/{docId}',
  async (event) => { ... }
);
```
