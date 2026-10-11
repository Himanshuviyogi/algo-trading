# Firestore Schema — Algo Trading App

## Collections inherited from `recom` (no changes needed)

### `users/{uid}`
```json
{
  "uid": "string",
  "phone_number": "string",
  "name": "string | null",
  "email": "string | null",
  "fcm_token": "string | null",
  "onboarding_skipped": false,
  "created_at": "Timestamp"
}
```

### `subscriptions/{userId_planId}`
```json
{
  "user_id": "string",
  "plan_id": "string",
  "start_date": "Timestamp",
  "expiry_date": "Timestamp",
  "is_active": true
}
```

### `subscription_plans/{planId}`
```json
{
  "name": "Gold Algo Plan",
  "category": "algo",
  "fcm_topic": "algo_gold",
  "pricing": {
    "1_month": 199900,
    "6_month": 999900,
    "1_year": 179900
  },
  "features": ["Auto execution", "F&O signals", "Risk management"],
  "is_active": true,
  "created_at": "Timestamp"
}
```

### `instrument_tokens/{symbol}`
```json
{
  "symbol": "RELIANCE",
  "token": "2885",
  "exchange": "NSE",
  "enabled": true
}
```

---

## New collections for algo trading

### `algo_signals/{signalId}`
This replaces `recommendations`. Same schema as `Recommendation` in the recom project.
The `plan_ids` field gates which subscribers can trigger auto-orders.

```json
{
  "title": "RELIANCE BUY",
  "body": "Strong breakout above 2950 resistance",
  "category": "stocks",
  "type": "short_term",
  "status": "live",
  "plan_ids": ["gold_algo", "silver_algo"],
  "is_published": true,
  "auto_execute": true,
  "posted_at": "Timestamp",
  "stock": {
    "name": "Reliance Industries",
    "symbol": "RELIANCE",
    "logo_url": "string | null"
  },
  "trade": {
    "action": "BUY",
    "entry_price": 2950.00,
    "current_price": 2948.50,
    "range": { "min": 2940.00, "max": 2960.00 },
    "exit_price": null,
    "exit_date": null,
    "option_type": null,
    "strike_price": null,
    "expiry_date": null,
    "lot_size": null
  },
  "analysis": {
    "target": 3100.00,
    "stoploss": 2880.00,
    "duration": "5-7 days"
  },
  "performance": {
    "gain_so_far": 0.0,
    "potential_left": 5.08
  },
  "risk_reward_ratio": 2.1,
  "confidence": "high",
  "meta": {
    "badge": "HOT",
    "posted_by": "Admin",
    "updated_at": "Timestamp"
  }
}
```

**Key new field: `auto_execute: bool`**
When `true` and `is_published` becomes `true`, the Firebase Function triggers an order.

---

### `orders/{orderId}`
Created by the price server order executor after placing an order on Angel One.

```json
{
  "signal_id": "string",
  "user_id": "string",
  "symbol": "RELIANCE",
  "exchange": "NSE",
  "action": "BUY",
  "order_type": "LIMIT",
  "quantity": 1,
  "price": 2950.00,
  "trigger_price": null,
  "angel_order_id": "string | null",
  "status": "pending | open | complete | rejected | cancelled",
  "rejection_reason": "string | null",
  "placed_at": "Timestamp",
  "updated_at": "Timestamp"
}
```

**Status lifecycle:**
```
pending → open → complete
        → rejected
        → cancelled
```

---

### `positions/{positionId}`
Maintained by Firebase Functions when orders are filled.

```json
{
  "user_id": "string",
  "signal_id": "string",
  "order_id": "string",
  "symbol": "RELIANCE",
  "exchange": "NSE",
  "action": "BUY",
  "quantity": 1,
  "avg_price": 2951.00,
  "current_price": 2965.00,
  "pnl": 14.00,
  "pnl_percent": 0.47,
  "status": "open | closed",
  "opened_at": "Timestamp",
  "closed_at": "Timestamp | null"
}
```

---

### `app_config/algo_risk`
Global risk parameters set by admin. Read by the order executor before placing any order.

```json
{
  "max_order_value": 50000,
  "max_open_positions": 5,
  "daily_loss_limit": 10000,
  "position_sizing_percent": 5,
  "enabled": true,
  "updated_at": "Timestamp"
}
```
