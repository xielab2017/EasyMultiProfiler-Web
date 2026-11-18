// One record per conversation. Each tab remembers which conversation it opened.
const PREFIX = 'emp_chat_transcript_v1:';
const ACTIVE = 'emp_chat_active_v1';
const newId = () => Array.from(globalThis.crypto.getRandomValues(new Uint8Array(16)),
  byte => byte.toString(16).padStart(2,'0')).join('');

function parseRecord(raw) {
  try {
    const data = JSON.parse(raw);
    if (!Array.isArray(data?.messages) || !Number.isFinite(data.updated)) return null;
    if (!data.messages.every(m => ['user', 'assistant'].includes(m.role) && typeof m.text === 'string')) return null;
    return data;
  } catch { return null; }
}

export function createChatHistory(storage, tabStorage, idFactory = newId) {
  let id = tabStorage?.getItem(ACTIVE) || idFactory();
  let previous = storage?.getItem(PREFIX + id) ?? null;
  let state = parseRecord(previous) || {updated: 0, messages: []};
  function activate(next, raw) {
    id = next;
    previous = raw;
    state = parseRecord(raw) || {updated: 0, messages: []};
    tabStorage?.setItem(ACTIVE, id);
  }
  function write() {
    if (!storage) return false;
    try {
      // Fork a stale tab's transcript rather than replacing another tab's newer turns.
      if (storage.getItem(PREFIX + id) !== previous) id = idFactory();
      const raw = JSON.stringify(state);
      storage.setItem(PREFIX + id, raw);
      previous = raw;
      tabStorage?.setItem(ACTIVE, id);
      return true;
    } catch { return false; }
  }
  return {
    get id() { return id; },
    get messages() { return state.messages; },
    append(role, text, model) {
      state.messages.push({role, text, ...(model ? {model} : {})});
      state.updated = Date.now();
      return write();
    },
    list() {
      const entries = [];
      for (let i = 0; i < (storage?.length || 0); i++) {
        const key = storage.key(i);
        if (!key?.startsWith(PREFIX)) continue;
        const record = parseRecord(storage.getItem(key));
        if (record?.messages.length) entries.push({id:key.slice(PREFIX.length), updated:record.updated,
          title:record.messages.find(m => m.role === 'user')?.text.slice(0,60) || 'EMP'});
      }
      return entries.sort((a,b) => b.updated-a.updated);
    },
    open(next) {
      const raw = storage?.getItem(PREFIX + next);
      if (!parseRecord(raw)) return false;
      activate(next,raw);
      return true;
    },
    start() { activate(idFactory(), null); },
    clear() {
      if (storage?.getItem(PREFIX + id) === previous) storage?.removeItem(PREFIX + id);
      this.start();
    },
  };
}

export function conversationMarkdown(messages) {
  return messages.map(m => '## ' + (m.role === 'user' ? 'User' : (m.model || 'Assistant')) + '\n\n' + m.text).join('\n\n');
}

export function downloadMarkdown(text, name) {
  const url = URL.createObjectURL(new Blob([text + '\n'], {type:'text/markdown;charset=utf-8'}));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
