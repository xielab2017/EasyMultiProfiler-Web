/**
 * User Guide page — bilingual render + install command copy.
 */
import { getLocale, t } from "./locale.js?v=2026-07-23-clinical-guide";

const INSTALL_MAC_ONE_LINE =
  'bash -c "$(curl -fsSL https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/master/webapp/scripts/install_from_github.sh)"';

const INSTALL_WIN_ONE_LINE = `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
irm https://raw.githubusercontent.com/xielab2017/EasyMultiProfiler-Web/master/webapp/scripts/install_from_github.ps1 | iex`;

const INSTALL_R_ONLY = `if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pak("liubingdong/EasyMultiProfiler")
library(EasyMultiProfiler)`;

const COPY = {
  zh: {
    heroTitle: "EasyMultiProfiler Web v9.0 使用指南",
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
    featTitle: "v9.0 新功能速览",
    navTitle: "左侧导航说明",
    faqTitle: "常见问题",
    clinDemoTitle: "Demo 操作指南：临床 × 16S（三线表 + 全流程关联）",
    clinDemoHint:
      "测试数据 <code>Clinical-test.csv</code> 与 16S 按患者键 <code>XYL_F_*</code> 一一对应（临床 130 行 ↔ 16S 132 样本）。" +
      "若临床页提示 <strong>No colData / 无临床变量</strong>，说明尚未导入临床表——请先完成下方「加载数据」。",
    clinDemoIds:
      "ID 规则：临床 <code>AK/BK</code>=UC 前后、<code>CJ/DJ</code>=IBS 前后；16S <code>K_*</code>=UC、<code>J_*</code>=IBS（<code>_01/_02</code> 为时点）。" +
      "系统自动对齐（例：<code>AK_XYL_F_0001</code> ↔ <code>K_XYL_F_0001_01</code>）。",
    clinDemoLoadTitle: "① 加载 Demo 数据",
    clinDemoThreeTitle: "② One-click 三线表",
    clinDemoSysTitle: "③ 系统临床统计（基线 + 前后 + 组间）",
    clinDemoCorTitle: "④ 微生物–性状关联（全流程）",
    clinDemoOutTitle: "⑤ 预期输出（基于测试数据实跑）",
    clinDemoTroubleshoot: "排错",
    m16sDemoTitle: "Demo 操作指南：16S Microbiome（全模块流程）",
    rnaDemoTitle: "Demo 操作指南：RNA-seq Transcriptomics（全模块流程）",
  },
  en: {
    heroTitle: "EasyMultiProfiler Web v9.0 User Guide",
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
    featTitle: "v9.0 highlights",
    navTitle: "Sidebar pages",
    faqTitle: "FAQ",
    clinDemoTitle: "Demo walkthrough: Clinical × 16S (three-line table + association)",
    clinDemoHint:
      "Test data <code>Clinical-test.csv</code> pairs with 16S via patient key <code>XYL_F_*</code> (130 clinical rows ↔ 132 16S samples). " +
      "If Clinical page shows <strong>No colData</strong>, load the clinical table first (step 1 below).",
    clinDemoIds:
      "IDs: clinical <code>AK/BK</code>=UC before/after, <code>CJ/DJ</code>=IBS; 16S <code>K_*</code>=UC, <code>J_*</code>=IBS (<code>_01/_02</code> timepoints). " +
      "Auto-aligned (e.g. <code>AK_XYL_F_0001</code> ↔ <code>K_XYL_F_0001_01</code>).",
    clinDemoLoadTitle: "① Load demo data",
    clinDemoThreeTitle: "② One-click three-line table",
    clinDemoSysTitle: "③ Systematic clinical stats (baseline + within + between)",
    clinDemoCorTitle: "④ Microbiome–trait association",
    clinDemoOutTitle: "⑤ Expected outputs (from test-data run)",
    clinDemoTroubleshoot: "Troubleshooting",
    m16sDemoTitle: "Demo walkthrough: 16S Microbiome (full module flow)",
    rnaDemoTitle: "Demo walkthrough: RNA-seq Transcriptomics (full module flow)",
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
        <span class="version-badge version-badge-lg">v9.0</span>
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
    ${renderFlowSection()}${renderClinicalDemoSection()}${renderM16sDemoSection()}${renderRnaseqDemoSection()}${renderFaqSection()}
  `;
}

function renderClinicalDemoSection() {
  const zh = getLocale() === "zh";
  const body = zh
    ? `
      <p class="hint">${L("clinDemoHint")}</p>
      <p class="hint">${L("clinDemoIds")}</p>

      <h4>${L("clinDemoLoadTitle")}</h4>
      <ol class="guide-steps">
        <li>打开 <code>http://127.0.0.1:8080/</code>，组学可选「全部」或 Microbiome 16S。</li>
        <li>左侧 <strong>数据</strong> → Course Demo：先点 <strong>Clinical Phenotypes</strong>，再点 <strong>16S Microbiome</strong>。</li>
        <li>或手动上传 <code>tests/Clinical-test.csv</code>（临床原始表）+ <code>tests/16S_level-7.csv</code> + <code>tests/16S_mapping.csv</code>。</li>
        <li>顶部实验下拉选中 <code>m16s_course</code>，再进入左侧 <strong>临床</strong>。</li>
      </ol>

      <h4>${L("clinDemoThreeTitle")}</h4>
      <ol class="guide-steps">
        <li>「当前分析策略」选 <strong>One-click 三线表</strong>。</li>
        <li>「临床数据来源」选 <strong>自动（优先已上传临床表）</strong>。</li>
        <li>勾选「跳过高基数分类变量」；引擎推荐 gtsummary（慢可改 EMP 备选）。</li>
        <li>点 <strong>检测临床变量</strong> → 摘要应出现 age / BMI 等数值列（不再是 No colData）。</li>
        <li>点 <strong>One-click 三线表</strong> → 下方出现按 Group（IBS/UC × before/after）的基线表，可下载 CSV。</li>
      </ol>

      <h4>${L("clinDemoSysTitle")}</h4>
      <ol class="guide-steps">
        <li>策略切换为 <strong>系统临床统计</strong>；队列可选「全部 / 仅 UC / 仅 IBS」。</li>
        <li>点 <strong>系统临床统计（基线+前后变化+组间差异）</strong>。</li>
        <li>查看 <strong>Within</strong>（同队列前后）与 <strong>Between</strong>（UC vs IBS 的 Δ）两张表。</li>
      </ol>

      <h4>${L("clinDemoCorTitle")}</h4>
      <ol class="guide-steps">
        <li>策略选 <strong>Feature × Trait correlation</strong>；实验保持 <code>m16s_course</code>。</li>
        <li>再次「检测临床变量」，勾选 3–6 个性状（如 age、BMI、weight、disease_duration）。</li>
        <li>运行相关 → taxa × traits 表/热图；再选一条做 <strong>Scatter + regression</strong>。</li>
      </ol>

      <h4>${L("clinDemoOutTitle")}</h4>
      <ul class="guide-bullets">
        <li>三线表约 <strong>44</strong> 行；示例：height 四组 P≈0.023，Drinking P≈0.004。</li>
        <li>Within：UC <code>partial_Mayo</code> 中位 4→2（P≈6.7×10⁻⁶）；IBS <code>IBS_SSS</code> 200→140（P≈2.3×10⁻⁷）。</li>
        <li>关联：ID 对齐 <strong>132/132</strong>；Spearman 约 2350 对检验。名义 Top 如 Phascolarctobacterium~weight（r≈0.31）。多数 padj 未过 0.05，宜作探索。</li>
      </ul>
      <div class="guide-demo-table-wrap">
        <table class="guide-demo-table">
          <thead><tr><th>变量</th><th>Overall</th><th>IBS_before</th><th>IBS_after</th><th>UC_before</th><th>UC_after</th><th>P</th></tr></thead>
          <tbody>
            <tr><td>age</td><td>47.55 ± 13.01</td><td>47.61 ± 13.81</td><td>47.64 ± 13.77</td><td>47.45 ± 12.34</td><td>47.48 ± 12.31</td><td>1.00</td></tr>
            <tr><td>BMI</td><td>23.86 ± 3.71</td><td>23.91 ± 3.32</td><td>23.90 ± 3.32</td><td>23.80 ± 4.25</td><td>23.79 ± 4.24</td><td>0.995</td></tr>
            <tr class="guide-demo-sig"><td>height</td><td>164.35 ± 7.03</td><td>166.00 ± 6.21</td><td>166.00 ± 6.21</td><td>162.31 ± 7.61</td><td>162.31 ± 7.61</td><td>0.023</td></tr>
            <tr class="guide-demo-sig"><td>Drinking</td><td>0.22 ± 0.41</td><td>0.33 ± 0.48</td><td>0.33 ± 0.48</td><td>0.07 ± 0.26</td><td>0.07 ± 0.26</td><td>0.004</td></tr>
          </tbody>
        </table>
        <p class="hint">三线表示例片段（测试数据实跑）。完整表可在临床页下载。</p>
      </div>

      <h4>${L("clinDemoTroubleshoot")}</h4>
      <dl class="guide-faq">
        <dt>No colData / 无临床变量</dt>
        <dd>先导入 Clinical Demo；数据来源选「自动」后点「检测临床变量」。</dd>
        <dt>Fewer than 5 samples have numeric trait</dt>
        <dd>临床与 16S ID 未对齐。请使用仓库 <code>Clinical-test.csv</code> + 16S Demo（勿混用不匹配样本表）。</dd>
        <dt>三线表很慢</dt>
        <dd>引擎改为「EMP 兼容备选」；保持「跳过高基数」。</dd>
      </dl>`
    : `
      <p class="hint">${L("clinDemoHint")}</p>
      <p class="hint">${L("clinDemoIds")}</p>

      <h4>${L("clinDemoLoadTitle")}</h4>
      <ol class="guide-steps">
        <li>Open <code>http://127.0.0.1:8080/</code>.</li>
        <li><strong>Data</strong> → Course Demo: load <strong>Clinical Phenotypes</strong>, then <strong>16S Microbiome</strong>.</li>
        <li>Or upload <code>tests/Clinical-test.csv</code> + <code>16S_level-7.csv</code> + <code>16S_mapping.csv</code>.</li>
        <li>Select experiment <code>m16s_course</code>, open <strong>Clinical</strong> in the sidebar.</li>
      </ol>

      <h4>${L("clinDemoThreeTitle")}</h4>
      <ol class="guide-steps">
        <li>Strategy → <strong>One-click three-line table</strong>.</li>
        <li>Data source → <strong>Auto (prefer uploaded clinical table)</strong>.</li>
        <li>Skip high-cardinality columns; engine gtsummary (or EMP fallback if slow).</li>
        <li><strong>Detect clinical variables</strong> until age/BMI appear (not No colData).</li>
        <li>Run <strong>One-click three-line table</strong> and download CSV if needed.</li>
      </ol>

      <h4>${L("clinDemoSysTitle")}</h4>
      <ol class="guide-steps">
        <li>Strategy → <strong>Systematic clinical stats</strong>; cohort All / UC / IBS.</li>
        <li>Run systematic summary (baseline + within + between).</li>
        <li>Inspect <strong>Within</strong> and <strong>Between</strong> tables.</li>
      </ol>

      <h4>${L("clinDemoCorTitle")}</h4>
      <ol class="guide-steps">
        <li>Strategy → <strong>Feature × Trait correlation</strong> on <code>m16s_course</code>.</li>
        <li>Detect variables; select age/BMI/weight/disease_duration.</li>
        <li>Run correlation, then optional scatter + regression for one pair.</li>
      </ol>

      <h4>${L("clinDemoOutTitle")}</h4>
      <ul class="guide-bullets">
        <li>Three-line table ~<strong>44</strong> rows; e.g. height P≈0.023, Drinking P≈0.004.</li>
        <li>Within: UC partial_Mayo 4→2; IBS IBS_SSS 200→140 (highly significant).</li>
        <li>Association: ID match <strong>132/132</strong>; ~2350 Spearman tests; exploratory top e.g. Phascolarctobacterium~weight (r≈0.31).</li>
      </ul>
      <div class="guide-demo-table-wrap">
        <table class="guide-demo-table">
          <thead><tr><th>Variable</th><th>Overall</th><th>IBS_before</th><th>IBS_after</th><th>UC_before</th><th>UC_after</th><th>P</th></tr></thead>
          <tbody>
            <tr><td>age</td><td>47.55 ± 13.01</td><td>47.61 ± 13.81</td><td>47.64 ± 13.77</td><td>47.45 ± 12.34</td><td>47.48 ± 12.31</td><td>1.00</td></tr>
            <tr><td>BMI</td><td>23.86 ± 3.71</td><td>23.91 ± 3.32</td><td>23.90 ± 3.32</td><td>23.80 ± 4.25</td><td>23.79 ± 4.24</td><td>0.995</td></tr>
            <tr class="guide-demo-sig"><td>height</td><td>164.35 ± 7.03</td><td>166.00 ± 6.21</td><td>166.00 ± 6.21</td><td>162.31 ± 7.61</td><td>162.31 ± 7.61</td><td>0.023</td></tr>
            <tr class="guide-demo-sig"><td>Drinking</td><td>0.22 ± 0.41</td><td>0.33 ± 0.48</td><td>0.33 ± 0.48</td><td>0.07 ± 0.26</td><td>0.07 ± 0.26</td><td>0.004</td></tr>
          </tbody>
        </table>
        <p class="hint">Sample three-line snippet from the test-data run.</p>
      </div>

      <h4>${L("clinDemoTroubleshoot")}</h4>
      <dl class="guide-faq">
        <dt>No colData</dt>
        <dd>Load Clinical demo first; set source to Auto; Detect variables.</dd>
        <dt>Fewer than 5 samples have numeric trait</dt>
        <dd>ID mismatch — use repo <code>Clinical-test.csv</code> + 16S course demo.</dd>
        <dt>Slow three-line table</dt>
        <dd>Switch engine to EMP fallback; keep high-cardinality skip on.</dd>
      </dl>`;

  return `
    <div class="card" id="guide-clinical-demo">
      <details class="guide-fold">
        <summary class="guide-fold-summary">${L("clinDemoTitle")}</summary>
        <div class="guide-fold-body">${body}</div>
      </details>
    </div>`;
}

function renderM16sDemoSection() {
  const zh = getLocale() === "zh";
  const body = zh
    ? `
      <p class="hint">Course Demo <code>m16s_course</code> 实跑：样本 <strong>132</strong> × 特征 <strong>470</strong>；Group 为 IBS/UC × before/after。推荐顺序见下（与 E2E 一致）。</p>

      <h4>① 加载数据</h4>
      <ol class="guide-steps">
        <li>组学选 <strong>16S Microbiome</strong>；左侧 <strong>数据</strong> → Course Demo → <strong>16S Microbiome</strong>。</li>
        <li>实验选 <code>m16s_course</code>；概览核对 132 样本、Group 四水平。</li>
      </ol>

      <h4>② 准备（务必按序）</h4>
      <ol class="guide-steps">
        <li>Filter：min prevalence <strong>0.1</strong>、min detect <strong>0.05</strong> → 约保留 <strong>132</strong> 特征、去掉 338。</li>
        <li><strong>16S Taxonomy prepare</strong>：Genus、Top <strong>40</strong>；<strong>不要</strong>同一步勾选 rclr。</li>
        <li>建议先跑 Alpha，再 Normalize <strong>rclr</strong>。经典 Collapse 若报错请改用 Taxonomy prepare。</li>
      </ol>

      <h4>③ 分析</h4>
      <ol class="guide-steps">
        <li>Alpha → Shannon（可同时见 simpson / chao1 等）。</li>
        <li>Dimension → PCA 与 PCoA（在 counts / 未 rclr 矩阵上更稳）。</li>
        <li>Differential → <strong>wilcox</strong>，示例 UC_before vs IBS_before（或纵向 before vs after）。</li>
        <li>Marker → <strong>randomForest</strong>；Correlation / Cluster / Network 可选。</li>
      </ol>

      <h4>④ 可视化 + Run All</h4>
      <ol class="guide-steps">
        <li>Structure / Bar / Alpha / Scatter(PCoA) / Heatmap / Volcano / Sankey；Network 相关阈值建议 <strong>≤0.3</strong>。</li>
        <li><strong>Run All</strong>（Group + Genus + Shannon + PCoA）→ 下载 zip（约 4–5 s）。</li>
      </ol>

      <h4>⑤ 预期输出（实跑）</h4>
      <div class="guide-demo-table-wrap">
        <table class="guide-demo-table">
          <thead><tr><th>项目</th><th>期望</th></tr></thead>
          <tbody>
            <tr><td>样本 / 原始特征</td><td>132 / 470</td></tr>
            <tr><td>Group 计数</td><td>IBS×2×36，UC×2×29（meta 130）</td></tr>
            <tr><td>Taxonomy Top40 后</td><td>40 features</td></tr>
            <tr><td>Shannon mean / median</td><td>≈ 1.49 / 1.56</td></tr>
            <tr class="guide-demo-sig"><td>DE（UC_before vs IBS_before）</td><td>40 行；FDR&lt;0.05≈0；p&lt;0.05≈1（<code>s__copri</code>）</td></tr>
            <tr><td>Run All</td><td>~4.4 s；alpha 多指数 + PCoA/PCA/NMDS + bar + heatmap + CSV</td></tr>
          </tbody>
        </table>
      </div>

      <h4>排错</h4>
      <dl class="guide-faq">
        <dt>Alpha 报 non-negative</dt>
        <dd>已做 rclr。请重新导入，或 Alpha 放在 rclr 之前 / 用 raw source。</dd>
        <dt>Taxonomy 与 rclr 一步失败</dt>
        <dd>拆开：先 Taxonomy，再单独 Normalize。</dd>
        <dt>Network 无边</dt>
        <dd>相关阈值改为 <strong>0.3</strong>（0.5+ 常为空）。</dd>
      </dl>`
    : `
      <p class="hint">Course demo <code>m16s_course</code>: <strong>132</strong> samples × <strong>470</strong> features; Group = IBS/UC × before/after.</p>

      <h4>① Load</h4>
      <ol class="guide-steps">
        <li>Omics → <strong>16S Microbiome</strong>; <strong>Data</strong> → Course Demo → 16S.</li>
        <li>Select experiment <code>m16s_course</code>; confirm 132 samples and four Group levels.</li>
      </ol>

      <h4>② Prepare (order matters)</h4>
      <ol class="guide-steps">
        <li>Filter prevalence <strong>0.1</strong> / detect <strong>0.05</strong> → ~132 features kept.</li>
        <li><strong>16S Taxonomy prepare</strong>: Genus, top <strong>40</strong>; do <strong>not</strong> enable rclr in the same step.</li>
        <li>Run Alpha on counts, then Normalize <strong>rclr</strong>. Prefer taxonomy prepare over classic Collapse.</li>
      </ol>

      <h4>③ Analyze</h4>
      <ol class="guide-steps">
        <li>Alpha (Shannon); PCA / PCoA; wilcox (e.g. UC_before vs IBS_before); RF marker.</li>
      </ol>

      <h4>④ Visualize + Run All</h4>
      <ol class="guide-steps">
        <li>Structure / bar / alpha / scatter / heatmap / volcano / sankey; network cutoff ≤ <strong>0.3</strong>.</li>
        <li>Run All (~4.4 s) and download the zip bundle.</li>
      </ol>

      <h4>⑤ Expected outputs</h4>
      <div class="guide-demo-table-wrap">
        <table class="guide-demo-table">
          <thead><tr><th>Item</th><th>Expected</th></tr></thead>
          <tbody>
            <tr><td>Samples / features</td><td>132 / 470</td></tr>
            <tr><td>After taxonomy top40</td><td>40 features</td></tr>
            <tr><td>Shannon mean / median</td><td>≈ 1.49 / 1.56</td></tr>
            <tr class="guide-demo-sig"><td>DE (UC_before vs IBS_before)</td><td>40 rows; FDR&lt;0.05≈0; p&lt;0.05≈1 (<code>s__copri</code>)</td></tr>
            <tr><td>Run All</td><td>~4.4 s with alpha + ordination + bar/heatmap</td></tr>
          </tbody>
        </table>
      </div>

      <h4>Troubleshooting</h4>
      <dl class="guide-faq">
        <dt>Alpha non-negative error</dt>
        <dd>Already rclr — re-import or run alpha before rclr.</dd>
        <dt>Empty network</dt>
        <dd>Lower correlation cutoff to <strong>0.3</strong>.</dd>
      </dl>`;

  return `
    <div class="card" id="guide-m16s-demo">
      <details class="guide-fold">
        <summary class="guide-fold-summary">${L("m16sDemoTitle")}</summary>
        <div class="guide-fold-body">${body}</div>
      </details>
    </div>`;
}

function renderRnaseqDemoSection() {
  const zh = getLocale() === "zh";
  const body = zh
    ? `
      <p class="hint">Course Demo <code>rnaseq_course</code> 实跑（29 PASS / 3 SKIP）：样本 <strong>24</strong> × 基因 <strong>19150</strong>；Group 实际 <strong>6</strong> 水平（DMSO / DMSO+LIPUS / T4400 / T4400+LIPUS / T3976 / T3976+LIPUS）。物种 <strong>mmu</strong>。</p>

      <h4>① 加载数据</h4>
      <ol class="guide-steps">
        <li>组学选 <strong>Transcriptomics</strong>；数据 → Course Demo → <strong>RNA-seq Transcriptomics</strong>。</li>
        <li>实验选 <code>rnaseq_course</code>；差分时务必显式指定 ref/test（示例 <strong>DMSO vs T4400</strong>）。</li>
      </ol>

      <h4>② 准备</h4>
      <ol class="guide-steps">
        <li>Filter：min count <strong>10</strong>、max NA <strong>0.2</strong> → 约保留 <strong>14245</strong> 基因。</li>
        <li>Normalize → <strong>log</strong>（DESeq2 仍优先用原始 counts）。</li>
      </ol>

      <h4>③ 分析</h4>
      <ol class="guide-steps">
        <li>Dimension → <strong>PCA</strong>，再 Scatter 按 Group 着色。</li>
        <li>Differential → <strong>DESeq2</strong>（DMSO vs T4400）；可选 wilcox。</li>
        <li>padj&lt;0.05 且 |LFC|≥1 常为 <strong>0</strong>；课堂富集请改用名义 <strong>p</strong>（约 <strong>23↑ / 2↓</strong>，共 25）。</li>
        <li>Enrichment organism=<code>mmu</code>：GO ≈ <strong>40</strong> 条；KEGG 可能 <strong>0</strong>；GSEA ≈ <strong>21</strong>。WGCNA / 全基因 correlation 建议跳过。</li>
      </ol>

      <h4>④ 可视化 + Run All</h4>
      <ol class="guide-steps">
        <li>Volcano、DEG heatmap（约 25 基因）、Top-variance heatmap、PCA scatter、Box/Bar。</li>
        <li><strong>RNAseq Run All</strong>（mmu + enrichment）→ 约 <strong>30–60 s</strong> 出 zip（~2 MB：plots + tables + summary.txt）。</li>
      </ol>

      <h4>⑤ 预期输出（实跑核对）</h4>
      <div class="guide-demo-table-wrap">
        <table class="guide-demo-table">
          <thead><tr><th>项目</th><th>期望</th></tr></thead>
          <tbody>
            <tr><td>样本 / 原始基因</td><td>24 / 19150 → filter 后 ≈ 14245</td></tr>
            <tr><td>DESeq2 对比</td><td>T4400 vs DMSO；检验 ≈ 14239</td></tr>
            <tr class="guide-demo-sig"><td>padj DEG / 名义 p DEG</td><td>0↑0↓ / <strong>23↑2↓</strong></td></tr>
            <tr><td>高 |LFC| 示例</td><td>Cntn6、Lilr4b、Galnt13、Clec4e、Ccl3…</td></tr>
            <tr><td>GO / KEGG / GSEA</td><td>40 / 0 / 21</td></tr>
            <tr><td>Run All</td><td>≈ 35 s；zip ≈ 2.1 MB</td></tr>
          </tbody>
        </table>
      </div>

      <h4>排错</h4>
      <dl class="guide-faq">
        <dt>无 padj 显著 DEG / 火山图空</dt>
        <dd>本 demo n 小、效应弱属正常。课堂改用名义 p，或换对比组；注明探索性。</dd>
        <dt>Correlation / Cluster / WGCNA 超时</dt>
        <dd>跳过；样本相关在 Run All 包内。</dd>
        <dt>API 断连</dt>
        <dd>重负载后偶发。重启本地 API 后再 Visualize / Run All。</dd>
      </dl>`
    : `
      <p class="hint">Course demo <code>rnaseq_course</code> (29 PASS / 3 SKIP): <strong>24</strong> × <strong>19150</strong>; <strong>6</strong> Group levels (DMSO / T4400 / T3976 ± LIPUS). Organism <strong>mmu</strong>.</p>

      <h4>① Load</h4>
      <ol class="guide-steps">
        <li>Omics → Transcriptomics; Data → Course Demo → RNA-seq → <code>rnaseq_course</code>.</li>
        <li>Set DESeq2 ref/test explicitly (e.g. <strong>DMSO vs T4400</strong>).</li>
      </ol>

      <h4>② Prepare</h4>
      <ol class="guide-steps">
        <li>Filter min count <strong>10</strong> → ~<strong>14245</strong> genes.</li>
        <li>Normalize <strong>log</strong>.</li>
      </ol>

      <h4>③ Analyze</h4>
      <ol class="guide-steps">
        <li>PCA + scatter; DESeq2. padj DEGs often <strong>0</strong>; use nominal p (~<strong>23↑ / 2↓</strong>) for enrichment demos.</li>
        <li>GO ~40; KEGG often 0; GSEA ~21. Skip WGCNA / full-matrix correlation.</li>
      </ol>

      <h4>④ Visualize + Run All</h4>
      <ol class="guide-steps">
        <li>Volcano / DEG heatmap / top-var heatmap / PCA scatter.</li>
        <li><strong>RNAseq Run All</strong> with enrichment → zip in ~<strong>30–60 s</strong> (~2.1 MB).</li>
      </ol>

      <h4>⑤ Expected outputs</h4>
      <div class="guide-demo-table-wrap">
        <table class="guide-demo-table">
          <thead><tr><th>Item</th><th>Expected</th></tr></thead>
          <tbody>
            <tr><td>Samples / genes</td><td>24 / 19150 → ~14245 after filter</td></tr>
            <tr class="guide-demo-sig"><td>padj / nominal-p DEGs</td><td>0 / <strong>23↑ 2↓</strong></td></tr>
            <tr><td>GO / KEGG / GSEA</td><td>40 / 0 / 21</td></tr>
            <tr><td>Run All</td><td>≈ 35 s; zip ≈ 2.1 MB</td></tr>
          </tbody>
        </table>
      </div>

      <h4>Troubleshooting</h4>
      <dl class="guide-faq">
        <dt>No padj DEGs</dt>
        <dd>Expected on this demo — use nominal p for classroom enrichment.</dd>
        <dt>API crash under load</dt>
        <dd>Restart local API, then Visualize / Run All.</dd>
      </dl>`;

  return `
    <div class="card" id="guide-rnaseq-demo">
      <details class="guide-fold">
        <summary class="guide-fold-summary">${L("rnaDemoTitle")}</summary>
        <div class="guide-fold-body">${body}</div>
      </details>
    </div>`;
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
      <dt>8080 打不开？</dt><dd>Mac: 双击 Stop-EMP-Web-Mac.command 后重启；Windows: Stop-EMP-Web-Windows.bat 或 Restart-EMP-Web.bat</dd>
      <dt>Mac 和 Windows 命令一样吗？</dt><dd><strong>不一样。</strong> 各用各平台脚本。</dd>
      <dt>AI 语言？</dt><dd>左侧语言栏选 中文 / EN / 自动；AI 解读会跟随界面语言。</dd>
    </dl></div>`;
  }
  return `<div class="card"><h3>${L("faqTitle")}</h3><dl class="guide-faq">
    <dt>Port 8080 not loading?</dt><dd>Mac: double-click Stop-EMP-Web-Mac.command then restart; Windows: Stop-EMP-Web-Windows.bat or Restart-EMP-Web.bat</dd>
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
