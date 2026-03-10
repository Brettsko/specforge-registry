#!/bin/bash
set -e

# Install dependencies
if [ -f "go.mod" ]; then
  go mod download
fi

# Compile the application
go build -o auth_server .

# Start the server in the background
./auth_server &
SERVER_PID=$!
trap "kill $SERVER_PID 2>/dev/null || true" EXIT

# Give server time to start
sleep 2

BASE_URL="http://localhost:8080"
REGISTER_EMAIL="testuser@example.com"
REGISTER_PASSWORD="password123"

echo "=== Test 1: User can register with valid email and password ==="
REGISTER_RESPONSE=$(curl -s -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$REGISTER_EMAIL\",\"password\":\"$REGISTER_PASSWORD\"}")
echo "Response: $REGISTER_RESPONSE"
REGISTER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"testuser2@example.com\",\"password\":\"password123\"}")
test "$REGISTER_STATUS" = "201" || (echo "ERROR: Expected 201, got $REGISTER_STATUS" && exit 1)
echo "PASS: Registration returns HTTP 201"

echo "=== Test 2: Registration rejects duplicate email with HTTP 409 ==="
DUPLICATE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$REGISTER_EMAIL\",\"password\":\"password456\"}")
test "$DUPLICATE_STATUS" = "409" || (echo "ERROR: Expected 409 for duplicate email, got $DUPLICATE_STATUS" && exit 1)
echo "PASS: Registration rejects duplicate email"

echo "=== Test 3: Registration rejects invalid email with HTTP 400 ==="
INVALID_EMAIL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"invalidemail\",\"password\":\"password123\"}")
test "$INVALID_EMAIL_STATUS" = "400" || (echo "ERROR: Expected 400 for invalid email, got $INVALID_EMAIL_STATUS" && exit 1)
echo "PASS: Registration rejects invalid email"

echo "=== Test 4: Registration rejects short password with HTTP 400 ==="
SHORT_PASSWORD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"newuser@example.com\",\"password\":\"short\"}")
test "$SHORT_PASSWORD_STATUS" = "400" || (echo "ERROR: Expected 400 for short password, got $SHORT_PASSWORD_STATUS" && exit 1)
echo "PASS: Registration rejects short password"

echo "=== Test 5: User can login with correct credentials ==="
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$REGISTER_EMAIL\",\"password\":\"$REGISTER_PASSWORD\"}")
echo "Login Response: $LOGIN_RESPONSE"
echo "$LOGIN_RESPONSE" | grep -q "access_token" || (echo "ERROR: Missing access_token in login response" && exit 1)
echo "$LOGIN_RESPONSE" | grep -q "refresh_token" || (echo "ERROR: Missing refresh_token in login response" && exit 1)
echo "PASS: Login returns access_token and refresh_token"

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
REFRESH_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)

echo "=== Test 6: Protected route rejects request without token ==="
NO_TOKEN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/profile")
test "$NO_TOKEN_STATUS" = "401" || (echo "ERROR: Expected 401 without token, got $NO_TOKEN_STATUS" && exit 1)
echo "PASS: Protected route rejects missing token"

echo "=== Test 7: Protected route rejects invalid token ==="
FAKE_TOKEN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/profile" \
  -H "Authorization: Bearer faketoken.invalid.signature")
test "$FAKE_TOKEN_STATUS" = "401" || (echo "ERROR: Expected 401 with fake token, got $FAKE_TOKEN_STATUS" && exit 1)
echo "PASS: Protected route rejects invalid token"

echo "=== Test 8: Protected route returns 200 with valid token ==="
PROFILE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/profile" \
  -H "Authorization: Bearer $ACCESS_TOKEN")
test "$PROFILE_STATUS" = "200" || (echo "ERROR: Expected 200 with valid token, got $PROFILE_STATUS" && exit 1)
echo "PASS: Protected route returns 200 with valid token"

echo "=== Test 9: Refresh token returns new access token ==="
REFRESH_RESPONSE=$(curl -s -X POST "$BASE_URL/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}")
echo "$REFRESH_RESPONSE" | grep -q "access_token" || (echo "ERROR: Missing access_token in refresh response" && exit 1)
echo "PASS: Refresh returns new access token"

echo "=== Test 10: Refresh rejects invalid refresh token ==="
FAKE_REFRESH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"fakeinvalidtoken\"}")
test "$FAKE_REFRESH_STATUS" = "401" || (echo "ERROR: Expected 401 with fake refresh token, got $FAKE_REFRESH_STATUS" && exit 1)
echo "PASS: Refresh rejects invalid token"

echo ""
echo "All acceptance criteria verified ✓"
