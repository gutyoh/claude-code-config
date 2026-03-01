# Serde Patterns

## Basic Derive

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub name: String,
    pub workers: usize,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

fn default_port() -> u16 {
    8080
}
```

---

## Rename and Case Conventions

```rust
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApiResponse {
    pub status_code: u16,          // serializes as "statusCode"
    pub response_body: String,     // serializes as "responseBody"
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventType {
    UserCreated,       // serializes as "user_created"
    OrderPlaced,       // serializes as "order_placed"
}
```

---

## Enum Representations

```rust
// Tagged (default) — {"type": "Circle", "radius": 5.0}
#[derive(Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Shape {
    Circle { radius: f64 },
    Rectangle { width: f64, height: f64 },
}

// Untagged — {"radius": 5.0} (inferred from fields)
#[derive(Serialize, Deserialize)]
#[serde(untagged)]
pub enum Value {
    Int(i64),
    Float(f64),
    Text(String),
}

// Adjacent tagging — {"t": "Circle", "c": {"radius": 5.0}}
#[derive(Serialize, Deserialize)]
#[serde(tag = "t", content = "c")]
pub enum Message {
    Request { id: u64, method: String },
    Response { id: u64, result: Value },
}
```

---

## Custom Serialization

```rust
use std::time::Duration;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

#[derive(Serialize, Deserialize)]
pub struct Record {
    #[serde(serialize_with = "serialize_duration")]
    #[serde(deserialize_with = "deserialize_duration")]
    pub timeout: Duration,
}

fn serialize_duration<S: Serializer>(duration: &Duration, s: S) -> Result<S::Ok, S::Error> {
    s.serialize_u64(duration.as_secs())
}

fn deserialize_duration<'de, D: Deserializer<'de>>(d: D) -> Result<Duration, D::Error> {
    let secs = u64::deserialize(d)?;
    Ok(Duration::from_secs(secs))
}
```

---

## Deny Unknown Fields

```rust
// Strict deserialization — reject unexpected keys
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StrictConfig {
    pub name: String,
    pub port: u16,
}
```

---

## Flattened and Nested Structures

```rust
#[derive(Serialize, Deserialize)]
pub struct Request {
    pub id: u64,
    #[serde(flatten)]
    pub metadata: Metadata,
    #[serde(flatten)]
    pub extra: HashMap<String, serde_json::Value>,
}

#[derive(Serialize, Deserialize)]
pub struct Metadata {
    pub timestamp: u64,
    pub source: String,
}
```

---

## Format-Specific Patterns

### JSON (serde_json)

```rust
// Parse
let config: Config = serde_json::from_str(&json_str)?;
let config: Config = serde_json::from_reader(file)?;

// Serialize
let json = serde_json::to_string_pretty(&config)?;
serde_json::to_writer(file, &config)?;

// Dynamic values
let value: serde_json::Value = serde_json::from_str(&input)?;
if let Some(name) = value.get("name").and_then(|v| v.as_str()) {
    // ...
}
```

### TOML

```rust
let config: Config = toml::from_str(&toml_str)?;
let toml_str = toml::to_string_pretty(&config)?;
```

### Binary (postcard)

```rust
// Compact binary format — good for snapshots, IPC, embedded
let bytes: Vec<u8> = postcard::to_allocvec(&value)?;
let decoded: MyType = postcard::from_bytes(&bytes)?;
```

---

## Common Patterns

### Version Field for Forward Compatibility

```rust
#[derive(Serialize, Deserialize)]
pub struct Snapshot {
    pub version: u32,
    pub data: SnapshotData,
}
```

### Borrow Deserialization for Zero-Copy

```rust
#[derive(Deserialize)]
pub struct LogEntry<'a> {
    #[serde(borrow)]
    pub message: &'a str,
    pub level: u8,
}

// Borrows from the input buffer — no allocation for `message`
let entry: LogEntry = serde_json::from_str(&line)?;
```

---

## Anti-Patterns

1. **Missing `deny_unknown_fields`**: Use on config types to catch typos in keys
2. **`String` when `&str` works**: Use `#[serde(borrow)]` for zero-copy deserialization
3. **No `#[serde(default)]`**: Add defaults for optional fields to handle missing keys gracefully
4. **Forgetting `skip_serializing_if`**: Use `Option::is_none` to omit null fields from output
5. **Untagged enums for everything**: They have poor error messages — prefer tagged when possible
