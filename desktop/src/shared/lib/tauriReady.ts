import { isTauri } from "@tauri-apps/api/core";

type TauriInternals = {
  invoke?: (...args: unknown[]) => Promise<unknown>;
  transformCallback?: (
    callback: (...args: unknown[]) => void,
    once?: boolean,
  ) => number;
};

function getTauriInternals(): TauriInternals | undefined {
  return (window as Window & { __TAURI_INTERNALS__?: TauriInternals })
    .__TAURI_INTERNALS__;
}

/** True when `invoke` and event `listen` can run without throwing. */
export function isTauriIpcReady(): boolean {
  const internals = getTauriInternals();
  return (
    typeof internals?.invoke === "function" &&
    typeof internals?.transformCallback === "function"
  );
}

const DEFAULT_TAURI_IPC_READY_TIMEOUT_MS = 30_000;

/**
 * Wait until the Tauri webview has injected `__TAURI_INTERNALS__`.
 * Vite can mount React before that injection finishes; calling `listen` or
 * `invoke` earlier throws on `transformCallback`.
 *
 * Returns false immediately in a plain browser (no Tauri host).
 */
export async function waitForTauriIpcReady(
  timeoutMs = DEFAULT_TAURI_IPC_READY_TIMEOUT_MS,
): Promise<boolean> {
  if (isTauriIpcReady()) return true;
  if (!isTauri()) return false;

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await new Promise<void>((resolve) => {
      window.setTimeout(resolve, 16);
    });
    if (isTauriIpcReady()) return true;
  }

  console.warn(
    "Tauri IPC was not ready before timeout; skipping native listeners",
  );
  return false;
}

export const noopTauriUnlisten = () => {};

/** Unlisten without throwing when registration failed or was already removed. */
export function safeTauriUnlisten(
  unlisten: (() => void) | null | undefined,
): void {
  if (!unlisten) return;
  try {
    unlisten();
  } catch {
    /* listener missing from Tauri registry or IPC torn down */
  }
}
