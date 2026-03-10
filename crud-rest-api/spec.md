# Task Manager REST API

## One-sentence summary
A minimal Node.js REST API using native `http` module and SQLite for CRUD operations on tasks with automatic timestamps, status filtering, and pagination.

## Dependencies
- Node.js 16+ (built-in `http` and `sqlite3` modules)
- `sqlite3` npm package

## Pages or Endpoints

| Method | Path | Query Parameters | Description |
|--------|------|------------------|-------------|
| POST | /tasks | — | Create a new task (title, description, status) |
| GET | /tasks | ?status=pending\|completed&limit=10&offset=0 | List tasks with optional status filter and pagination |
| GET | /tasks/:id | — | Retrieve a single task by ID |
| PUT | /tasks/:id | — | Update a task (title, description, status) |
| DELETE | /tasks/:id | — | Delete a task by ID |

## Data model

**Tasks table:**
```sql
CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

**Task object:**
```json
{
  "id": 1,
  "title": "Buy groceries",
  "description": "Milk, eggs, bread",
  "status": "pending",
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-15T10:30:00Z"
}
```

## Acceptance criteria

- [ ] POST /tasks with valid title and status creates a task and returns 201 with the new task object including id, created_at, and updated_at timestamps
- [ ] POST /tasks with missing title returns 400 with error message
- [ ] POST /tasks with invalid status (not "pending" or "completed") returns 400 with error message
- [ ] GET /tasks with no parameters returns 200 with all tasks in a JSON array
- [ ] GET /tasks?status=pending returns 200 with only tasks where status="pending"
- [ ] GET /tasks?status=completed returns 200 with only tasks where status="completed"
- [ ] GET /tasks?limit=5&offset=0 returns 200 with at most 5 tasks
- [ ] GET /tasks?limit=5&offset=5 returns 200 with the next 5 tasks (pagination offset works)
- [ ] GET /tasks/:id with valid id returns 200 with the task object
- [ ] GET /tasks/:id with invalid id returns 404 with error message
- [ ] PUT /tasks/:id with valid title or status updates the task and returns 200 with updated object including new updated_at timestamp
- [ ] PUT /tasks/:id with invalid status returns 400 with error message
- [ ] PUT /tasks/:id with valid id but non-existent id returns 404 with error message
- [ ] DELETE /tasks/:id with valid id returns 204 with no response body
- [ ] DELETE /tasks/:id with invalid id returns 404 with error message
- [ ] All task timestamps (created_at, updated_at) are in ISO 8601 format (YYYY-MM-DDTHH:mm:ssZ)
- [ ] POST and PUT requests validate Content-Type is application/json

## Implementation checklist

- [ ] Initialize Node.js project with sqlite3 dependency
- [ ] Create SQLite database and initialize tasks table schema
- [ ] Implement native http server with routing logic for /tasks endpoints
- [ ] Implement POST /tasks handler with inline validation (title required, status enum check, timestamps auto-inserted)
- [ ] Implement GET /tasks handler with status filter query parameter and pagination (limit/offset)
- [ ] Implement GET /tasks/:id handler with 404 handling
- [ ] Implement PUT /tasks/:id handler with inline validation and updated_at auto-update
- [ ] Implement DELETE /tasks/:id handler with 204 response
- [ ] Parse JSON request bodies in POST/PUT handlers
- [ ] Return appropriate HTTP status codes (200, 201, 204, 400, 404)
- [ ] Return JSON responses with Content-Type: application/json header
- [ ] Test all endpoints with curl or similar tool

## Verification Script

```bash
#!/bin/bash
set -e

# Install dependencies
npm install -q sqlite3

# Create a test directory and app
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Create package.json
cat > package.json << 'EOF'
{
  "name": "task-manager-api",
  "version": "1.0.0",
  "type": "module"
}
EOF

# Create the API server
cat > server.js << 'EOF'
import http from 'http';
import sqlite3 from 'sqlite3';
import { URL } from 'url';

const db = new sqlite3.Database(':memory:');

// Initialize database
db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )`);
});

// Validation helpers
const isValidStatus = (status) => ['pending', 'completed'].includes(status);
const getCurrentTimestamp = () => new Date().toISOString();

// Route handler
const handleRequest = async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;
  const searchParams = url.searchParams;
  const method = req.method;

  res.setHeader('Content-Type', 'application/json');

  // Helper: parse JSON body
  const parseBody = () => new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
  });

  // Helper: database run promise
  const dbRun = (sql, params = []) => new Promise((resolve, reject) => {
    db.run(sql, params, function(err) {
      if (err) reject(err);
      else resolve(this);
    });
  });

  // Helper: database get promise
  const dbGet = (sql, params = []) => new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row);
    });
  });

  // Helper: database all promise
  const dbAll = (sql, params = []) => new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows);
    });
  });

  try {
    // POST /tasks
    if (method === 'POST' && pathname === '/tasks') {
      const data = await parseBody();
      const { title, description = '', status = 'pending' } = data;

      if (!title || typeof title !== 'string' || !title.trim()) {
        res.writeHead(400);
        res.end(JSON.stringify({ error: 'title is required' }));
        return;
      }

      if (!isValidStatus(status)) {
        res.writeHead(400);
        res.end(JSON.stringify({ error: 'invalid status' }));
        return;
      }

      const now = getCurrentTimestamp();
      const result = await dbRun(
        `INSERT INTO tasks (title, description, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`,
        [title, description, status, now, now]
      );

      const task = await dbGet('SELECT * FROM tasks WHERE id = ?', [result.lastID]);
      res.writeHead(201);
      res.end(JSON.stringify(task));
      return;
    }

    // GET /tasks
    if (method === 'GET' && pathname === '/tasks') {
      const status = searchParams.get('status');
      const limit = Math.max(1, parseInt(searchParams.get('limit')) || 100