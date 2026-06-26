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

## Automated Fabric setup via code

This repo includes a PowerShell provisioning script that creates the full demo foundation in Fabric:

- One demo workspace
- Bronze Lakehouse in that workspace
- Deployment pipeline and stage 0 workspace assignment

Run from repo root:

```powershell
.\scripts\fabric\setup_fabric_demo.ps1 -ConfigPath ".\cicd\fabric-setup.config.json" -OutputPath ".\cicd\fabric-setup.output.json"
```

Files:

- `scripts/fabric/setup_fabric_demo.ps1`
- `cicd/fabric-setup.config.json`
- `cicd/fabric-setup.output.json` (generated execution summary)

## Bronze ingestion pipeline (`pl_bronze_ingestion`)

A Fabric Data Factory pipeline orchestrates the multi-source bronze ingestion and a
map-rendering overview. Definition: `fabric/pipelines/pl_bronze_ingestion.json`.

Activities:

1. `Ingest_PC_Collections` → notebook `bronze_pc_collections` (Microsoft Planetary
   Computer STAC → 7 bronze tables). Runs in parallel with the next activity.
2. `Ingest_BC_Geology` → notebook `bronze_bc_surficial_geology` (DataBC WFS → 3 bronze
   tables). Runs in parallel.
3. `Build_Overview` → notebook `bronze_data_overview`. Runs only after both ingestions
   succeed; reads every bronze table and renders one folium map per layer over the
   Maple Ridge, BC area of interest.

### Reproduce end-to-end

Prerequisites:

- Azure CLI signed in: `az login` (tenant `711a9076-1115-4c36-b7b4-82b4f3a05f6f`).
- The Fabric capacity backing the workspace must be **Active** (not paused):

  ```powershell
  az fabric capacity resume --resource-group rg-fabric --capacity-name cpfabric
  ```

- Workspace, lakehouses, and notebooks provisioned (see "Automated Fabric setup via
  code" above). Resolved IDs are recorded in `cicd/fabric-setup.output.json`.

Key identifiers (workspace `Englobecorp_Geohazard` = `a7d0f907-bf14-4169-8d34-b8765824aa09`):

| Item | Display name | ID |
| --- | --- | --- |
| Data pipeline | `pl_bronze_ingestion` | `1bcd4990-7fca-4e8b-a356-c5f20405a5dc` |
| Notebook (PC) | `bronze_pc_collections` | `2ea8d23a-e499-412b-a096-ec78ebe08145` |
| Notebook (BC) | `bronze_bc_surficial_geology` | `4cc8d648-1183-4a7a-85dd-d1f9bf5ea91b` |
| Notebook (map) | `bronze_data_overview` | `e6047d17-ef87-4aaa-b044-d07acdc41d6e` |
| Lakehouse (default) | `bronze_lakehouse` | `fbdd7d1d-00a2-4e0f-84f8-655fce72e4c9` |

> Each bronze notebook must have `bronze_lakehouse` set as its **default lakehouse**
> (stored in the notebook's `metadata.dependencies.lakehouse`). Without it, relative
> `saveAsTable` / `spark.read.table` calls fail and the Spark session is cancelled.

Run the whole pipeline from the terminal (PowerShell):

```powershell
$ws   = "a7d0f907-bf14-4169-8d34-b8765824aa09"
$plid = "1bcd4990-7fca-4e8b-a356-c5f20405a5dc"
$base = "https://api.fabric.microsoft.com/v1"
$h    = @{ Authorization = "Bearer $(az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv)" }

# Start the pipeline
$r   = Invoke-WebRequest -Method Post -Uri "$base/workspaces/$ws/items/$plid/jobs/instances?jobType=Pipeline" -Headers $h -Body '{}' -ContentType 'application/json'
$loc = @($r.Headers['Location'])[0]

# Poll to completion
do { Start-Sleep 20; $j = Invoke-RestMethod -Uri $loc -Headers $h; $j.status } while ($j.status -in "NotStarted","InProgress","Running")
"FINAL: $($j.status)"   # expect: Completed
```

Validate the result:

```powershell
# All three notebooks should report Succeeded
$s = Invoke-RestMethod -Uri "$base/workspaces/$ws/spark/livySessions" -Headers $h
$s.value | Sort-Object submittedDateTime -Descending | Select-Object -First 3 |
  ForEach-Object { "{0} | {1}" -f $_.itemName, $_.state }
```

A `Succeeded` state for `bronze_data_overview` means the folium maps rendered without
error. Open that notebook in the Fabric portal to view the rendered map outputs per
layer.

### Run notebooks individually

To run the bronze notebooks on demand (outside the pipeline):

```powershell
.\scripts\fabric\run_notebooks.ps1
```

When finished, pause the capacity to stop incurring Azure cost:

```powershell
az fabric capacity suspend --resource-group rg-fabric --capacity-name cpfabric
```
