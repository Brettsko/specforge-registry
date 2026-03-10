# JWT Authentication Server

## One-sentence summary
A stateless JWT auth server with user registration, login, token refresh, and a protected route using SQLite persistence.

## Dependencies
- Go 1.21+
- SQLite3
- Standard library (crypto/bcrypt, crypto/hmac, encoding/json, net/http, time, database/sql)

## Pages or Endpoints

| Endpoint | Method | Auth Required | Purpose |
|----------|--------|---------------|---------|
| `/register` | POST | No | Create new user account with email and password |
| `/login` | POST | No | Authenticate user and return access and refresh tokens |
| `/refresh` | POST | Yes (refresh token) | Exchange expired access token for new one |
| `/profile` | GET | Yes (access token) | Protected route returning authenticated user information |

## Data model

**Users Table**
```sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**Refresh Tokens Table**
```sql
CREATE TABLE refresh_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  token TEXT UNIQUE NOT NULL,
  expires_at DATETIME NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

**Request/Response Payloads**

Register Request:
```json
{
  "email": "user@example.com",
  "password": "securepassword123"
}
```

Login Request:
```json
{
  "email": "user@example.com",
  "password": "securepassword123"
}
```

Login Response:
```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "expires_in": 3600
}
```

Refresh Request:
```json
{
  "refresh_token": "eyJhbGc..."
}
```

Protected Route Response (`/profile`):
```json
{
  "id": 1,
  "email": "user@example.com"
}
```

## Acceptance criteria

- [ ] User can register with valid email and password via POST `/register` endpoint
- [ ] Registration returns HTTP 201 status code on successful account creation
- [ ] Registration rejects duplicate email address with HTTP 409 Conflict status
- [ ] Registration rejects email without at symbol character with HTTP 400 Bad Request
- [ ] Registration rejects password shorter than eight characters with HTTP 400 Bad Request
- [ ] User can login with registered email and correct password via POST `/login` endpoint
- [ ] Login returns HTTP 200 status code with access token and refresh token
- [ ] Login rejects unregistered email address with HTTP 401 Unauthorized status
- [ ] Login rejects registered email with incorrect password using HTTP 401 Unauthorized status
- [ ] Login response contains access token expiring in three thousand six hundred seconds
- [ ] User can refresh expired access token via POST `/refresh` endpoint with valid refresh token
- [ ] Refresh endpoint returns HTTP 200 status code with new access token on success
- [ ] Refresh rejects expired refresh token with HTTP 401 Unauthorized status code
- [ ] Refresh rejects invalid or nonexistent refresh token with HTTP 401 Unauthorized status
- [ ] Protected route `/profile` rejects requests without JWT token using HTTP 401 Unauthorized
- [ ] Protected route `/profile` rejects requests with invalid JWT token using HTTP 401 Unauthorized
- [ ] Protected route `/profile` returns HTTP 200 with user email when given valid access token
- [ ] Password hashing uses bcrypt algorithm to store user passwords securely in database

## Implementation checklist

- [ ] Set up Go project with main.go and database initialization
- [ ] Create SQLite database schema with users and refresh_tokens tables
- [ ] Implement user registration handler with email validation and bcrypt hashing
- [ ] Implement login handler with password verification and JWT generation
- [ ] Implement token refresh handler with refresh token validation and expiry checking
- [ ] Implement JWT middleware for protected routes using HS256 verification
- [ ] Implement `/profile` protected route demonstrating middleware functionality
- [ ] Add request validation for email format and password length
- [ ] Configure JWT claims structure with user ID and expiry timestamps
- [ ] Implement refresh token storage in SQLite with expiry timestamps
- [ ] Test all endpoints with curl or similar HTTP client
- [ ] Verify bcrypt password hashing is working correctly
- [ ] Verify JWT tokens are signed with HS256 algorithm
- [ ] Verify expired refresh tokens are rejected by server

## Verification Script

```bash
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
echo "$LOGIN_