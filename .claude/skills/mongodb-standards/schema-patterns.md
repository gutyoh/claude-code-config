# Schema Design Patterns

## Embedding vs Referencing

The most fundamental MongoDB schema decision. Design for your queries, not your entities.

### When to Embed

- Data is always accessed together (1:1 or 1:few)
- Child data doesn't make sense without the parent
- Array is bounded (won't grow unboundedly)
- Atomic updates needed (single document = atomic)

```javascript
// GOOD: Address embedded in user (1:1, always accessed together)
{
  _id: ObjectId("..."),
  name: "Alice",
  email: "alice@example.com",
  address: {
    street: "123 Main St",
    city: "New York",
    state: "NY",
    zip: "10001"
  }
}

// GOOD: Order items embedded (1:few, bounded array)
{
  _id: ObjectId("..."),
  orderId: "ORD-001",
  items: [
    { productId: "P1", name: "Widget", quantity: 2, price: 9.99 },
    { productId: "P2", name: "Gadget", quantity: 1, price: 24.99 }
  ],
  total: 44.97
}
```

### When to Reference

- Data is accessed independently
- Array would grow unboundedly (comments, logs, events)
- Many-to-many relationships
- Child data is large or frequently updated independently

```javascript
// Users collection
{ _id: ObjectId("u1"), name: "Alice", email: "alice@example.com" }

// Orders collection (references user)
{ _id: ObjectId("o1"), userId: ObjectId("u1"), total: 44.97, createdAt: ISODate("...") }

// Use $lookup to join when needed
db.orders.aggregate([
  { $match: { userId: ObjectId("u1") } },
  { $lookup: { from: "users", localField: "userId", foreignField: "_id", as: "user" } }
])
```

## Schema Design Patterns

### Computed Pattern

Pre-compute frequently accessed aggregations to avoid expensive `$group` at read time.

```javascript
// Instead of aggregating orders every read:
// Store running totals on the customer document
{
  _id: ObjectId("..."),
  name: "Alice",
  totalOrders: 42,
  totalSpent: 1847.50,
  lastOrderAt: ISODate("2026-03-15T10:30:00Z")
}

// Update on each new order
db.customers.updateOne(
  { _id: customerId },
  {
    $inc: { totalOrders: 1, totalSpent: orderTotal },
    $set: { lastOrderAt: new Date() }
  }
)
```

### Subset Pattern

Store frequently accessed subset of data in the parent, full data in a child collection.

```javascript
// Product with top 10 reviews embedded (fast read)
{
  _id: ObjectId("..."),
  name: "Widget Pro",
  price: 29.99,
  avgRating: 4.5,
  recentReviews: [
    { userId: "u1", rating: 5, text: "Great!", createdAt: ISODate("...") },
    { userId: "u2", rating: 4, text: "Good value", createdAt: ISODate("...") }
  ]
}

// Full reviews in separate collection
// reviews: { productId, userId, rating, text, createdAt, ... }
```

### Bucket Pattern

Group time-series or sequential data into buckets to reduce document count.

```javascript
// Instead of one document per sensor reading:
// Bucket readings by hour
{
  sensorId: "temp-001",
  date: ISODate("2026-03-15T10:00:00Z"),
  readings: [
    { ts: ISODate("2026-03-15T10:00:15Z"), value: 22.5 },
    { ts: ISODate("2026-03-15T10:00:30Z"), value: 22.6 },
    { ts: ISODate("2026-03-15T10:00:45Z"), value: 22.4 }
  ],
  count: 3,
  sum: 67.5,
  min: 22.4,
  max: 22.6
}
```

### Extended Reference Pattern

Store a copy of frequently accessed fields from referenced documents to avoid `$lookup`.

```javascript
// Order stores a copy of customer name and email (denormalized)
{
  _id: ObjectId("..."),
  customer: {
    _id: ObjectId("u1"),
    name: "Alice",        // copied from customers collection
    email: "alice@ex.com" // copied from customers collection
  },
  items: [...],
  total: 44.97
}
```

Trade-off: faster reads, but copied data can become stale. Use when the referenced data rarely changes.

## Document Size Guidelines

- MongoDB max document size: **16 MB**
- Keep documents under **1 MB** for optimal performance
- Arrays should be bounded — if an array can grow to thousands of items, use a separate collection
- Nesting depth: **3 levels max** for readability and query simplicity

## Anti-Patterns

1. **Unbounded arrays**: Comments, logs, events arrays that grow forever — use separate collections
2. **Massive documents**: Embedding everything creates 16MB+ documents — split into references
3. **Normalizing like SQL**: Over-referencing forces expensive `$lookup` chains — embed when data is accessed together
4. **No schema consistency**: Even though MongoDB is schema-flexible, use consistent field names and types across documents
5. **Storing computed values without updating them**: Pre-computed fields must be maintained on every write
