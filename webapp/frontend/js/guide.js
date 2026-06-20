/**
 * User Guide page — bilingual render + install command copy.
 */
import { getLocale, t } from "./locale.js?v=2026-06-20-v5.0.0";

const INSTALL_MAC_ONE_LINE =
  'bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/master/webapp/scripts/install_from_github.sh)"';

const INSTALL_WIN_ONE_LINE = `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/master/webapp/scripts/install_from_github.ps1 | iex`;

const INSTALL_R_ONLY = `if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")
library(EasyMultiProfiler)`;

const COPY = {
  zh: {
    heroTitle: "EasyMultiProfiler Web v5.0.0 使用指南",
    heroHint: "本页汇总<strong>安装路径</strong>（Mac / Windows / 仅 R 包）与<strong>网页内分析流程</strong>。零基础：先完成对应系统安装，再从 Course 或「一键示例数据」开始。",
    pathsTitle: "三条安装路径（请只选与你电脑匹配的一条）",
    macCard: "🍎 macOS · Web 版",
    macCardP: "终端一行命令，或双击 <code>Run-EMP-Web.command</code>",
    macBtn: "查看 Mac 步骤",
    winCard: "🪟 Windows · Web 版",
    winCardP: "PowerShell 一行命令，或双击 <code>Repair-and-Start-EMP-Web.bat</code>",
    winBtn: "查看 Windows 步骤",
    rCard: "📊 已有 R / RStudio",
    rCardP: "只装 EMP R 包（不使用本网页）",
    rBtn: "查看 R 包步骤",
    installTitle: "安装说明（分平台）",
    macH: "Mac 推荐：一键安装（首次约 15–40 分钟）",
    macS1: "打开「终端 Terminal」",
    macS2: "粘贴下面整行并回车（自动克隆、装 R 依赖、启动网页）",
    macN1: "已有仓库？双击 <code>Run-EMP-Web.command</code>；缺包：<code>bash webapp/scripts/launch_emp_web.sh --repair</code>",
    macN2: "没有 R？<code>brew install --cask r python@3.12 git</code>，详见 docs/INSTALL_MAC.md",
    macN3: "成功：浏览器 <code>http://127.0.0.1:8080</code>；API <code>/api/health</code> 为 ok",
    winH: "Windows 推荐：PowerShell 一键安装",
    winS1: "若未装 R：管理员 PowerShell 运行 <code>winget install --id RProject.R -e</code> 等",
    winS2: "关闭并重新打开 PowerShell，粘贴下面命令",
    winN1: "已有文件夹：",
    winL1: "首次：双击 <code>Repair-and-Start-EMP-Web.bat</code>",
    winL2: "日常：双击 <code>Start-EMP-Web.bat</code>",
    winL3: "缺包/更新：再运行 Repair bat",
    winN2: "<strong>勿与 Mac 脚本混用</strong>（.bat/.ps1 vs .sh/.command）。见 docs/INSTALL_WINDOWS.md",
    winN3: "R 找不到：设置 <code>$env:EMPI_RSCRIPT</code> 为 Rscript.exe 完整路径",
    rH: "仅安装 EMP R 包",
    rP: "Web 版 AI、Course、Run All <strong>仅在浏览器版</strong>提供。",
    rCopy: "复制 R 代码",
    flowTitle: "网页内分析流程（v5 推荐）",
    featTitle: "v5.0.0 新功能速览",
    navTitle: "左侧导航说明",
    faqTitle: "常见问题",
  },
  en: {
    heroTitle: "EasyMultiProfiler Web v5.0.0 User Guide",
    heroHint: "Install paths (Mac / Windows / R-only) and the in-app workflow. Complete install first, then start from <strong>Course</strong> or one-click demo data.",
    pathsTitle: "Three install paths (pick one for your computer)",
    macCard: "🍎 macOS · Web",
    macCardP: "One-line Terminal command or double-click <code>Run-EMP-Web.command</code>",
    macBtn: "Mac steps",
    winCard: "🪟 Windows · Web",
    winCardP: "PowerShell one-liner or <code>Repair-and-Start-EMP-Web.bat</code>",
    winBtn: "Windows steps",
    rCard: "📊 R / RStudio only",
    rCardP: "EMP R package only (no browser UI)",
    rBtn: "R package steps",
    installTitle: "Install instructions (by platform)",
    macH: "Mac: one-line install (15–40 min first time)",
    macS1: "Open Terminal",
    macS2: "Paste the line below and press Enter",
    macN1: "Have the repo? Double-click <code>Run-EMP-Web.command</code>; repair: <code>launch_emp_web.sh --repair</code>",
    macN2: "No R? <code>brew install --cask r python@3.12 git</code> — see docs/INSTALL_MAC.md",
    macN3: "Success: <code>http://127.0.0.1:8080</code> and API health returns ok",
    winH: "Windows: PowerShell one-line install",
    winS1: "If R missing: admin PowerShell — <code>winget install --id RProject.R -e</code> etc.",
    winS2: "Reopen PowerShell and paste the command below",
    winN1: "Local folder:",
    winL1: "First time: <code>Repair-and-Start-EMP-Web.bat</code>",
    winL2: "Daily: <code>Start-EMP-Web.bat</code>",
    winL3: "Missing packages: run Repair bat again",
    winN2: "<strong>Do not mix</strong> Mac scripts (.sh) with Windows (.bat/.ps1). See INSTALL_WINDOWS.md",
    winN3: "R not found: set <code>$env:EMPI_RSCRIPT</code> to full Rscript.exe path",
    rH: "EMP R package only",
    rP: "AI interpret, Course, Run All are <strong>web-only</strong> features.",
    rCopy: "Copy R code",
    flowTitle: "In-app workflow (v5)",
    featTitle: "v5.0.0 highlights",
    navTitle: "Sidebar pages",
    faqTitle: "FAQ",
  },
};

