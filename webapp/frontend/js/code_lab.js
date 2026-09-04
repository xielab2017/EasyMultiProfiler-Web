/**
 * Code lab: reference snippets + optional **real** R execution via POST /api/user_r/run.
 * Drafts + edit history remain in localStorage.
 */
import { CODE_LAB_TEMPLATES } from "./code_lab_templates.js?v=2026-07-16-multi-demo";
import { codeLabArtifactURL, execUserR, getOpenRouterVerified, optimizeRCode, probeOpenRouterModels } from "./api.js?v=2026-07-22-script-fusion-v1";
import { t } from "./locale.js?v=i18n-zh-default-v1";

const LS_KEY = "emp_code_lab_store_v1";
const LLM_CFG_KEY = "emp_code_lab_llm_config_v2";
const CAMPUS_LLM_PRESET = {
  provider: "campus",
  base_url: "http://10.22.18.12:9901/v1",
  api_key: "",
  model: "mixed",
  task_type: "code_optimize",
  campus_models: {
    fast: "deepseek-v4-flash",
    accurate: "Qwen3.6-35B-A3B",
    vision: "Qwen3-VL-8B-Instruct",
    embedding: "Qwen-embedding",
  },
};

const OPENROUTER_PROBE_CANDIDATES = [
  "deepseek/deepseek-v4-pro",
  "deepseek/deepseek-v4-flash",
  "moonshotai/kimi-k2.7-code",
  "qwen/qwen3.7-max",
  "z-ai/glm-5.2",
  "z-ai/glm-5",
  "openai/gpt-5.6-sol",
  "openai/gpt-5.6-terra",
  "openai/gpt-5.6-luna",
  "openai/gpt-5.5",
  "openai/gpt-5.5-pro",
  "anthropic/claude-fable-5",
  "anthropic/claude-sonnet-5",
  "anthropic/claude-opus-4.8",
  "google/gemini-3.1-pro-preview",
  "google/gemini-3.5-flash",
  "openai/gpt-4o-mini",
  "deepseek/deepseek-chat",
  "meta-llama/llama-3.3-70b-instruct",
];
const OPENROUTER_MODEL_LABELS = {
  "deepseek/deepseek-v4-pro": "DeepSeek V4 Pro",
  "deepseek/deepseek-v4-flash": "DeepSeek V4 Flash（快）",
  "moonshotai/kimi-k2.7-code": "Kimi K2.7 Code",
  "qwen/qwen3.7-max": "Qwen3.7 Max",
  "z-ai/glm-5.2": "GLM 5.2",
  "z-ai/glm-5": "GLM 5",
  "openai/gpt-5.6-sol": "GPT-5.6 Sol",
  "openai/gpt-5.6-terra": "GPT-5.6 Terra",
  "openai/gpt-5.6-luna": "GPT-5.6 Luna（快）",
  "openai/gpt-5.5": "GPT-5.5",
  "openai/gpt-5.5-pro": "GPT-5.5 Pro",
  "anthropic/claude-fable-5": "Claude Fable 5",
  "anthropic/claude-sonnet-5": "Claude Sonnet 5",
  "anthropic/claude-opus-4.8": "Claude Opus 4.8",
  "google/gemini-3.1-pro-preview": "Gemini 3.1 Pro",
  "google/gemini-3.5-flash": "Gemini 3.5 Flash（快）",
  "openai/gpt-4o-mini": "GPT-4o mini",
  "deepseek/deepseek-chat": "DeepSeek Chat",
  "meta-llama/llama-3.3-70b-instruct": "Llama 3.3 70B",
};
let openRouterVerified = null;

function openRouterModelLabel(id) {
  return OPENROUTER_MODEL_LABELS[id] || id;
}

function applyOpenRouterVerifiedManifest(manifest = {}) {
  const working = Array.isArray(manifest.working) ? manifest.working : [];
  const workingIds = working.map((row) => row.model || row.id).filter(Boolean);
  if (!workingIds.length) return false;

  const verifiedModels = workingIds.map((id) => ({
    id,
    label: openRouterModelLabel(id),
  }));
  LLM_PROVIDER_CATALOG.openrouter.models = [
    { id: "fusion", label: "Auto 融合 5 模型（推荐）" },
    ...verifiedModels,
    { id: "__custom__", label: "自定义 OpenRouter 模型…" },
  ];

  const fusionDefaults = Array.isArray(manifest.fusion_defaults) && manifest.fusion_defaults.length
    ? manifest.fusion_defaults.slice(0, 5)
    : workingIds.slice(0, 5);
  OPENROUTER_DEFAULT_FUSION_MODELS.length = 0;
  OPENROUTER_DEFAULT_FUSION_MODELS.push(...fusionDefaults);
  OPENROUTER_LLM_PRESET.openrouter_models = [...fusionDefaults];
  if (manifest.fusion_model) {
    OPENROUTER_LLM_PRESET.fusion_model = manifest.fusion_model;
  }
  return true;
}

async function refreshOpenRouterVerifiedModels({ repopulate = true } = {}) {
  try {
    const res = await getOpenRouterVerified();
    if (!res?.success) return false;
    openRouterVerified = res;
    const applied = applyOpenRouterVerifiedManifest(res);
    if (applied && repopulate && llmConfigEls.provider?.value === "openrouter") {
      applyProviderToForm("openrouter");
    }
    return applied;
  } catch {
    return false;
  }
}
const OPENROUTER_DEFAULT_FUSION_MODELS = [
  "deepseek/deepseek-v4-pro",
  "deepseek/deepseek-v4-flash",
  "moonshotai/kimi-k2.7-code",
  "qwen/qwen3.7-max",
  "z-ai/glm-5.2",
];
const OPENROUTER_FUSION_LEARN_KEY = "emp_openrouter_fusion_learn_v1";
const OPENROUTER_LLM_PRESET = {
  provider: "openrouter",
  base_url: "https://openrouter.ai/api/v1",
  api_key: "",
  model: "fusion",
  fusion_model: "deepseek/deepseek-v4-pro",
  openrouter_models: OPENROUTER_DEFAULT_FUSION_MODELS,
};

