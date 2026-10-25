import assert from "node:assert/strict";
import test from "node:test";
import { QueryClient } from "@tanstack/react-query";

import { threadRepliesKey } from "./messageQueryKeys.ts";
import {
  mergeThreadReplyIntoCache,
  removeThreadReplyFromCache,
} from "./threadReplyCache.ts";

const CHANNEL_ID = "28c8bf26-10fa-42e7-b658-38092562bfe1";
const ROOT_ID = "1".repeat(64);
const PARENT_ID = "2".repeat(64);

function threadReplyEvent(id, pubkey = "c".repeat(64)) {
  return {
    id: id.padEnd(64, "0"),
    pubkey,
    created_at: 100,
    kind: 9,
    tags: [
      ["h", CHANNEL_ID],
      ["e", ROOT_ID, "", "root"],
      ["e", PARENT_ID, "", "reply"],
    ],
    content: id,
    sig: "d".repeat(128),
  };
}

test("mergeThreadReplyIntoCache inserts a new reply and reports isNew", () => {
  const client = new QueryClient();
  const event = threadReplyEvent("reply-a");

  const result = mergeThreadReplyIntoCache(client, CHANNEL_ID, event);
  assert.deepEqual(result, { rootId: ROOT_ID, isNew: true });

  const cached =
    client.getQueryData(threadRepliesKey(CHANNEL_ID, ROOT_ID)) ?? [];
  assert.equal(cached.length, 1);
  assert.equal(cached[0].id, event.id);
});

test("mergeThreadReplyIntoCache dedupes by event id", () => {
  const client = new QueryClient();
  const event = threadReplyEvent("reply-b");

  assert.deepEqual(mergeThreadReplyIntoCache(client, CHANNEL_ID, event), {
    rootId: ROOT_ID,
    isNew: true,
  });
  assert.deepEqual(mergeThreadReplyIntoCache(client, CHANNEL_ID, event), {
    rootId: ROOT_ID,
    isNew: false,
  });

  const cached =
    client.getQueryData(threadRepliesKey(CHANNEL_ID, ROOT_ID)) ?? [];
  assert.equal(cached.length, 1);
});

test("mergeThreadReplyIntoCache returns null for top-level messages", () => {
  const client = new QueryClient();
  const topLevel = {
    id: "3".repeat(64),
    pubkey: "c".repeat(64),
    created_at: 100,
    kind: 9,
    tags: [["h", CHANNEL_ID]],
    content: "top",
    sig: "d".repeat(128),
  };

  assert.equal(mergeThreadReplyIntoCache(client, CHANNEL_ID, topLevel), null);
});

test("removeThreadReplyFromCache drops only the targeted optimistic id", () => {
  const client = new QueryClient();
  const keep = threadReplyEvent("keep");
  const drop = threadReplyEvent("drop");
  mergeThreadReplyIntoCache(client, CHANNEL_ID, keep);
  mergeThreadReplyIntoCache(client, CHANNEL_ID, drop);

  removeThreadReplyFromCache(client, CHANNEL_ID, ROOT_ID, drop.id);

  const cached =
    client.getQueryData(threadRepliesKey(CHANNEL_ID, ROOT_ID)) ?? [];
  assert.deepEqual(
    cached.map((event) => event.id),
    [keep.id],
  );
});
