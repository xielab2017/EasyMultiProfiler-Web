export const CONTRACT = 'emp-count-workbench-v1';

// Every edit revokes the exact prepared plan. A running job stays independent.
export class WorkflowState {
  constructor(translate = source => source) { this.translate = translate; this.revision = 0; this.steps = []; this.dataset = null; this.prepared = null; this.context = null; this.active = null; }
  change() { this.revision++; this.prepared = null; this.context = null; }
  setSteps(steps, catalog) {
    if (!Array.isArray(steps) || !steps.length || steps.length > 6) throw Error(this.translate('流程需要 1–6 个登记步骤'));
    const seen = new Set();
    const copy = steps.map((step, i) => {
      const entry = catalog.operations[step.operation];
      if (!entry || seen.has(step.operation)) throw Error(this.translate('AI 提议包含未支持或重复的操作'));
      seen.add(step.operation);
      if (!step.parameters || typeof step.parameters !== 'object' || Array.isArray(step.parameters) || Object.keys(step.parameters).some(k => !(k in entry.parameters))) throw Error(this.translate('操作参数不符合登记表'));
      return {id: `step${i+1}`, operation: step.operation, parameters: {...entry.parameters, ...step.parameters}};
    });
    this.change(); this.steps = copy;
  }
  move(from, to) {
    if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to < 0 || from >= this.steps.length || to >= this.steps.length) return;
    const [step] = this.steps.splice(from, 1); this.steps.splice(to, 0, step); this.change();
  }
  acceptPrepared(value, revision) {
    if (revision !== this.revision) throw Error(this.translate('流程或样本已改变，请重新检查'));
    this.prepared = value.valid ? value : null;
  }
  executionRequest(payload, confirmed) {
    if (!this.prepared || confirmed !== true || payload.plan_sha256 !== this.prepared.plan_sha256) throw Error(this.translate('请重新审核并明确确认当前计划'));
    return {...payload, confirmed: true};
  }
}

export function resultTSV(rows,method='DESeq2') {
  const columns = method==='edgeR'?['feature_id','logFC','logCPM','F','PValue','FDR']:['feature_id', 'baseMean', 'log2FoldChange', 'lfcSE', 'stat', 'pvalue', 'padj'];
  const clean = value => {
    if (value === null || value === undefined) return '';
    const text = String(value).replace(/[\r\n\t]/g, ' ');
    return typeof value === 'string' && /^[=+@-]/.test(text) ? "'" + text : text;
  };
  return [columns.join('\t'), ...rows.map(row => columns.map(k => clean(row[k])).join('\t'))].join('\n') + '\n';
}
