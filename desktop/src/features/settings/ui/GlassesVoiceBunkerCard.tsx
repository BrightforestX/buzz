import { useCallback, useEffect, useState } from "react";
import { Copy, LoaderCircle, Power, ShieldCheck } from "lucide-react";
import { toast } from "sonner";

import {
  allowGlassesClient,
  getGlassesBunkerStatus,
  startGlassesBunker,
  stopGlassesBunker,
  type Nip46BunkerStatus,
} from "@/shared/api/tauriGlassesBunker";
import { writeTextToClipboard } from "@/shared/lib/clipboard";
import { Button } from "@/shared/ui/button";
import { Input } from "@/shared/ui/input";
import { SettingsOptionGroup, SettingsOptionRow } from "./SettingsOptionGroup";
import { SettingsSectionHeader } from "./SettingsSectionHeader";

const EMPTY_STATUS: Nip46BunkerStatus = {
  running: false,
  port: 9476,
  owner_pubkey: null,
  bunker_url: null,
  allowed_clients: [],
};

export function GlassesVoiceBunkerCard() {
  const [status, setStatus] = useState<Nip46BunkerStatus>(EMPTY_STATUS);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [clientPubkey, setClientPubkey] = useState("");

  const refresh = useCallback(async () => {
    try {
      const next = await getGlassesBunkerStatus();
      setStatus(next);
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : "Could not load bunker status.";
      toast.error(message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const toggleBunker = async () => {
    setBusy(true);
    try {
      if (status.running) {
        await stopGlassesBunker();
        toast.success("Glasses voice bunker stopped.");
      } else {
        const next = await startGlassesBunker();
        setStatus(next);
        toast.success("Glasses voice bunker is running.");
      }
      await refresh();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Bunker action failed.";
      toast.error(message);
    } finally {
      setBusy(false);
    }
  };

  const approveClient = async () => {
    const trimmed = clientPubkey.trim();
    if (!trimmed) return;
    setBusy(true);
    try {
      const allowed = await allowGlassesClient(trimmed);
      setStatus((prev) => ({ ...prev, allowed_clients: allowed }));
      setClientPubkey("");
      toast.success("Mentra client allowlisted for channel messages.");
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Could not allowlist client.";
      toast.error(message);
    } finally {
      setBusy(false);
    }
  };

  const copyBunkerUrl = async () => {
    if (!status.bunker_url) return;
    await writeTextToClipboard(status.bunker_url);
    toast.success("Bunker URL copied.");
  };

  return (
    <section className="min-w-0" data-testid="settings-glasses-bunker">
      <SettingsSectionHeader
        description="Let Mentra glasses send Buzz channel messages as you. Only kind 9 and NIP-42 auth (22242) are signed — your nsec never leaves this device."
        title="Glasses voice bunker"
      />
      <SettingsOptionGroup>
        <SettingsOptionRow>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium">Bunker</p>
            <p className="text-xs text-muted-foreground/70">
              {status.running
                ? `Listening on port ${status.port}. Desktop must stay online for voice turns.`
                : "Start the local NIP-46 bunker before using Buzz wake phrases on glasses."}
            </p>
          </div>
          <Button
            data-testid="glasses-bunker-toggle"
            disabled={busy || loading}
            onClick={() => void toggleBunker()}
            type="button"
            variant={status.running ? "secondary" : "default"}
          >
            {busy ? (
              <LoaderCircle className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Power className="mr-2 h-4 w-4" />
            )}
            {status.running ? "Stop" : "Start"}
          </Button>
        </SettingsOptionRow>

        {status.bunker_url ? (
          <SettingsOptionRow>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium">Bunker URL</p>
              <p className="text-xs text-muted-foreground/70">
                Paste into Mentra BUZZ_NIP46_BUNKER_URL (use ngrok for remote
                glasses).
              </p>
            </div>
            <div className="flex max-w-full items-center gap-2">
              <code className="truncate text-xs">{status.bunker_url}</code>
              <Button
                aria-label="Copy bunker URL"
                onClick={() => void copyBunkerUrl()}
                size="icon"
                type="button"
                variant="ghost"
              >
                <Copy className="h-4 w-4" />
              </Button>
            </div>
          </SettingsOptionRow>
        ) : null}

        <SettingsOptionRow>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium">Allow Mentra client</p>
            <p className="text-xs text-muted-foreground/70">
              When Mentra connects, approve its ephemeral client pubkey here.
              Prompt: &quot;Glasses Mentra wants to send channel messages as
              you.&quot;
            </p>
          </div>
          <div className="flex w-full max-w-md flex-col gap-2 sm:flex-row">
            <Input
              data-testid="glasses-bunker-client-pubkey"
              onChange={(event) => setClientPubkey(event.target.value)}
              placeholder="64-char hex client pubkey"
              value={clientPubkey}
            />
            <Button
              data-testid="glasses-bunker-allow-client"
              disabled={busy || !clientPubkey.trim()}
              onClick={() => void approveClient()}
              type="button"
            >
              <ShieldCheck className="mr-2 h-4 w-4" />
              Allow
            </Button>
          </div>
        </SettingsOptionRow>

        {status.allowed_clients.length > 0 ? (
          <SettingsOptionRow>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium">Allowlisted clients</p>
              <p className="text-xs text-muted-foreground/70">
                Only these client pubkeys may request sign_event.
              </p>
            </div>
            <ul className="space-y-1 text-xs font-mono">
              {status.allowed_clients.map((pk) => (
                <li key={pk}>{pk}</li>
              ))}
            </ul>
          </SettingsOptionRow>
        ) : null}
      </SettingsOptionGroup>
    </section>
  );
}
