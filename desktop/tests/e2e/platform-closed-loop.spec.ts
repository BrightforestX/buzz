/**
 * S06 wire stub — mock closed-loop dispatch (no live Baseten/Daytona/Temporal keys).
 * Design: specs/011-buzz-durable-agent-platform/docs/e2e-closed-loop.md
 */
import { expect, test } from "@playwright/test";
import { parse as parseYaml } from "yaml";

import { installMockBridge } from "../helpers/bridge";

const PLATFORM_AGENT_PUBKEY = "ab".repeat(32);
const PLATFORM_PERSONA_ID = "custom:platform-agent";

async function waitForInvokeBridge(page: import("@playwright/test").Page) {
  await page.waitForFunction(
    () => {
      const w = window as Window & {
        __BUZZ_E2E_INVOKE_MOCK_COMMAND__?: unknown;
        __TAURI_INTERNALS__?: { invoke?: unknown };
      };
      return (
        typeof w.__BUZZ_E2E_INVOKE_MOCK_COMMAND__ === "function" ||
        typeof w.__TAURI_INTERNALS__?.invoke === "function"
      );
    },
    null,
    { timeout: 5_000 },
  );
}

async function gotoApp(page: import("@playwright/test").Page) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await waitForInvokeBridge(page);
  await expect(page.getByTestId("open-agents-view")).toBeVisible({
    timeout: 10_000,
  });
}

async function invokeTauri<T>(
  page: import("@playwright/test").Page,
  command: string,
  payload: Record<string, unknown> = {},
): Promise<T> {
  await waitForInvokeBridge(page);
  return page.evaluate(
    async ({ cmd, args }) => {
      const w = window as typeof window & {
        __BUZZ_E2E_INVOKE_MOCK_COMMAND__?: (
          command: string,
          payload?: Record<string, unknown>,
        ) => Promise<unknown>;
        __TAURI_INTERNALS__?: {
          invoke: (
            command: string,
            payload?: Record<string, unknown>,
          ) => Promise<unknown>;
        };
      };
      const invoke =
        w.__BUZZ_E2E_INVOKE_MOCK_COMMAND__ ?? w.__TAURI_INTERNALS__?.invoke;
      if (!invoke) {
        throw new Error("Tauri invoke unavailable in e2e harness");
      }
      return invoke(cmd, args) as Promise<T>;
    },
    { cmd: command, args: payload },
  );
}

/** Appends a step after the given step number on the workflow canvas. */
async function addStepAfterStep(
  page: import("@playwright/test").Page,
  dialog: import("@playwright/test").Locator,
  afterStepNumber: number,
) {
  const ingress = dialog.getByTestId("workflow-node-ingress").last();
  await ingress.hover();
  await ingress
    .getByRole("button", { name: `Add after Step ${afterStepNumber}` })
    .click();
  await page.getByRole("menuitem", { name: "Send Message" }).click();
}

