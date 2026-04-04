# Administration Patterns

## User and Role Management

### Create Users

```javascript
// Create admin user
use admin
db.createUser({
  user: "adminUser",
  pwd: "securePassword",
  roles: [{ role: "root", db: "admin" }]
})

// Create application user (read-write on specific DB)
use mydb
db.createUser({
  user: "appUser",
  pwd: "appPassword",
  roles: [{ role: "readWrite", db: "mydb" }]
})

// Create read-only user
db.createUser({
  user: "reportUser",
  pwd: "reportPassword",
  roles: [{ role: "read", db: "mydb" }]
})
```

### Built-in Roles

| Role | Scope | Description |
|------|-------|-------------|
| `read` | Database | Read all non-system collections |
| `readWrite` | Database | Read + write all non-system collections |
| `dbAdmin` | Database | Schema management, indexing, stats |
| `userAdmin` | Database | Create/modify users and roles |
| `clusterAdmin` | Cluster | Replica set and sharding management |
| `root` | All | Superuser (all privileges) |
| `readAnyDatabase` | All DBs | Read any database |
| `readWriteAnyDatabase` | All DBs | Read/write any database |

### List and Manage Users

```javascript
db.getUsers()
db.getUser("appUser")
db.updateUser("appUser", { roles: [{ role: "read", db: "mydb" }] })
db.dropUser("oldUser")
```

## Server Status and Monitoring

### Quick Health Check

```javascript
// Server status (comprehensive)
db.serverStatus()

// Connection info
db.serverStatus().connections

// Current operations
db.currentOp()

// Kill a long-running operation
db.killOp(opId)

// Database stats
db.stats()

// Collection stats
db.users.stats()
```

### CLI Monitoring One-Liners

```bash
# Server status summary
mongosh --quiet --json=relaxed --eval "
  const s = db.serverStatus();
  EJSON.stringify({
    uptime: s.uptime,
    connections: s.connections,
    opcounters: s.opcounters,
    mem: s.mem
  }, null, 2)
"

# Active operations
mongosh --quiet --json=relaxed --eval "db.currentOp({active: true})"

# Database sizes
mongosh --quiet --json=relaxed --eval "
  db.adminCommand('listDatabases').databases.map(d => ({
    name: d.name,
    sizeMB: (d.sizeOnDisk / 1048576).toFixed(2)
  }))
"
```

## Replica Set Basics

### Check Replica Set Status

```javascript
rs.status()           // Full replica set status
rs.isMaster()         // Who is primary
rs.conf()             // Replica set configuration
rs.printReplicationInfo()   // Oplog status
rs.printSecondaryReplicationInfo()  // Replication lag
```

### Read Preference

```javascript
// Read from secondary (distribute read load)
db.users.find({}).readPref("secondaryPreferred")

// Read preferences: primary, primaryPreferred, secondary, secondaryPreferred, nearest
```

## Profiling (Slow Query Detection)

```javascript
// Enable profiling for slow queries (> 100ms)
db.setProfilingLevel(1, { slowms: 100 })

// View slow queries
db.system.profile.find().sort({ ts: -1 }).limit(5)

// Disable profiling
db.setProfilingLevel(0)
```

## Validation (Schema Enforcement)

```javascript
// Add JSON Schema validation to a collection
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["name", "email"],
      properties: {
        name: { bsonType: "string", description: "required string" },
        email: { bsonType: "string", pattern: "^.+@.+$" },
        age: { bsonType: "int", minimum: 0, maximum: 150 }
      }
    }
  },
  validationLevel: "moderate",
  validationAction: "warn"
})
```

## Anti-Patterns

1. **Using `root` for application users**: Create specific roles per application with minimum required permissions
2. **No profiling enabled**: Enable slow query profiling (`slowms: 100`) in all non-test environments
3. **Ignoring replica set lag**: Monitor `rs.printSecondaryReplicationInfo()` regularly
4. **No schema validation**: Use `$jsonSchema` validators on critical collections even though MongoDB is schema-flexible
