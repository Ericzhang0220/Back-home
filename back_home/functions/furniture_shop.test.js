"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createFurnitureShop, validFurnitureId} = require("./furniture_shop");

function fixture() {
  const data = new Map();
  const db = {
    doc: (id) => id,
    collection: () => ({get: async () => ({docs: [...data.entries()].filter(([id]) => id.startsWith("furnitureSales/")).map(([id, value]) => ({id: id.split("/")[1], data: () => value}))})}),
    runTransaction: async (fn) => fn({
      get: async (id) => ({exists: data.has(id), data: () => data.get(id)}),
      create: (id, value) => data.set(id, value),
      set: (id, value) => data.set(id, value.count?.increment ? {count: (data.get(id)?.count || 0) + value.count.increment} : value),
    }),
  };
  class HttpsError extends Error {constructor(code, message) {super(message); this.code = code;}}
  const shop = createFurnitureShop({db, FieldValue: {serverTimestamp: () => 1, increment: (value) => ({increment: value})}, HttpsError});
  return {shop, data};
}
test("catalog whitelist accepts exactly 330 new SKUs and preserves original IDs", () => {
  for (const kind of ["bed", "nightstand", "wardrobe", "vanity", "ottoman", "floorLamp", "plant", "table", "chair", "sofa", "bookshelf"]) {
    for (let form = 0; form < 10; form++) for (let finish = 0; finish < 3; finish++) assert.ok(validFurnitureId(`studio-${kind}-${form}-${finish}`));
  }
  assert.ok(validFurnitureId("sunset-bed"));
  for (const id of ["studio-table-10-0", "studio-table-1-3", "studio-fake-0-0", "../users", null]) assert.equal(validFurnitureId(id), false);
});
test("only authenticated reports count; retries are idempotent and conflicts fail", async () => {
  const {shop} = fixture();
  const request = {auth: {uid: "alice"}, data: {itemId: "studio-table-1-2", eventId: "a".repeat(22)}};
  await assert.rejects(shop.record({data: request.data}), {code: "unauthenticated"});
  await assert.rejects(shop.popularity({}), {code: "unauthenticated"});
  await shop.record(request); await shop.record(request);
  assert.deepEqual(await shop.popularity(request), {"studio-table-1-2": 1});
  await assert.rejects(shop.record({...request, data: {...request.data, itemId: "sunset-bed"}}), {code: "already-exists"});
  await shop.record({...request, auth: {uid: "bob"}});
  assert.deepEqual(await shop.popularity(request), {"studio-table-1-2": 2});
});
test("cold start has no fabricated sales; invalid SKUs cannot enter ranking", async () => {
  const {shop} = fixture();
  assert.deepEqual(await shop.popularity({auth: {uid: "alice"}}), {});
  await assert.rejects(shop.record({auth: {uid: "alice"}, data: {itemId: "fake", eventId: "a".repeat(22)}}), {code: "invalid-argument"});
});
