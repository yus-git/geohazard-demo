# Geohazard Medallion Demo on Microsoft Fabric

An end-to-end Microsoft Fabric demo that ingests public geospatial data and builds a
**bronze → silver → gold** medallion pipeline for a geohazard screening workflow. It
shows realistic data-engineering patterns (parameterized ingestion, Delta lakehouses,
pipeline orchestration) together with CI/CD controls (Git integration and a Fabric
deployment pipeline).

The worked example is **RF-1 soft-soil susceptibility** over Maple Ridge, British
Columbia: catalogue satellite/geology/soil metadata, extract and align the pixels,
blend in surveyed soil ground truth, compute per-pixel Susceptibility (S) and
Consequence (C) ratings, then score a 5×5 risk matrix.

## Medallion architecture

| Layer | Notebook | Lakehouse | What it produces |
| --- | --- | --- | --- |
| **Bronze** | `bronze_pc_collections`, `bronze_bc_surficial_geology`, `bronze_bc_soil_survey`, `bronze_data_overview` | `bronze_lakehouse` | STAC item + WFS feature **metadata** (satellite, geology, soil survey) catalogued into Delta tables; folium overview maps |
| **Silver** | `silver_rf1_soil_susceptibility` | `silver_lakehouse` | AOI pixels clipped to a 10 m grid; RF-1 factor metrics + surveyed soil ground truth + per-pixel S/C ratings |
| **Gold** | `gold_rf1_risk_matrix` | `gold_lakehouse` | `risk_score = S × C` (1–25), banded Low/Moderate/High/Extreme; risk matrix + band summary |

```
bronze (catalogue metadata)  ─►  silver (clip + score pixels)  ─►  gold (risk matrix)
```

`bronze_planetary_ingestion` is a standalone single-collection ingestion demo
(`sentinel-2-l2a` → `bronze_satellite_stac_items`) kept for the simplest possible
parameterized-notebook example.

## Repo structure

```
fabric/
  notebooks/
    bronze_pc_collections.ipynb          # Planetary Computer STAC → 7 bronze tables
    bronze_bc_surficial_geology.ipynb    # DataBC WFS → 3 bronze geology tables
    bronze_bc_soil_survey.ipynb          # DataBC WFS (SIFT) → bronze soil survey tables
    bronze_data_overview.ipynb           # reads bronze tables, renders folium maps
    bronze_planetary_ingestion.ipynb     # single-collection parameterized demo
    silver_rf1_soil_susceptibility.ipynb # clip + extract pixels, compute S/C ratings
    gold_rf1_risk_matrix.ipynb           # S × C risk scoring + matrix
  pipelines/
    pl_bronze_ingestion.json             # parallel bronze ingestion + overview build
cicd/
  fabric-setup.config.json              # provisioning inputs
  fabric-setup.output.json              # generated provisioning summary (IDs)
  parameters.dev.json / parameters.prod.json
  promotion-checklist.md
docs/
  data-sources.md                       # every external source, endpoint, and table
  workload-context-geohazard.md         # RF-1..RF-10 geohazard linkage
scripts/
  fabric/
    setup_fabric_demo.ps1               # provisions workspace, lakehouses, notebooks, pipelines
    run_notebooks.ps1                   # runs notebooks on demand
```

## Data sources

All sources are **public and anonymous** (no keys or token signing) and anchor on the
same Area of Interest. Only metadata/pixels are read on demand — underlying rasters are
not downloaded into bronze.

| Source | Protocol | Layers / collections | Notebook |
| --- | --- | --- | --- |
| Microsoft Planetary Computer STAC | `POST /search` | 7 collections (Sentinel-1/2, Copernicus DEM, ESA WorldCover, IO LULC, ALOS PALSAR, HGB) | `bronze_pc_collections` |
| BC DataBC (BC Geographic Warehouse) | WFS 2.0.0 `GetFeature` | Quaternary geology, bedrock, faults | `bronze_bc_surficial_geology` |
| BC DataBC — Soil Information Finder Tool (SIFT) | WFS 2.0.0 `GetFeature` | Soil survey polygons, project boundaries | `bronze_bc_soil_survey` |

**AOI:** Maple Ridge, BC · centre `49.2193, -122.5984` · 20 km bronze catalogue radius,
3 km silver analysis clip. Full details in `docs/data-sources.md`.

## Provisioned identifiers

Workspace `Englobecorp_Geohazard` = `a7d0f907-bf14-4169-8d34-b8765824aa09`. Resolved IDs
are recorded in `cicd/fabric-setup.output.json`.

