import {
  expandWorkflowTriggerBodyTemplate,
  extractPlatformDispatchContext,
  extractWorkflowMentionNames,
  type PlatformDispatchContext,
} from "./platformDispatchContext";

export type WorkflowSendMessageStep = {
  action?: string;
  text?: string;
};

export type ManagedAgentMentionTarget = {
  pubkey: string;
  /** Display name used for `@mention` resolution in workflow text. */
  displayName: string;
  status: string;
};

export type PlatformDispatchWakeInput = {
  steps: readonly WorkflowSendMessageStep[];
  webhookBody?: Record<string, unknown>;
  fallbackTenant?: string | null;
  agents: readonly ManagedAgentMentionTarget[];
};

export type PlatformDispatchWakePlan = {
  context: PlatformDispatchContext;
  agentPubkey: string;
  renderedMessage: string;
};

function resolveAgentByMentionName(
  mentionName: string,
  agents: readonly ManagedAgentMentionTarget[],
): ManagedAgentMentionTarget | null {
  const normalized = mentionName.toLowerCase();
  return (
    agents.find((agent) => agent.displayName.toLowerCase() === normalized) ??
    null
  );
}

function isAgentRunning(status: string): boolean {
  return status === "running" || status === "deployed";
}

/**
 * Derive the first stopped managed agent @mentioned in a webhook workflow run
 * that should receive `BUZZ_PLATFORM_*` on wake.
 */
export function planPlatformDispatchWake(
  input: PlatformDispatchWakeInput,
): PlatformDispatchWakePlan | null {
  const context = extractPlatformDispatchContext(
    input.webhookBody,
    input.fallbackTenant,
  );
  if (!context) return null;

  const body = input.webhookBody ?? {};
  for (const step of input.steps) {
    if (step.action !== "send_message") continue;
    const authored = typeof step.text === "string" ? step.text : "";
    if (!authored.trim()) continue;

    const rendered = expandWorkflowTriggerBodyTemplate(authored, body);
    for (const mentionName of extractWorkflowMentionNames(rendered)) {
      const agent = resolveAgentByMentionName(mentionName, input.agents);
      if (!agent || isAgentRunning(agent.status)) continue;
      return {
        context,
        agentPubkey: agent.pubkey,
        renderedMessage: rendered,
      };
    }
  }

  return null;
}
