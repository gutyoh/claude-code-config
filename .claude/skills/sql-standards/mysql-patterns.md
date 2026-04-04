# MySQL Patterns

## CLI: `mysql`

### Connection

```bash
# Standard
mysql -h localhost -P 3306 -u root -p mydb

# URI format (MySQL 8.0+)
mysql "mysql://user:pass@localhost:3306/mydb"

# With password inline (avoid in production)
mysql -h localhost -u root --password=secret mydb

# Execute and exit
mysql -h localhost -u root -p mydb -e "SELECT 1;"
```

### Output Formats

```bash
# Batch mode (tab-separated, no box drawing)
mysql -B -e "SELECT * FROM users LIMIT 10;" mydb

# Batch + no headers
mysql -B -N -e "SELECT * FROM users LIMIT 10;" mydb

# Vertical (one column per line, like \G)
mysql -E -e "SELECT * FROM users LIMIT 1;" mydb

# XML output
mysql --xml -e "SELECT * FROM users LIMIT 10;" mydb

# JSON (via SQL)
mysql -B -N -e "SELECT JSON_ARRAYAGG(JSON_OBJECT('id', id, 'name', name)) FROM users LIMIT 10;" mydb
```

### Schema Discovery

```bash
# List databases
mysql -e "SHOW DATABASES;" -B

# List tables
mysql mydb -e "SHOW TABLES;" -B

# Describe table
mysql mydb -e "DESCRIBE users;" -B

# Show create table (full DDL)
mysql mydb -e "SHOW CREATE TABLE users\G"

# List columns with types
mysql mydb -e "SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'users' ORDER BY ORDINAL_POSITION;" -B

# List indexes
mysql mydb -e "SHOW INDEX FROM users;" -B

# Show table sizes
mysql mydb -e "SELECT table_name, ROUND(data_length/1024/1024, 2) AS size_mb, table_rows FROM information_schema.tables WHERE table_schema = 'mydb' ORDER BY data_length DESC;" -B
```

### MySQL-Specific SQL

```sql
-- UPSERT (ON DUPLICATE KEY)
INSERT INTO users (email, name) VALUES ('alice@example.com', 'Alice')
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- Auto-increment
CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    total DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- JSON functions (MySQL 5.7+)
SELECT JSON_EXTRACT(data, '$.name') AS name,
       JSON_UNQUOTE(JSON_EXTRACT(data, '$.address.city')) AS city
FROM documents
WHERE JSON_EXTRACT(data, '$.status') = '"active"';

-- IFNULL (MySQL-specific, use COALESCE for portability)
SELECT IFNULL(nickname, name) AS display_name FROM users;

-- GROUP_CONCAT
SELECT department, GROUP_CONCAT(name ORDER BY name SEPARATOR ', ') AS members
FROM employees GROUP BY department;

-- EXPLAIN
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE email = 'alice@example.com';

-- Full-text search
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('database performance' IN NATURAL LANGUAGE MODE);
```

### MariaDB Compatibility Note

MariaDB is a MySQL fork. The `mariadb` CLI is interchangeable with `mysql`:

```bash
mariadb -h localhost -u root -p mydb -e "SHOW TABLES;"
```

Key differences from MySQL:
- MariaDB has `SEQUENCE` objects (MySQL does not)
- MariaDB supports `INTERSECT` and `EXCEPT` (MySQL added in 8.0)
- MariaDB's JSON is stored as `LONGTEXT` (MySQL uses native binary JSON)
- MariaDB has `SHOW EXPLAIN FOR <thread_id>` (MySQL does not)
- Window functions syntax is identical in both
