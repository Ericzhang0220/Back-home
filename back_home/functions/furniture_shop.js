"use strict";

const originalIds = new Set([
  "sunset-bed", "soft-nightstand", "linen-wardrobe", "mirror-vanity",
  "cloud-ottoman", "dusk-lamp", "fern-tree",
]);
const kinds = new Set([
  "bed", "nightstand", "wardrobe", "vanity", "ottoman", "floorLamp",
  "plant", "table", "chair", "sofa", "bookshelf",
]);
function validFurnitureId(id) {
  if (typeof id !== "string") return false;
  if (originalIds.has(id)) return true;
  const match = /^studio-([A-Za-z]+)-([0-9])-([0-2])$/.exec(id);
  return !!match && kinds.has(match[1]);
}

// The existing Likes shop is a local wallet. These are authenticated,
// idempotent client purchase reports, NOT a payment-verification service.
// No invented initial sales; original starter inventory never enters here.
function createFurnitureShop({db, FieldValue, HttpsError}) {
  async function record(request) {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    const {itemId, eventId} = request.data || {};
    if (!validFurnitureId(itemId) || typeof eventId !== "string" ||
        !/^[A-Za-z0-9_-]{20,64}$/.test(eventId)) {
      throw new HttpsError("invalid-argument", "Invalid furniture purchase.");
    }
    const receipt = db.doc(`users/${uid}/furniturePurchaseReports/${eventId}`);
    const aggregate = db.doc(`furnitureSales/${itemId}`);
    const day = new Date().toISOString().slice(0, 10);
    const rate = db.doc(`users/${uid}/furniturePurchaseDays/${day}`);
    await db.runTransaction(async (tx) => {
      const [previous, daily] = await Promise.all([tx.get(receipt), tx.get(rate)]);
      if (previous.exists) {
        if (previous.data().itemId !== itemId) throw new HttpsError("already-exists", "Event already used.");
        return;
      }
      const count = daily.data()?.count || 0;
      if (count >= 200) throw new HttpsError("resource-exhausted", "Purchase report limit reached.");
      tx.create(receipt, {itemId, createdAt: FieldValue.serverTimestamp()});
      tx.set(rate, {count: count + 1});
      tx.set(aggregate, {count: FieldValue.increment(1)}, {merge: true});
    });
    return {ok: true};
  }
  async function popularity(request) {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in first.");
    const snapshot = await db.collection("furnitureSales").get();
    const result = {};
    for (const doc of snapshot.docs) {
      if (validFurnitureId(doc.id)) result[doc.id] = Math.max(0, Number(doc.data().count) || 0);
    }
    return result;
  }
  return {record, popularity};
}
module.exports = {createFurnitureShop, validFurnitureId};