function loadFusionLearnScores() {
  try {
    const raw = localStorage.getItem(OPENROUTER_FUSION_LEARN_KEY);
    const parsed = raw ? JSON.parse(raw) : {};
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function saveFusionLearnScores(scores) {
  try {
    localStorage.setItem(OPENROUTER_FUSION_LEARN_KEY, JSON.stringify(scores || {}));
  } catch {
    /* quota */
  }
}

function recordFusionLearn(models, delta = 1) {
  const list = Array.isArray(models) ? models.filter(Boolean) : [models].filter(Boolean);
  if (!list.length || !Number.isFinite(delta) || delta === 0) return;
  const scores = loadFusionLearnScores();
  for (const model of list) {
    scores[model] = (Number(scores[model]) || 0) + delta;
  }
  saveFusionLearnScores(scores);
}

function rankFusionModels(models, scores = loadFusionLearnScores()) {
  const uniq = [...new Set((models || []).filter(Boolean))];
  return uniq
    .map((id) => ({ id, score: Number(scores[id]) || 0 }))
    .sort((a, b) => b.score - a.score || uniq.indexOf(a.id) - uniq.indexOf(b.id))
    .map((x) => x.id);
}

function resolveOpenRouterFusionModels(extra = []) {
  const pool = rankFusionModels([
    ...OPENROUTER_DEFAULT_FUSION_MODELS,
    ...extra,
    ...Object.keys(loadFusionLearnScores()),
  ]);
  const picked = [];
  for (const model of pool) {
    if (!picked.includes(model)) picked.push(model);
    if (picked.length >= 5) break;
  }
  for (const model of OPENROUTER_DEFAULT_FUSION_MODELS) {
    if (!picked.includes(model)) picked.push(model);
    if (picked.length >= 5) break;
  }
  return picked.slice(0, 5);
}

let lastLlmOptimizeMeta = null;

/** NVIDIA NIM chat / instruct LLMs (from integrate.api.nvidia.com/v1/models). */
const NVIDIA_NIM_CHAT_MODELS = [
  { id: "nvidia/nemotron-3-ultra-550b-a55b", label: "nemotron-3-ultra-550b-a55b（旗舰）" },
  { id: "nvidia/nemotron-3-super-120b-a12b", label: "nemotron-3-super-120b-a12b" },
  { id: "nvidia/llama-3.1-nemotron-ultra-253b-v1", label: "llama-3.1-nemotron-ultra-253b-v1" },
  { id: "deepseek-ai/deepseek-v4-pro", label: "deepseek-v4-pro" },
  { id: "deepseek-ai/deepseek-v4-flash", label: "deepseek-v4-flash（快）" },
  { id: "z-ai/glm-5.2", label: "glm-5.2" },
  { id: "qwen/qwen3.5-397b-a17b", label: "qwen3.5-397b-a17b" },
  { id: "meta/llama-3.3-70b-instruct", label: "llama-3.3-70b-instruct" },
  { id: "01-ai/yi-large", label: "yi-large" },
  { id: "abacusai/dracarys-llama-3.1-70b-instruct", label: "dracarys-llama-3.1-70b-instruct" },
  { id: "adept/fuyu-8b", label: "fuyu-8b" },
  { id: "ai21labs/jamba-1.5-large-instruct", label: "jamba-1.5-large-instruct" },
  { id: "aisingapore/sea-lion-7b-instruct", label: "sea-lion-7b-instruct" },
  { id: "bigcode/starcoder2-15b", label: "starcoder2-15b" },
  { id: "bytedance/seed-oss-36b-instruct", label: "seed-oss-36b-instruct" },
  { id: "databricks/dbrx-instruct", label: "dbrx-instruct" },
  { id: "deepseek-ai/deepseek-coder-6.7b-instruct", label: "deepseek-coder-6.7b-instruct" },
  { id: "google/codegemma-1.1-7b", label: "codegemma-1.1-7b" },
  { id: "google/codegemma-7b", label: "codegemma-7b" },
  { id: "google/diffusiongemma-26b-a4b-it", label: "diffusiongemma-26b-a4b-it" },
  { id: "google/gemma-2-2b-it", label: "gemma-2-2b-it" },
  { id: "google/gemma-2b", label: "gemma-2b" },
  { id: "google/gemma-3-12b-it", label: "gemma-3-12b-it" },
  { id: "google/gemma-3-4b-it", label: "gemma-3-4b-it" },
  { id: "google/gemma-3n-e2b-it", label: "gemma-3n-e2b-it" },
  { id: "google/gemma-3n-e4b-it", label: "gemma-3n-e4b-it" },
  { id: "google/gemma-4-31b-it", label: "gemma-4-31b-it" },
  { id: "google/recurrentgemma-2b", label: "recurrentgemma-2b" },
  { id: "ibm/granite-3.0-3b-a800m-instruct", label: "granite-3.0-3b-a800m-instruct" },
  { id: "ibm/granite-3.0-8b-instruct", label: "granite-3.0-8b-instruct" },
  { id: "ibm/granite-34b-code-instruct", label: "granite-34b-code-instruct" },
  { id: "ibm/granite-8b-code-instruct", label: "granite-8b-code-instruct" },
  { id: "meta/codellama-70b", label: "codellama-70b" },
  { id: "meta/llama-3.1-70b-instruct", label: "llama-3.1-70b-instruct" },
  { id: "meta/llama-3.1-8b-instruct", label: "llama-3.1-8b-instruct" },
  { id: "meta/llama-3.2-11b-vision-instruct", label: "llama-3.2-11b-vision-instruct" },
  { id: "meta/llama-3.2-1b-instruct", label: "llama-3.2-1b-instruct" },
  { id: "meta/llama-3.2-3b-instruct", label: "llama-3.2-3b-instruct" },
  { id: "meta/llama-3.2-90b-vision-instruct", label: "llama-3.2-90b-vision-instruct" },
  { id: "meta/llama-4-maverick-17b-128e-instruct", label: "llama-4-maverick-17b-128e-instruct" },
  { id: "meta/llama-guard-4-12b", label: "llama-guard-4-12b" },
  { id: "meta/llama2-70b", label: "llama2-70b" },
  { id: "microsoft/kosmos-2", label: "kosmos-2" },
  { id: "microsoft/phi-3-vision-128k-instruct", label: "phi-3-vision-128k-instruct" },
  { id: "microsoft/phi-3.5-moe-instruct", label: "phi-3.5-moe-instruct" },
  { id: "microsoft/phi-4-mini-instruct", label: "phi-4-mini-instruct" },
  { id: "microsoft/phi-4-multimodal-instruct", label: "phi-4-multimodal-instruct" },
  { id: "minimaxai/minimax-m2.7", label: "minimax-m2.7" },
  { id: "minimaxai/minimax-m3", label: "minimax-m3" },
  { id: "mistralai/codestral-22b-instruct-v0.1", label: "codestral-22b-instruct-v0.1" },
  { id: "mistralai/ministral-14b-instruct-2512", label: "ministral-14b-instruct-2512" },
  { id: "mistralai/mistral-7b-instruct-v0.3", label: "mistral-7b-instruct-v0.3" },
  { id: "mistralai/mistral-large", label: "mistral-large" },
  { id: "mistralai/mistral-large-2-instruct", label: "mistral-large-2-instruct" },
  { id: "mistralai/mistral-large-3-675b-instruct-2512", label: "mistral-large-3-675b-instruct-2512" },
  { id: "mistralai/mistral-medium-3.5-128b", label: "mistral-medium-3.5-128b" },
  { id: "mistralai/mistral-nemotron", label: "mistral-nemotron" },
  { id: "mistralai/mistral-small-4-119b-2603", label: "mistral-small-4-119b-2603" },
  { id: "mistralai/mixtral-8x22b-v0.1", label: "mixtral-8x22b-v0.1" },
  { id: "mistralai/mixtral-8x7b-instruct-v0.1", label: "mixtral-8x7b-instruct-v0.1" },
  { id: "moonshotai/kimi-k2.6", label: "kimi-k2.6" },
  { id: "nv-mistralai/mistral-nemo-12b-instruct", label: "mistral-nemo-12b-instruct" },
  { id: "nvidia/cosmos-reason2-8b", label: "cosmos-reason2-8b" },
  { id: "nvidia/ising-calibration-1-35b-a3b", label: "ising-calibration-1-35b-a3b" },
  { id: "nvidia/llama-3.1-nemotron-51b-instruct", label: "llama-3.1-nemotron-51b-instruct" },
  { id: "nvidia/llama-3.1-nemotron-70b-instruct", label: "llama-3.1-nemotron-70b-instruct" },
  { id: "nvidia/llama-3.1-nemotron-nano-8b-v1", label: "llama-3.1-nemotron-nano-8b-v1" },
  { id: "nvidia/llama-3.1-nemotron-nano-vl-8b-v1", label: "llama-3.1-nemotron-nano-vl-8b-v1" },
  { id: "nvidia/llama-3.3-nemotron-super-49b-v1", label: "llama-3.3-nemotron-super-49b-v1" },
  { id: "nvidia/llama-3.3-nemotron-super-49b-v1.5", label: "llama-3.3-nemotron-super-49b-v1.5" },
  { id: "nvidia/llama3-chatqa-1.5-70b", label: "llama3-chatqa-1.5-70b" },
  { id: "nvidia/mistral-nemo-minitron-8b-8k-instruct", label: "mistral-nemo-minitron-8b-8k-instruct" },
  { id: "nvidia/nemoretriever-parse", label: "nemoretriever-parse" },
  { id: "nvidia/nemotron-3-nano-30b-a3b", label: "nemotron-3-nano-30b-a3b" },
  { id: "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning", label: "nemotron-3-nano-omni-30b-a3b-reasoning" },
  { id: "nvidia/nemotron-4-340b-instruct", label: "nemotron-4-340b-instruct" },
  { id: "nvidia/nemotron-mini-4b-instruct", label: "nemotron-mini-4b-instruct" },
  { id: "nvidia/nemotron-nano-12b-v2-vl", label: "nemotron-nano-12b-v2-vl" },
  { id: "nvidia/nemotron-nano-3-30b-a3b", label: "nemotron-nano-3-30b-a3b" },
  { id: "nvidia/nemotron-parse", label: "nemotron-parse" },
  { id: "nvidia/neva-22b", label: "neva-22b" },
  { id: "nvidia/nvidia-nemotron-nano-9b-v2", label: "nvidia-nemotron-nano-9b-v2" },
  { id: "nvidia/vila", label: "vila" },
  { id: "openai/gpt-oss-120b", label: "gpt-oss-120b" },
  { id: "openai/gpt-oss-20b", label: "gpt-oss-20b" },
  { id: "qwen/qwen3-next-80b-a3b-instruct", label: "qwen3-next-80b-a3b-instruct" },
  { id: "qwen/qwen3.5-122b-a10b", label: "qwen3.5-122b-a10b" },
  { id: "sarvamai/sarvam-m", label: "sarvam-m" },
  { id: "stepfun-ai/step-3.5-flash", label: "step-3.5-flash" },
  { id: "stepfun-ai/step-3.7-flash", label: "step-3.7-flash" },
  { id: "stockmark/stockmark-2-100b-instruct", label: "stockmark-2-100b-instruct" },
  { id: "upstage/solar-10.7b-instruct", label: "solar-10.7b-instruct" },
  { id: "writer/palmyra-creative-122b", label: "palmyra-creative-122b" },
  { id: "writer/palmyra-fin-70b-32k", label: "palmyra-fin-70b-32k" },
  { id: "writer/palmyra-med-70b", label: "palmyra-med-70b" },
  { id: "writer/palmyra-med-70b-32k", label: "palmyra-med-70b-32k" },
  { id: "zyphra/zamba2-7b-instruct", label: "zamba2-7b-instruct" },
];

const LLM_PROVIDER_CATALOG = {
  auto: {
    models: [{ id: "", label: "自动依次尝试（见高级 Auto Providers）" }],
    defaultModel: "",
    baseUrl: "",
    baseUrlEditable: false,
    keyRequired: false,
  },
  campus: {
    models: [
      { id: "mixed", label: "混合（DeepSeek-v4-flash → Qwen3.6-35B-A3B）" },
      { id: "deepseek-v4-flash", label: "deepseek-v4-flash" },
      { id: "Qwen3.6-35B-A3B", label: "Qwen3.6-35B-A3B" },
      { id: "Qwen3-VL-8B-Instruct", label: "Qwen3-VL-8B-Instruct" },
    ],
    defaultModel: "mixed",
    baseUrl: CAMPUS_LLM_PRESET.base_url,
    baseUrlEditable: false,
    keyRequired: false,
  },
  chatgpt: {
    models: [
      { id: "gpt-5.6-sol", label: "gpt-5.6-sol（旗舰）" },
      { id: "gpt-5.6-terra", label: "gpt-5.6-terra" },
      { id: "gpt-5.6-luna", label: "gpt-5.6-luna（快）" },
      { id: "gpt-5.5", label: "gpt-5.5" },
      { id: "gpt-5.5-pro", label: "gpt-5.5-pro" },
      { id: "gpt-4o-mini", label: "gpt-4o-mini" },
      { id: "gpt-4o", label: "gpt-4o" },
      { id: "gpt-4.1-mini", label: "gpt-4.1-mini" },
      { id: "gpt-4.1", label: "gpt-4.1" },
      { id: "o3-mini", label: "o3-mini" },
      { id: "__custom__", label: "自定义模型…" },
    ],
    defaultModel: "gpt-5.6-sol",
    baseUrl: "https://api.openai.com/v1",
    baseUrlEditable: false,
    keyRequired: true,
  },
  deepseek: {
    models: [
      { id: "deepseek-v4-pro", label: "deepseek-v4-pro（推荐）" },
      { id: "deepseek-v4-flash", label: "deepseek-v4-flash（快）" },
      { id: "deepseek-chat", label: "deepseek-chat" },
      { id: "deepseek-reasoner", label: "deepseek-reasoner" },
      { id: "__custom__", label: "自定义模型…" },
    ],
    defaultModel: "deepseek-v4-pro",
    baseUrl: "https://api.deepseek.com",
    baseUrlEditable: false,
    keyRequired: true,
  },
  qwen: {
    models: [
      { id: "qwen3.7-max", label: "qwen3.7-max（推荐）" },
      { id: "qwen-max", label: "qwen-max" },
      { id: "qwen-plus", label: "qwen-plus" },
      { id: "qwen-turbo", label: "qwen-turbo" },
      { id: "qwen2.5-72b-instruct", label: "qwen2.5-72b-instruct" },
      { id: "__custom__", label: "自定义模型…" },
    ],
    defaultModel: "qwen3.7-max",
    baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    baseUrlEditable: false,
    keyRequired: true,
  },
  minimax: {
    models: [
      { id: "MiniMax-M2.5", label: "MiniMax-M2.5（推荐）" },
      { id: "MiniMax-M3", label: "MiniMax-M3" },
      { id: "MiniMax-Text-01", label: "MiniMax-Text-01" },
      { id: "__custom__", label: "自定义模型…" },
    ],
    defaultModel: "MiniMax-M2.5",
    baseUrl: "https://api.minimax.chat/v1",
    baseUrlEditable: false,
    keyRequired: true,
  },
  gemini: {
    models: [
      { id: "gemini-3.5-flash", label: "gemini-3.5-flash（推荐）" },
      { id: "gemini-3.1-pro-preview", label: "gemini-3.1-pro-preview" },
      { id: "gemini-2.0-flash", label: "gemini-2.0-flash" },
      { id: "gemini-1.5-pro", label: "gemini-1.5-pro" },
      { id: "gemini-1.5-flash", label: "gemini-1.5-flash" },
      { id: "__custom__", label: "自定义模型…" },
    ],
    defaultModel: "gemini-3.5-flash",
    baseUrl: "https://generativelanguage.googleapis.com/v1beta",
    baseUrlEditable: false,
    keyRequired: true,
  },
  claude: {
    models: [
      { id: "claude-sonnet-5", label: "claude-sonnet-5（推荐）" },
      { id: "claude-fable-5", label: "claude-fable-5" },
      { id: "claude-opus-4.8", label: "claude-opus-4.8" },
      { id: "claude-3-7-sonnet-latest", label: "claude-3-7-sonnet-latest" },
      { id: "claude-3-5-sonnet-latest", label: "claude-3-5-sonnet-latest" },
      { id: "claude-3-5-haiku-latest", label: "claude-3-5-haiku-latest" },
      { id: "__custom__", label: "自定义模型…" },
    ],
    defaultModel: "claude-sonnet-5",
    baseUrl: "https://api.anthropic.com/v1",
    baseUrlEditable: false,
    keyRequired: true,
  },
  nvidia: {
    models: [
      ...NVIDIA_NIM_CHAT_MODELS,
      { id: "__custom__", label: "自定义模型…" },
    ],
    defaultModel: "nvidia/nemotron-3-ultra-550b-a55b",
    baseUrl: "https://integrate.api.nvidia.com/v1",
    baseUrlEditable: false,
    keyRequired: true,
  },
  openrouter: {
    models: [
      { id: "fusion", label: "Auto 融合 5 模型（推荐）" },
      { id: "deepseek/deepseek-v4-pro", label: "DeepSeek V4 Pro" },
      { id: "deepseek/deepseek-v4-flash", label: "DeepSeek V4 Flash（快）" },
      { id: "moonshotai/kimi-k2.7-code", label: "Kimi K2.7 Code" },
      { id: "qwen/qwen3.7-max", label: "Qwen3.7 Max" },
      { id: "z-ai/glm-5.2", label: "GLM 5.2" },
      { id: "z-ai/glm-5", label: "GLM 5" },
      { id: "openai/gpt-5.6-sol", label: "GPT-5.6 Sol" },
      { id: "openai/gpt-5.6-terra", label: "GPT-5.6 Terra" },
      { id: "openai/gpt-5.6-luna", label: "GPT-5.6 Luna（快）" },
      { id: "openai/gpt-5.5", label: "GPT-5.5" },
      { id: "openai/gpt-5.5-pro", label: "GPT-5.5 Pro" },
      { id: "anthropic/claude-fable-5", label: "Claude Fable 5" },
      { id: "anthropic/claude-sonnet-5", label: "Claude Sonnet 5" },
      { id: "anthropic/claude-opus-4.8", label: "Claude Opus 4.8" },
      { id: "google/gemini-3.1-pro-preview", label: "Gemini 3.1 Pro" },
      { id: "google/gemini-3.5-flash", label: "Gemini 3.5 Flash（快）" },
      { id: "openai/gpt-4o-mini", label: "GPT-4o mini" },
      { id: "deepseek/deepseek-chat", label: "DeepSeek Chat" },
      { id: "meta-llama/llama-3.3-70b-instruct", label: "Llama 3.3 70B" },
      { id: "__custom__", label: "自定义 OpenRouter 模型…" },
    ],
    defaultModel: "fusion",
    baseUrl: OPENROUTER_LLM_PRESET.base_url,
    baseUrlEditable: false,
    keyRequired: true,
  },
  custom: {
    models: [{ id: "__custom__", label: "自定义 OpenAI-compatible 模型" }],
    defaultModel: "",
    baseUrl: "",
    baseUrlEditable: true,
    keyRequired: true,
  },
  remote: {
    models: [{ id: "", label: "由远程服务决定" }],
    defaultModel: "",
    baseUrl: "",
    baseUrlEditable: false,
    keyRequired: false,
  },
};
const DEFAULT_LLM_PRESET = {
  provider: "auto",
  providers: ["campus", "deepseek", "chatgpt"],
  base_url: "",
  api_key: "",
  model: "",
  task_type: "code_optimize",
  campus_models: CAMPUS_LLM_PRESET.campus_models,
};
const PAGES = new Set(["preparation", "analysis", "clinical", "runall", "visualization"]);

const DEFAULT_TAB = {
  preparation: "prep-filter",
  analysis: "ana-alpha",
  clinical: "overview",
  runall: "runall-rnaseq",
  visualization: "viz-barplot",
};

const CLINICAL_SNIPPET_LABELS = {
  overview: "Overview / vars / reorient",
  cor: "Feature × trait correlation",
  fitline: "Scatter + fit line",
  wgcna: "WGCNA (async)",
  three_line: "One-click baseline table",
  systematic: "Systematic clinical stats",
  joint: "Multi-omics joint",
  marker_model: "Multi-omics marker model",
  reorient: "Reorient rows/columns",
};

const CLINICAL_NO_EXPERIMENT_TABS = new Set(["overview", "three_line", "systematic", "reorient", "marker_model"]);

/** Prefetched *.r.txt (run webapp/scripts/build_code_snippets.py after plumber/viz edits). */
const SNIPPET_URLS = (() => {
  const m = {};
  for (const [workflow, tabs] of Object.entries(CODE_LAB_TEMPLATES)) {
    for (const tab of Object.keys(tabs)) {
      m[`${workflow}::${tab}`] = `snippets/${workflow}__${tab}.r.txt`;
    }
  }
  return m;
})();

/** After full viz.R function bodies, optional one-liner to materialize a plot (last expr). */
const EXEC_ONE_LINER = {
  "visualization::viz-barplot": '\n\nmake_barplot(session_id, experiment, NULL, NULL, "top20", 20L)\n',
  "visualization::viz-boxplot": "\n\nmake_boxplot(session_id, experiment, NULL, NULL, 9, 6, NULL, NULL)\n",
  "visualization::viz-heatmap":
    "\n\nmake_heatmap(session_id, experiment, NULL, 50L, 11, 8, NULL, TRUE, TRUE, NULL, 11, NULL, NULL)\n",
  "visualization::viz-volcano": "\n\nmake_volcano(session_id, experiment)\n",
  "visualization::viz-scatter":
    "\n\nmake_scatter(session_id, experiment, NULL, 1L, 2L, 8, 6, NULL, \"auto\", NULL)\n",
  "visualization::viz-structure": "\n\nmake_structure(session_id, experiment, NULL, 10L, 11, 6, NULL, NULL)\n",
  "visualization::viz-alpha":
    "\n\nmake_alpha_plot(session_id, experiment, NULL, \"shannon\", \"current\", 8, 6, NULL, NULL)\n",
};

async function prefetchSnippets() {
  const out = {};
  for (const [key, rel] of Object.entries(SNIPPET_URLS)) {
    try {
      const r = await fetch(new URL(rel, import.meta.url), { cache: "no-cache" });
      if (r.ok) out[key] = await r.text();
    } catch {
      /* offline */
    }
  }
  globalThis.__empPrefetchedSnippets = out;
}

function buildFreshTemplate(workflow, tab) {
  const k = draftKey(workflow, tab);
  const full = globalThis.__empPrefetchedSnippets?.[k];
  const base = templateFor(workflow, tab);
  if (!full) return workflow === "clinical" ? injectClinicalUiDefaults(base, tab) : base;
  const tail = EXEC_ONE_LINER[k] || "";
  const body = workflow === "clinical" ? injectClinicalUiDefaults(full, tab) : full;
  return `# --- 服务器全文 / 同源片段（可改后「在 R 中执行」）---\n${body}${tail}\n\n# --- 路由说明 ---\n${base}`;
}

function rString(v) {
  if (v === null || v === undefined || v === "") return "NULL";
  return JSON.stringify(String(v));
}

function rBool(v) {
  return v ? "TRUE" : "FALSE";
}

function rVector(vals, fallback = "character()") {
  const xs = (vals || []).filter((v) => v !== null && v !== undefined && String(v).trim() !== "");
  if (!xs.length) return fallback;
  return `c(${xs.map((v) => rString(v)).join(", ")})`;
}

function selectedValues(id) {
  const el = document.getElementById(id);
  return Array.from(el?.selectedOptions || []).map((o) => o.value);
}

function clinicalSourceValue() {
  const v = document.getElementById("clin-data-source")?.value || "auto";
  return v === "auto" ? (window._emp?.clinicalResolvedSource || "standalone") : v;
}

function injectClinicalUiDefaults(code, tab) {
  const source = clinicalSourceValue();
  const group = document.getElementById("clin-three-group")?.value || null;
  const maxLevels = Number(document.getElementById("clin-three-max-levels")?.value || 20);
  const engine = document.getElementById("clin-three-engine")?.value || "gtsummary";
  const skipHigh = document.getElementById("clin-three-skip-high-card")?.checked !== false;
  let replacement = null;

  if (tab === "three_line" || tab === "systematic") {
    const cohortFilter = tab === "systematic"
      ? (document.getElementById("clin-systematic-cohort")?.value || null)
      : null;
    const cohortLine = tab === "systematic"
      ? `, cohort_filter = ${rString(cohortFilter)}`
      : "";
    replacement = `b <- list(
  session_id = session_id,
  experiment = if (exists("experiment", inherits = FALSE) && !is.null(experiment)) as.character(experiment)[1] else NULL,
  source = ${rString(source)}, group_var = ${rString(group)}, skip_high_cardinality = ${rBool(skipHigh)},
  max_levels = ${Number.isFinite(maxLevels) ? Math.trunc(maxLevels) : 20}L, table_engine = ${rString(engine)}${cohortLine}
)`;
  } else if (tab === "cor") {
    replacement = `b <- list(
  session_id = session_id, experiment = as.character(experiment)[1],
  traits = ${rVector(selectedValues("clin-cor-traits"), 'c("REPLACE_WITH_NUMERIC_CLINICAL_COL")')},
  method = ${rString(document.getElementById("clin-cor-method")?.value || "spearman")},
  top_n_features = ${Math.trunc(Number(document.getElementById("clin-cor-topn")?.value || 30))}L,
  p_adjust = ${rString(document.getElementById("clin-cor-padj")?.value || "BH")},
  clinical_source = ${rString(source)}
)`;
  } else if (tab === "fitline") {
    replacement = `b <- list(
  session_id = session_id, experiment = as.character(experiment)[1],
  feature = ${rString(document.getElementById("clin-fit-feature")?.value || "REPLACE_FEATURE")},
  trait = ${rString(document.getElementById("clin-fit-trait")?.value || "REPLACE_TRAIT")},
  group = ${rString(document.getElementById("clin-fit-group")?.value || null)},
  method = ${rString(document.getElementById("clin-fit-method")?.value || "lm")},
  log_y = ${rBool(document.getElementById("clin-fit-logy")?.value === "true")},
  clinical_source = ${rString(source)}
)`;
  } else if (tab === "wgcna") {
    replacement = `b <- list(
  session_id = session_id, experiment = as.character(experiment)[1],
  traits = ${rVector(selectedValues("clin-wgcna-traits"), "character()")},
  min_module_size = ${Math.trunc(Number(document.getElementById("clin-wgcna-minmod")?.value || 30))}L,
  clinical_source = ${rString(source)}
)`;
  } else if (tab === "marker_model") {
    replacement = `b <- list(
  session_id = session_id,
  experiments = ${rVector(selectedValues("clin-marker-experiments"), 'c("REPLACE_EXPERIMENT")')},
  outcome_var = ${rString(document.getElementById("clin-marker-outcome")?.value || "REPLACE_BINARY_OUTCOME")},
  positive_class = ${rString(document.getElementById("clin-marker-positive")?.value || null)},
  methods = ${rVector(selectedValues("clin-marker-methods"), 'c("randomForest", "lasso", "xgboost")')},
  clinical_source = ${rString(source)},
  include_clinical_numeric = ${rBool(document.getElementById("clin-marker-include-clinical")?.checked !== false)},
  max_features_per_omics = ${Math.trunc(Number(document.getElementById("clin-marker-max-features")?.value || 200))}L,
  validation_fraction = ${Number(document.getElementById("clin-marker-validation")?.value || 0.3)},
  top_n = 30L, seed = 123L
)`;
  }
  if (!replacement) return code;
  return code.replace(/b <- list\([\s\S]*?\n\)/, replacement);
}

let rootEl;
let consoleEl;
let execOut;
let originalEl;
let taEl;
let clinicalRow;
let clinicalSel;
let histEl;
let llmStatusEl;
let llmConfigEls = {};
let state = {
  workflow: null,
  tab: null,
  debounce: null,
  lastRecorded: "",
};

function loadStore() {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) return { drafts: {}, optimized: {}, history: [] };
    const j = JSON.parse(raw);
    if (!j || typeof j !== "object") return { drafts: {}, history: [] };
    if (!j.drafts || typeof j.drafts !== "object") j.drafts = {};
    if (!j.optimized || typeof j.optimized !== "object") j.optimized = {};
    if (!Array.isArray(j.history)) j.history = [];
    return j;
  } catch {
    return { drafts: {}, optimized: {}, history: [] };
  }
}

