# Typed workflow plan preflight (experimental)

`webapp/scripts/workflow_plans.py` is a dependency-free, pure Python JSON validator. It is **not an analysis runner**. It does not read matrices, verify file checksums, call R, run subprocesses, contact services, or evaluate user-supplied formulas/code. `valid: true` means declared metadata passed this limited preflight, never that data or statistical conclusions have been validated. Every response has `executable: false` and explains that execution adapters and an R/Bioconductor runtime have not been verified.

## API

- `templates() -> dict`: independent editable catalog, typed operation input/output registry and recommended parameter defaults. Template steps are operation names to expand into explicit step objects; they are not complete plans.
- `validate_plan(plan: dict) -> dict`: returns `valid`, `executable`, `errors`, `warnings`, `execution_blockers`, `recommended_template_ids`, and `record`. Diagnostics contain `code`, `path`, and `message`. A JSON-compatible plan gets an immutable-by-copy snapshot and deterministic SHA-256 of canonical JSON in `record`; malformed JSON gets `record: null`.

## Example plan

```json
{
  "version": 1,
  "datasets": [{
    "id": "rna",
    "omics": "bulk_rnaseq",
    "data_type": "raw_counts",
    "provenance": {
      "source": "GEO accession and original filename",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    "sample_ids": ["A1", "A2", "B1", "B2"]
  }],
  "samples": [
    {"id": "A1", "group": "control", "batch": "one"},
    {"id": "A2", "group": "control", "batch": "two"},
    {"id": "B1", "group": "treated", "batch": "one"},
    {"id": "B2", "group": "treated", "batch": "two"}
  ],
  "design": {"group": "group", "batch": "batch", "contrast": ["treated", "control"]},
  "steps": [
    {"id": "qc", "operation": "qc", "dataset_id": "rna"},
    {"id": "de", "operation": "deseq2", "dataset_id": "rna", "parameters": {"alpha": 0.05, "min_count": 10}}
  ]
}
```

Replace the illustrative checksum with the actual file hash. `sample_ids` describes matrix column order and must match distinct metadata IDs exactly; alignment is by ID, never array position. Different datasets may share sample IDs only when they mean the same samples; use distinct IDs for distinct biological samples. Extra metadata generates a warning. The validator trusts the declared IDs and does not inspect file contents.

## Supported scope and limitations

- Bulk RNA-seq `raw_counts`: QC, exploratory PCA/heatmap and DESeq2 **plan validation**. Raw integer counts must be verified upstream. Raw-count visualization still requires library-size normalization and a suitable transformation upstream; merely taking log2(count+1) is not sufficient protection against library-size effects.
- `tpm`, `fpkm`, and `normalized`: QC, PCA and heatmap plans only. DESeq2 rejects all three, and also rejects `unknown`. Known normalization/transform provenance must be inspected before interpreting results; the module cannot infer log scale or choose transforms safely from a label.
- Steps can be added, removed or reordered and parameters edited within the allowlisted registry. Each operation reads a declared dataset and has a typed terminal output. Arbitrary DAG wiring, derived-input edges, code, formulas and custom operations are not implemented.
- Multiple datasets are checked independently. There is no pooling, batch correction, cross-study meta-analysis or multiomics integration. The catalog exposes explicitly unsupported placeholders for other omics; any requested integration is rejected rather than accepted as executable.
- DESeq2 requires a two-group contrast and at least two declared biological replicates in every included group; fewer than three triggers a low-power warning. Independence cannot be checked from labels. Repeated measures, paired designs, interactions and continuous covariates are unsupported.
- Optional additive categorical `group + batch` checks missing batches, rank deficiency using connectivity of the group/batch incidence graph, and residual degrees of freedom. This detects full confounding, not all statistical risks. An omitted batch term with existing batch metadata generates a warning.
- Provenance requires a source string and syntactically valid SHA-256. This records an assertion, not verification. The reproducibility record stores the submitted plan and its hash; it does not claim package versions, random seeds, environment capture, results or completed runs.
- No authentication, persistence, upload or execution boundary is introduced by this module. An API caller must independently apply request limits/access controls and retain records if desired.

## Verification

```sh
python -m unittest discover -s webapp/tests -p test_workflow_plans.py
```

Tests cover positive validation with execution blocked, deterministic records, mutation isolation, incompatible matrix types, malformed JSON/data shapes, source provenance, duplicate/mismatched IDs, biological replication, contrasts, confounded/unconfounded batch designs, exhausted residual degrees of freedom, invalid parameters, unknown operations, multi-dataset limitations and unsupported integration.
