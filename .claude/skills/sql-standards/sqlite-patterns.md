# SQLite Patterns

## CLI: `sqlite3`

SQLite is file-based — no server, no connection string, no authentication. One database per file. Pre-installed on macOS and most Linux distributions.

### Connection

```bash
# Open a database file
sqlite3 /path/to/database.db

# Open in read-only mode
sqlite3 -readonly /path/to/database.db

# In-memory database
sqlite3 ":memory:"

# Execute and exit
sqlite3 database.db "SELECT * FROM users LIMIT 10;"
```

### Output Formats

```bash
# JSON mode (SQLite 3.33+)
sqlite3 database.db ".mode json" "SELECT * FROM users LIMIT 10;"

# CSV mode
sqlite3 database.db ".mode csv" ".headers on" "SELECT * FROM users LIMIT 10;"

# Column mode (tabular)
sqlite3 database.db ".mode column" ".headers on" "SELECT * FROM users LIMIT 10;"

# Line mode (one column per line)
sqlite3 database.db ".mode line" "SELECT * FROM users LIMIT 1;"

# Multiple commands via heredoc
sqlite3 database.db <<'SQL'
.mode json
.headers on
SELECT * FROM users LIMIT 10;
SQL
```

### Schema Discovery

```bash
# List tables
sqlite3 database.db ".tables"

# List tables (SQL, more detail)
sqlite3 database.db "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view') ORDER BY name;"

# Describe table (show CREATE statement)
sqlite3 database.db ".schema users"

# Column info (PRAGMA)
sqlite3 database.db "PRAGMA table_info(users);"

# List indexes
sqlite3 database.db ".indexes users"
sqlite3 database.db "PRAGMA index_list(users);"

# Foreign keys
sqlite3 database.db "PRAGMA foreign_key_list(users);"

# Database size
sqlite3 database.db "PRAGMA page_count;" "PRAGMA page_size;"
# Size in bytes = page_count * page_size
```

### SQLite-Specific SQL

```sql
-- UPSERT (ON CONFLICT, SQLite 3.24+)
INSERT INTO users (email, name) VALUES ('alice@example.com', 'Alice')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

-- AUTOINCREMENT
CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL,
    total REAL,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Note: INTEGER PRIMARY KEY is already auto-incrementing without AUTOINCREMENT
-- AUTOINCREMENT adds the guarantee that IDs are never reused

-- Date/time functions (stored as TEXT, REAL, or INTEGER)
SELECT datetime('now');
SELECT date('now', '-30 days');
SELECT strftime('%Y-%m-%d', created_at) FROM orders;

-- JSON functions (SQLite 3.38+)
SELECT json_extract(data, '$.name') AS name FROM documents;
SELECT * FROM documents WHERE json_extract(data, '$.status') = 'active';

-- String concatenation (|| operator)
SELECT first_name || ' ' || last_name AS full_name FROM users;

-- No ILIKE — use lower()
SELECT * FROM users WHERE lower(name) LIKE '%alice%';

-- EXPLAIN
EXPLAIN QUERY PLAN SELECT * FROM users WHERE email = 'alice@example.com';

-- Attach another database
ATTACH DATABASE 'other.db' AS other;
SELECT * FROM other.users LIMIT 10;
```

### Key SQLite Limitations

- No `ALTER TABLE DROP COLUMN` (before 3.35.0)
- No `RIGHT JOIN` or `FULL OUTER JOIN` (before 3.39.0)
- No native `BOOLEAN` type (uses 0/1 integers)
- No `GRANT`/`REVOKE` (file-system permissions only)
- No concurrent write access (single-writer, multiple-reader)
- Types are suggestions, not enforced (dynamic typing)
