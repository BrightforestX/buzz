import type { QueryClient } from "@tanstack/react-query";

import { mergeMessages } from "@/features/messages/lib/messageMerge";
import { threadRepliesKey } from "@/features/messages/lib/messageQueryKeys";
import { getThreadReference } from "@/features/messages/lib/threading";
import type { RelayEvent } from "@/shared/api/types";

export type ThreadReplyCacheMerge = {
  rootId: string;
  isNew: boolean;
};

/**
 * Merge a thread reply into the per-root `threadRepliesKey` cache.
 * Returns null when the event is not a threaded reply.
 */
export function mergeThreadReplyIntoCache(
  queryClient: QueryClient,
  channelId: string,
  event: RelayEvent,
): ThreadReplyCacheMerge | null {
  const threadReference = getThreadReference(event.tags);
  if (threadReference.parentId == null) {
    return null;
  }

  const rootId = threadReference.rootId;
  if (!rootId) {
    return null;
  }

  const queryKey = threadRepliesKey(channelId, rootId);
  let isNew = false;
  queryClient.setQueryData<RelayEvent[]>(queryKey, (current = []) => {
    if (current.some((candidate) => candidate.id === event.id)) {
      return current;
    }
    isNew = true;
    return mergeMessages(current, event);
  });

  return { rootId, isNew };
}

/** Remove a single reply from the per-root thread cache (optimistic rollback). */
export function removeThreadReplyFromCache(
  queryClient: QueryClient,
  channelId: string,
  rootId: string,
  eventId: string,
): void {
  queryClient.setQueryData<RelayEvent[]>(
    threadRepliesKey(channelId, rootId),
    (current = []) => current.filter((event) => event.id !== eventId),
  );
}
