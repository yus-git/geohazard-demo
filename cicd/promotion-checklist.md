# Fabric Promotion Checklist (Dev -> Test -> Prod)

## 1. Dev setup

- Create or open a Fabric workspace for Dev.
- Create a Lakehouse and attach it to the notebook.
- Import `fabric/notebooks/bronze_planetary_ingestion.ipynb`.
- Run with `cicd/parameters.dev.json` values.
- Validate that `bronze_satellite_stac_items` is created and populated.

## 2. Git integration

- Connect Dev workspace to a Git repo/branch.
- Commit notebook and supporting assets.
- Open PR and merge into your main branch.

## 3. Deployment pipeline

- Create a Fabric Deployment Pipeline with Dev, Test, Prod stages.
- Assign corresponding workspaces to each stage.
- Deploy from Dev to Test.
- In Test, run notebook with test parameter values and verify table contents.
- Deploy from Test to Prod after validation.

## 4. Environment controls

- Keep notebook code identical across environments.
- Change only parameter values (date window, item limit, output table).
- If needed, use stage-specific Lakehouse names while preserving output schema.

## 5. Demo talking points

- Same notebook logic runs in all stages.
- Source control captures exact notebook version and parameter intent.
- Deployment pipeline gives auditable, repeatable promotion.
- Bronze layer remains raw/lightweight for downstream Silver transformations.
