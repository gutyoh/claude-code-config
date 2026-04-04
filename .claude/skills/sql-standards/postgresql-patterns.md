# PostgreSQL Patterns

## CLI: `psql`

### Connection

```bash
# URI format (preferred)
psql "postgresql://user:pass@localhost:5432/mydb"

# Flag format
psql -h localhost -p 5432 -U myuser -d mydb

# Environment variables (no password prompt)
PGHOST=localhost PGPORT=5432 PGUSER=myuser PGDATABASE=mydb PGPASSWORD=secret psql
```

### Output Formats

```bash
# CSV (best for parsing)
psql -c "SELECT * FROM users LIMIT 10;" --csv

# Unaligned, no headers (for scripting)
psql -c "SELECT count(*) FROM users;" -t -A

# JSON (via SQL)
psql -c "SELECT json_agg(t) FROM (SELECT * FROM users LIMIT 10) t;" -t -A

# Expanded (vertical, one column per line)
psql -c "SELECT * FROM users LIMIT 1;" -x
```

### Schema Discovery

```bash
# List databases
psql -c "\l" --csv

# List schemas
psql -d mydb -c "\dn" --csv

# List tables in public schema
psql -d mydb -c "\dt public.*" --csv

# Describe table
psql -d mydb -c "\d users" --csv

# List columns with types (information_schema)
psql -d mydb -c "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = 'users' ORDER BY ordinal_position;" --csv

# List indexes
psql -d mydb -c "\di" --csv

# List foreign keys
psql -d mydb -c "SELECT tc.constraint_name, tc.table_name, kcu.column_name, ccu.table_name AS foreign_table, ccu.column_name AS foreign_column FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name WHERE tc.constraint_type = 'FOREIGN KEY';" --csv
```

### PostgreSQL-Specific SQL

```sql
-- UPSERT (ON CONFLICT)
INSERT INTO users (email, name) VALUES ('alice@example.com', 'Alice')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

-- JSON/JSONB
SELECT data->>'name' AS name, data->'address'->>'city' AS city
FROM documents
WHERE data @> '{"status": "active"}';

-- Array operations
SELECT * FROM products WHERE tags @> ARRAY['sale'];

-- ILIKE (case-insensitive LIKE)
SELECT * FROM users WHERE name ILIKE '%alice%';

-- Generate series
SELECT generate_series('2026-01-01'::date, '2026-12-31'::date, '1 month'::interval);

-- Window functions
SELECT name, department, salary,
    rank() OVER (PARTITION BY department ORDER BY salary DESC) as rank
FROM employees;

-- CTE (Common Table Expression)
WITH active_users AS (
    SELECT * FROM users WHERE is_active = true
)
SELECT * FROM active_users WHERE created_at > now() - interval '30 days';

-- EXPLAIN ANALYZE
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM users WHERE email = 'alice@example.com';
```

### CockroachDB Compatibility Note

CockroachDB is PostgreSQL wire-compatible. `psql` connects to CockroachDB directly:

```bash
psql "postgresql://root@localhost:26257/defaultdb?sslmode=disable"
```

CockroachDB also has its own CLI: `cockroach sql --url "postgresql://..."`. Most PostgreSQL SQL works unchanged. Key differences:
- No `LISTEN`/`NOTIFY`
- Limited stored procedure support
- `SERIAL` maps to `INT DEFAULT unique_rowid()` (not a sequence)
- Distributed transactions behave differently under contention