| Item | Display name | ID |
| --- | --- | --- |
| Lakehouse | `bronze_lakehouse` | `fbdd7d1d-00a2-4e0f-84f8-655fce72e4c9` |
| Lakehouse | `silver_lakehouse` | `7818d0c8-eacb-4599-a91c-68d795175857` |
| Lakehouse | `gold_lakehouse` | `05034b20-db81-4356-8b7c-dbf6ac86f929` |
| Data pipeline | `pl_bronze_ingestion` | `1bcd4990-7fca-4e8b-a356-c5f20405a5dc` |
| Deployment pipeline | `geohazard-demo-single-pipeline` | `965750c8-3575-4cb9-855d-82ada8c65a75` |
| Notebook (PC) | `bronze_pc_collections` | `2ea8d23a-e499-412b-a096-ec78ebe08145` |
| Notebook (BC) | `bronze_bc_surficial_geology` | `4cc8d648-1183-4a7a-85dd-d1f9bf5ea91b` |
| Notebook (soil) | `bronze_bc_soil_survey` | _resolved on next `setup_fabric_demo.ps1` run_ |
| Notebook (map) | `bronze_data_overview` | `e6047d17-ef87-4aaa-b044-d07acdc41d6e` |

> Each notebook must have its layer lakehouse set as the **default lakehouse** (stored in
> the notebook's `metadata.dependencies.lakehouse`). Without it, relative `saveAsTable` /
> `spark.read.table` calls fail and the Spark session is cancelled.

## Setup — provision the foundation

A PowerShell script provisions the workspace, the three lakehouses, the notebooks, and
the deployment pipeline. It is idempotent (existing items are detected, not recreated).

```powershell
.\scripts\fabric\setup_fabric_demo.ps1 -ConfigPath ".\cicd\fabric-setup.config.json" -OutputPath ".\cicd\fabric-setup.output.json"
```

Prerequisites:

- Azure CLI signed in: `az login` (tenant `711a9076-1115-4c36-b7b4-82b4f3a05f6f`).
- The Fabric capacity backing the workspace must be **Active** (not paused):

  ```powershell
  az fabric capacity resume --resource-group rg-fabric --capacity-name cpfabric
  ```

## Run — bronze ingestion pipeline

`pl_bronze_ingestion` runs the two ingestions in parallel, then builds the overview maps:

```
Ingest_PC_Collections ─┐
                        ├─► Build_Overview
Ingest_BC_Geology ──────┘
```

Run the whole pipeline from PowerShell:

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

Validate the run — all three notebooks should report `Succeeded`:

```powershell
$s = Invoke-RestMethod -Uri "$base/workspaces/$ws/spark/livySessions" -Headers $h
$s.value | Sort-Object submittedDateTime -Descending | Select-Object -First 3 |
  ForEach-Object { "{0} | {1}" -f $_.itemName, $_.state }
```

A `Succeeded` state for `bronze_data_overview` means the folium maps rendered without
error. Open that notebook in the Fabric portal to view the rendered map outputs per
layer.

### Run notebooks individually

```powershell
.\scripts\fabric\run_notebooks.ps1
```

## Run — silver and gold (RF-1)

After bronze is populated, run the analytics notebooks in order (in the Fabric portal or
via `run_notebooks.ps1`):

1. `silver_rf1_soil_susceptibility` — clips the AOI to a 10 m UTM 10N grid, pulls the
   Planetary Computer COG pixels, computes the RF-1 factor metrics, **rasterizes the BC
   soil-survey (SIFT) polygons as soft-soil ground truth**, and writes
   `silver_rf1_soil_susceptibility` with the soil signal and per-pixel **S** and **C**
   ratings (1–5). The soil survey carries the largest weight in S, so it flows straight
   through to the gold risk score.
2. `gold_rf1_risk_matrix` — scores `risk_score = S × C` (1–25), bands it
   (Low 1–4 · Moderate 5–9 · High 10–19 · Extreme 20–25), and writes:
   - `gold_rf1_risk_pixels` — per-pixel risk score + band (with coordinates)
   - `gold_rf1_risk_matrix` — the 5×5 S×C grid (pixel count, mean risk, band)
   - `gold_rf1_band_summary` — area (km²) and share per risk band

## CI/CD path

- **Git integration** — commit notebook and pipeline changes through Fabric's source
  control to version the workspace.
- **Deployment pipeline** — `geohazard-demo-single-pipeline` has the workspace assigned
  to stage 0. Assign additional workspaces to later stages for true cross-stage
  promotion. See `cicd/promotion-checklist.md` and `cicd/parameters.{dev,prod}.json`.

## Cost — pause when finished

```powershell
az fabric capacity suspend --resource-group rg-fabric --capacity-name cpfabric
```

## Scope note

This repo demonstrates ingestion and medallion engineering patterns plus a worked RF-1
risk model. The RF-1 ratings use availability-weighted proxies over public data for
illustration; production hazard scoring would extend the silver/gold layers with field
data and calibrated models. Geohazard RF-1..RF-10 context is in
`docs/workload-context-geohazard.md`.