function saveStore(store) {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(store));
  } catch {
    /* quota */
  }
}

function draftKey(workflow, tab) {
  return `${workflow}::${tab}`;
}

function loadLlmConfig() {
  try {
    const raw = localStorage.getItem(LLM_CFG_KEY) || localStorage.getItem("emp_code_lab_llm_config_v1");
    if (!raw) return migrateLlmConfig({});
    const cfg = JSON.parse(raw);
    return migrateLlmConfig(cfg && typeof cfg === "object" ? cfg : {});
  } catch {
    return migrateLlmConfig({});
  }
}

function migrateLlmConfig(cfg) {
  cfg = cfg && typeof cfg === "object" ? { ...cfg } : {};
  if (!cfg.profiles || typeof cfg.profiles !== "object") {
    cfg.profiles = {};
    const legacyProvider = cfg.provider;
    if (legacyProvider && legacyProvider !== "auto" &&
        (cfg.api_key || cfg.model || cfg.base_url)) {
      cfg.profiles[legacyProvider] = {
        api_key: cfg.api_key || "",
        model: cfg.model || "",
        base_url: cfg.base_url || "",
      };
    }
  }
  if (cfg.provider === "campus" && !cfg.profiles.campus?.model) {
    cfg.profiles.campus = {
      ...(cfg.profiles.campus || {}),
      model: cfg.profiles.campus?.model || "mixed",
      base_url: cfg.profiles.campus?.base_url || CAMPUS_LLM_PRESET.base_url,
      api_key: cfg.profiles.campus?.api_key || "",
    };
  }
  return cfg;
}

