/** Local lesson media with an explicit, non-blocking reading fallback. */
const boundPlayers = new WeakSet();

function copy(locale) {
  return String(locale).startsWith("zh") ? {
    missing: "当前安装包未包含本课完整视频。",
    unavailable: "本课尚未配置视频文件。",
    failed: "视频无法播放。",
    aborted: "视频加载已中断。",
    network: "视频加载失败，请检查本地服务或网络连接。",
    decode: "浏览器无法解码此视频，文件可能损坏或格式不受支持。",
    unsupported: "视频文件不可用，或浏览器不支持其格式。",
    reading: "可先阅读下方已展开的讲稿、要点与分镜，再继续测验；这不代表已观看视频。",
    retry: "重试视频",
    retrying: "正在重试视频；仍可阅读下方课程内容。",
  } : {
    missing: "The full video for this lesson is not included in this installation.",
    unavailable: "No video file is configured for this lesson.",
    failed: "The video could not be played.",
    aborted: "Video loading was interrupted.",
    network: "Video loading failed. Check the local service or network connection.",
    decode: "The browser could not decode this video. The file may be damaged or unsupported.",
    unsupported: "The video file is unavailable or its format is not supported by this browser.",
    reading: "Read the expanded transcript, takeaways and storyboard below, then continue to the quiz. This does not count as watching the video.",
    retry: "Retry video",
    retrying: "Retrying the video. You can still read the lesson below.",
  };
}

function escapeHtml(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

export function renderLessonVideo(lesson, locale = "en") {
  const labels = copy(locale);
  if (!lesson.local_video) {
    return `<div class="teaching-local-media"><p class="hint" role="status">${labels.unavailable} ${labels.reading}</p></div>`;
  }
  // Preserve the catalog source; a short preview must not replace a full lesson.
  return `<div class="teaching-local-media">
    <div class="teaching-video-embed teaching-local-video">
      <video controls preload="metadata" playsinline src="${escapeHtml(lesson.local_video)}" aria-label="${escapeHtml(lesson.title || lesson.id)}">${labels.failed}</video>
    </div>
    <p class="hint" data-video-status role="status" aria-live="polite" hidden></p>
    <button type="button" class="btn btn-outline" data-video-retry hidden>${labels.retry}</button>
  </div>`;
}

/** Probe only local URLs. Failed/unsupported HEAD is inconclusive, not "missing". */
export async function isLessonVideoMissing(source, fetchFn = globalThis.fetch, baseUrl = globalThis.location?.href) {
  if (!fetchFn || !baseUrl) return false;
  let url;
  try {
    url = new URL(source, baseUrl);
    if (!/^https?:$/.test(url.protocol) || url.origin !== new URL(baseUrl).origin) return false;
  } catch {
    return false;
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetchFn(url.href, { method: "HEAD", cache: "no-store", credentials: "same-origin", signal: controller.signal });
    return response.status === 404 || response.status === 410;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

export function bindLessonVideos(root, { locale = "en", onEvent = () => {}, fetchFn, baseUrl } = {}) {
  const labels = copy(locale);
  root.querySelectorAll(".teaching-local-media").forEach((wrapper) => {
    const block = wrapper.closest(".teaching-video-block");
    const openReading = () => block?.querySelectorAll(".teaching-script-fold, .teaching-storyboard")
      .forEach((details) => { details.open = true; });
    const video = wrapper.querySelector("video");
    if (!video) { openReading(); return; }
    if (boundPlayers.has(video)) return;
    boundPlayers.add(video);
    const status = wrapper.querySelector("[data-video-status]");
    const retry = wrapper.querySelector("[data-video-retry]");
    let generation = 0;
    const show = (message) => {
      status.textContent = message;
      status.hidden = false;
    };
    const failed = async () => {
      const current = ++generation;
      const code = video.error?.code || 0;
      const reason = ({ 1: labels.aborted, 2: labels.network, 3: labels.decode, 4: labels.unsupported })[code] || labels.failed;
      show(`${reason} ${labels.reading}`);
      retry.hidden = false;
      openReading();
      onEvent({ event_type: "video_error", video_id: block?.dataset.videoId, media_error_code: code });
      const missing = await isLessonVideoMissing(video.currentSrc || video.src, fetchFn, baseUrl);
      // A newer retry, successful load or navigation wins over this old check.
      if (current !== generation || !video.isConnected) return;
      if (missing) show(`${labels.missing} ${labels.reading}`);
    };
    video.addEventListener("error", failed);
    video.addEventListener("loadedmetadata", () => {
      generation += 1;
      status.hidden = true;
      retry.hidden = true;
      onEvent({ event_type: "video_load", video_id: block?.dataset.videoId });
    });
    retry.addEventListener("click", () => {
      generation += 1;
      show(labels.retrying);
      // Keep Retry available even if a stalled server never fires a media event.
      video.load();
    });
    // An already cached failure may occur before the lesson's handlers bind.
    if (video.error) void failed();
  });
}
