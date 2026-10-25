import { invokeTauri } from "@/shared/api/tauri";

export type Nip46BunkerStatus = {
  running: boolean;
  port: number;
  owner_pubkey: string | null;
  bunker_url: string | null;
  allowed_clients: string[];
};

export async function startGlassesBunker(
  port?: number,
): Promise<Nip46BunkerStatus> {
  return invokeTauri<Nip46BunkerStatus>("nip46_start_glasses_bunker", { port });
}

export async function stopGlassesBunker(): Promise<void> {
  return invokeTauri<void>("nip46_stop_glasses_bunker");
}

export async function allowGlassesClient(
  clientPubkey: string,
): Promise<string[]> {
  return invokeTauri<string[]>("nip46_allow_glasses_client", {
    clientPubkey,
  });
}

export async function getGlassesBunkerStatus(): Promise<Nip46BunkerStatus> {
  return invokeTauri<Nip46BunkerStatus>("nip46_get_glasses_bunker_status");
}
