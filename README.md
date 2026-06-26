# Fabric CI/CD Bronze Ingestion Demo

A lightweight repo to demonstrate end-to-end Fabric engineering patterns:

1. Parameterized notebook ingestion from Microsoft Planetary Computer STAC API
2. Bronze write into a Lakehouse Delta table
3. Git integration for source control
4. Promotion path through a Fabric Deployment Pipeline

## Repo structure

- `fabric/notebooks/bronze_planetary_ingestion.ipynb`: Main notebook for bronze ingestion.
- `cicd/parameters.dev.json`: Suggested notebook parameters for Dev.
- `cicd/parameters.prod.json`: Suggested notebook parameters for Prod.
- `cicd/promotion-checklist.md`: Practical promotion walkthrough.
- `docs/workload-context-geohazard.md`: How geohazard RF-1 to RF-10 context maps to this dataset.

## Demo flow

1. Open the notebook in Fabric workspace `geohazard-demo` and attach `bronze_lakehouse`.
2. Set parameters (collection, center point, radius, date range).
3. Run notebook to ingest STAC item metadata and write to bronze table.
4. Commit notebook changes via Fabric Git integration.
5. Demonstrate pipeline path by assigning the workspace to stage 0.

## Bronze output

Default output table:

- `bronze_satellite_stac_items`

Primary columns include:

- `ingestion_ts`
- `item_id`
- `collection`
- `datetime_utc`
- `platform`
- `eo_cloud_cover`
- `bbox_minx`, `bbox_miny`, `bbox_maxx`, `bbox_maxy`
- `asset_count`
- Query context fields (`query_lat`, `query_lon`, `query_radius_km`, `query_start_date`, `query_end_date`)

## Notes

- This notebook intentionally keeps transformation minimal (bronze pattern).
- Planetary Computer credentials are not required for basic STAC metadata search.
- Use this as a starter pattern for repeatable data engineering and promotion controls.

## One-stop deploy (scripted)

Use the provisioning script to create the full demo foundation in one run:

- Fabric workspace
- Bronze Lakehouse
- Notebook item
- Deployment pipeline with stage 0 workspace assignment

### Prerequisites

- Azure CLI installed
- Authenticated session (`az login`)
- Fabric/Power BI permissions to create workspaces, items, and deployment pipelines
- Optional: set a target subscription if you have multiple

```powershell
az account set --subscription "<your-subscription-name-or-id>"
```

### Deploy

Run from repo root:

```powershell
.\scripts\fabric\setup_fabric_demo.ps1 -ConfigPath ".\cicd\fabric-setup.config.json" -OutputPath ".\cicd\fabric-setup.output.json"
```

### What gets created

- Workspace: `geohazard-demo` (from config)
- Lakehouse: `bronze_lakehouse`
- Notebook item: `bronze_planetary_ingestion`
- Deployment pipeline: `geohazard-demo-single-pipeline`
- Stage assignment: workspace assigned to stage 0

### Verify

- Check generated output summary: `cicd/fabric-setup.output.json`
- In Fabric UI, confirm workspace, lakehouse, notebook, and deployment pipeline exist
- Open notebook and verify it is attached to `bronze_lakehouse`

Files involved:

- `scripts/fabric/setup_fabric_demo.ps1`
- `cicd/fabric-setup.config.json`
- `cicd/fabric-setup.output.json` (generated after run)

## Manual setup (UI-first)

If you prefer not to run the script, use this checklist.

### 1. Create workspace

1. In Fabric, create a new workspace named `geohazard-demo`.
2. Assign to an active capacity if needed in your tenant.

### 2. Create Lakehouse

1. Inside `geohazard-demo`, create a Lakehouse named `bronze_lakehouse`.
2. Keep default options (schema-enabled is fine).

### 3. Add notebook

1. In the workspace, create or import a notebook named `bronze_planetary_ingestion`.
2. Import notebook content from `fabric/notebooks/bronze_planetary_ingestion.ipynb`.
3. Attach the notebook to `bronze_lakehouse`.

### 4. Configure and run notebook

1. Use values from `cicd/parameters.dev.json` (or your own).
2. Run the notebook to load metadata into table `bronze_satellite_stac_items`.

### 5. Create deployment pipeline

1. In Power BI/Fabric deployment pipelines, create pipeline `geohazard-demo-single-pipeline`.
2. Assign workspace `geohazard-demo` to stage 0.

### 6. Optional Git integration

1. Connect workspace Git integration to this repository.
2. Commit notebook and item changes through your normal promotion workflow.
