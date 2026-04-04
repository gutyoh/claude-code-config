# Oracle Patterns

## CLI: `sql` (SQLcl) or `sqlplus`

Oracle has two CLIs:
- **SQLcl** (`sql`) — modern, Java-based, better UX, JSON/CSV output. Recommended.
- **SQL*Plus** (`sqlplus`) — legacy, ships with Oracle Instant Client. Ubiquitous but clunky output.

### Connection

```bash
# SQLcl (preferred)
sql user/password@host:1521/service_name
sql user/password@//host:1521/service_name

# SQL*Plus
sqlplus user/password@host:1521/service_name
sqlplus user/password@//host:1521/service_name

# Easy Connect (TNS-less)
sqlplus user/password@host/service_name

# Execute and exit (SQLcl)
sql -S user/password@host/service <<< "SELECT 1 FROM DUAL;"

# Execute and exit (SQL*Plus)
echo "SELECT 1 FROM DUAL;" | sqlplus -S user/password@host/service
```

### Output Formats

```bash
# SQLcl — CSV
sql -S user/pass@host/svc <<< "SET SQLFORMAT CSV; SELECT * FROM users WHERE ROWNUM <= 10;"

# SQLcl — JSON
sql -S user/pass@host/svc <<< "SET SQLFORMAT JSON; SELECT * FROM users WHERE ROWNUM <= 10;"

# SQL*Plus — control formatting
sqlplus -S user/pass@host/svc <<'SQL'
SET PAGESIZE 0
SET LINESIZE 200
SET COLSEP ','
SET HEADING ON
SET FEEDBACK OFF
SELECT * FROM users WHERE ROWNUM <= 10;
SQL
```

### Schema Discovery

```bash
# List schemas (users with objects)
sql -S user/pass@host/svc <<< "SELECT username FROM all_users ORDER BY username;"

# List tables in current schema
sql -S user/pass@host/svc <<< "SELECT table_name FROM user_tables ORDER BY table_name;"

# List tables in another schema
sql -S user/pass@host/svc <<< "SELECT table_name FROM all_tables WHERE owner = 'HR' ORDER BY table_name;"

# Describe table
sql -S user/pass@host/svc <<< "DESCRIBE users;"

# Column info
sql -S user/pass@host/svc <<< "SELECT column_name, data_type, nullable, data_default FROM user_tab_columns WHERE table_name = 'USERS' ORDER BY column_id;"

# List indexes
sql -S user/pass@host/svc <<< "SELECT index_name, column_name FROM user_ind_columns WHERE table_name = 'USERS' ORDER BY column_position;"

# List constraints
sql -S user/pass@host/svc <<< "SELECT constraint_name, constraint_type, search_condition FROM user_constraints WHERE table_name = 'USERS';"
```

### Oracle-Specific SQL

```sql
-- Pagination (Oracle 12c+)
SELECT * FROM users
ORDER BY id
FETCH FIRST 10 ROWS ONLY;

-- Pagination (pre-12c)
SELECT * FROM (
    SELECT u.*, ROWNUM rn FROM users u WHERE ROWNUM <= 20
) WHERE rn > 10;

-- MERGE (Oracle's UPSERT)
MERGE INTO users target
USING (SELECT 'alice@example.com' AS email, 'Alice' AS name FROM DUAL) source
ON (target.email = source.email)
WHEN MATCHED THEN UPDATE SET name = source.name
WHEN NOT MATCHED THEN INSERT (email, name) VALUES (source.email, source.name);

-- Sequences (auto-increment equivalent)
CREATE SEQUENCE users_seq START WITH 1 INCREMENT BY 1;
INSERT INTO users (id, name) VALUES (users_seq.NEXTVAL, 'Alice');

-- Identity columns (Oracle 12c+)
CREATE TABLE orders (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id NUMBER NOT NULL,
    total NUMBER(10,2),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- String concatenation (|| operator)
SELECT first_name || ' ' || last_name AS full_name FROM users;

-- NVL (Oracle-specific, use COALESCE for portability)
SELECT NVL(nickname, name) AS display_name FROM users;

-- SYSDATE and SYSTIMESTAMP
SELECT SYSDATE, SYSTIMESTAMP FROM DUAL;

-- EXPLAIN PLAN
EXPLAIN PLAN FOR SELECT * FROM users WHERE email = 'alice@example.com';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());

-- JSON (Oracle 12c+)
SELECT JSON_VALUE(data, '$.name') AS name FROM documents;

-- Dual table (required for SELECT without FROM)
SELECT 1 + 1 FROM DUAL;
```

### Key Oracle Differences

- **DUAL table**: `SELECT 1 FROM DUAL` (not just `SELECT 1`)
- **No LIMIT**: Use `FETCH FIRST N ROWS ONLY` (12c+) or `ROWNUM`
- **Case-sensitive identifiers**: Unquoted identifiers are UPPERCASE by default
- **VARCHAR2** instead of VARCHAR (Oracle recommends `VARCHAR2`)
- **NUMBER** instead of INT/DECIMAL (Oracle uses `NUMBER(precision, scale)`)
- **DATE** includes time component (unlike standard SQL DATE)
- **Empty string = NULL**: Oracle treats `''` as `NULL` (controversial, unique to Oracle)
- **Heavy install**: Oracle Instant Client required for `sqlplus`; SQLcl requires Java