function providerProfile(provider) {
  const cfg = loadLlmConfig();
  return cfg.profiles?.[provider] || {};
}

function providerHasPresetUrl(provider) {
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  return Boolean(cat.baseUrl);
}

function inferBaseUrlMode(provider, profile = {}) {
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  if (profile.base_url_mode === "custom" || profile.base_url_mode === "preset") {
    return profile.base_url_mode;
  }
  const saved = (profile.base_url || "").trim();
  if (saved && cat.baseUrl && saved !== cat.baseUrl) return "custom";
  if (provider === "custom") return "custom";
  return "preset";
}

function isBaseUrlCustomMode(provider) {
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  if (cat.baseUrlEditable && provider === "custom") return true;
  if (!providerHasPresetUrl(provider)) return cat.baseUrlEditable;
  return llmConfigEls.base_url_mode?.value === "custom";
}

function resolveBaseUrl(provider) {
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  const saved = (providerProfile(provider).base_url || "").trim();
  if (provider === "custom") {
    return llmConfigEls.base_url?.value?.trim() || saved || "";
  }
  if (isBaseUrlCustomMode(provider)) {
    return llmConfigEls.base_url?.value?.trim() || saved || cat.baseUrl || "";
  }
  return cat.baseUrl || saved || "";
}

function getSelectedModel() {
  const provider = llmConfigEls.provider?.value || "auto";
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  if (provider === "auto" || provider === "remote") {
    return llmConfigEls.model?.value || "";
  }
  const picked = llmConfigEls.model?.value || "";
  if (picked === "__custom__") {
    return llmConfigEls.model_custom?.value?.trim() || "";
  }
  return picked || cat.defaultModel || "";
}

function populateModelSelect(provider, selectedModel = "") {
  const sel = llmConfigEls.model;
  const customWrap = llmConfigEls.model_custom_wrap;
  const customInp = llmConfigEls.model_custom;
  const cat = LLM_PROVIDER_CATALOG[provider];
  if (!sel || !cat) return;
  sel.innerHTML = cat.models.map((m) =>
    `<option value="${String(m.id).replace(/"/g, "&quot;")}">${m.label}</option>`
  ).join("");
  const catalogIds = new Set(cat.models.map((m) => m.id));
  const want = selectedModel || cat.defaultModel || cat.models[0]?.id || "";
  if (want && !catalogIds.has(want)) {
    sel.value = "__custom__";
    customWrap?.classList.remove("hidden");
    if (customInp) customInp.value = want;
    return;
  }
  sel.value = want;
  if (sel.value === "__custom__") {
    customWrap?.classList.remove("hidden");
    if (customInp && !customInp.value) customInp.value = "";
  } else {
    customWrap?.classList.add("hidden");
    if (customInp) customInp.value = "";
  }
}

function updateBaseUrlField(provider, { preferUiMode = false } = {}) {
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  const el = llmConfigEls.base_url;
  const wrap = llmConfigEls.base_url_wrap;
  const modeSel = llmConfigEls.base_url_mode;
  if (!el) return;

  const profile = providerProfile(provider);
  const saved = (profile.base_url || "").trim();

  if (provider === "custom" && cat.baseUrlEditable) {
    modeSel?.classList.add("hidden");
    el.readOnly = false;
    el.classList.remove("code-lab-llm-readonly");
    el.value = saved;
    el.placeholder = "https://your-api.example.com/v1";
    wrap?.classList.remove("hidden");
    return;
  }

  if (!providerHasPresetUrl(provider)) {
    modeSel?.classList.add("hidden");
    if (cat.baseUrlEditable) {
      el.readOnly = false;
      el.classList.remove("code-lab-llm-readonly");
      el.value = saved || cat.baseUrl || "";
      wrap?.classList.remove("hidden");
    } else {
      el.readOnly = true;
      el.classList.add("code-lab-llm-readonly");
      el.value = provider === "auto" ? "（按各 Provider 默认地址依次尝试）" : "";
      wrap?.classList.toggle("hidden", provider === "remote");
    }
    return;
  }

  modeSel?.classList.remove("hidden");
  const mode = (preferUiMode && modeSel?.value)
    ? modeSel.value
    : inferBaseUrlMode(provider, profile);
  if (modeSel && !preferUiMode) modeSel.value = mode;

  if (mode === "custom") {
    el.readOnly = false;
    el.classList.remove("code-lab-llm-readonly");
    el.value = saved;
    el.placeholder = cat.baseUrl;
  } else {
    el.readOnly = true;
    el.classList.add("code-lab-llm-readonly");
    el.value = cat.baseUrl;
    el.placeholder = "";
  }
  wrap?.classList.remove("hidden");
}

function applyProviderToForm(provider) {
  const profile = providerProfile(provider);
  populateModelSelect(provider, profile.model);
  if (llmConfigEls.api_key) {
    llmConfigEls.api_key.value = profile.api_key || "";
  }
  updateBaseUrlField(provider);
  updateLlmFormHints(provider);
}

function saveCurrentProviderProfile() {
  const provider = llmConfigEls.provider?.value;
  if (!provider) return;
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  const mode = llmConfigEls.base_url_mode?.value || inferBaseUrlMode(provider, providerProfile(provider));
  let baseUrl = "";
  if (provider === "custom" && cat.baseUrlEditable) {
    baseUrl = llmConfigEls.base_url?.value?.trim() || "";
  } else if (isBaseUrlCustomMode(provider)) {
    baseUrl = llmConfigEls.base_url?.value?.trim() || "";
  }
  const cfg = loadLlmConfig();
  cfg.profiles = cfg.profiles || {};
  cfg.profiles[provider] = {
    api_key: llmConfigEls.api_key?.value || "",
    model: getSelectedModel(),
    base_url: baseUrl,
    ...(providerHasPresetUrl(provider) ? { base_url_mode: mode } : {}),
  };
  if (provider === "openrouter" && isOpenRouterFusionMode(provider)) {
    const raw = llmConfigEls.openrouter_models?.value || "";
    const models = raw
      .split(/[,;\s]+/)
      .map((s) => s.trim())
      .filter(Boolean);
    cfg.openrouter_models = resolveOpenRouterFusionModels(models);
    cfg.fusion_model = llmConfigEls.fusion_model?.value?.trim() || OPENROUTER_LLM_PRESET.fusion_model;
    cfg.fusion_max_models = 5;
    cfg.fusion_learn_scores = loadFusionLearnScores();
    cfg.profiles.openrouter.openrouter_models = cfg.openrouter_models;
    cfg.profiles.openrouter.fusion_model = cfg.fusion_model;
  }
  cfg.provider = provider;
  cfg.task_type = llmConfigEls.task_type?.value || cfg.task_type || "code_optimize";
  saveLlmConfig(cfg);
  setLlmStatus(`已保存 ${provider} 的配置（本机浏览器，切换 Provider 会自动恢复）`, "ok");
}

function saveLlmConfig(cfg) {
  try {
    localStorage.setItem(LLM_CFG_KEY, JSON.stringify(cfg || {}));
  } catch {
    /* quota */
  }
}

function templateFor(workflow, tab) {
  const w = CODE_LAB_TEMPLATES[workflow];
  if (!w) return `# (no template for workflow "${workflow}")\n`;
  const t = w[tab];
  if (typeof t === "string" && t.trim()) return t;
  return `# Template not defined for ${workflow} / ${tab}\n# See webapp/backend/plumber.R\n`;
}

function detectActiveTabInPage(page) {
  const sec = document.getElementById(`page-${page}`);
  if (!sec) return null;
  const bar = sec.querySelector(".tab-bar");
  const activeBtn = bar?.querySelector(".tab.active");
  if (activeBtn?.dataset?.tab) return activeBtn.dataset.tab;
  const activePanel = sec.querySelector(".tab-panel.active");
  return activePanel?.id || null;
}

function syncDockLayout() {
  if (!rootEl) return;
  const open = rootEl.classList.contains("code-lab--open");
  const visible = !rootEl.classList.contains("code-lab--hidden");
  const docked = visible && open;
  document.body.classList.toggle("code-lab-docked", docked);
  consoleEl?.classList.toggle("hidden", !docked);
  if (docked) repositionConsolePanel();
}

function repositionConsolePanel() {
  if (!consoleEl) return;
  const activePage = document.querySelector("#main > .page.active");
  if (activePage) {
    activePage.insertAdjacentElement("afterend", consoleEl);
  }
}

function ensureConsolePanel() {
  consoleEl = document.getElementById("code-lab-console");
  execOut = document.getElementById("code-lab-exec-out");
  if (!consoleEl || !execOut) return;
  if (consoleEl.dataset.bound) return;
  consoleEl.dataset.bound = "1";
  document.getElementById("code-lab-console-clear")?.addEventListener("click", () => {
    execOut.innerHTML = `<p class="code-lab-exec-placeholder">${t("codelab.placeholder")}</p>`;
  });
}

function hideDock() {
  state.workflow = null;
  state.tab = null;
  rootEl?.classList.add("code-lab--hidden");
  syncDockLayout();
}

function showDock() {
  rootEl?.classList.remove("code-lab--hidden");
  syncDockLayout();
}

function saveCurrentDraft() {
  if (!state.workflow || !state.tab || !taEl) return;
  const s = loadStore();
  if (!s.optimized) s.optimized = {};
  s.optimized[draftKey(state.workflow, state.tab)] = taEl.value;
  // Backward compatibility with older localStorage shape.
  s.drafts[draftKey(state.workflow, state.tab)] = taEl.value;
  saveStore(s);
}

function sourceCodeForCurrent() {
  if (!state.workflow || !state.tab) return "";
  return originalEl?.value || buildFreshTemplate(state.workflow, state.tab);
}

function setOptimizedCode(code, kind = "llm") {
  if (!taEl || !state.workflow || !state.tab) return;
  taEl.value = code;
  saveCurrentDraft();
  const s = loadStore();
  s.history.push({
    t: Date.now(),
    workflow: state.workflow,
    tab: state.tab,
    code,
    kind,
  });
  while (s.history.length > 500) s.history.shift();
  saveStore(s);
  state.lastRecorded = code;
  renderHistory();
}

