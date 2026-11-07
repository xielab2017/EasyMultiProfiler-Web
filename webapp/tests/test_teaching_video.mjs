/** Run with: node webapp/tests/test_teaching_video.mjs */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { bindLessonVideos, isLessonVideoMissing, renderLessonVideo } from "../frontend/js/teaching_video.js";

const baseUrl = "http://127.0.0.1:8080/index.html";
const lesson = { id: "m16s_import", title: '16S <lesson> "one"', local_video: "videos/m16s_import.mp4?edition=1&lang=zh" };
const html = renderLessonVideo(lesson);
assert.ok(html.includes('src="videos/m16s_import.mp4?edition=1&amp;lang=zh"'));
assert.ok(html.includes("&lt;lesson&gt; &quot;one&quot;"));
assert.ok(html.includes('data-video-status role="status" aria-live="polite" hidden'));
assert.ok(html.includes("Retry video"));
assert.ok(renderLessonVideo(lesson, "zh").includes("重试视频"));
assert.ok(renderLessonVideo(lesson, "zh-TW").includes("重试视频"));
assert.ok(renderLessonVideo(lesson, "fr").includes("Retry video"));
assert.ok(renderLessonVideo({}).includes("No video file is configured"));
assert.ok(!renderLessonVideo({}).includes("<video"));

// Every real catalog source remains unchanged; the preview is never substituted.
const catalog = JSON.parse(readFileSync(new URL("../data/teaching_videos.json", import.meta.url), "utf8"));
for (const [id, item] of Object.entries(catalog.modules)) {
  const rendered = renderLessonVideo({ ...item, id });
  if (item.local_video) assert.ok(rendered.includes(`src="${item.local_video}"`));
  assert.ok(!rendered.includes("m16s_import_test_30s"));
}

for (const [status, expected] of [[404, true], [410, true], [200, false], [206, false], [401, false], [403, false], [405, false], [500, false]]) {
  assert.equal(await isLessonVideoMissing("videos/lesson.mp4", async (url, options) => {
    assert.equal(url, "http://127.0.0.1:8080/videos/lesson.mp4");
    assert.equal(options.method, "HEAD");
    assert.equal(options.credentials, "same-origin");
    return { status };
  }, baseUrl), expected);
}
assert.equal(await isLessonVideoMissing("videos/lesson.mp4", async () => { throw new Error("offline"); }, baseUrl), false);
for (const source of ["https://example.com/lesson.mp4", "//example.com/lesson.mp4", "javascript:alert(1)", "data:video/mp4,none"]) {
  assert.equal(await isLessonVideoMissing(source, () => { throw new Error("Must not probe outside this origin"); }, baseUrl), false);
}

function player(fetchFn = async () => ({ status: 404 }), locale = "en", initialError = null) {
  const events = {};
  const retryEvents = {};
  const status = { hidden: true, textContent: "" };
  const retry = { hidden: true, addEventListener: (name, fn) => { retryEvents[name] = fn; } };
  const details = [{ open: false }, { open: false }];
  const traces = [];
  const video = {
    error: initialError, src: "videos/m16s_import.mp4", currentSrc: "", isConnected: true, loads: 0,
    addEventListener: (name, fn) => { events[name] = fn; },
    load() { this.loads += 1; this.error = null; },
  };
  const block = { dataset: { videoId: "m16s_import" }, querySelectorAll: () => details };
  const wrapper = {
    closest: () => block,
    querySelector: (selector) => ({ video, "[data-video-status]": status, "[data-video-retry]": retry })[selector],
  };
  const root = { querySelectorAll: () => [wrapper] };
  const options = { locale, fetchFn, baseUrl, onEvent: (event) => traces.push(event) };
  bindLessonVideos(root, options);
  return { events, retryEvents, status, retry, details, traces, video, root, options };
}

const missing = player();
missing.video.error = { code: 4 };
await missing.events.error();
assert.equal(missing.status.hidden, false);
assert.ok(missing.status.textContent.includes("not included in this installation"));
assert.ok(missing.status.textContent.includes("does not count as watching"));
assert.ok(missing.details.every((item) => item.open));
assert.equal(missing.retry.hidden, false);
assert.deepEqual(missing.traces, [{ event_type: "video_error", video_id: "m16s_import", media_error_code: 4 }]);
missing.retryEvents.click();
missing.retryEvents.click();
assert.equal(missing.video.loads, 2);
assert.ok(missing.status.textContent.includes("Retrying"));
missing.events.loadedmetadata();
assert.equal(missing.status.hidden, true);
assert.equal(missing.retry.hidden, true);
assert.equal(missing.traces.at(-1).event_type, "video_load");

for (const [code, phrase] of [[1, "interrupted"], [2, "network"], [3, "decode"], [4, "not supported"], [0, "could not be played"]]) {
  const item = player(async () => ({ status: 200 }));
  item.video.error = { code };
  await item.events.error();
  assert.ok(item.status.textContent.includes(phrase));
  assert.ok(!item.status.textContent.includes("not included in this installation"));
}
const offline = player(async () => { throw new Error("offline"); }, "zh");
offline.video.error = { code: 2 };
await offline.events.error();
assert.ok(offline.status.textContent.includes("网络连接"));
assert.ok(offline.status.textContent.includes("这不代表已观看视频"));

// Late availability checks must not overwrite a retry, success, or removed lesson.
for (const change of ["retry", "success", "navigation"]) {
  let resolve;
  const pending = player(() => new Promise((done) => { resolve = done; }));
  pending.video.error = { code: 4 };
  const check = pending.events.error();
  if (change === "retry") pending.retryEvents.click();
  if (change === "success") pending.events.loadedmetadata();
  if (change === "navigation") pending.video.isConnected = false;
  resolve({ status: 404 });
  await check;
  assert.ok(!pending.status.textContent.includes("not included in this installation"));
  if (change === "success") assert.equal(pending.status.hidden, true);
}

const alreadyFailed = player(async () => ({ status: 404 }), "en", { code: 4 });
assert.equal(alreadyFailed.status.hidden, false);
assert.equal(alreadyFailed.traces.length, 1);
bindLessonVideos(alreadyFailed.root, alreadyFailed.options);
assert.equal(alreadyFailed.traces.length, 1, "Repeated binding must not duplicate errors or handlers");
await new Promise((resolve) => setTimeout(resolve, 0));
assert.ok(alreadyFailed.status.textContent.includes("not included in this installation"));

const noFileDetails = [{ open: false }];
bindLessonVideos({ querySelectorAll: () => [{ closest: () => ({ querySelectorAll: () => noFileDetails }), querySelector: () => null }] });
assert.equal(noFileDetails[0].open, true);
console.log("Teaching video fallback assertions passed");
