import { expect, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import { openSettings } from "../helpers/settings";

test.describe("agent MCP settings", () => {
  test("green: loads toggles, persists off via set_agent_mcp_settings", async ({
    page,
  }) => {
    await installMockBridge(page);
    await page.goto("/");
    await openSettings(page, "agents");

    await expect(page.getByTestId("settings-chain-mcp-switch")).toBeChecked();
    await expect(
      page.getByTestId("settings-mirofish-mcp-switch"),
    ).toBeChecked();
    await expect(
      page.getByText("Resolved: /mock/baseten-chain-mcp"),
    ).toBeVisible();

    await page.getByTestId("settings-mirofish-mcp-switch").click();
    await expect(
      page.getByTestId("settings-mirofish-mcp-switch"),
    ).not.toBeChecked();

    await expect
      .poll(() =>
        page.evaluate(() => {
          const call = window.__BUZZ_E2E_COMMAND_LOG__?.findLast(
            ({ command }) => command === "set_agent_mcp_settings",
          );
          return (call?.payload as { mirofishMcpEnabled?: boolean } | null)
            ?.mirofishMcpEnabled;
        }),
      )
      .toBe(false);
  });

  test("green: base URL blur persists trimmed value", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");
    await openSettings(page, "agents");

    const input = page
      .getByTestId("settings-mirofish-base-url")
      .locator("input");
    await input.fill("  http://127.0.0.1:5001  ");
    await input.blur();

    await expect
      .poll(() =>
        page.evaluate(() => {
          const call = window.__BUZZ_E2E_COMMAND_LOG__?.findLast(
            ({ command }) => command === "set_agent_mcp_settings",
          );
          return (call?.payload as { mirofishBaseUrl?: string | null } | null)
            ?.mirofishBaseUrl;
        }),
      )
      .toBe("http://127.0.0.1:5001");
  });

  test("red: switches disabled when MCP binaries are not resolvable", async ({
    page,
  }) => {
    await installMockBridge(page, {
      agentMcpSettings: {
        chainMcpResolvable: false,
        mirofishMcpResolvable: false,
        resolvedChainCommand: null,
        resolvedMirofishCommand: null,
      },
    });
    await page.goto("/");
    await openSettings(page, "agents");

    await expect(page.getByTestId("settings-chain-mcp-switch")).toBeDisabled();
    await expect(
      page.getByTestId("settings-mirofish-mcp-switch"),
    ).toBeDisabled();
    await expect(
      page.getByText("Not found on this machine").first(),
    ).toBeVisible();
  });

  test("red: get_agent_mcp_settings failure surfaces load error", async ({
    page,
  }) => {
    await installMockBridge(page, {
      agentMcpSettings: {
        getError: "Command get_agent_mcp_settings not found",
      },
    });
    await page.goto("/");
    await openSettings(page, "agents");

    await expect(
      page.getByText(/Command get_agent_mcp_settings not found/),
    ).toBeVisible();
  });
});
