# DuckDB Patterns

## CLI: `duckdb`

DuckDB is an in-process analytical database. Single dependency-free binary. PostgreSQL-compatible SQL dialect. Can query Parquet, CSV, JSON files directly and ATTACH to PostgreSQL, MySQL, and SQLite databases.

### Connection

```bash
# In-memory (no persistence)
duckdb

# Persistent database file
duckdb /path/to/analytics.duckdb

# Read-only
duckdb -readonly analytics.duckdb

# Execute and exit
duckdb -c "SELECT 42;"

# Execute with JSON output
duckdb -c "SELECT * FROM read_parquet('data.parquet') LIMIT 10;" -json
```

### Output Formats

```bash
# JSON (best for parsing)
duckdb -c "SELECT * FROM users LIMIT 10;" -json

# CSV
duckdb -c "SELECT * FROM users LIMIT 10;" -csv

# Markdown table
duckdb -c ".mode markdown" -c "SELECT * FROM users LIMIT 10;"

# Line mode (one column per line)
duckdb -c ".mode line" -c "SELECT * FROM users LIMIT 1;"
```

### Schema Discovery

```bash
# List databases (including attached)
duckdb -c "SHOW DATABASES;" -json

# List tables
duckdb db.duckdb -c "SHOW TABLES;" -json

# Describe table
duckdb db.duckdb -c "DESCRIBE users;" -json

# Show create table
duckdb db.duckdb -c "SELECT sql FROM duckdb_tables() WHERE table_name = 'users';" -json

# Column info
duckdb db.duckdb -c "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = 'users';" -json

# Database size
duckdb db.duckdb -c "CALL pragma_database_size();" -json
```

### Cross-Database Queries (Killer Feature)

DuckDB can attach to PostgreSQL, MySQL, and SQLite databases and query them in a single SQL statement.

```bash
# Install extensions (one-time)
duckdb -c "INSTALL postgres; INSTALL mysql; INSTALL sqlite;"

# Attach PostgreSQL
duckdb -c "
ATTACH 'postgresql://user:pass@localhost:5432/mydb' AS pg (TYPE postgres);
SELECT * FROM pg.public.users LIMIT 10;
"

# Attach MySQL
duckdb -c "
ATTACH 'mysql://user:pass@localhost:3306/mydb' AS my (TYPE mysql);
SELECT * FROM my.users LIMIT 10;
"

# Attach SQLite
duckdb -c "
ATTACH 'sqlite:data.db' AS sq;
SELECT * FROM sq.users LIMIT 10;
"

# Cross-database JOIN
duckdb -c "
ATTACH 'postgresql://user:pass@localhost/crm' AS pg (TYPE postgres);
ATTACH 'sqlite:analytics.db' AS sq;
SELECT pg.public.customers.name, sq.events.event_type, sq.events.created_at
FROM pg.public.customers
JOIN sq.events ON pg.public.customers.id = sq.events.customer_id
LIMIT 100;
" -json
```

### File Queries (No Database Needed)

```bash
# Query Parquet files
duckdb -c "SELECT * FROM read_parquet('data/*.parquet') LIMIT 10;" -json

# Query CSV files
duckdb -c "SELECT * FROM read_csv('data.csv', header=true) LIMIT 10;" -json

# Query JSON files
duckdb -c "SELECT * FROM read_json('data.json') LIMIT 10;" -json

# Query remote files (S3, HTTP)
duckdb -c "SELECT * FROM read_parquet('s3://bucket/path/data.parquet') LIMIT 10;" -json
duckdb -c "SELECT * FROM read_parquet('https://example.com/data.parquet') LIMIT 10;" -json

# Export query results
duckdb -c "COPY (SELECT * FROM read_csv('input.csv')) TO 'output.parquet' (FORMAT PARQUET);"
```

### DuckDB-Specific SQL

```sql
-- PostgreSQL-compatible syntax (DuckDB's dialect is based on PostgreSQL)
SELECT * FROM users WHERE name ILIKE '%alice%';

-- UPSERT (ON CONFLICT, same as PostgreSQL)
INSERT INTO users (email, name) VALUES ('alice@example.com', 'Alice')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

-- Friendly SQL (column aliases in WHERE)
SELECT name, length(name) AS name_len FROM users WHERE name_len > 5;

-- PIVOT
PIVOT sales ON product_category USING sum(amount);

-- List comprehensions in SQL
SELECT list_transform([1, 2, 3], x -> x * 2);

-- EXPLAIN ANALYZE
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'alice@example.com';

-- SUMMARIZE (quick stats)
SUMMARIZE SELECT * FROM users;

-- SAMPLE (random rows)
SELECT * FROM users USING SAMPLE 10;
```
