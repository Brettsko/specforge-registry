# Stripe Subscription Server with Webhook Handling

## One-sentence summary
A Go web API that ingests Stripe webhooks, maintains local customer and subscription state in SQLite, and exposes REST endpoints for customer creation, subscription tracking, and operational dashboards.

## Dependencies
- Go 1.19+
- SQLite3
- Stripe Go SDK (`github.com/stripe/stripe-go/v72`)
- Standard library: `net/http`, `database/sql`, `crypto/hmac`, `encoding/json`

## Pages or Endpoints

### webhook_handler
- **POST /webhooks/stripe**
  - Validates Stripe event signature (HMAC-SHA256).
  - Deduplicates by event_id; skips already-processed events.
  - Processes: `customer.created`, `customer.updated`, `invoice.payment_succeeded`.
  - Atomically writes customer, subscription, and event records to SQLite.
  - Returns 200 JSON `{"success": true}` on valid signature; 400 on invalid.

### customer_api
- **POST /customers**
  - Accepts `{"email": "...", "name": "..."}`.
  - Calls Stripe API to create a remote customer; stores local record in SQLite.
  - Returns 201 JSON `{"id": "cus_...", "email": "...", "created_at": "..."}`.
  - Returns 400 if Stripe API call fails.

- **GET /customers/{customer_id}**
  - Retrieves local customer record from SQLite by Stripe customer ID.
  - Returns 200 JSON with customer details or 404 if not found.

### subscription_tracking
- **POST /subscriptions**
  - Accepts `{"customer_id": "cus_...", "price_id": "price_..."}`.
  - Calls Stripe API to create a subscription; stores local record in SQLite.
  - Returns 201 JSON `{"id": "sub_...", "customer_id": "...", "status": "active", "created_at": "..."}`.
  - Returns 400 if Stripe API call fails.

- **GET /subscriptions/{subscription_id}**
  - Retrieves local subscription record from SQLite by Stripe subscription ID.
  - Returns 200 JSON with subscription state or 404 if not found.

### dashboard_query
- **GET /dashboard**
  - Returns 200 JSON aggregated counts: `{"active": int, "inactive": int, "canceled": int}`.
  - Queries SQLite for subscriptions grouped by current status.

### idempotent_replay
- Integrated into webhook_handler: maintains unique constraint on `(event_id)` in `events` table.
- Webhook endpoint checks event_id before processing; silently returns 200 if already seen.

## Data model

### customers
| Column | Type | Notes |
|--------|------|-------|
| stripe_customer_id | TEXT PRIMARY KEY | Stripe customer ID (cus_...) |
| email | TEXT NOT NULL | Customer email address |
| name | TEXT | Customer display name |
| created_at | TEXT | ISO 8601 timestamp |
| updated_at | TEXT | ISO 8601 timestamp |

### subscriptions
| Column | Type | Notes |
|--------|------|-------|
| stripe_subscription_id | TEXT PRIMARY KEY | Stripe subscription ID (sub_...) |
| stripe_customer_id | TEXT NOT NULL FK | References `customers.stripe_customer_id` |
| status | TEXT NOT NULL | One of: active, inactive, canceled, trialing |
| created_at | TEXT | ISO 8601 timestamp |
| updated_at | TEXT | ISO 8601 timestamp |

### events
| Column | Type | Notes |
|--------|------|-------|
| event_id | TEXT PRIMARY KEY | Stripe event ID; enforces idempotency |
| event_type | TEXT NOT NULL | Event type (customer.created, customer.updated, invoice.payment_succeeded) |
| processed_at | TEXT | ISO 8601 timestamp |

## Acceptance criteria

- [ ] Webhook endpoint validates HMAC-SHA256 signature using Stripe signing secret; rejects invalid signatures with HTTP 400.
- [ ] Webhook endpoint deduplicates by `event_id`; silently returns 200 if event already processed.
- [ ] Webhook endpoint processes `customer.created` events: creates/updates local customer record in SQLite.
- [ ] Webhook endpoint processes `customer.updated` events: updates name and email in local customer record.
- [ ] Webhook endpoint processes `invoice.payment_succeeded` events: marks associated subscription as `active` in SQLite.
- [ ] POST /customers calls Stripe API to create a remote customer and persists local record; returns 201 with Stripe customer ID.
- [ ] POST /customers returns 400 if Stripe API call fails (e.g., invalid email).
- [ ] GET /customers/{customer_id} returns 200 with customer details from SQLite or 404 if not found.
- [ ] POST /subscriptions calls Stripe API to create a remote subscription and persists local record; returns 201 with Stripe subscription ID and status.
- [ ] POST /subscriptions returns 400 if Stripe API call fails (e.g., invalid customer or price).
- [ ] GET /subscriptions/{subscription_id} returns 200 with subscription state from SQLite or 404 if not found.
- [ ] GET /dashboard returns 200 with JSON containing active, inactive, and canceled subscription counts.
- [ ] All customer and subscription records are persisted in SQLite; no in-memory storage without disk backup.

## Implementation checklist

- [ ] Initialize SQLite database with `customers`, `subscriptions`, and `events` tables.
- [ ] Implement HMAC-SHA256 signature validation for Stripe webhooks.
- [ ] Implement event deduplication logic using `event_id` uniqueness constraint.
- [ ] Implement customer.created, customer.updated, invoice.payment_succeeded event handlers.
- [ ] Implement Stripe API integration for customer creation (use test key in verification).
- [ ] Implement Stripe API integration for subscription creation.
- [ ] Implement POST /customers endpoint with validation and error handling.
- [ ] Implement GET /customers/{customer_id} endpoint.
- [ ] Implement POST /subscriptions endpoint with validation and error handling.
- [ ] Implement GET /subscriptions/{subscription_id} endpoint.
- [ ] Implement GET /dashboard endpoint with count aggregation from SQLite.
- [ ] Add HTTP server startup on configurable port (default 8080).
- [ ] Test webhook signature validation and idempotent replay with mock requests.
- [ ] Test Stripe API integration with test keys (sk_test_...).

## Verification Script

```bash
#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Stripe Subscription Server Verification ==="

# 1. Check for Go source files
if ! test -f main.go; then
  echo -e "${RED}ERROR: main.go not found${NC}"
  exit 1
fi
echo -e "${GREEN}✓ main.go exists${NC}"

# 2. Build the application
if ! go build -o subscription-server . 2>&1 | head -20; then
  echo -e "${RED}ERROR: Build failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Build successful${NC}"

# 3. Remove any existing database
rm -f subscription.db

# 4. Start server in background
timeout 10 ./subscription-server &
SERVER_PID=$!
sleep 2

# Verify process started
if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo -e "${RED}ERROR: Server failed to start${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Server started (PID: $SERVER_PID)${NC}"

# 5. Check database was created
if ! test -f subscription.db; then
  kill $SERVER_PID 2>/dev/null || true
  echo -e "${RED}ERROR: subscription.db not created${NC}"
  exit 1
fi
echo -e "${GREEN}✓ SQLite database created${NC}"

# 6. Verify database schema
if ! sqlite3 subscription.db ".tables" | grep -q "customers"; then
  kill $SERVER_PID 2>/dev/null ||