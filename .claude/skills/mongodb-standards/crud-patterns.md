# CRUD Patterns

## Read Operations

### find

```javascript
// Find with filter and projection
db.users.find(
  { status: "active", age: { $gte: 18 } },
  { name: 1, email: 1, _id: 0 }
).limit(100)

// Find one document
db.users.findOne({ email: "alice@example.com" })

// Regex search (case-insensitive)
db.products.find({ name: { $regex: /laptop/i } }).limit(20)

// Array contains
db.products.find({ tags: { $in: ["sale", "featured"] } })

// Nested field
db.orders.find({ "address.city": "New York" })

// Exists check
db.users.find({ phone: { $exists: true } })

// Comparison operators
db.products.find({
  price: { $gte: 10, $lte: 100 },
  stock: { $gt: 0 }
})

// Sort, skip, limit (pagination)
db.products.find({}).sort({ createdAt: -1 }).skip(20).limit(10)
```

### CLI One-Liners

```bash
# Find with JSON output
mongosh "mongodb://localhost/mydb" --quiet --json=relaxed \
  --eval "db.users.find({status:'active'}).limit(10).toArray()"

# Count documents
mongosh "mongodb://localhost/mydb" --quiet \
  --eval "db.users.countDocuments({status:'active'})"

# Distinct values
mongosh "mongodb://localhost/mydb" --quiet --json=relaxed \
  --eval "db.users.distinct('status')"
```

## Create Operations

### insertOne

```javascript
db.users.insertOne({
  name: "Alice",
  email: "alice@example.com",
  status: "active",
  createdAt: new Date()
})
```

### insertMany

```javascript
db.users.insertMany([
  { name: "Bob", email: "bob@example.com", status: "active" },
  { name: "Carol", email: "carol@example.com", status: "pending" }
])
```

## Update Operations

### updateOne

```javascript
// $set — set field values
db.users.updateOne(
  { email: "alice@example.com" },
  { $set: { status: "inactive", updatedAt: new Date() } }
)

// $inc — increment numeric field
db.products.updateOne(
  { _id: ObjectId("...") },
  { $inc: { stock: -1, soldCount: 1 } }
)

// $push — add to array
db.users.updateOne(
  { _id: ObjectId("...") },
  { $push: { tags: "premium" } }
)

// $pull — remove from array
db.users.updateOne(
  { _id: ObjectId("...") },
  { $pull: { tags: "trial" } }
)

// $addToSet — add to array only if not present
db.users.updateOne(
  { _id: ObjectId("...") },
  { $addToSet: { roles: "admin" } }
)

// $unset — remove a field
db.users.updateOne(
  { _id: ObjectId("...") },
  { $unset: { temporaryField: "" } }
)
```

### updateMany

```javascript
// Always use a specific filter — NEVER empty {}
db.users.updateMany(
  { status: "trial", createdAt: { $lt: new Date("2025-01-01") } },
  { $set: { status: "expired" } }
)
```

### replaceOne

```javascript
// Replaces the entire document (except _id)
db.users.replaceOne(
  { email: "alice@example.com" },
  { name: "Alice Smith", email: "alice@example.com", status: "active", updatedAt: new Date() }
)
```

## Delete Operations

### deleteOne

```javascript
db.sessions.deleteOne({ _id: ObjectId("...") })
```

### deleteMany

```javascript
// Always use a specific filter — NEVER empty {}
db.sessions.deleteMany({ expiresAt: { $lt: new Date() } })
```

## Bulk Operations

```javascript
db.users.bulkWrite([
  { insertOne: { document: { name: "Dave", email: "dave@example.com" } } },
  { updateOne: { filter: { email: "alice@example.com" }, update: { $set: { status: "vip" } } } },
  { deleteOne: { filter: { email: "old@example.com" } } }
], { ordered: false })
```

## Query Operators Reference

| Operator | Description | Example |
|----------|-------------|---------|
| `$eq` | Equals | `{ status: { $eq: "active" } }` |
| `$ne` | Not equals | `{ status: { $ne: "deleted" } }` |
| `$gt`, `$gte` | Greater than (or equal) | `{ age: { $gte: 18 } }` |
| `$lt`, `$lte` | Less than (or equal) | `{ price: { $lt: 100 } }` |
| `$in` | In array | `{ status: { $in: ["active", "pending"] } }` |
| `$nin` | Not in array | `{ role: { $nin: ["banned"] } }` |
| `$exists` | Field exists | `{ phone: { $exists: true } }` |
| `$regex` | Pattern match | `{ name: { $regex: /^A/i } }` |
| `$elemMatch` | Array element match | `{ scores: { $elemMatch: { $gte: 80 } } }` |
| `$and` | Logical AND | `{ $and: [{ a: 1 }, { b: 2 }] }` |
| `$or` | Logical OR | `{ $or: [{ a: 1 }, { b: 2 }] }` |
| `$not` | Logical NOT | `{ age: { $not: { $lt: 18 } } }` |
