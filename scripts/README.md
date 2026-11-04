# Migration Scripts

One-time data migration utilities for the algo-trading Firebase project.

---

## migrate_instrument_tokens.js

Copies the entire `instrument_tokens` collection from the **recom** Firestore project
into the **algo-trading** Firestore project.

Safe to re-run — uses `set()` so existing documents are overwritten, not duplicated.

---

### Step 1 — Get your service account keys

You need one key file per project.

1. Open [Firebase Console](https://console.firebase.google.com)
2. Select the **recom** project → Project Settings → Service Accounts tab
3. Click **Generate new private key** → save as `scripts/recom-service-account.json`
4. Repeat for the **algo-trading** project → save as `scripts/algo-trading-service-account.json`

> ⚠️ These files are listed in `.gitignore` and will never be committed. Keep them local.

---

### Step 2 — Install dependencies

```bash
cd scripts
npm install
```

---

### Step 3 — Run the migration

```bash
# From the repo root:
node scripts/migrate_instrument_tokens.js

# Or from inside the scripts/ folder:
npm run migrate:tokens
```

Expected output:
```
🔍  Reading "instrument_tokens" from recom…
📦  Found 2847 document(s). Writing to algo-trading…

  ✅  Written 500 / 2847 documents…
  ✅  Written 1000 / 2847 documents…
  ...

✅  Migration complete — 2847 document(s) written to "instrument_tokens".
```

---

### Troubleshooting

| Error | Fix |
|---|---|
| `Missing service-account key for "recom"` | Download the key from Firebase Console (Step 1) |
| `PERMISSION_DENIED` | Make sure the service account has the **Cloud Datastore User** role in GCP IAM |
| `Cannot find module 'firebase-admin'` | Run `npm install` inside the `scripts/` folder |
