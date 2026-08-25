#!/usr/bin/env node
/**
 * Self-check: upload BED → user picks Mouse → refresh must keep mm (no re-upload).
 * Mirrors adoptChipLastPeaks / chipNormalizeAnnoGenome logic in app.js.
 */
function chipNormalizeAnnoGenome(g) {
  const s = String(g || "").toLowerCase().trim();
  if (!s) return "mm";
  if (s === "mm" || s.startsWith("mm") || s.includes("mouse")) return "mm";
  if (s === "hg19" || s === "grch37") return "hg19";
  if (s === "hs" || s.startsWith("hg") || s.includes("human")) return "hs";
  return "mm";
}

function chipAssemblyForAnnoGenome(g) {
  const key = chipNormalizeAnnoGenome(g);
  if (key === "mm") return "mm10";
  if (key === "hg19") return "hg19";
  return "hg38";
}

function adoptChipLastPeaks(prev, serverLp, { userSet, userGenome }) {
  const merged = { ...prev, ...(serverLp || {}) };
  if (userSet) {
    const g = chipNormalizeAnnoGenome(userGenome || prev.genome);
    merged.genome = g;
    merged.assembly = chipAssemblyForAnnoGenome(g);
  }
  return merged;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

// Simulate: upload registered as hs → user selects mm → listPeaks returns hs
const afterUpload = { peak_file: "/tmp/HA_summits.bed", genome: "hs", assembly: "hg38" };
const afterUserPick = { ...afterUpload, genome: "mm", assembly: "mm10" };
const fromServer = { peak_file: "/tmp/HA_summits.bed", genome: "hs", assembly: "hg38", n_peaks: 100 };
const afterRefresh = adoptChipLastPeaks(afterUserPick, fromServer, {
  userSet: true,
  userGenome: "mm",
});
assert(afterRefresh.genome === "mm", `expected mm after refresh, got ${afterRefresh.genome}`);
assert(afterRefresh.assembly === "mm10", `expected mm10 assembly, got ${afterRefresh.assembly}`);
assert(afterRefresh.n_peaks === 100, "server metadata should still merge");

// Human must still work
const human = adoptChipLastPeaks(afterUpload, fromServer, {
  userSet: true,
  userGenome: "hs",
});
assert(human.genome === "hs", `expected hs when user picks Human, got ${human.genome}`);

// Without userSet, server genome wins
const seeded = adoptChipLastPeaks({}, fromServer, { userSet: false, userGenome: "mm" });
assert(seeded.genome === "hs", `expected server hs when not userSet, got ${seeded.genome}`);

console.log("ok: chip genome session stickiness");
