# SQL Server (T-SQL) Patterns

## CLI: `sqlcmd`

### Connection

```bash
# Standard
sqlcmd -S localhost,1433 -U sa -P 'YourPassword' -d mydb

# Windows Authentication (trusted)
sqlcmd -S localhost -E -d mydb

# Azure SQL
sqlcmd -S myserver.database.windows.net -U myuser -P 'pass' -d mydb -G

# Execute and exit
sqlcmd -S localhost -U sa -P 'pass' -d mydb -Q "SELECT 1;"
```

### Output Formats

```bash
# Comma-separated with trimmed whitespace
sqlcmd -Q "SELECT * FROM users;" -W -s ","

# No headers, no dashes
sqlcmd -Q "SELECT * FROM users;" -W -s "," -h -1

# Unlimited column width (prevents truncation)
sqlcmd -Q "SELECT * FROM users;" -y 0

# JSON output (via SQL FOR JSON)
sqlcmd -Q "SELECT * FROM users FOR JSON PATH;" -y 0 -h -1

# XML output (via SQL FOR XML)
sqlcmd -Q "SELECT * FROM users FOR XML PATH('user'), ROOT('users');"
```

### Schema Discovery

```bash
# List databases
sqlcmd -Q "SELECT name FROM sys.databases;" -W -s "," -h -1

# List schemas
sqlcmd -d mydb -Q "SELECT name FROM sys.schemas;" -W -s ","

# List tables
sqlcmd -d mydb -Q "SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS full_name FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE';" -W -s ","

# Describe table
sqlcmd -d mydb -Q "SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'users' ORDER BY ORDINAL_POSITION;" -W -s ","

# sp_help (detailed info)
sqlcmd -d mydb -Q "EXEC sp_help 'users';"

# List indexes
sqlcmd -d mydb -Q "SELECT i.name AS index_name, c.name AS column_name, i.type_desc FROM sys.indexes i JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id WHERE i.object_id = OBJECT_ID('users');" -W -s ","

# Table sizes
sqlcmd -d mydb -Q "EXEC sp_spaceused 'users';"
```

### T-SQL-Specific SQL

```sql
-- Pagination (SQL Server 2012+)
SELECT * FROM users
ORDER BY id
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

-- Legacy pagination (pre-2012)
SELECT TOP 10 * FROM users ORDER BY id;

-- UPSERT (MERGE)
MERGE INTO users AS target
USING (VALUES ('alice@example.com', 'Alice')) AS source (email, name)
ON target.email = source.email
WHEN MATCHED THEN UPDATE SET name = source.name
WHEN NOT MATCHED THEN INSERT (email, name) VALUES (source.email, source.name);

-- Identity column
CREATE TABLE orders (
    id INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT NOT NULL,
    total DECIMAL(10,2),
    created_at DATETIME2 DEFAULT GETDATE()
);

-- String concatenation (+ operator)
SELECT first_name + ' ' + last_name AS full_name FROM users;

-- JSON (SQL Server 2016+)
SELECT JSON_VALUE(data, '$.name') AS name,
       JSON_QUERY(data, '$.address') AS address
FROM documents
WHERE ISJSON(data) = 1;

-- OPENJSON for parsing JSON arrays
SELECT * FROM OPENJSON(@json) WITH (name NVARCHAR(100), age INT);

-- Identifier quoting uses [brackets]
SELECT [user].[name], [order].[total]
FROM [dbo].[user]
JOIN [dbo].[order] ON [user].[id] = [order].[user_id];

-- EXPLAIN equivalent
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT * FROM users WHERE email = 'alice@example.com';
-- Or: display estimated execution plan
SET SHOWPLAN_TEXT ON;
GO
SELECT * FROM users WHERE email = 'alice@example.com';
GO
SET SHOWPLAN_TEXT OFF;
```
