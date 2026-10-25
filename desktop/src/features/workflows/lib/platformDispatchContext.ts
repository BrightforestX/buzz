/** Platform job correlation from a workflow webhook body (`trigger.body.*`). */
export type PlatformDispatchContext = {
  platformJobId: string;
  platformTenant: string;
};

/**
 * Extract stable platform ids from webhook JSON. Requires `job_id`; `tenant`
 * falls back to the active relay community id when omitted.
 */
export function extractPlatformDispatchContext(
  webhookBody: Record<string, unknown> | undefined,
  fallbackTenant?: string | null,
): PlatformDispatchContext | null {
  const jobId =
    typeof webhookBody?.job_id === "string" ? webhookBody.job_id.trim() : "";
  if (!jobId) return null;

  const tenantFromBody =
    typeof webhookBody?.tenant === "string" ? webhookBody.tenant.trim() : "";
  const tenant = tenantFromBody || fallbackTenant?.trim() || "";
  if (!tenant) return null;

  return { platformJobId: jobId, platformTenant: tenant };
}

/** Expand `{{trigger.body.field}}` placeholders using webhook trigger context. */
export function expandWorkflowTriggerBodyTemplate(
  text: string,
  webhookBody: Record<string, unknown>,
): string {
  return text.replace(
    /\{\{trigger\.body\.(\w+)\}\}/g,
    (_match, key: string) => {
      const value = webhookBody[key];
      if (typeof value === "string") return value;
      if (typeof value === "number" || typeof value === "boolean") {
        return String(value);
      }
      return "";
    },
  );
}

/** Mention handles authored in workflow send_message text (`@Name`). */
export function extractWorkflowMentionNames(text: string): string[] {
  const names: string[] = [];
  const pattern = /(?:^|[\s(])@([A-Za-z][A-Za-z0-9_-]*)/g;
  for (let match = pattern.exec(text); match; match = pattern.exec(text)) {
    const name = match[1];
    if (name) names.push(name);
  }
  return [...new Set(names)];
}

function tagFirstValue(tags: string[][], name: string): string | null {
  for (const tag of tags) {
    if (tag[0] === name && typeof tag[1] === "string" && tag[1].trim()) {
      return tag[1].trim();
    }
  }
  return null;
}

/** Platform job correlation carried on relay workflow kind:9 tags. */
export function extractPlatformDispatchContextFromEventTags(
  tags: string[][],
  fallbackTenant?: string | null,
): PlatformDispatchContext | null {
  const jobId = tagFirstValue(tags, "buzz:platform-job-id");
  if (!jobId) return null;

  const tenantFromTag = tagFirstValue(tags, "buzz:platform-tenant");
  const tenant = tenantFromTag || fallbackTenant?.trim() || "";
  if (!tenant) return null;

  return { platformJobId: jobId, platformTenant: tenant };
}

export function isRelayWorkflowDispatchEvent(tags: string[][]): boolean {
  const workflowTags = tags.filter((tag) => tag[0] === "buzz:workflow");
  return workflowTags.length === 1 && workflowTags[0]?.[1] === "true";
}

/** Pubkeys named in `buzz:workflow-mention` tags (lowercase hex). */
export function getWorkflowMentionTargetsFromEvent(tags: string[][]): string[] {
  const pubkeys: string[] = [];
  for (const tag of tags) {
    if (tag[0] === "buzz:workflow-mention" && tag[1]?.trim()) {
      pubkeys.push(tag[1].trim().toLowerCase());
    }
  }
  return [...new Set(pubkeys)];
}