async function navigateToWorkflows(page: import("@playwright/test").Page) {
  await page.goto("/");
  await page.getByTestId("open-workflows-view").click();
  await expect(page).toHaveURL(/#\/workflows$/);
  await expect(page.getByTestId("workflows-view")).toBeVisible();
}

async function selectWorkflowChannel(
  page: import("@playwright/test").Page,
  dialog: import("@playwright/test").Locator,
) {
  const channelList = page.getByTestId("channel-combobox-list");
  if (!(await channelList.isVisible())) {
    await dialog.getByRole("combobox", { name: "Channel" }).click();
  }
  await expect(channelList).toBeVisible();
  await channelList
    .getByRole("option", { name: "agents", exact: true })
    .click();
}

async function dismissWebhookReadyDialog(
  page: import("@playwright/test").Page,
) {
  const webhookDialog = page.getByRole("dialog", { name: "Webhook ready" });
  await expect(webhookDialog).toBeVisible();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  const confirmation = page.getByRole("alertdialog", {
    name: "Continue without this secret?",
  });
  await expect(confirmation).toBeVisible();
  await confirmation.getByRole("button", { name: "Continue" }).click();
  await expect(webhookDialog).not.toBeVisible();
}

test.beforeEach(async ({ page }) => {
  await installMockBridge(page);
});

test("mock platform dispatch workflow saves webhook trigger on agents channel", async ({
  page,
}) => {
  const workflowName = `platform_dispatch_${Date.now()}`;

  await navigateToWorkflows(page);
  await page.getByRole("button", { name: "Create Workflow" }).click();
  const dialog = page.getByRole("dialog", { name: "Create workflow" });
  await selectWorkflowChannel(page, dialog);

  await dialog.getByRole("button", { name: "Edit workflow name" }).click();
  const nameInput = dialog.getByRole("textbox", { name: "Workflow name" });
  await nameInput.fill(workflowName);
  await dialog.getByRole("button", { name: "Save workflow name" }).click();

  await dialog.getByRole("button", { name: "Trigger: Message Posted" }).click();
  await dialog.getByRole("button", { name: "Trigger event" }).click();
  await page.getByRole("menuitem", { name: "Webhook" }).click();

  await dialog.getByRole("button", { name: "Add step", exact: true }).click();
  await page.getByRole("menuitem", { name: "Send Message" }).click();
  await dialog
    .getByLabel("Message text")
    .fill("@PlatformAgent dispatch job {{trigger.body.job_id}}");
  await dialog.getByRole("button", { name: "Create" }).click();

  await expect(
    page.getByRole("heading", { name: "Create Workflow" }),
  ).not.toBeVisible();

  const yaml = await page.evaluate(() => {
    const call = [...(window.__BUZZ_E2E_COMMAND_PAYLOADS__ ?? [])]
      .reverse()
      .find((candidate) => candidate.command === "create_workflow");
    return (call?.payload as { yamlDefinition?: string } | undefined)
      ?.yamlDefinition;
  });

  expect(yaml).toBeTruthy();
  const parsed = parseYaml(yaml ?? "") as {
    name?: string;
    trigger?: { on?: string };
    steps?: Array<{ action?: string }>;
  };
  expect(parsed.name).toBe(workflowName);
  expect(parsed.trigger?.on).toBe("webhook");
  expect(parsed.steps?.some((step) => step.action === "send_message")).toBe(
    true,
  );

  await expect(page.getByTestId("workflows-view")).toContainText(workflowName);
});

test("managed agent start forwards platform job id and tenant", async ({
  page,
}) => {
  await installMockBridge(page, {
    personas: [
      {
        id: PLATFORM_PERSONA_ID,
        displayName: "PlatformAgent",
        isActive: true,
        systemPrompt: "Platform dispatch agent.",
      },
    ],
    managedAgents: [
      {
        name: "platform-agent-instance",
        displayName: "PlatformAgent",
        personaId: PLATFORM_PERSONA_ID,
        pubkey: PLATFORM_AGENT_PUBKEY,
        status: "stopped",
      },
    ],
  });

  await gotoApp(page);
  await invokeTauri(page, "start_managed_agent", {
    pubkey: PLATFORM_AGENT_PUBKEY,
    expectedRelayUrl: null,
    expectedSignerPubkey: null,
    replayFloorUnix: null,
    platformJobId: "job-e2e-mock-001",
    platformTenant: "test-community",
  });

  const startCall = await page.evaluate(() => {
    return [...(window.__BUZZ_E2E_COMMAND_PAYLOADS__ ?? [])]
      .reverse()
      .find((candidate) => candidate.command === "start_managed_agent");
  });

  expect(startCall?.payload).toMatchObject({
    pubkey: PLATFORM_AGENT_PUBKEY,
    platformJobId: "job-e2e-mock-001",
    platformTenant: "test-community",
  });
});

test("mock webhook trigger completes dispatch ack workflow run", async ({
  page,
}) => {
  const workflowName = `platform_ack_${Date.now()}`;

  await navigateToWorkflows(page);
  await page.getByRole("button", { name: "Create Workflow" }).click();
  const dialog = page.getByRole("dialog", { name: "Create workflow" });
  await selectWorkflowChannel(page, dialog);

  await dialog.getByRole("button", { name: "Edit workflow name" }).click();
  await dialog
    .getByRole("textbox", { name: "Workflow name" })
    .fill(workflowName);
  await dialog.getByRole("button", { name: "Save workflow name" }).click();

  await dialog.getByRole("button", { name: "Trigger: Message Posted" }).click();
  await dialog.getByRole("button", { name: "Trigger event" }).click();
  await page.getByRole("menuitem", { name: "Webhook" }).click();

  await dialog.getByRole("button", { name: "Add step", exact: true }).click();
  await page.getByRole("menuitem", { name: "Send Message" }).click();
  await dialog
    .getByTestId("workflow-node-inspector")
    .getByLabel("Message text")
    .fill("@PlatformAgent run job {{trigger.body.job_id}}");

  await addStepAfterStep(page, dialog, 1);
  await expect(dialog.getByTestId("workflow-node-inspector")).toContainText(
    "Step 2",
  );
  await dialog
    .getByTestId("workflow-node-inspector")
    .getByLabel("Message text")
    .fill("Platform job {{trigger.body.job_id}} dispatched to @PlatformAgent.");

  await dialog.getByRole("button", { name: "Create" }).click();
  await dismissWebhookReadyDialog(page);
  await expect(page.getByTestId("workflows-view")).toContainText(workflowName);

  await page.getByRole("button", { name: `View ${workflowName}` }).click();
  const detailDialog = page.getByRole("dialog", { name: "Edit workflow" });
  await expect(detailDialog).toBeVisible();

  const workflowId = await page.evaluate(() => {
    const match = window.location.hash.match(/#\/workflows\/([^/?]+)/);
    return match?.[1] ?? null;
  });
  expect(workflowId).toBeTruthy();

  await detailDialog.getByRole("button", { name: "Workflow actions" }).click();
  await page.getByRole("menuitem", { name: "Trigger" }).click();

  const triggerResult = await page.evaluate(() => {
    const call = [...(window.__BUZZ_E2E_COMMAND_PAYLOADS__ ?? [])]
      .reverse()
      .find((candidate) => candidate.command === "trigger_workflow");
    return call?.payload as { workflowId?: string } | undefined;
  });
  expect(triggerResult?.workflowId).toBe(workflowId);

  const runs = await invokeTauri<{
    runs: Array<{
      status: string;
      execution_trace?: Array<{ output?: { preview?: string } }>;
    }>;
  }>(page, "get_workflow_runs", { workflowId, limit: 1 });
  expect(runs.runs[0]?.status).toBe("completed");
  expect(runs.runs[0]?.execution_trace?.length).toBeGreaterThanOrEqual(2);
  const ackPreview = runs.runs[0]?.execution_trace?.[1]?.output?.preview ?? "";
  expect(ackPreview).toContain("Platform job");
  expect(ackPreview).toContain("dispatched");
});

test("mock webhook POST wakes @mentioned agent with platform job context", async ({
  page,
}) => {
  const jobId = "job-e2e-webhook-004";
  const tenant = "test-community";
  const workflowName = `platform_webhook_wake_${Date.now()}`;

  await installMockBridge(page, {
    personas: [
      {
        id: PLATFORM_PERSONA_ID,
        displayName: "PlatformAgent",
        isActive: true,
        systemPrompt: "Platform dispatch agent.",
      },
    ],
    managedAgents: [
      {
        name: "PlatformAgent",
        personaId: PLATFORM_PERSONA_ID,
        pubkey: PLATFORM_AGENT_PUBKEY,
        status: "stopped",
        channelNames: ["agents"],
      },
    ],
  });

  await navigateToWorkflows(page);
  await page.getByRole("button", { name: "Create Workflow" }).click();
  const dialog = page.getByRole("dialog", { name: "Create workflow" });
  await selectWorkflowChannel(page, dialog);

  await dialog.getByRole("button", { name: "Edit workflow name" }).click();
  await dialog
    .getByRole("textbox", { name: "Workflow name" })
    .fill(workflowName);
  await dialog.getByRole("button", { name: "Save workflow name" }).click();

  await dialog.getByRole("button", { name: "Trigger: Message Posted" }).click();
  await dialog.getByRole("button", { name: "Trigger event" }).click();
  await page.getByRole("menuitem", { name: "Webhook" }).click();

  await dialog.getByRole("button", { name: "Add step", exact: true }).click();
  await page.getByRole("menuitem", { name: "Send Message" }).click();
  await dialog
    .getByLabel("Message text")
    .fill("@PlatformAgent dispatch job {{trigger.body.job_id}}");
  await dialog.getByRole("button", { name: "Create" }).click();
  await dismissWebhookReadyDialog(page);
  await expect(page.getByTestId("workflows-view")).toContainText(workflowName);

  const resolvedWorkflowId = await page.evaluate(async (name) => {
    const createCall = [...(window.__BUZZ_E2E_COMMAND_PAYLOADS__ ?? [])]
      .reverse()
      .find((candidate) => candidate.command === "create_workflow");
    const channelId = (
      createCall?.payload as { channelId?: string } | undefined
    )?.channelId;
    if (!channelId) return null;
    const invoke =
      window.__BUZZ_E2E_INVOKE_MOCK_COMMAND__ ??
      window.__TAURI_INTERNALS__?.invoke;
    if (!invoke) return null;
    const workflows = (await invoke("get_channels_workflows", {
      channelIds: [channelId],
    })) as Array<{ id: string; name: string }>;
    return workflows.find((workflow) => workflow.name === name)?.id ?? null;
  }, workflowName);

  expect(resolvedWorkflowId).toBeTruthy();

  await invokeTauri(page, "mock_workflow_webhook_post", {
    workflowId: resolvedWorkflowId,
    body: { job_id: jobId, tenant },
  });

  const startCall = await page.evaluate((expectedJobId) => {
    return [...(window.__BUZZ_E2E_COMMAND_PAYLOADS__ ?? [])]
      .reverse()
      .find(
        (candidate) =>
          candidate.command === "start_managed_agent" &&
          (candidate.payload as { platformJobId?: string }).platformJobId ===
            expectedJobId,
      );
  }, jobId);

  expect(startCall?.payload).toMatchObject({
    pubkey: PLATFORM_AGENT_PUBKEY,
    platformJobId: jobId,
    platformTenant: tenant,
  });

  const runs = await invokeTauri<{
    runs: Array<{ execution_trace?: Array<{ output?: { preview?: string } }> }>;
  }>(page, "get_workflow_runs", { workflowId: resolvedWorkflowId, limit: 1 });
  const dispatchPreview =
    runs.runs[0]?.execution_trace?.[0]?.output?.preview ?? "";
  expect(dispatchPreview).toContain(jobId);
});

test("workflow form offers invoke chainlet relay action", async ({ page }) => {
  await installMockBridge(page);
  await gotoApp(page);
  await navigateToWorkflows(page);
  await page.getByRole("button", { name: "Create Workflow" }).click();
  const dialog = page.getByRole("dialog", { name: "Create workflow" });
  await selectWorkflowChannel(page, dialog);
  await dialog.getByRole("button", { name: "Add step", exact: true }).click();
  await expect(
    page.getByRole("menuitem", { name: "Invoke Chainlet (relay)" }),
  ).toBeVisible();
});
