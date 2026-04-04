# Index Patterns

## Index Fundamentals

Every query should use an index. Without one, MongoDB scans every document (COLLSCAN).

### Create Index

```javascript
// Single field index
db.users.createIndex({ email: 1 })     // ascending
db.events.createIndex({ createdAt: -1 }) // descending

// Compound index (multi-field)
db.orders.createIndex({ customerId: 1, createdAt: -1 })

// Unique index
db.users.createIndex({ email: 1 }, { unique: true })

// Partial index (only index documents matching a filter)
db.orders.createIndex(
  { status: 1, createdAt: -1 },
  { partialFilterExpression: { status: "active" } }
)

// TTL index (auto-expire documents)
db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 })

// Text index (full-text search)
db.articles.createIndex({ title: "text", body: "text" })

// Wildcard index (dynamic schemas)
db.logs.createIndex({ "metadata.$**": 1 })
```

### List and Drop Indexes

```javascript
// List all indexes on a collection
db.users.getIndexes()

// Drop a specific index
db.users.dropIndex("email_1")

// Drop all indexes except _id
db.users.dropIndexes()
```

## ESR Rule for Compound Indexes

Order compound index fields by **Equality → Sort → Range**:

```javascript
// Query: find active users in a city, sorted by createdAt
db.users.find({ status: "active", city: "NYC" }).sort({ createdAt: -1 })

// GOOD: ESR order — Equality (status, city), Sort (createdAt)
db.users.createIndex({ status: 1, city: 1, createdAt: -1 })

// BAD: Range before equality
db.users.createIndex({ createdAt: -1, status: 1, city: 1 })
```

## Explain — Verify Index Usage

Always use `explain()` to confirm your query uses the intended index.

```javascript
// Quick check — shows winning plan
db.users.find({ email: "alice@example.com" }).explain()

// Full execution stats — shows actual performance
db.users.find({ email: "alice@example.com" }).explain("executionStats")

// All plans considered
db.users.find({ email: "alice@example.com" }).explain("allPlansExecution")
```

### CLI One-Liner

```bash
mongosh "mongodb://localhost/mydb" --quiet --json=relaxed \
  --eval "db.users.find({email:'alice@example.com'}).explain('executionStats')"
```

### Reading explain() Output

| Field | Good Value | Bad Value |
|-------|-----------|-----------|
| `winningPlan.stage` | `IXSCAN` (index scan) | `COLLSCAN` (full collection scan) |
| `executionStats.totalDocsExamined` | Close to `nReturned` | Much larger than `nReturned` |
| `executionStats.executionTimeMillis` | Low (< 100ms) | High (> 1000ms) |

## Index Types Reference

| Type | Syntax | Use Case |
|------|--------|----------|
| Single field | `{ field: 1 }` | Simple equality/range queries |
| Compound | `{ a: 1, b: -1 }` | Multi-field queries, sorted results |
| Unique | `{ field: 1 }, { unique: true }` | Enforce uniqueness (email, username) |
| TTL | `{ field: 1 }, { expireAfterSeconds: N }` | Auto-delete expired documents (sessions, logs) |
| Text | `{ field: "text" }` | Full-text search |
| Wildcard | `{ "$**": 1 }` or `{ "field.$**": 1 }` | Dynamic/unknown field names |
| Partial | `{ field: 1 }, { partialFilterExpression: {...} }` | Index only documents matching a condition |
| Geospatial | `{ location: "2dsphere" }` | Location-based queries |
| Hashed | `{ field: "hashed" }` | Hash-based sharding |

## Anti-Patterns

1. **Too many indexes**: Each index consumes RAM and slows writes — only create indexes for actual query patterns
2. **Missing compound indexes**: Multiple single-field indexes are less efficient than one compound index
3. **Wrong field order in compound indexes**: Follow ESR rule (Equality, Sort, Range)
4. **Not checking explain()**: Always verify queries use the intended index
5. **Indexing low-selectivity fields**: Indexing a boolean field with 50/50 distribution is rarely useful
6. **Foreground index builds on production**: Use `{ background: true }` (pre-4.2) or let MongoDB 4.2+ handle it automatically
