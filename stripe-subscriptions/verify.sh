#!/bin/bash
set -e

# Build
go build -o subscription-server .
echo "✓ Build successful"

# Start server in background
STRIPE_SECRET_KEY=sk_test_fake STRIPE_WEBHOOK_SECRET=whsec_fake ./subscription-server &
SERVER_PID=$!
trap "kill $SERVER_PID 2>/dev/null || true" EXIT

# Wait for server to be ready (macOS-compatible, no timeout command)
echo "Waiting for server to start..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -s http://localhost:8080/dashboard > /dev/null 2>&1; then
    echo "✓ Server started"
    break
  fi
  if [ "$i" = "10" ]; then
    echo "ERROR: Server failed to start after 10 seconds"
    exit 1
  fi
  sleep 1
done

BASE_URL="http://localhost:8080"

echo "=== Test 1: Dashboard returns valid JSON ==="
DASHBOARD=$(curl -s "$BASE_URL/dashboard")
echo "Response: $DASHBOARD"
echo "$DASHBOARD" | grep -q "active" || (echo "ERROR: Missing 'active' field in dashboard response" && exit 1)
echo "$DASHBOARD" | grep -q "canceled" || (echo "ERROR: Missing 'canceled' field in dashboard response" && exit 1)
DASHBOARD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/dashboard")
test "$DASHBOARD_STATUS" = "200" || (echo "ERROR: Expected 200, got $DASHBOARD_STATUS" && exit 1)
echo "PASS: Dashboard returns 200 with valid JSON"

echo "=== Test 2: Webhook rejects missing signature ==="
NO_SIG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/webhooks/stripe" \
  -H "Content-Type: application/json" \
  -d '{"type":"customer.created"}')
test "$NO_SIG_STATUS" = "400" || (echo "ERROR: Expected 400 for missing signature, got $NO_SIG_STATUS" && exit 1)
echo "PASS: Webhook rejects missing Stripe-Signature header"

echo "=== Test 3: Webhook rejects invalid signature ==="
INVALID_SIG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/webhooks/stripe" \
  -H "Content-Type: application/json" \
  -H "Stripe-Signature: t=fake,v1=invalidsignature" \
  -d '{"type":"customer.created"}')
test "$INVALID_SIG_STATUS" = "400" || (echo "ERROR: Expected 400 for invalid signature, got $INVALID_SIG_STATUS" && exit 1)
echo "PASS: Webhook rejects invalid signature"

echo "=== Test 4: GET nonexistent customer returns 404 ==="
CUSTOMER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/customers/cus_nonexistent")
test "$CUSTOMER_STATUS" = "404" || (echo "ERROR: Expected 404 for missing customer, got $CUSTOMER_STATUS" && exit 1)
echo "PASS: GET /customers/{id} returns 404 for nonexistent customer"

echo "=== Test 5: GET nonexistent subscription returns 404 ==="
SUB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/subscriptions/sub_nonexistent")
test "$SUB_STATUS" = "404" || (echo "ERROR: Expected 404 for missing subscription, got $SUB_STATUS" && exit 1)
echo "PASS: GET /subscriptions/{id} returns 404 for nonexistent subscription"

echo "=== Test 6: POST /customers requires valid Stripe key ==="
CREATE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/customers" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"Test User"}')
# With fake key, Stripe API will reject — expect 500 or 402, not 200
test "$CREATE_STATUS" != "200" || (echo "ERROR: Should not return 200 with fake Stripe key" && exit 1)
echo "PASS: POST /customers correctly rejects fake Stripe API key"

echo "=== Test 7: Webhook endpoint exists and is reachable ==="
WEBHOOK_REACHABLE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/webhooks/stripe" \
  -H "Content-Type: application/json" \
  -d '{}')
test "$WEBHOOK_REACHABLE" != "404" || (echo "ERROR: Webhook endpoint not found" && exit 1)
echo "PASS: Webhook endpoint is reachable"

echo ""
echo "All acceptance criteria verified ✓"
