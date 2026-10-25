import { invokeTauri } from "@/shared/api/tauri";
import { Input } from "@/shared/ui/input";
import { Switch } from "@/shared/ui/switch";
import { useCallback, useEffect, useState } from "react";
import { SettingsOptionGroup, SettingsOptionRow } from "./SettingsOptionGroup";

export type AgentMcpSettingsView = {
  chainMcpEnabled: boolean;
  mirofishMcpEnabled: boolean;
  mirofishBaseUrl: string | null;
  chainMcpResolvable: boolean;
  mirofishMcpResolvable: boolean;
  resolvedChainCommand: string | null;
  resolvedMirofishCommand: string | null;
};

async function persistAgentMcpSettings(
  patch: Partial<
    Pick<
      AgentMcpSettingsView,
      "chainMcpEnabled" | "mirofishMcpEnabled" | "mirofishBaseUrl"
    >
  >,
  current: AgentMcpSettingsView,
): Promise<AgentMcpSettingsView> {
  return invokeTauri<AgentMcpSettingsView>("set_agent_mcp_settings", {
    chainMcpEnabled: patch.chainMcpEnabled ?? current.chainMcpEnabled,
    mirofishMcpEnabled: patch.mirofishMcpEnabled ?? current.mirofishMcpEnabled,
    mirofishBaseUrl:
      patch.mirofishBaseUrl !== undefined
        ? patch.mirofishBaseUrl
        : current.mirofishBaseUrl,
  });
}

function availabilityHint(
  resolvable: boolean,
  resolved: string | null,
): string {
  if (resolvable && resolved) {
    return `Resolved: ${resolved}`;
  }
  if (resolvable) {
    return "Available via environment configuration.";
  }
  return "Not found on this machine. Set MIROFISH_MCP_COMMAND or BASETEN_CHAIN_MCP_COMMAND, or install the bundled MCP.";
}

export function AgentMcpSettingsCard() {
  const [settings, setSettings] = useState<AgentMcpSettingsView | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [baseUrlDraft, setBaseUrlDraft] = useState("");

  useEffect(() => {
    let cancelled = false;
    void invokeTauri<AgentMcpSettingsView>("get_agent_mcp_settings")
      .then((view) => {
        if (cancelled) return;
        setSettings(view);
        setBaseUrlDraft(view.mirofishBaseUrl ?? "");
      })
      .catch((error: unknown) => {
        if (cancelled) return;
        const message =
          error instanceof Error
            ? error.message
            : "Could not load MCP settings";
        const hint =
          message.includes("get_agent_mcp_settings") &&
          message.toLowerCase().includes("not found")
            ? `${message} — restart Buzz desktop (pnpm tauri dev or rebuild the app) so the Rust backend includes the new MCP settings commands.`
            : message;
        setLoadError(hint);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const applyPatch = useCallback(
    async (
      patch: Partial<
        Pick<
          AgentMcpSettingsView,
          "chainMcpEnabled" | "mirofishMcpEnabled" | "mirofishBaseUrl"
        >
      >,
    ) => {
      if (!settings) return;
      try {
        const next = await persistAgentMcpSettings(patch, settings);
        setSettings(next);
        setBaseUrlDraft(next.mirofishBaseUrl ?? "");
      } catch (error) {
        console.error("Failed to save agent MCP settings:", error);
      }
    },
    [settings],
  );

  if (loadError) {
    return (
      <SettingsOptionGroup title="Agent MCP servers">
        <p className="text-sm text-destructive">{loadError}</p>
      </SettingsOptionGroup>
    );
  }

  if (!settings) {
    return (
      <SettingsOptionGroup title="Agent MCP servers">
        <p className="text-sm text-muted-foreground">Loading…</p>
      </SettingsOptionGroup>
    );
  }

  return (
    <SettingsOptionGroup title="Agent MCP servers">
      <p
        className="px-4 pb-2 text-xs text-muted-foreground/70"
        data-settings-subcopy
      >
        Optional MCP servers injected when agents start. Restart running agents
        after changing these toggles.
      </p>

      <SettingsOptionRow data-testid="settings-chain-mcp">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium" id="settings-chain-mcp-label">
            Baseten chain MCP
          </p>
          <p className="text-xs text-muted-foreground/70" data-settings-subcopy>
            Surreal experiments and chain tools for personas with a chain
            specialty.
          </p>
          <p className="mt-1 text-xs text-muted-foreground/60">
            {availabilityHint(
              settings.chainMcpResolvable,
              settings.resolvedChainCommand,
            )}
          </p>
        </div>
        <Switch
          aria-labelledby="settings-chain-mcp-label"
          checked={settings.chainMcpEnabled}
          data-testid="settings-chain-mcp-switch"
          disabled={!settings.chainMcpResolvable}
          onCheckedChange={(enabled) => {
            void applyPatch({ chainMcpEnabled: enabled });
          }}
        />
      </SettingsOptionRow>

      <SettingsOptionRow data-testid="settings-mirofish-mcp">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium" id="settings-mirofish-mcp-label">
            MiroFish MCP
          </p>
          <p className="text-xs text-muted-foreground/70" data-settings-subcopy>
            Simulations, graph tools, and experiment tracking against a local
            MiroFish stack.
          </p>
          <p className="mt-1 text-xs text-muted-foreground/60">
            {availabilityHint(
              settings.mirofishMcpResolvable,
              settings.resolvedMirofishCommand,
            )}
          </p>
        </div>
        <Switch
          aria-labelledby="settings-mirofish-mcp-label"
          checked={settings.mirofishMcpEnabled}
          data-testid="settings-mirofish-mcp-switch"
          disabled={!settings.mirofishMcpResolvable}
          onCheckedChange={(enabled) => {
            void applyPatch({ mirofishMcpEnabled: enabled });
          }}
        />
      </SettingsOptionRow>

      <SettingsOptionRow data-testid="settings-mirofish-base-url">
        <div className="min-w-0 flex-1">
          <label
            className="text-sm font-medium"
            htmlFor="settings-mirofish-base-url-input"
          >
            MiroFish API base URL
          </label>
          <p className="text-xs text-muted-foreground/70" data-settings-subcopy>
            Used when MIROFISH_BASE_URL is not set in the environment. Default
            local stack: http://127.0.0.1:5001
          </p>
        </div>
        <Input
          className="max-w-xs"
          id="settings-mirofish-base-url-input"
          placeholder="http://127.0.0.1:5001"
          value={baseUrlDraft}
          onBlur={() => {
            const normalized = baseUrlDraft.trim();
            if (normalized === (settings.mirofishBaseUrl ?? "")) return;
            void applyPatch({
              mirofishBaseUrl: normalized.length > 0 ? normalized : null,
            });
          }}
          onChange={(event) => setBaseUrlDraft(event.target.value)}
        />
      </SettingsOptionRow>
    </SettingsOptionGroup>
  );
}
