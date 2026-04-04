# Aggregation Pipeline Patterns

## Pipeline Basics

An aggregation pipeline is an ordered sequence of stages. Each stage transforms the documents and passes them to the next. Always put `$match` and `$project` early to reduce the working set.

```javascript
db.orders.aggregate([
  { $match: { status: "completed" } },           // 1. Filter early
  { $project: { customerId: 1, total: 1 } },     // 2. Reduce document size
  { $group: { _id: "$customerId", sum: { $sum: "$total" } } },
  { $sort: { sum: -1 } },
  { $limit: 10 }
])
```

## Key Stages

### $match — Filter Documents

```javascript
{ $match: { status: "active", createdAt: { $gte: new Date("2026-01-01") } } }
```

Always place `$match` as early as possible — it uses indexes and reduces documents for subsequent stages.

### $group — Group and Aggregate

```javascript
{ $group: {
  _id: "$department",
  count: { $sum: 1 },
  totalSalary: { $sum: "$salary" },
  avgSalary: { $avg: "$salary" },
  maxSalary: { $max: "$salary" },
  employees: { $push: "$name" },
  uniqueRoles: { $addToSet: "$role" }
}}
```

### $project / $addFields / $set

```javascript
// $project — include/exclude/compute fields
{ $project: {
  name: 1,
  email: 1,
  fullName: { $concat: ["$firstName", " ", "$lastName"] },
  ageGroup: { $cond: { if: { $gte: ["$age", 18] }, then: "adult", else: "minor" } }
}}

// $addFields / $set — add fields without removing existing ones
{ $addFields: {
  totalWithTax: { $multiply: ["$total", 1.08] }
}}
```

### $lookup — Join Collections

```javascript
// Basic lookup (left outer join)
{ $lookup: {
  from: "orders",
  localField: "_id",
  foreignField: "customerId",
  as: "customerOrders"
}}

// Pipeline lookup (more control)
{ $lookup: {
  from: "orders",
  let: { custId: "$_id" },
  pipeline: [
    { $match: { $expr: { $eq: ["$customerId", "$$custId"] } } },
    { $sort: { createdAt: -1 } },
    { $limit: 5 }
  ],
  as: "recentOrders"
}}
```

Ensure the foreign field has an index — `$lookup` without an index on `foreignField` is a full collection scan per document.

### $unwind — Flatten Arrays

```javascript
// Unwind tags array (one document per tag)
{ $unwind: "$tags" }

// Preserve documents with empty/missing arrays
{ $unwind: { path: "$tags", preserveNullAndEmptyArrays: true } }
```

### $sort / $limit / $skip

```javascript
{ $sort: { createdAt: -1 } }   // Descending
{ $limit: 10 }
{ $skip: 20 }                   // For pagination (use range-based pagination for large datasets)
```

### $merge / $out — Write Results

```javascript
// $merge — upsert into target collection (idempotent)
{ $merge: {
  into: "monthly_stats",
  on: ["year", "month"],
  whenMatched: "replace",
  whenNotMatched: "insert"
}}

// $out — replace entire target collection
{ $out: "aggregated_results" }
```

## Common Aggregation Patterns

### Group by Date (Monthly Revenue)

```javascript
db.orders.aggregate([
  { $match: { status: "completed" } },
  { $group: {
    _id: { year: { $year: "$createdAt" }, month: { $month: "$createdAt" } },
    revenue: { $sum: "$total" },
    orders: { $sum: 1 }
  }},
  { $sort: { "_id.year": 1, "_id.month": 1 } }
])
```

### Top N per Group (Window-like)

```javascript
db.employees.aggregate([
  { $sort: { department: 1, salary: -1 } },
  { $group: {
    _id: "$department",
    topEarners: { $push: { name: "$name", salary: "$salary" } }
  }},
  { $project: {
    department: "$_id",
    topEarners: { $slice: ["$topEarners", 3] }
  }}
])
```

### Faceted Search (Multiple Aggregations in One)

```javascript
db.products.aggregate([
  { $match: { status: "active" } },
  { $facet: {
    byCategory: [
      { $group: { _id: "$category", count: { $sum: 1 } } },
      { $sort: { count: -1 } }
    ],
    priceRange: [
      { $group: {
        _id: null,
        min: { $min: "$price" },
        max: { $max: "$price" },
        avg: { $avg: "$price" }
      }}
    ],
    total: [{ $count: "count" }]
  }}
])
```

## Aggregation Operators Reference

| Category | Operators |
|----------|----------|
| Arithmetic | `$add`, `$subtract`, `$multiply`, `$divide`, `$mod`, `$round` |
| String | `$concat`, `$substr`, `$toLower`, `$toUpper`, `$trim`, `$split` |
| Date | `$year`, `$month`, `$dayOfMonth`, `$hour`, `$dateToString`, `$dateDiff` |
| Array | `$size`, `$slice`, `$filter`, `$map`, `$reduce`, `$arrayElemAt` |
| Conditional | `$cond`, `$ifNull`, `$switch` |
| Accumulator | `$sum`, `$avg`, `$min`, `$max`, `$push`, `$addToSet`, `$first`, `$last` |
| Type | `$type`, `$convert`, `$toInt`, `$toString`, `$toDate` |