function L(key) {
  const loc = getLocale();
  return COPY[loc]?.[key] ?? COPY.zh[key] ?? key;
}

function renderGuideHtml() {
  return `
    <div class="card guide-hero">
      <div class="guide-hero-head">
        <h2>${L("heroTitle")}</h2>
        <span class="version-badge version-badge-lg">v5.0.0</span>
      </div>
      <p class="hint">${L("heroHint")}</p>
    </div>
    <div class="card">
      <h3>${L("pathsTitle")}</h3>
      <div class="guide-path-grid">
        <div class="guide-path-card guide-path-mac">
          <h4>${L("macCard")}</h4><p>${L("macCardP")}</p>
          <button type="button" class="btn btn-outline btn-sm guide-goto-tab" data-guide-tab="mac">${L("macBtn")}</button>
        </div>
        <div class="guide-path-card guide-path-win">
          <h4>${L("winCard")}</h4><p>${L("winCardP")}</p>
          <button type="button" class="btn btn-outline btn-sm guide-goto-tab" data-guide-tab="windows">${L("winBtn")}</button>
        </div>
        <div class="guide-path-card guide-path-r">
          <h4>${L("rCard")}</h4><p>${L("rCardP")}</p>
          <button type="button" class="btn btn-outline btn-sm guide-goto-tab" data-guide-tab="rstudio">${L("rBtn")}</button>
        </div>
      </div>
    </div>
    <div class="card">
      <h3>${L("installTitle")}</h3>
      <div class="guide-install-tabs">
        <button type="button" class="guide-install-tab active" data-guide-tab="mac">macOS</button>
        <button type="button" class="guide-install-tab" data-guide-tab="windows">Windows</button>
        <button type="button" class="guide-install-tab" data-guide-tab="rstudio">R / RStudio</button>
      </div>
      <div class="guide-install-panel" data-guide-panel="mac">
        <h4>${L("macH")}</h4>
        <ol class="guide-steps"><li>${L("macS1")}</li><li>${L("macS2")}</li></ol>
        <div class="guide-cmd-block">
          <pre id="guide-cmd-mac" class="guide-cmd">${INSTALL_MAC_ONE_LINE}</pre>
          <button type="button" class="btn btn-sm guide-copy-btn guide-copy-btn-dark" data-copy-target="guide-cmd-mac">${t("guide.copy")}</button>
        </div>
        <p class="hint">${L("macN1")}</p><p class="hint">${L("macN2")}</p><p class="hint">${L("macN3")}</p>
      </div>
      <div class="guide-install-panel hidden" data-guide-panel="windows">
        <h4>${L("winH")}</h4>
        <ol class="guide-steps"><li>${L("winS1")}</li><li>${L("winS2")}</li></ol>
        <div class="guide-cmd-block">
          <pre id="guide-cmd-win" class="guide-cmd">${INSTALL_WIN_ONE_LINE}</pre>
          <button type="button" class="btn btn-sm guide-copy-btn guide-copy-btn-dark" data-copy-target="guide-cmd-win">${t("guide.copy")}</button>
        </div>
        <p class="hint"><strong>${L("winN1")}</strong></p>
        <ul class="guide-bullets">
          <li>${L("winL1")}</li><li>${L("winL2")}</li><li>${L("winL3")}</li>
        </ul>
        <p class="hint">${L("winN2")}</p><p class="hint">${L("winN3")}</p>
      </div>
      <div class="guide-install-panel hidden" data-guide-panel="rstudio">
        <h4>${L("rH")}</h4>
        <p class="hint">${L("rP")}</p>
        <div class="guide-cmd-block">
          <pre id="guide-cmd-r" class="guide-cmd">${INSTALL_R_ONLY}</pre>
          <button type="button" class="btn btn-sm guide-copy-btn guide-copy-btn-dark" data-copy-target="guide-cmd-r">${L("rCopy")}</button>
        </div>
      </div>
    </div>
    ${renderFlowSection()}${renderFaqSection()}
  `;
}

