import * as React from "react";

import { useManagedAgentsQuery } from "@/features/agents/hooks";
import { useCommunities } from "@/features/communities/useCommunities";
import { useDetachedAgentStart } from "@/features/messages/ui/useDetachedAgentStart";
import {
  extractPlatformDispatchContextFromEventTags,
  getWorkflowMentionTargetsFromEvent,
  isRelayWorkflowDispatchEvent,
} from "@/features/workflows/lib/platformDispatchContext";
import { relayClient } from "@/shared/api/relayClient";
import type { ManagedAgent, RelayEvent } from "@/shared/api/types";
import { CHANNEL_MESSAGE_EVENT_KINDS } from "@/shared/constants/kinds";
import { normalizePubkey } from "@/shared/lib/pubkey";

const LIVE_LOOKBACK_SECS = 120;
const MAX_HANDLED_EVENTS = 512;

function isAgentRunning(status: ManagedAgent["status"]): boolean {
  return status === "running" || status === "deployed";
}

function isE2eMockBridgeActive(): boolean {
  return typeof window !== "undefined" && Boolean(window.__BUZZ_E2E__?.mock);
}

/**
 * Production path: relay webhook workflow → kind:9 with platform tags → wake
 * stopped managed agents via `start_managed_agent` + `BUZZ_PLATFORM_*`.
 *
 * Mock E2E keeps using `e2eBridge.dispatchPlatformWakeForMockWorkflow`; this
 * hook is disabled when `__BUZZ_E2E__.mock` is set.
 */
export function usePlatformWorkflowRelayWake() {
  const startAgentDetached = useDetachedAgentStart();
  const managedAgentsQuery = useManagedAgentsQuery();
  const { activeCommunity } = useCommunities();

  const managedAgents = managedAgentsQuery.data ?? [];
  const fallbackTenant = activeCommunity?.id ?? null;

  const stoppedAgentPubkeysKey = React.useMemo(() => {
    return managedAgents
      .filter((agent) => !isAgentRunning(agent.status))
      .map((agent) => normalizePubkey(agent.pubkey))
      .filter(Boolean)
      .sort()
      .join(",");
  }, [managedAgents]);

  const managedAgentsByPubkey = React.useMemo(() => {
    const map = new Map<string, ManagedAgent>();
    for (const agent of managedAgents) {
      map.set(normalizePubkey(agent.pubkey), agent);
    }
    return map;
  }, [managedAgents]);

  const handledEventIdsRef = React.useRef<Set<string>>(new Set());
  const subscriptionStartedAtRef = React.useRef(
    Math.floor(Date.now() / 1_000) - LIVE_LOOKBACK_SECS,
  );

  const handleWorkflowDispatchEvent = React.useEffectEvent(
    (event: RelayEvent) => {
      if (isE2eMockBridgeActive()) return;
      if (!isRelayWorkflowDispatchEvent(event.tags)) return;

      const context = extractPlatformDispatchContextFromEventTags(
        event.tags,
        fallbackTenant,
      );
      if (!context) return;

      const mentionTargets = getWorkflowMentionTargetsFromEvent(event.tags);
      if (mentionTargets.length === 0) return;

      if (handledEventIdsRef.current.has(event.id)) return;
      handledEventIdsRef.current.add(event.id);
      if (handledEventIdsRef.current.size > MAX_HANDLED_EVENTS) {
        const oldest = handledEventIdsRef.current.values().next().value;
        if (oldest) handledEventIdsRef.current.delete(oldest);
      }

      for (const mentionPubkey of mentionTargets) {
        const agent = managedAgentsByPubkey.get(mentionPubkey);
        if (!agent || isAgentRunning(agent.status)) continue;

        startAgentDetached(agent, {
          replayFloorUnix: event.created_at,
          platformJobId: context.platformJobId,
          platformTenant: context.platformTenant,
        });
      }
    },
  );

  React.useEffect(() => {
    if (isE2eMockBridgeActive()) return;
    if (!stoppedAgentPubkeysKey) return;

    let disposed: (() => Promise<void>) | undefined;
    let cancelled = false;

    const pubkeys = stoppedAgentPubkeysKey.split(",").filter(Boolean);

    void (async () => {
      try {
        subscriptionStartedAtRef.current =
          Math.floor(Date.now() / 1_000) - LIVE_LOOKBACK_SECS;
        disposed = await relayClient.subscribeLive(
          {
            kinds: [...CHANNEL_MESSAGE_EVENT_KINDS],
            "#p": pubkeys,
            limit: 1000,
            since: subscriptionStartedAtRef.current,
          },
          handleWorkflowDispatchEvent,
        );
        if (cancelled && disposed) {
          await disposed().catch(() => {});
        }
      } catch (error) {
        console.error(
          "[usePlatformWorkflowRelayWake] live subscription failed",
          error,
        );
      }
    })();

    return () => {
      cancelled = true;
      if (disposed) {
        void disposed().catch(() => {});
      }
    };
  }, [stoppedAgentPubkeysKey]);
}
