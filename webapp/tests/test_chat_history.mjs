import test from 'node:test';
import assert from 'node:assert/strict';
import {createChatHistory, conversationMarkdown} from '../frontend/js/chat_history.mjs';

function memoryStorage() {
  const map = new Map();
  return {get length() { return map.size; }, key: index => [...map.keys()][index],
    getItem: key => map.get(key) ?? null, setItem:(key,value) => map.set(key,value),
    removeItem: key => map.delete(key)};
}

test('restore the selected conversation, switch threads, and export the visible response as Markdown',() => {
  const browser=memoryStorage(), tab=memoryStorage();
  let id=0;
  const mount=()=>createChatHistory(browser,tab,()=>String(++id));
  const first=mount();
  first.append('user','Explain this figure');
  first.append('assistant','**Synthetic result**','MiniMax');
  const again=mount();
  assert.deepEqual(again.messages,first.messages);
  assert.match(conversationMarkdown(again.messages),/## MiniMax\n\n\*\*Synthetic result\*\*/);
  again.start();
  assert.equal(again.messages.length,0);
  again.append('user','Another question');
  assert.equal(again.list().length,2);
  assert.ok(again.open(first.id));
  again.clear();
  assert.equal(again.list().length,1);
  assert.equal(again.list()[0].title,'Another question');
});

test('concurrent changes in a duplicated tab keep both transcripts',() => {
  const local=memoryStorage(),session=memoryStorage();
  let i=0;
  const init=()=>createChatHistory(local,session,()=>String(++i));
  const a=init(); a.append('user','first');
  const b=init(); a.append('assistant','A'); b.append('assistant','B');
  assert.equal(b.list().length,2); assert.notEqual(a.id,b.id);
});