function renderFlowSection() {
  const zh = getLocale() === "zh";
  return `
    <div class="card">
      <h3>${L("flowTitle")}</h3>
      <div class="guide-flow">
        <div class="guide-flow-step"><strong>1 Course</strong><span>${zh ? "视频+测验 / 示例数据" : "Videos + demo data"}</span></div>
        <div class="guide-flow-arrow">→</div>
        <div class="guide-flow-step"><strong>2 Data</strong><span>${zh ? "上传或 demo" : "Upload or demo"}</span></div>
        <div class="guide-flow-arrow">→</div>
        <div class="guide-flow-step"><strong>3 Prepare</strong><span>${zh ? "推荐参数" : "Recommended defaults"}</span></div>
        <div class="guide-flow-arrow">→</div>
        <div class="guide-flow-step"><strong>4 Analyze</strong><span>${zh ? "AI 解读" : "AI interpret"}</span></div>
        <div class="guide-flow-arrow">→</div>
        <div class="guide-flow-step"><strong>5 Run All</strong><span>zip</span></div>
        <div class="guide-flow-arrow">→</div>
        <div class="guide-flow-step"><strong>6 Visualize</strong><span>${zh ? "发表级出图" : "Publication plots"}</span></div>
      </div>
    </div>`;
}

function renderFaqSection() {
  const zh = getLocale() === "zh";
  if (zh) {
    return `<div class="card"><h3>${L("faqTitle")}</h3><dl class="guide-faq">
      <dt>8080 打不开？</dt><dd>Mac: stop_local.sh 后重启；Windows: Restart-EMP-Web.bat</dd>
      <dt>Mac 和 Windows 命令一样吗？</dt><dd><strong>不一样。</strong> 各用各平台脚本。</dd>
      <dt>AI 语言？</dt><dd>左侧语言栏选 中文 / EN / 自动；AI 解读会跟随界面语言。</dd>
    </dl></div>`;
  }
  return `<div class="card"><h3>${L("faqTitle")}</h3><dl class="guide-faq">
    <dt>Port 8080 not loading?</dt><dd>Mac: stop_local.sh then restart; Windows: Restart-EMP-Web.bat</dd>
    <dt>Same install command on Mac and Windows?</dt><dd><strong>No.</strong> Use platform-specific scripts only.</dd>
    <dt>AI language?</dt><dd>Use the sidebar Language control (Auto / 中文 / EN). AI interpret follows UI locale.</dd>
  </dl></div>`;
}

function bindGuideTabs(root) {
  const tabs = root.querySelectorAll(".guide-install-tab");
  const panels = root.querySelectorAll(".guide-install-panel");
  const show = (id) => {
    tabs.forEach((t) => t.classList.toggle("active", t.dataset.guideTab === id));
    panels.forEach((p) => p.classList.toggle("hidden", p.dataset.guidePanel !== id));
  };
  tabs.forEach((tab) => tab.addEventListener("click", () => show(tab.dataset.guideTab)));
  const pref = root.dataset.guidePlatform || detectPlatform();
  show(pref === "windows" ? "windows" : pref === "rstudio" ? "rstudio" : "mac");
}

function detectPlatform() {
  const ua = navigator.userAgent || "";
  if (/Win/i.test(ua)) return "windows";
  if (/Mac/i.test(ua)) return "mac";
  return "unknown";
}

function bindCopyButtons(root) {
  root.querySelectorAll(".guide-copy-btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const el = document.getElementById(btn.dataset.copyTarget);
      const text = el?.textContent?.trim() || "";
      if (!text) return;
      try {
        await navigator.clipboard.writeText(text);
        const old = btn.textContent;
        btn.textContent = t("guide.copied");
        setTimeout(() => { btn.textContent = old; }, 1600);
      } catch {
        window.dispatchEvent(new CustomEvent("emp:toast", {
          detail: { msg: getLocale() === "en" ? "Copy failed" : "复制失败", type: "error" },
        }));
      }
    });
  });
}

export function renderGuidePage() {
  const root = document.getElementById("guide-root");
  if (!root) return;
  root.dataset.guidePlatform = detectPlatform();
  root.innerHTML = renderGuideHtml();
  bindGuideTabs(root);
  bindCopyButtons(root);
  root.querySelectorAll(".guide-goto-tab").forEach((btn) => {
    btn.addEventListener("click", () => openGuideInstallTab(btn.dataset.guideTab));
  });
  if (window.lucide) window.lucide.createIcons({ nodes: [root] });
}

export function initGuide() {
  renderGuidePage();
}

export function openGuideInstallTab(tab) {
  const page = document.getElementById("page-guide");
  if (page && !page.classList.contains("active")) return;
  renderGuidePage();
  const root = document.getElementById("guide-root");
  const btn = root?.querySelector(`.guide-install-tab[data-guide-tab="${tab}"]`);
  btn?.click();
  root?.scrollIntoView({ behavior: "smooth", block: "start" });
}

window.addEventListener("emp:locale-change", () => {
  if (document.getElementById("page-guide")?.classList.contains("active")) renderGuidePage();
});
