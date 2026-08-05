import { closeMainWindow, open, showHUD } from "@raycast/api";

/// Every command is one URL away: Wick registers the wick:// scheme, so this
/// launches it if it isn't running and hands the command to it if it is.
export async function send(command: string, duration?: string, hud?: string) {
  const d = (duration ?? "").trim();
  const url = `wick://${command}${d ? `?d=${encodeURIComponent(d)}` : ""}`;
  await closeMainWindow();
  await open(url);
  if (hud) await showHUD(hud);
}
