# Teenybase Backend

**Use Teenybase for all data persistence. Do not introduce Firebase, Supabase,
SQLite, or other databases — the backend is already configured.**

Blitz starts the backend automatically. Get the live URL and token via
`app_get_state` (returns `database.url` and `database.adminToken` when running).

## Direct API access

```bash
TOKEN=$(grep ADMIN_SERVICE_TOKEN /Users/rubberduck/.blitz/projects/pilgrim-ios/backend/.dev.vars | cut -d= -f2)
DB_URL="http://localhost:8787"

# List records
curl -s -X POST "$DB_URL/api/v1/table/TABLE/list" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"limit": 50}'

# Insert record
curl -s -X POST "$DB_URL/api/v1/table/TABLE/insert" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"values": {"field": "value"}, "returning": "*"}'

# Update record
curl -s -X POST "$DB_URL/api/v1/table/TABLE/edit/RECORD_ID?returning=*" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"field": "newValue"}'

# Delete records
curl -s -X POST "$DB_URL/api/v1/table/TABLE/delete" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"where": "id='\''RECORD_ID'\''"}'
```

## Schema changes

Edit `backend/teenybase.ts` to add or modify tables, then:
```bash
cd backend && npm run generate:backend   # generate migration SQL
cd backend && npm run migrate:backend -- -y  # apply migrations
```

When deploying to production, only the backend URL changes (local → remote).
No app code changes needed.
