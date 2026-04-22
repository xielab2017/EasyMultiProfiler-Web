# EasyMultiProfiler Web Workflow Roadmap

This roadmap follows the "framework first, workflows second" strategy.

## Phase 1: Framework (done)

- Unified workflow registry (`backend/helpers/workflow_registry.R`)
- Workflow APIs:
  - `GET /api/workflows`
  - `GET /api/workflows/<workflow_id>`
- Frontend workflow blueprint panel in Import page

## Phase 2: Transcriptomics (Batch 1 in progress)

Completed in Batch 1:

1. Added transcriptomics workflow helper backend scaffold (`workflow_transcriptomics.R`)
2. Added transcriptomics workflow API routes under `/api/workflows/transcriptomics/...`
3. Added transcriptomics frontend API client methods
4. Added transcriptomics analysis/visualization UI controls (`tx-` prefixed ids)

Remaining for Phase 2:

1. Differential + volcano/heatmap polish
2. GSEA statistical tuning and richer outputs
3. Native WGCNA backend module (replace current correlation fallback)
4. Enrichment companion plots and transcriptomics-specific exports

## Phase 3: Microbiome 16S

Batch 2 status:

1. Taxonomy profile + taxonomy-aware preparation routes added under `/api/workflows/microbiome_16s/...` (done)
2. 16S Sankey plot endpoint + frontend controls (`m16s-` prefixed ids) added (done)
3. 16S dedicated network plot endpoint + frontend controls (`m16s-` prefixed ids) added (done)
4. Existing generic endpoints preserved; additive workflow-specific modules only (done)
5. TODO: add taxonomy-specific import validation guardrails for malformed lineage strings

## Phase 4: Metagenomics

Batch 3 status:

1. [x] Functional ID-aware workflow checks (KO/EC/pathway) via `/api/workflows/metagenomics/profile`
2. [x] Functional preprocess endpoint with validation-safe defaults via `/api/workflows/metagenomics/preprocess`
3. [x] Differential + enrichment workflow endpoints via `/api/workflows/metagenomics/analyze/...`
4. [x] Functional visualization workflow endpoints via `/api/workflows/metagenomics/visualize/...`
5. [x] Workflow-specific differential export via `/api/workflows/metagenomics/export/result/<session_id>/<experiment>`
6. [x] Dedicated frontend API and `mgx-` UI controls wired for profile/preprocess/analyze/visualize/export
7. [ ] Add automated tests for metagenomics workflow routes and UI interactions

## Phase 5: Metabolomics (Batch 4 status)

- [x] Missingness/normalization-aware profile + preprocessing routes (`/api/workflows/metabolomics/profile`, `/api/workflows/metabolomics/preprocess`)
- [x] Differential workflow endpoint with defaults and group auto-resolution (`/api/workflows/metabolomics/analyze/differential`)
- [x] Volcano visualization + differential CSV export (`/api/workflows/metabolomics/visualize/volcano`, `/api/workflows/metabolomics/export/differential/<session_id>/<experiment>`)
- [x] Frontend metabolomics API wiring + dedicated `mbx-` controls (profile/preprocess/differential/volcano/export)
- [ ] Marker-specific metabolomics endpoint (kept for follow-up batch)

## Phase 6: Multi-omics Integration

1. Unified sample map checks across experiments
2. Cross-omics correlation/network API
3. Integrated reporting and export bundles

## Development Rules

- Keep R computation in package/core functions
- Keep backend as thin orchestration layer
- Keep frontend modular per workflow tab/panel
- Add each workflow as an independent API+UI slice

## Quality Loop (new)

- Added workflow pre-check endpoints:
  - `/api/workflows/transcriptomics/validate`
  - `/api/workflows/microbiome_16s/validate`
  - `/api/workflows/metagenomics/validate`
  - `/api/workflows/metabolomics/validate`
- Added smoke regression script: `webapp/tests/smoke_workflows.py`
