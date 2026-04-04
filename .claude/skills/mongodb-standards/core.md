# Core Principles

## 1. Safety Guardrails

### Read-Only by Default

The agent operates in read-only mode unless the user explicitly requests a write operation.

| Level | Operations | When |
|-------|-----------|------|
| **Default (read-only)** | `find`, `findOne`, `countDocuments`, `estimatedDocumentCount`, `aggregate` (without `$merge`/`$out`), `distinct`, `getIndexes`, `stats`, `explain`, `listDatabases`, `listCollections` | Always |
| **Write (explicit + confirm)** | `insertOne`, `insertMany`, `updateOne`, `updateMany` (with filter), `deleteOne`, `deleteMany` (with filter), `createIndex`, `createCollection` | Only when user explicitly asks AND confirms |
| **Destructive (double confirm)** | `dropIndex`, `deleteMany` (with broad filter), `updateMany` (with broad filter) | User asks + confirms + agent warns |
| **NEVER** | `db.dropDatabase()`, `db.collection.drop()`, `deleteMany({})`, `remove({})` with empty filter | Blocked by `sql-guardrail.sh` PreToolUse hook |

### Query Limits

Always add `.limit(100)` to `find()` queries unless the user specifies otherwise. For aggregation pipelines, include a `$limit` stage.

### No Blind Mutations

Never execute `insertMany`, `updateMany`, or `deleteMany` without first inspecting sample documents and confirming with the user.

---

## 2. mongosh Connection and Output

### Connection Patterns

```bash
# Local instance
mongosh "mongodb://localhost:27017/mydb"

# With authentication
mongosh "mongodb://user:password@localhost:27017/mydb?authSource=admin"

# MongoDB Atlas
mongosh "mongodb+srv://user:password@cluster.abc123.mongodb.net/mydb"

# Environment variable
mongosh "${MONGODB_URI}"
```

### Scriptable Output Patterns

```bash
# JSON output (relaxed — parseable by jq)
mongosh "mongodb://localhost:27017/mydb" --quiet --json=relaxed \
  --eval "db.users.find({}).limit(10).toArray()"

# EJSON.stringify for precise control (pretty-printed)
mongosh --quiet --eval "EJSON.stringify(db.users.find({}).limit(10).toArray(), null, 2)"

# Canonical EJSON (preserves BSON types like NumberLong, ObjectId)
mongosh --quiet --json=canonical \
  --eval "db.users.findOne({})"

# Count documents
mongosh --quiet --eval "db.users.countDocuments({})"

# Execute script file
mongosh "mongodb://localhost:27017/mydb" --quiet -f script.js
```

### Detect mongosh Availability

```bash
command -v mongosh &>/dev/null && echo "mongosh available" || echo "mongosh not found"
```

Install: `brew install mongosh` (macOS) or download from https://www.mongodb.com/try/download/shell

---

## 3. Discovery-First Workflow

**CRITICAL**: Never assume which database, collection, or field names exist. Always discover dynamically.

### Step 1: Test Connection

```bash
mongosh "mongodb://localhost:27017" --quiet --eval "db.runCommand({ping: 1})"
# Expected: { ok: 1 }
```

### Step 2: List Databases

```bash
mongosh --quiet --json=relaxed --eval "db.adminCommand('listDatabases').databases.map(d => ({name: d.name, sizeGB: (d.sizeOnDisk/1073741824).toFixed(2)}))"
```

Or interactively: `show dbs`

### Step 3: List Collections

```bash
mongosh "mongodb://localhost:27017/mydb" --quiet --json=relaxed \
  --eval "db.getCollectionNames()"
```

Or interactively: `show collections`

### Step 4: Sample Documents (Inspect Schema)

**Never guess field names.** Always sample first.

```bash
# Get 3 sample documents to understand the schema
mongosh "mongodb://localhost:27017/mydb" --quiet --json=relaxed \
  --eval "db.users.find().limit(3).toArray()"

# Get distinct field names from a sample
mongosh --quiet --eval "
  const sample = db.users.find().limit(100).toArray();
  const fields = new Set();
  sample.forEach(doc => Object.keys(doc).forEach(k => fields.add(k)));
  EJSON.stringify([...fields].sort(), null, 2);
"
```

### Step 5: Write Query Using Exact Field Names

Only after discovering the collection schema, write queries using exact field names from the sample documents.

---

## 4. Output Formatting

### Present Results as Formatted JSON

```
Query succeeded (5 documents)

[
  { "_id": "abc123", "name": "Alice", "email": "alice@example.com", "createdAt": "2026-01-15T08:30:00Z" },
  { "_id": "def456", "name": "Bob", "email": "bob@example.com", "createdAt": "2026-02-20T14:22:00Z" }
]
```

### Truncated Results

```
Query succeeded (100 of 45,231 documents shown — .limit(100) applied)
```

### Aggregation Results

```
Pipeline completed (3 groups)

| department | count | avgSalary |
|------------|-------|-----------|
| Engineering | 42 | 125,000 |
| Marketing | 18 | 95,000 |
| Sales | 25 | 88,000 |
```

### Error Case

```
Query failed: MongoServerError: ns not found (collection does not exist)
```

---

## 5. Anti-Patterns to Avoid

1. **Hardcoded credentials**: Never embed passwords in commands — use connection strings from config files or environment variables (`MONGODB_URI`, `MONGO_URL`)
2. **Guessing field names**: Always sample documents before writing queries
3. **Missing `.limit()`**: Always add `.limit(100)` to `find()` queries
4. **Empty filters in mutations**: Never use `{}` as filter in `deleteMany`, `updateMany`, or `remove`
5. **`$lookup` without indexes**: Always ensure the foreign field has an index before using `$lookup`
6. **Deep nesting**: Keep document nesting to 3 levels max — flatten or reference beyond that
7. **Unbounded arrays**: Arrays that grow unboundedly (e.g., comments, logs) should be in a separate collection
8. **Using `remove()` instead of `deleteOne`/`deleteMany`**: `remove` is deprecated — use the modern CRUD API
9. **Not using `--quiet`**: Without `--quiet`, `mongosh` outputs connection banners that break JSON parsing
10. **Ignoring `explain()`**: Always check query execution plans for slow queries
