/**
 * migrate_instrument_tokens.js
 *
 * One-time script that copies the `instrument_tokens` collection from the
 * recom Firebase project into the algo-trading Firebase project.
 *
 * The script is READ-ONLY on recom — it only calls .get() on the source DB.
 * Nothing in recom is ever modified or deleted.
 *
 * Prerequisites
 * -------------
 * 1. Place service-account JSON keys in this folder:
 *      scripts/recom-service-account.json          ← recom (source)
 *      scripts/algo-trading-service-account.json   ← algo-trading (destination)
 *
 * 2. Install firebase-admin (once):
 *      cd scripts && npm install
 *
 * Usage
 * -----
 *   Dry-run (preview only, nothing written):
 *      node scripts/migrate_instrument_tokens.js --dry-run
 *
 *   Live run (writes to algo-trading Firestore):
 *      node scripts/migrate_instrument_tokens.js
 *
 * Safe to re-run — uses set() so existing docs are overwritten, not duplicated.
 */

"use strict";

const path  = require("path");
const admin = require("firebase-admin");

// ── Dry-run flag ──────────────────────────────────────────────────────────────
const DRY_RUN = process.argv.includes("--dry-run");

// ── Service account paths ─────────────────────────────────────────────────────

const RECOM_SA  = path.join(__dirname, "recom-service-account.json");
const ALGO_SA   = path.join(__dirname, "algo-trading-service-account.json");

// ── Validate keys exist before doing anything ─────────────────────────────────

const fs = require("fs");
for (const [label, file] of [["recom", RECOM_SA], ["algo-trading", ALGO_SA]]) {
  if (!fs.existsSync(file)) {
    console.error(
      `\n❌  Missing service-account key for "${label}".\n` +
      `    Expected: ${file}\n\n` +
      `    Download it from:\n` +
      `    Firebase Console → Project Settings → Service Accounts → Generate new private key\n`
    );
    process.exit(1);
  }
}

// ── Initialise both Firebase apps ─────────────────────────────────────────────

const recomApp = admin.initializeApp(
  { credential: admin.credential.cert(require(RECOM_SA)) },
  "recom"
);

const algoApp = admin.initializeApp(
  { credential: admin.credential.cert(require(ALGO_SA)) },
  "algo"
);

const srcDb = admin.firestore(recomApp);
const dstDb = admin.firestore(algoApp);

// ── Migration ─────────────────────────────────────────────────────────────────

const COLLECTION = "instrument_tokens";
const BATCH_SIZE = 500; // Firestore batch write limit

const PREVIEW_LIMIT = 5; // Number of sample docs to print in dry-run

async function migrate() {
  if (DRY_RUN) {
    console.log("\n🧪  DRY-RUN mode — recom is READ-ONLY, nothing will be written to algo-trading.\n");
  }

  console.log(`🔍  Reading "${COLLECTION}" from recom (project: oxer-3015f)…`);
  // Filter: only migrate enabled instruments — skip expired/disabled contracts
  const snap = await srcDb.collection(COLLECTION).where("enabled", "==", true).get();

  if (snap.empty) {
    console.warn(`⚠️   Collection "${COLLECTION}" is empty in recom — nothing to migrate.`);
    return;
  }

  console.log(`📦  Found ${snap.size} document(s) in recom (filter: enabled=true, skipping ${296 - snap.size} expired/disabled).\n`);

  if (DRY_RUN) {
    // ── Preview: print sample documents and field structure ──────────────────
    console.log(`🔎  Sample documents (first ${Math.min(PREVIEW_LIMIT, snap.size)}):\n`);
    console.log("    " + "─".repeat(60));

    let shown = 0;
    for (const doc of snap.docs) {
      if (shown >= PREVIEW_LIMIT) break;
      const data = doc.data();
      console.log(`    ID     : ${doc.id}`);
      for (const [key, val] of Object.entries(data)) {
        console.log(`    ${key.padEnd(10)}: ${JSON.stringify(val)}`);
      }
      console.log("    " + "─".repeat(60));
      shown++;
    }

    // ── Field summary ─────────────────────────────────────────────────────────
    const firstDoc = snap.docs[0].data();
    console.log(`\n📋  Fields detected in each document:`);
    for (const key of Object.keys(firstDoc)) {
      const sampleVal = firstDoc[key];
      console.log(`    • ${key} (${typeof sampleVal})`);
    }

    // ── Batch breakdown ───────────────────────────────────────────────────────
    const batches = Math.ceil(snap.size / BATCH_SIZE);
    console.log(`\n📊  Migration plan:`);
    console.log(`    Collection   : ${COLLECTION}`);
    console.log(`    Source       : recom (oxer-3015f)`);
    console.log(`    Destination  : algo-trading (algo-stockara)`);
    console.log(`    Total docs   : ${snap.size}`);
    console.log(`    Batch size   : ${BATCH_SIZE}`);
    console.log(`    Batches      : ${batches}`);
    console.log(`    Write op     : set() — safe to re-run, overwrites if doc exists`);
    console.log(`    Recom impact : NONE — only .get() reads were performed\n`);
    console.log(`✅  Dry-run complete. Run without --dry-run to perform the actual migration.\n`);
    return;
  }

  // ── Live run: write to algo-trading Firestore ─────────────────────────────
  console.log(`✍️   Writing to algo-trading (project: algo-stockara)…\n`);

  let batch      = dstDb.batch();
  let batchCount = 0;
  let total      = 0;

  for (const doc of snap.docs) {
    const ref = dstDb.collection(COLLECTION).doc(doc.id);
    batch.set(ref, doc.data()); // set() — overwrites existing, safe to re-run
    batchCount++;
    total++;

    if (batchCount === BATCH_SIZE) {
      await batch.commit();
      console.log(`  ✅  Written ${total} / ${snap.size} documents…`);
      batch      = dstDb.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  console.log(`\n✅  Migration complete — ${total} document(s) written to "${COLLECTION}".\n`);
}

migrate().catch((err) => {
  console.error("\n❌  Migration failed:\n", err);
  process.exit(1);
});
