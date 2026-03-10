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