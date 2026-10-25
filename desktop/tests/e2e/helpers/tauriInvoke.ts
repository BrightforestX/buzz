import type { Page } from "@playwright/test";

type InvokeFn = (
  command: string,
  payload?: Record<string, unknown>,
) => Promise<unknown>;

/**
 * True when the page has real Tauri IPC (embedded webview), not the mock bridge.
 */
export async function hasRealTauriInvoke(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const w = window as Window & {
      __BUZZ_E2E_INVOKE_MOCK_COMMAND__?: unknown;
      __TAURI_INTERNALS__?: { invoke?: unknown };
    };
    if (typeof w.__BUZZ_E2E_INVOKE_MOCK_COMMAND__ === "function") {
      return false;
    }
    return typeof w.__TAURI_INTERNALS__?.invoke === "function";
  });
}

/**
 * Invoke a Tauri command from an in-page context (real webview or mock bridge).
 */
export async function invokeFromPage<T>(
  page: Page,
  command: string,
  payload: Record<string, unknown> = {},
): Promise<T> {
  return page.evaluate(
    async ({ cmd, args }) => {
      const w = window as typeof window & {
        __BUZZ_E2E_INVOKE_MOCK_COMMAND__?: InvokeFn;
        __TAURI_INTERNALS__?: { invoke: InvokeFn };
      };
      const invoke =
        w.__BUZZ_E2E_INVOKE_MOCK_COMMAND__ ?? w.__TAURI_INTERNALS__?.invoke;
      if (!invoke) {
        throw new Error(
          "No Tauri invoke available (mock bridge not installed and not running inside Buzz desktop)",
        );
      }
      return invoke(cmd, args) as Promise<T>;
    },
    { cmd: command, args: payload },
  );
}

export async function waitForInvokeBridge(page: Page, timeoutMs = 15_000) {
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
    { timeout: timeoutMs },
  );
}
