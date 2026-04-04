# Database Tools Patterns

## Install

```bash
# mongosh (primary CLI)
brew install mongosh

# Database tools (mongoexport, mongoimport, mongodump, mongorestore, mongostat, mongotop)
brew install mongodb-database-tools

# Atlas CLI (cloud management)
brew install mongodb-atlas-cli
```

## mongoexport — Export to JSON/CSV

```bash
# Export collection to JSON (one document per line)
mongoexport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --out=users.json

# Export as JSON array
mongoexport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --jsonArray --out=users.json

# Export to CSV with specific fields
mongoexport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --type=csv --fields=name,email,status --out=users.csv

# Export with query filter
mongoexport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --query='{"status":"active"}' --out=active_users.json

# Export with authentication
mongoexport --uri="mongodb+srv://user:pass@cluster.mongodb.net/mydb" \
  --collection=orders --out=orders.json
```

## mongoimport — Import from JSON/CSV

```bash
# Import JSON (one document per line — JSONL format)
mongoimport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --file=users.json

# Import JSON array
mongoimport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --jsonArray --file=users.json

# Import CSV with header row
mongoimport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --type=csv --headerline --file=users.csv

# Upsert (update existing, insert new)
mongoimport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --mode=upsert --upsertFields=email --file=users.json

# Drop collection before import
mongoimport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --drop --file=users.json
```

## mongodump — Binary Backup

```bash
# Dump entire database
mongodump --uri="mongodb://localhost:27017/mydb" --out=./backup

# Dump specific collection
mongodump --uri="mongodb://localhost:27017/mydb" \
  --collection=users --out=./backup

# Dump with compression
mongodump --uri="mongodb://localhost:27017/mydb" \
  --gzip --out=./backup

# Dump to archive file
mongodump --uri="mongodb://localhost:27017/mydb" \
  --archive=mydb_backup.archive --gzip

# Dump from Atlas
mongodump --uri="mongodb+srv://user:pass@cluster.mongodb.net/mydb" \
  --out=./backup
```

## mongorestore — Restore from Backup

```bash
# Restore entire database
mongorestore --uri="mongodb://localhost:27017" ./backup

# Restore specific database
mongorestore --uri="mongodb://localhost:27017" \
  --db=mydb ./backup/mydb

# Restore specific collection
mongorestore --uri="mongodb://localhost:27017" \
  --db=mydb --collection=users ./backup/mydb/users.bson

# Restore from archive
mongorestore --uri="mongodb://localhost:27017" \
  --archive=mydb_backup.archive --gzip

# Drop existing collections before restore
mongorestore --uri="mongodb://localhost:27017" --drop ./backup
```

## mongostat — Real-Time Server Stats

```bash
# Default output (every second)
mongostat --uri="mongodb://localhost:27017"

# JSON output
mongostat --uri="mongodb://localhost:27017" --json

# Specific interval (every 5 seconds)
mongostat --uri="mongodb://localhost:27017" --rowcount=10 5
```

Key columns: `insert`, `query`, `update`, `delete` (operations/sec), `res` (resident memory), `conn` (connections).

## mongotop — Per-Collection Read/Write Time

```bash
# Default output (every second)
mongotop --uri="mongodb://localhost:27017"

# JSON output
mongotop --uri="mongodb://localhost:27017" --json

# Every 5 seconds
mongotop --uri="mongodb://localhost:27017" 5
```

## Atlas CLI — Cloud Management

```bash
# Login to Atlas
atlas auth login

# List clusters
atlas clusters list

# Create a cluster
atlas clusters create myCluster --provider AWS --region US_EAST_1 --tier M10

# Get connection string
atlas clusters connectionStrings describe myCluster

# List databases in a cluster
atlas clusters search indexes list --clusterName myCluster

# Pause/resume a cluster
atlas clusters pause myCluster
atlas clusters start myCluster
```

## Common Workflows

### Migrate Data Between Environments

```bash
# Export from staging
mongoexport --uri="mongodb://staging:27017/mydb" \
  --collection=users --jsonArray --out=users.json

# Import to local
mongoimport --uri="mongodb://localhost:27017/mydb" \
  --collection=users --jsonArray --drop --file=users.json
```

### Backup and Restore

```bash
# Backup (compressed archive)
mongodump --uri="mongodb://localhost:27017/mydb" \
  --archive=backup_$(date +%Y%m%d).archive --gzip

# Restore
mongorestore --uri="mongodb://localhost:27017" \
  --archive=backup_20260403.archive --gzip --drop
```

### Quick Data Inspection

```bash
# Count documents per collection
mongosh "mongodb://localhost/mydb" --quiet --eval "
  db.getCollectionNames().forEach(c => {
    print(c + ': ' + db[c].countDocuments({}))
  })
"

# Collection sizes
mongosh "mongodb://localhost/mydb" --quiet --json=relaxed --eval "
  db.getCollectionNames().map(c => ({
    name: c,
    count: db[c].estimatedDocumentCount(),
    sizeMB: (db[c].stats().size / 1048576).toFixed(2)
  }))
"
```