function formatLlmError(message) {
  const raw = String(message || "").trim();
  if (!raw) return "LLM 优化失败，请检查 Provider / Base URL / Model / API Key。";
  const lines = raw.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const useful = lines.filter(
    (l) =>
      !/^Traceback \(most recent call last\)/i.test(l) &&
      !/^File "/.test(l) &&
      !/urllib\.error\./.test(l) &&
      !/^curl: \(/.test(l) &&
      l !== "During handling of the above exception, another exception occurred:"
  );
  const joined = (useful.length ? useful : lines).slice(0, 4).join(" ");
  if (/404|not found/i.test(joined)) {
    return `${joined} — 请检查 Code Lab 中 LLM 的 Base URL 与 Model，或改用 Auto / DeepSeek 并填写 API Key。`;
  }
  if (/401|403|auth/i.test(joined)) {
    return `${joined} — 请检查 OpenRouter API Key、账户余额及该模型访问权限（部分旗舰模型需单独开通）。`;
  }
  if (/empty LLM response|non-parseable R code/i.test(joined)) {
    return `${joined} — 推理模型可能超时或返回了解释而非代码，可重试或改用「Auto 融合 5 模型」。`;
  }
  return joined.slice(0, 480);
}

function setLlmStatus(message, kind = "muted") {
  if (!llmStatusEl) return;
  llmStatusEl.textContent = kind === "error" ? formatLlmError(message) : (message || "");
  llmStatusEl.dataset.kind = kind;
}

function applyLlmConfigToForm() {
  const cfg = loadLlmConfig();
  const provider = cfg.provider || "auto";
  if (llmConfigEls.provider) llmConfigEls.provider.value = provider;
  if (llmConfigEls.task_type) {
    llmConfigEls.task_type.value = cfg.task_type || "code_optimize";
  }
  if (llmConfigEls.providers) {
    llmConfigEls.providers.value = Array.isArray(cfg.providers)
      ? cfg.providers.join(",")
      : (cfg.providers || "");
  }
  if (llmConfigEls.remote_host) llmConfigEls.remote_host.value = cfg.remote_host || "";
  if (llmConfigEls.remote_port) llmConfigEls.remote_port.value = cfg.remote_port || "";
  if (llmConfigEls.remote_path) {
    llmConfigEls.remote_path.value = cfg.remote_path || "/api/llm/optimize_r";
  }
  if (llmConfigEls.openrouter_models) {
    const models = resolveOpenRouterFusionModels(
      Array.isArray(cfg.openrouter_models)
        ? cfg.openrouter_models
        : (cfg.profiles?.openrouter?.openrouter_models || OPENROUTER_DEFAULT_FUSION_MODELS)
    );
    llmConfigEls.openrouter_models.value = models.join(", ");
  }
  if (llmConfigEls.fusion_model) {
    llmConfigEls.fusion_model.value = cfg.fusion_model
      || cfg.profiles?.openrouter?.fusion_model
      || OPENROUTER_LLM_PRESET.fusion_model;
  }
  applyProviderToForm(provider);
}

function applyDefaultLlmPreset() {
  const cfg = loadLlmConfig();
  cfg.provider = cfg.provider || "auto";
  if (!cfg.providers?.length) cfg.providers = [...DEFAULT_LLM_PRESET.providers];
  saveLlmConfig(cfg);
  applyLlmConfigToForm();
}

function applyOpenRouterLlmPreset() {
  const cfg = { ...loadLlmConfig(), ...OPENROUTER_LLM_PRESET };
  cfg.openrouter_models = resolveOpenRouterFusionModels(cfg.openrouter_models || []);
  cfg.profiles = {
    ...(cfg.profiles || {}),
    openrouter: {
      ...(cfg.profiles?.openrouter || {}),
      model: cfg.profiles?.openrouter?.model || "fusion",
      base_url: OPENROUTER_LLM_PRESET.base_url,
      api_key: cfg.profiles?.openrouter?.api_key || "",
      openrouter_models: cfg.openrouter_models,
      fusion_model: cfg.fusion_model || OPENROUTER_LLM_PRESET.fusion_model,
    },
  };
  saveLlmConfig(cfg);
  applyLlmConfigToForm();
}

async function runOpenRouterProbe() {
  const cfg = collectLlmConfig({ persistGlobal: false });
  const apiKey = (cfg.api_key || cfg.profiles?.openrouter?.api_key || "").trim();
  if (!apiKey) {
    setLlmStatus("请先填写 OpenRouter API Key，再点「探测可用模型」。", "error");
    return;
  }
  const btn = llmConfigEls.probe_btn;
  if (btn) btn.disabled = true;
  setLlmStatus(`正在探测 ${OPENROUTER_PROBE_CANDIDATES.length} 个 OpenRouter 模型，请稍候…`, "muted");
  try {
    const res = await probeOpenRouterModels({
      config: {
        api_key: apiKey,
        base_url: cfg.base_url || OPENROUTER_LLM_PRESET.base_url,
        timeout: 60,
        probe_models: OPENROUTER_PROBE_CANDIDATES,
      },
      models: OPENROUTER_PROBE_CANDIDATES,
      write_manifest: true,
    });
    if (!res?.success) {
      throw new Error(res?.error || "探测失败");
    }
    openRouterVerified = res;
    applyOpenRouterVerifiedManifest(res);
    applyProviderToForm("openrouter");
    if (llmConfigEls.openrouter_models) {
      llmConfigEls.openrouter_models.value = resolveOpenRouterFusionModels(res.fusion_defaults || []).join(", ");
    }
    if (llmConfigEls.fusion_model && res.fusion_model) {
      llmConfigEls.fusion_model.value = res.fusion_model;
    }
    collectLlmConfig({ persistGlobal: true });
    const failed = Array.isArray(res.failed) ? res.failed.map((row) => row.model).filter(Boolean) : [];
    const failHint = failed.length ? `；不可用：${failed.join("、")}` : "";
    setLlmStatus(
      `探测完成：${res.working_count || 0}/${res.probed || OPENROUTER_PROBE_CANDIDATES.length} 可用，已更新 EMP 模型选项${failHint}`,
      "ok"
    );
  } catch (err) {
    setLlmStatus(err?.message || String(err), "error");
  } finally {
    if (btn) btn.disabled = false;
  }
}

function applyCampusLlmPreset() {
  const cfg = loadLlmConfig();
  cfg.provider = "campus";
  cfg.profiles = cfg.profiles || {};
  cfg.profiles.campus = {
    ...(cfg.profiles.campus || {}),
    model: cfg.profiles.campus?.model || "mixed",
    base_url: CAMPUS_LLM_PRESET.base_url,
    api_key: cfg.profiles.campus?.api_key || "",
  };
  saveLlmConfig(cfg);
  applyProviderToForm("campus");
}

function updateLlmFormHints(provider) {
  const keyEl = llmConfigEls.api_key;
  const taskEl = llmConfigEls.task_type;
  const cat = LLM_PROVIDER_CATALOG[provider] || {};
  if (taskEl) {
    const wrap = taskEl.closest("label");
    if (wrap) wrap.classList.toggle("hidden", provider !== "campus");
  }
  llmConfigEls.openrouter_models?.closest("label")
    ?.classList.toggle("hidden", !isOpenRouterFusionMode(provider));
  llmConfigEls.fusion_model?.closest("label")
    ?.classList.toggle("hidden", !isOpenRouterFusionMode(provider));
  llmConfigEls.probe_btn?.classList.toggle("hidden", provider !== "openrouter");
  if (keyEl) {
    if (provider === "campus") {
      keyEl.placeholder = "可选：留空则使用服务端 webapp/config/campus_llm.json";
    } else if (provider === "openrouter") {
      keyEl.placeholder = "OpenRouter API Key（https://openrouter.ai/keys）";
    } else if (provider === "auto" || provider === "remote") {
      keyEl.placeholder = cat.keyRequired ? "按实际 Provider 填写 API Key" : "可选";
    } else {
      keyEl.placeholder = "仅保存在本机浏览器（点「保存配置」）";
    }
  }
  const modelWrap = llmConfigEls.model?.closest("label");
  modelWrap?.classList.toggle("hidden", provider === "remote");
}

function isOpenRouterFusionMode(provider = llmConfigEls.provider?.value || "auto") {
  if (provider !== "openrouter") return false;
  const model = getSelectedModel();
  return !model || model === "fusion";
}

function resolveApiKey(provider, cfg = loadLlmConfig(), profile = providerProfile(provider)) {
  return llmConfigEls.api_key?.value?.trim()
    || profile.api_key?.trim()
    || cfg.profiles?.[provider]?.api_key?.trim()
    || cfg.api_key?.trim()
    || "";
}

function collectLlmConfig({ persistGlobal = false } = {}) {
  const provider = llmConfigEls.provider?.value || "auto";
  const profile = providerProfile(provider);
  const cfg = loadLlmConfig();
  const merged = {
    ...cfg,
    provider,
    mode: "api",
    api_key: resolveApiKey(provider, cfg, profile),
    model: getSelectedModel(),
    base_url: resolveBaseUrl(provider),
    task_type: llmConfigEls.task_type?.value || "code_optimize",
    remote_host: llmConfigEls.remote_host?.value || "",
    remote_port: llmConfigEls.remote_port?.value || "",
    remote_path: llmConfigEls.remote_path?.value || "/api/llm/optimize_r",
    providers: (llmConfigEls.providers?.value || "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    profiles: cfg.profiles || {},
  };
  if (provider === "campus") {
    merged.campus_models = { ...CAMPUS_LLM_PRESET.campus_models };
  }
  if (provider === "openrouter") {
    merged.fusion_mode = isOpenRouterFusionMode(provider);
    merged.single_model_only = !merged.fusion_mode;
    if (merged.fusion_mode) {
      const raw = llmConfigEls.openrouter_models?.value || "";
      const models = raw
        .split(/[,;\s]+/)
        .map((s) => s.trim())
        .filter(Boolean);
      merged.openrouter_models = resolveOpenRouterFusionModels(models);
      merged.fusion_model = llmConfigEls.fusion_model?.value?.trim()
        || profile.fusion_model
        || OPENROUTER_LLM_PRESET.fusion_model;
      merged.fusion_max_models = 5;
      merged.fusion_learn_scores = loadFusionLearnScores();
      if (llmConfigEls.openrouter_models) {
        llmConfigEls.openrouter_models.value = merged.openrouter_models.join(", ");
      }
    }
  }
  if (persistGlobal) {
    saveLlmConfig(merged);
  }
  return {
    provider: provider === "remote" ? "remote" : provider,
    config: merged,
  };
}

async function runCodeInR(code, label = "优化脚本", sourceCode = null) {
  if (!execOut) ensureConsolePanel();
  const exp = window._emp?.currentExp;
  if (!execOut) return;
  const canRunWithoutExperiment = state.workflow === "clinical" && CLINICAL_NO_EXPERIMENT_TABS.has(state.tab);
  if (!exp && !canRunWithoutExperiment) {
    execOut.innerHTML = `<p class="code-lab-exec-err">${t("codelab.noExperiment")}</p>`;
    consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    return { ok: false, error: "no experiment selected" };
  }
  execOut.innerHTML = `<p class="code-lab-exec-wait">${t("codelab.running", null, { label })}</p>`;
  consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  try {
    const res = await execUserR({
      experiment: exp || null,
      code,
      width: 9,
      height: 6,
      workflow: state.workflow,
      tab: state.tab,
      label,
      source_code: sourceCode ?? sourceCodeForCurrent(),
    });
    if (!res.success) {
      if (lastLlmOptimizeMeta && label === "优化脚本" && lastLlmOptimizeMeta.fusion_models?.length) {
        recordFusionLearn(lastLlmOptimizeMeta.fusion_models, -2);
      }
      execOut.innerHTML = `<p class="code-lab-exec-err">${escapeHtml(res.error || "failed")}</p>`;
      return { ok: false, error: res.error || "failed" };
    }
    const bits = [];
    const plotSrc = execPlotImageSrc(res.plot) ?? execPlotImageSrc(res.png);
    if (plotSrc) {
      bits.push(`<h5>${escapeHtml(label)} · ${escapeHtml(t("codelab.plotOut"))}</h5><img class="code-lab-exec-img" alt="plot" src="${plotSrc.replace(/"/g, "&quot;")}" />`);
    }
    if (res.stdout && res.stdout.trim()) {
      bits.push(`<h5>${escapeHtml(t("codelab.stdout"))}</h5><pre class="code-lab-exec-pre">${escapeHtml(res.stdout)}</pre>`);
    }
    if (res.value_text && String(res.value_text).trim()) {
      bits.push(`<h5>${escapeHtml(t("codelab.returnVal"))}</h5><pre class="code-lab-exec-pre">${escapeHtml(res.value_text)}</pre>`);
    }
    const tableBits = renderExecTables(res.tables);
    if (tableBits) bits.push(tableBits);
    if (res.artifact_name) {
      bits.push(`<h5>${escapeHtml(t("codelab.downloadBundle"))}</h5>
        <p><a class="btn btn-outline code-lab-download" href="${escapeAttr(codeLabArtifactURL(res.artifact_name))}" download>
          ${escapeHtml(t("codelab.downloadBundleBtn"))}
        </a></p>`);
    }
    if (!bits.length) bits.push(`<p>${escapeHtml(t("codelab.doneNoOutput", null, { label }))}</p>`);
    bits.push(`<p class="code-lab-exec-meta">${escapeHtml(`${label}; backend_ms=${res.backend_ms ?? "?"}`)}</p>`);
    execOut.innerHTML = bits.join("");
    if (lastLlmOptimizeMeta && label === "优化脚本" && lastLlmOptimizeMeta.fusion_models?.length) {
      const models = lastLlmOptimizeMeta.fusion_models;
      recordFusionLearn(models, 3);
      if (llmConfigEls.provider?.value === "openrouter" && llmConfigEls.openrouter_models) {
        llmConfigEls.openrouter_models.value = resolveOpenRouterFusionModels(models).join(", ");
      }
    }
    consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    return { ok: true, res };
  } catch (err) {
    const msg = err.message || String(err);
    execOut.innerHTML = `<p class="code-lab-exec-err">${escapeHtml(msg)}</p>`;
    consoleEl?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    return { ok: false, error: msg };
  }
}

function normalizeExecTableRows(tab) {
  if (!tab) return [];
  if (Array.isArray(tab)) return tab;
  if (typeof tab === "string") {
    try {
      const parsed = JSON.parse(tab);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  if (tab.json) {
    try {
      const parsed = JSON.parse(tab.json);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

function renderExecTables(tables) {
  if (!Array.isArray(tables) || !tables.length) return "";
  const parts = [];
  for (const tab of tables) {
    const rows = normalizeExecTableRows(tab);
    if (!rows.length) continue;
    const cols = Object.keys(rows[0] || {});
    if (!cols.length) continue;
    const body = rows.slice(0, 200).map((row) =>
      `<tr>${cols.map((c) => `<td>${escapeHtml(row[c] ?? "")}</td>`).join("")}</tr>`
    ).join("");
    parts.push(`<h5>${escapeHtml(tab.name || "表格输出")} (${escapeHtml(`${tab.n_rows ?? rows.length} rows`)})</h5>
      <div class="code-lab-table-wrap"><table class="code-lab-result-table">
        <thead><tr>${cols.map((c) => `<th>${escapeHtml(c)}</th>`).join("")}</tr></thead>
        <tbody>${body}</tbody>
      </table></div>`);
  }
  return parts.join("");
}

function pushHistoryEntry() {
  if (!state.workflow || !state.tab || !taEl) return;
  const code = taEl.value;
  if (code === state.lastRecorded) return;
  state.lastRecorded = code;
  const s = loadStore();
  s.history.push({
    t: Date.now(),
    workflow: state.workflow,
    tab: state.tab,
    code,
    kind: "edit",
  });
  while (s.history.length > 500) s.history.shift();
  saveStore(s);
  renderHistory();
}

function renderHistory() {
  if (!histEl) return;
  const s = loadStore();
  const wf = state.workflow;
  const tab = state.tab;
  const matches = s.history.filter((h) => h.workflow === wf && h.tab === tab);
  const rows = matches.slice(-40).reverse();
  if (!rows.length) {
    histEl.innerHTML =
      '<div class="code-lab-history-item"><span class="code-lab-history-preview">No edits recorded yet for this step.</span></div>';
    return;
  }
  histEl.innerHTML = rows
    .map((h) => {
      const when = new Date(h.t).toLocaleString();
      const preview = (h.code || "").replace(/\s+/g, " ").trim().slice(0, 120);
      return `<div class="code-lab-history-item">
        <span class="code-lab-history-meta">${escapeHtml(when)}</span>
        <span class="code-lab-history-preview" title="${escapeAttr(h.code)}">${escapeHtml(preview)}</span>
        <span class="code-lab-history-actions"><button type="button" class="btn btn-outline code-lab-restore" data-ts="${h.t}">Restore</button></span>
      </div>`;
    })
    .join("");
  histEl.querySelectorAll(".code-lab-restore").forEach((btn) => {
    btn.addEventListener("click", () => {
      const ts = +btn.getAttribute("data-ts");
      const hit = loadStore().history.find((x) => x.t === ts);
      if (hit && taEl) {
        taEl.value = hit.code;
        saveCurrentDraft();
        pushHistoryEntry();
      }
    });
  });
}

function escapeHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Normalize user_r/run plot payload → img src, or null when not a renderable PNG. */
function execPlotImageSrc(raw) {
  const toSrc = (s) => (s.startsWith("data:") ? s : `data:image/png;base64,${s}`);
  if (typeof raw === "string" && raw.length > 0) return toSrc(raw);
  if (Array.isArray(raw)) {
    const s = raw.find((v) => typeof v === "string" && v.length > 0);
    return s ? toSrc(s) : null;
  }
  if (raw && typeof raw === "object") {
    for (const v of Object.values(raw)) {
      if (typeof v === "string" && v.length > 0) return toSrc(v);
    }
  }
  return null;
}

function escapeAttr(s) {
  return escapeHtml(s).replace(/\n/g, "&#10;");
}

function clinicalSnippetLabel(key) {
  const i18n = {
    three_line: "clinical.threeLine",
    systematic: "clinical.systematic",
    reorient: "clinical.reorient",
    overview: "clinical.overview",
  };
  return i18n[key] ? t(i18n[key]) : (CLINICAL_SNIPPET_LABELS[key] || key);
}

function setHeadTitle() {
  const h = rootEl?.querySelector(".code-lab-head h4");
  if (!h) return;
  if (!state.workflow) {
    h.textContent = t("codelab.headTitle");
    return;
  }
  const tabLabel =
    state.workflow === "clinical"
      ? clinicalSnippetLabel(state.tab) || state.tab
      : state.tab;
  h.textContent = `${t("codelab.workflowCode")} · ${state.workflow} · ${tabLabel}`;
}

export function applyCodeLabI18n() {
  if (!rootEl) return;
  const q = (sel) => rootEl.querySelector(sel);
  const setText = (sel, key) => { const el = q(sel); if (el) el.textContent = t(key); };
  setText(".code-lab-head h4", "codelab.headTitle");
  const badge = q(".code-lab-badge");
  if (badge) badge.textContent = t("codelab.badge");
  const hint = q(".code-lab-hint");
  if (hint) hint.innerHTML = t("codelab.intro");
  setText("#code-lab-clinical-row label", "codelab.clinicalStep");
  const srcTitle = q(".code-lab-code-block:first-of-type .code-lab-code-title span");
  if (srcTitle) srcTitle.textContent = t("codelab.sourceLabel");
  setText("#code-lab-use-source", "codelab.copyToOpt");
  const optTitle = q(".code-lab-code-block:nth-of-type(2) .code-lab-code-title span");
  if (optTitle) optTitle.textContent = t("codelab.optLabel");
  setText("#code-lab-run-source", "codelab.runSource");
  const llmSum = q("#code-lab-llm-wrap > summary");
  if (llmSum) llmSum.textContent = t("codelab.llmConfig");
  setText("#code-lab-exec", "codelab.runOptShort");
  setText("#code-lab-llm-optimize", "codelab.optimize");
  setText("#code-lab-llm-fuse", "codelab.fuseExternal");
  setText("#code-lab-llm-save", "codelab.llmSave");
  if (taEl) taEl.placeholder = t("codelab.optPlaceholder");
  const instEl = q("#code-lab-llm-instruction");
  if (instEl) instEl.placeholder = t("codelab.instructionPlaceholder");
  const baseModeSel = q("#code-lab-llm-base-url-mode");
  if (baseModeSel) {
    const presetOpt = baseModeSel.querySelector('option[value="preset"]');
    const customOpt = baseModeSel.querySelector('option[value="custom"]');
    if (presetOpt) presetOpt.textContent = t("codelab.llmBaseUrlPreset");
    if (customOpt) customOpt.textContent = t("codelab.llmBaseUrlCustom");
  }
  const saveHint = q(".code-lab-llm-save-hint");
  if (saveHint) saveHint.textContent = t("codelab.llmSaveHint");
  const hist = q(".code-lab-history summary");
  if (hist) hist.textContent = t("codelab.history");
  const instLab = q(".code-lab-llm-instruction");
  if (instLab) {
    for (const n of instLab.childNodes) {
      if (n.nodeType === Node.TEXT_NODE && n.textContent.trim()) {
        n.textContent = t("codelab.instruction");
        break;
      }
    }
  }
  if (clinicalSel) {
    const cur = clinicalSel.value;
    [...clinicalSel.options].forEach((o) => {
      o.textContent = clinicalSnippetLabel(o.value);
    });
    clinicalSel.value = cur;
  }
  setHeadTitle();
}

function applyContext(workflow, tab) {
  if (!PAGES.has(workflow)) {
    hideDock();
    return;
  }
  saveCurrentDraft();
  state.workflow = workflow;
  state.tab = tab;
  if (workflow === "clinical") {
    clinicalRow?.classList.remove("hidden");
    if (clinicalSel && clinicalSel.value !== tab) clinicalSel.value = tab;
  } else {
    clinicalRow?.classList.add("hidden");
  }
  const s = loadStore();
  const key = draftKey(workflow, tab);
  const source = buildFreshTemplate(workflow, tab);
  const draft = s.optimized?.[key] ?? s.drafts?.[key];
  if (originalEl) originalEl.value = source;
  taEl.value = typeof draft === "string" ? draft : source;
  state.lastRecorded = taEl.value;
  setHeadTitle();
  showDock();
  renderHistory();
}

function runallTabId() {
  const sel = document.getElementById("ra-pipeline");
  const v = sel?.value === "m16s" ? "m16s" : "rnaseq";
  return `runall-${v}`;
}

export function applyCopilotAction({ page, tab, instruction, autoOptimize = false } = {}) {
  if (!rootEl) return;
  const wf = page || state.workflow || "analysis";
  if (PAGES.has(wf)) {
    applyContext(wf, tab || detectActiveTabInPage(wf) || DEFAULT_TAB[wf]);
    showDock();
    rootEl.classList.add("code-lab--open");
    syncDockLayout();
  }
  const inst = document.getElementById("code-lab-llm-instruction");
  if (inst && instruction) inst.value = instruction;
  if (autoOptimize && instruction) {
    rootEl.querySelector("#code-lab-llm-optimize")?.click();
  }
  rootEl.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

export function openCodeLabPanel(page) {
  if (!rootEl || !PAGES.has(page)) return;
  notifyCodeLabNavigate(page);
  showDock();
  rootEl.classList.add("code-lab--open");
  syncDockLayout();
  rootEl.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

export function notifyCodeLabNavigate(page) {
  if (!rootEl) return;
  if (!PAGES.has(page)) {
    saveCurrentDraft();
    hideDock();
    return;
  }
  if (page === "clinical") {
    const t = document.getElementById("clin-analysis-strategy")?.value || clinicalSel?.value || DEFAULT_TAB.clinical;
    applyContext("clinical", t);
    return;
  }
  if (page === "runall") {
    applyContext("runall", runallTabId());
    return;
  }
  const tab = detectActiveTabInPage(page) || DEFAULT_TAB[page];
  applyContext(page, tab);
  repositionConsolePanel();
}

export function notifyCodeLabTab(page, tabId) {
  if (!rootEl || !PAGES.has(page) || page === "clinical" || page === "runall") return;
  applyContext(page, tabId);
}

export function notifyCodeLabClinicalStep(tabId) {
  if (!rootEl || !CLINICAL_SNIPPET_LABELS[tabId]) return;
  applyContext("clinical", tabId);
  repositionConsolePanel();
}

export function refreshCodeLabContext() {
  if (!rootEl || !state.workflow || !state.tab) return;
  applyContext(state.workflow, state.tab);
}

export async function initCodeLab() {
  await prefetchSnippets();
  ensureConsolePanel();

  document.getElementById("code-lab-root")?.remove();

  rootEl = document.createElement("div");
  rootEl.id = "code-lab-root";
  rootEl.dataset.empLayout = "v3";
  rootEl.className = "code-lab--hidden code-lab--open";
  rootEl.innerHTML = `
    <div class="code-lab-head" title="Click to expand / collapse">
      <h4>流程代码</h4>
      <span class="code-lab-badge">原始/优化 R · LLM</span>
    </div>
    <div class="code-lab-body">
      <div class="code-lab-pane-src code-lab-pane-src--full">
        <div class="code-lab-pane-src-head">System Source vs Optimized R</div>
        <p class="code-lab-hint">
          上方是系统生成的纯 R 原始脚本；下方可粘贴外来分析/绘图脚本，或人工/LLM 优化。
          <strong>「融合外来脚本」</strong>会把外来意图并入系统脚本。
          <strong>「运行优化脚本」</strong> → <code>POST /api/user_r/run</code>。切勿对公网暴露。
        </p>
        <div class="code-lab-clinical-row hidden" id="code-lab-clinical-row">
          <label for="code-lab-clinical-snippet">Clinical 子步骤</label>
          <select id="code-lab-clinical-snippet"></select>
        </div>
        <div class="code-lab-compare">
          <section class="code-lab-code-block">
            <div class="code-lab-code-title">
              <span>系统原始脚本（只读，可直接运行）</span>
              <button type="button" class="btn btn-outline" id="code-lab-use-source">复制到优化区</button>
            </div>
            <textarea class="code-lab-editor code-lab-editor--source" id="code-lab-original" spellcheck="false" autocomplete="off" readonly></textarea>
          </section>
          <section class="code-lab-code-block">
            <div class="code-lab-code-title">
              <span>优化脚本（可粘贴外来脚本；LLM 将融合进系统代码）</span>
              <button type="button" class="btn btn-outline" id="code-lab-run-source">运行原始脚本</button>
            </div>
            <textarea class="code-lab-editor" id="code-lab-editor" spellcheck="false" autocomplete="off" placeholder="可粘贴外部分析/绘图脚本。LLM 会提取核心意图并并入系统原始脚本，而非整段替换。"></textarea>
          </section>
        </div>
        <details class="code-lab-llm-wrap" id="code-lab-llm-wrap">
          <summary>LLM 代码优化配置（默认 API 直连）</summary>
          <div class="code-lab-llm-grid">
            <label>Provider
              <select id="code-lab-llm-provider">
                <option value="auto">Auto 多模型（推荐）</option>
                <option value="campus">校园内网模型（混合）</option>
                <option value="chatgpt">ChatGPT / OpenAI</option>
                <option value="deepseek">DeepSeek</option>
                <option value="qwen">Qwen</option>
                <option value="minimax">MiniMax</option>
                <option value="gemini">Gemini</option>
                <option value="claude">Claude</option>
                <option value="nvidia">NVIDIA NIM</option>
                <option value="openrouter">OpenRouter 多模型</option>
                <option value="custom">Custom OpenAI-compatible</option>
                <option value="remote">Remote 远程服务</option>
              </select>
            </label>
            <label>任务类型
              <select id="code-lab-llm-task-type">
                <option value="code_optimize">代码优化（快→准混合）</option>
                <option value="complex">复杂推理（准→快混合）</option>
                <option value="vision">视觉理解</option>
                <option value="embedding">向量嵌入</option>
              </select>
            </label>
            <label>Model
              <select id="code-lab-llm-model"></select>
            </label>
            <label class="hidden" id="code-lab-llm-model-custom-wrap">自定义 Model
              <input type="text" id="code-lab-llm-model-custom" placeholder="输入模型 ID">
            </label>
            <label>API Key
              <input type="password" id="code-lab-llm-key" placeholder="填写后点「保存配置」">
            </label>
            <label id="code-lab-llm-base-url-wrap">Base URL
              <select id="code-lab-llm-base-url-mode" class="code-lab-llm-base-url-mode">
                <option value="preset">标准配置</option>
                <option value="custom">自定义</option>
              </select>
              <input type="text" id="code-lab-llm-base-url" readonly class="code-lab-llm-readonly">
            </label>
            <label class="hidden" id="code-lab-llm-openrouter-models-wrap">OpenRouter 融合 5 模型（自动学习排序）
              <input type="text" id="code-lab-llm-openrouter-models" placeholder="deepseek/deepseek-v4-pro,deepseek/deepseek-v4-flash,moonshotai/kimi-k2.7-code,qwen/qwen3.7-max,z-ai/glm-5.2">
            </label>
            <label class="hidden" id="code-lab-llm-fusion-model-wrap">融合裁决 / 单模型备选
              <input type="text" id="code-lab-llm-fusion-model" placeholder="deepseek/deepseek-v4-pro">
            </label>
          </div>
          <div class="code-lab-llm-save-row">
            <button type="button" class="btn btn-outline" id="code-lab-llm-save">保存配置</button>
            <button type="button" class="btn btn-outline hidden" id="code-lab-llm-probe-openrouter">探测可用模型</button>
            <span class="code-lab-llm-save-hint">各 Provider 独立保存；OpenRouter 可先探测再选模型</span>
          </div>
          <details class="code-lab-llm-advanced">
            <summary>高级设置：Auto 多模型 / Remote IP + 端口</summary>
            <div class="code-lab-llm-grid">
              <label>Auto Providers
                <input type="text" id="code-lab-llm-providers" placeholder="deepseek,qwen,chatgpt">
              </label>
              <label>远程 IP/Host
                <input type="text" id="code-lab-llm-remote-host" placeholder="192.168.1.10 或 http://host">
              </label>
              <label>远程端口
                <input type="text" id="code-lab-llm-remote-port" placeholder="8001">
              </label>
              <label>远程 API Path
                <input type="text" id="code-lab-llm-remote-path" placeholder="/api/llm/optimize_r">
              </label>
            </div>
          </details>
          <label class="code-lab-llm-instruction">优化要求
            <textarea id="code-lab-llm-instruction" placeholder="例如：融合外来脚本的差异分析与火山图思路；保留 session_id/experiment；用 emp_pub_theme 出图"></textarea>
          </label>
          <div class="code-lab-llm-actions">
            <button type="button" class="btn btn-primary" id="code-lab-llm-optimize">用 LLM 优化原始脚本</button>
            <button type="button" class="btn btn-outline" id="code-lab-llm-fuse">融合外来脚本</button>
            <span class="code-lab-llm-status" id="code-lab-llm-status"></span>
          </div>
        </details>
        <div class="code-lab-toolbar">
          <button type="button" class="btn btn-primary" id="code-lab-exec">运行优化脚本</button>
          <button type="button" class="btn btn-outline" id="code-lab-reset">优化区恢复原始</button>
          <button type="button" class="btn btn-outline" id="code-lab-copy">复制</button>
          <button type="button" class="btn btn-outline" id="code-lab-toggle-collapse">收起面板</button>
        </div>
        <details id="code-lab-history-wrap" class="code-lab-history-wrap">
          <summary>编辑历史（本机）</summary>
          <div class="code-lab-history" id="code-lab-history"></div>
        </details>
      </div>
    </div>
  `;
  document.body.appendChild(rootEl);

  taEl = rootEl.querySelector("#code-lab-editor");
  originalEl = rootEl.querySelector("#code-lab-original");
  histEl = rootEl.querySelector("#code-lab-history");
  llmStatusEl = rootEl.querySelector("#code-lab-llm-status");
  llmConfigEls = {
    mode: rootEl.querySelector("#code-lab-llm-mode"),
    provider: rootEl.querySelector("#code-lab-llm-provider"),
    task_type: rootEl.querySelector("#code-lab-llm-task-type"),
    model: rootEl.querySelector("#code-lab-llm-model"),
    model_custom: rootEl.querySelector("#code-lab-llm-model-custom"),
    model_custom_wrap: rootEl.querySelector("#code-lab-llm-model-custom-wrap"),
    api_key: rootEl.querySelector("#code-lab-llm-key"),
    base_url: rootEl.querySelector("#code-lab-llm-base-url"),
    base_url_mode: rootEl.querySelector("#code-lab-llm-base-url-mode"),
    base_url_wrap: rootEl.querySelector("#code-lab-llm-base-url-wrap"),
    save_btn: rootEl.querySelector("#code-lab-llm-save"),
    providers: rootEl.querySelector("#code-lab-llm-providers"),
    remote_host: rootEl.querySelector("#code-lab-llm-remote-host"),
    remote_port: rootEl.querySelector("#code-lab-llm-remote-port"),
    remote_path: rootEl.querySelector("#code-lab-llm-remote-path"),
    openrouter_models: rootEl.querySelector("#code-lab-llm-openrouter-models"),
    fusion_model: rootEl.querySelector("#code-lab-llm-fusion-model"),
    probe_btn: rootEl.querySelector("#code-lab-llm-probe-openrouter"),
  };
  applyLlmConfigToForm();
  refreshOpenRouterVerifiedModels({ repopulate: false }).then((applied) => {
    if (applied && llmConfigEls.provider?.value === "openrouter") {
      applyProviderToForm("openrouter");
    }
  });
  const saved = loadLlmConfig();
  if (!saved.provider) applyDefaultLlmPreset();
  else if (saved.provider === "campus" && !saved.profiles?.campus?.base_url) applyCampusLlmPreset();
  llmConfigEls.provider?.addEventListener("change", () => {
    const provider = llmConfigEls.provider.value;
    const cfg = loadLlmConfig();
    cfg.provider = provider;
    saveLlmConfig(cfg);
    if (provider === "campus") applyCampusLlmPreset();
    else if (provider === "openrouter") applyOpenRouterLlmPreset();
    else applyProviderToForm(provider);
  });
  llmConfigEls.model?.addEventListener("change", () => {
    const isCustom = llmConfigEls.model.value === "__custom__";
    llmConfigEls.model_custom_wrap?.classList.toggle("hidden", !isCustom);
    updateLlmFormHints(llmConfigEls.provider?.value || "auto");
  });
  llmConfigEls.base_url_mode?.addEventListener("change", (e) => {
    e.stopPropagation();
    const provider = llmConfigEls.provider?.value;
    if (provider) updateBaseUrlField(provider, { preferUiMode: true });
  });
  llmConfigEls.base_url_mode?.addEventListener("click", (e) => e.stopPropagation());
  llmConfigEls.save_btn?.addEventListener("click", (e) => {
    e.stopPropagation();
    saveCurrentProviderProfile();
  });
  llmConfigEls.probe_btn?.addEventListener("click", (e) => {
    e.stopPropagation();
    runOpenRouterProbe();
  });
  [llmConfigEls.providers, llmConfigEls.remote_host, llmConfigEls.remote_port, llmConfigEls.remote_path, llmConfigEls.task_type, llmConfigEls.openrouter_models, llmConfigEls.fusion_model]
    .forEach((el) => {
      el?.addEventListener("change", () => collectLlmConfig({ persistGlobal: true }));
    });
  clinicalRow = rootEl.querySelector("#code-lab-clinical-row");
  clinicalSel = rootEl.querySelector("#code-lab-clinical-snippet");
  for (const [val, lab] of Object.entries(CLINICAL_SNIPPET_LABELS)) {
    const o = document.createElement("option");
    o.value = val;
    o.textContent = clinicalSnippetLabel(val);
    clinicalSel.appendChild(o);
  }
  clinicalSel.addEventListener("change", () => {
    applyContext("clinical", clinicalSel.value);
  });

  rootEl.querySelector(".code-lab-head").addEventListener("click", () => {
    rootEl.classList.toggle("code-lab--open");
    syncDockLayout();
  });

  rootEl.querySelector("#code-lab-toggle-collapse").addEventListener("click", (e) => {
    e.stopPropagation();
    rootEl.classList.remove("code-lab--open");
    syncDockLayout();
  });

  syncDockLayout();

  taEl.addEventListener("input", () => {
    saveCurrentDraft();
    clearTimeout(state.debounce);
    state.debounce = setTimeout(() => pushHistoryEntry(), 800);
  });

  taEl.addEventListener("blur", () => {
    saveCurrentDraft();
    pushHistoryEntry();
  });

  rootEl.querySelector("#code-lab-use-source").addEventListener("click", (e) => {
    e.stopPropagation();
    setOptimizedCode(sourceCodeForCurrent(), "source-copy");
  });

  rootEl.querySelector("#code-lab-run-source").addEventListener("click", async (e) => {
    e.stopPropagation();
    await runCodeInR(sourceCodeForCurrent(), "系统原始脚本", sourceCodeForCurrent());
  });

function collectUiContext() {
  const ctx = {};
  if (window._emp?.currentExp) ctx.experiment = window._emp.currentExp;
  const omics = document.getElementById("omics-pipeline")?.value;
  if (omics) ctx.omics = omics;
  for (const id of ["tx-group", "m16s-group", "mbx-group", "mgx-group"]) {
    const el = document.getElementById(id);
    if (el?.value) { ctx.group_var = el.value; break; }
  }
  for (const [id, key] of [
    ["tx-fc", "fc_cutoff"], ["tx-padj", "padj_cutoff"],
    ["diff-fc", "fc_cutoff"], ["diff-padj", "padj_cutoff"],
  ]) {
    const el = document.getElementById(id);
    if (el?.value) ctx[key] = el.value;
  }
  return Object.keys(ctx).length ? ctx : null;
}

/** Optimized-pane content when it differs from system source (external / draft). */
function externalCodeForOptimize() {
  const opt = taEl?.value ?? "";
  const src = sourceCodeForCurrent() ?? "";
  if (!String(opt).trim()) return null;
  if (String(opt).trim() === String(src).trim()) return null;
  return opt;
}

async function runLlmOptimize({ forceExternal = false } = {}) {
  if (!state.workflow || !state.tab) return;
  const { provider, config } = collectLlmConfig();
  const instruction = rootEl.querySelector("#code-lab-llm-instruction")?.value || "";
  const sourceCode = sourceCodeForCurrent();
  const externalCode = externalCodeForOptimize();
  if (forceExternal && !externalCode) {
    setLlmStatus(t("codelab.fuseNeedExternal"), "error");
    return;
  }
  const fuseMode = !!externalCode;
  setLlmStatus(
    fuseMode
      ? "正在请求 LLM：以系统原始脚本为基座，融合优化区外来脚本…"
      : "正在请求 LLM 优化，结果会写入优化脚本区…",
    "wait"
  );
  try {
    const res = await optimizeRCode({
      provider,
      config,
      workflow: state.workflow,
      tab: state.tab,
      source_code: sourceCode,
      external_code: externalCode,
      instruction: fuseMode
        ? [
            instruction,
            "请将优化区中的外来脚本核心分析/绘图意图融合进系统原始脚本；",
            "保留 EMP session_id、experiment、emp_pub_theme 与 /api/user_r/run 约定，不要整段替换系统脚手架。",
          ].filter(Boolean).join(" ")
        : instruction,
      ui_context: collectUiContext(),
    });
    const code = res.optimized_code || res.code || "";
    if (!code.trim()) throw new Error("LLM 未返回可用 R 代码");
    lastLlmOptimizeMeta = {
      provider: res.provider || provider,
      model: res.model || config.model,
      fusion_models: (res.mode === "fusion" || res.mode === "fusion_fallback")
        && Array.isArray(res.fusion_models) && res.fusion_models.length
        ? res.fusion_models
        : null,
      mode: res.mode || null,
      external_fused: fuseMode,
    };
    const fusionUsed = lastLlmOptimizeMeta.mode === "fusion"
      || lastLlmOptimizeMeta.mode === "fusion_fallback";
    if (!res.fallback && fusionUsed && lastLlmOptimizeMeta.fusion_models?.length) {
      recordFusionLearn(lastLlmOptimizeMeta.fusion_models, 2);
      if (provider === "openrouter" && llmConfigEls.openrouter_models) {
        llmConfigEls.openrouter_models.value = resolveOpenRouterFusionModels(
          lastLlmOptimizeMeta.fusion_models
        ).join(", ");
      }
    }
    setOptimizedCode(code, fuseMode ? `llm-fuse:${res.provider || res.model || provider}` : `llm:${res.provider || res.model || provider}`);
    const modelHint = res.model ? `，模型 ${res.model}` : "";
    const requestedHint = res.requested_model && res.requested_model !== res.model
      ? `（请求 ${res.requested_model}）`
      : "";
    const fusionHint = fusionUsed && lastLlmOptimizeMeta.fusion_models?.length
      ? `，融合 ${lastLlmOptimizeMeta.fusion_models.join(" + ")}`
      : "";
    const externalHint = fuseMode ? "；已融合外来脚本意图" : "";
    const fallbackHint = res.fallback
      ? "（LLM 不可达，已使用本地规则润色，请人工检查）"
      : "";
    const learnHint = fusionUsed
      ? `；已学习 ${Object.keys(loadFusionLearnScores()).length} 个模型偏好`
      : "";
    setLlmStatus(`已生成优化脚本（${res.provider || provider}${modelHint}${requestedHint}${fusionHint}${externalHint}）${fallbackHint}${learnHint}，请先检查再运行。`, "ok");
    import("./teaching.js?v=2026-06-19-course-v9")
      .then((m) => m.traceEvent?.({
        event_type: fuseMode ? "llm_fuse_external" : "llm_optimize",
        workflow: state.workflow,
        tab: state.tab,
        provider: res.provider || provider,
        model: res.model,
      }))
      .catch(() => {});
  } catch (err) {
    setLlmStatus(err.message || String(err), "error");
  }
}

  rootEl.querySelector("#code-lab-llm-optimize").addEventListener("click", async (e) => {
    e.stopPropagation();
    await runLlmOptimize({ forceExternal: false });
  });

  rootEl.querySelector("#code-lab-llm-fuse").addEventListener("click", async (e) => {
    e.stopPropagation();
    await runLlmOptimize({ forceExternal: true });
  });

  rootEl.querySelector("#code-lab-reset").addEventListener("click", (e) => {
    e.stopPropagation();
    if (!state.workflow || !state.tab) return;
    const s = loadStore();
    delete s.drafts[draftKey(state.workflow, state.tab)];
    if (s.optimized) delete s.optimized[draftKey(state.workflow, state.tab)];
    saveStore(s);
    const source = buildFreshTemplate(state.workflow, state.tab);
    if (originalEl) originalEl.value = source;
    setOptimizedCode(source, "reset");
  });

  rootEl.querySelector("#code-lab-copy").addEventListener("click", async (e) => {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(taEl.value);
    } catch {
      /* ignore */
    }
  });

  rootEl.querySelector("#code-lab-exec").addEventListener("click", async (e) => {
    e.stopPropagation();
    const first = await runCodeInR(taEl.value, "优化脚本", sourceCodeForCurrent());
    if (first?.ok || !first?.error) return;
    await autoRepairAndRerun(first.error);
  });

  // AI auto-repair: when the optimized script fails, ask the LLM to fix it
  // (feeding back the exact R error) and re-run once. Best-effort; silently
  // gives up if no LLM is reachable.
  async function autoRepairAndRerun(errorMessage) {
    if (!state.workflow || !state.tab) return;
    const repairErrors = [
      "no experiment selected", "请先选择全局",
      "session", "code is empty",
    ];
    if (repairErrors.some((s) => String(errorMessage || "").includes(s))) return;
    let cfg;
    try { cfg = collectLlmConfig(); } catch { return; }
    if (!cfg?.provider) return;
    setLlmStatus("脚本运行报错，AI 正在尝试自动修复并重跑…", "wait");
    try {
      const res = await optimizeRCode({
        provider: cfg.provider,
        config: cfg.config,
        workflow: state.workflow,
        tab: state.tab,
        source_code: taEl.value,
        instruction:
          `上一版脚本运行报错，请仅修复使其能在当前会话内成功运行，` +
          `保持分析意图与发表级出图风格（emp_pub_theme）。报错信息：\n${errorMessage}`,
        ui_context: collectUiContext(),
      });
      const fixed = res.optimized_code || res.code || "";
      if (!fixed.trim()) throw new Error("AI 未返回修复后的代码");
      setOptimizedCode(fixed, `repair:${res.provider || cfg.provider}`);
      setLlmStatus("AI 已生成修复版脚本，正在重跑…", "wait");
      const second = await runCodeInR(taEl.value, "AI 修复后脚本", sourceCodeForCurrent());
      if (second?.ok) {
        setLlmStatus("AI 自动修复成功，脚本已正常运行。", "ok");
      } else {
        setLlmStatus(`AI 自动修复后仍报错，请手动检查：${second?.error || ""}`, "error");
      }
    } catch (err) {
      setLlmStatus(`AI 自动修复失败：${err.message || String(err)}`, "error");
    }
  }

  const ra = document.getElementById("ra-pipeline");
  ra?.addEventListener("change", () => {
    if (state.workflow === "runall") applyContext("runall", runallTabId());
  });

  applyCodeLabI18n();
  window.addEventListener("emp:locale-change", () => applyCodeLabI18n());
}
