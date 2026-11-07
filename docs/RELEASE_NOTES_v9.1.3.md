# v9.1.3 candidate: tutorial and new-feature visibility

This is a local candidate pending Mac installation review. It has not been pushed or published as a GitHub release.

## Changes

- Startup/sidebar now clearly points to instructions for the separate metadata service; the former same-origin static link could not reach its API. See START_NEW_FEATURES.md. Main/default-branch downloads do not contain the independent development branch.
- Installer/launcher display labels align with the candidate version. Package instructions use existing filenames and local metadata launchers instead of recommending the old main-branch installer.
- Original illustrated tutorial: 2:47, 1280×720 H.264/AAC, offline English synthetic narration, 17 synchronized bilingual cues across 9 chapters. It explains v9.1.2 capabilities and is bundled in v9.1.3. It is not a screen recording. No external TTS, paid services, stock footage, live AI or R analysis was used.
- Tutorial links from startup and metadata pages; allowlisted local MP4/VTT assets with Range/HEAD support, selectable captions and textual fallback.
- All 20 legacy course MP4 references are missing from the source tree. The existing 31.85-second preview is valid but is not a full lesson. New native media error handling explains missing files versus decode/network problems, opens transcripts/storyboards and permits retry without falsely marking lessons watched.

## Verified in cloud

- 122 Python unit/integration tests passed (including 4 new tutorial HTTP tests).
- Node teaching-video fallback tests, runtime-port tests, locale tests and frontend syntax checks passed.
- Actual tutorial full ffmpeg decode, H.264/AAC/fast-start metadata, caption timings and content, and source evidence assertions passed. Representative frames visually inspected.
- Actual loopback tutorial MP4 Range returned206 with the requested bytes; HTML and both VTT assets returned200 with correct media types.
- No credentials, personal PDFs, downloaded matrix contents, caches or runtime configuration are included. Tutorial evidence contains public archive metadata and explicitly synthetic teaching fixtures.

## Not verified / not provided

- Interactive browser playback: cloud browser could not reach the isolated local service; file navigation was not permitted. No alternate browser automation bypass was used.
- Mac/Windows native installation and user-specific upgrade are pending separate local review.
- No full R workflow execution, live model call, raw-read download executor or general multi-omics execution.
- The 20 missing full lesson videos are not replaced by this one tutorial.
- Source archive includes code/media, not installed R/Python dependencies. Unpack into a new directory rather than overwriting an existing installation.
