// The authenticated catalog grants access to the host research-chat renderer.
let active = null;
const listeners = new Set();

export function publishChatPanels(installed) {
  const panel = (installed || []).filter(p => p.enabled && p.abi === 'emp.chat-ui.v1' &&
    p.definition.renderer === 'research-chat').sort((a,b) => a.id.localeCompare(b.id))[0];
  const next = panel ? {id:panel.id, startup:panel.settings.startup} : null;
  if (active?.id === next?.id && active?.startup === next?.startup) return;
  active = next;
  for (const listen of listeners) listen(active);
}

export function watchChatPanel(listen) {
  listeners.add(listen);
  listen(active);
}
