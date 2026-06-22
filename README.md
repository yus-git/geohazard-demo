# Fabric CI/CD Bronze Ingestion Demo

A lightweight repo to demonstrate end-to-end Fabric engineering patterns:

1. Parameterized notebook ingestion from Microsoft Planetary Computer STAC API
2. Bronze write into a Lakehouse Delta table
3. Git integration for source control
4. Promotion through Fabric Deployment Pipelines (Dev -> Test -> Prod)

## Repo structure

- `fabric/notebooks/bronze_planetary_ingestion.ipynb`: Main notebook for bronze ingestion.
- `cicd/parameters.dev.json`: Suggested notebook parameters for Dev.
- `cicd/parameters.prod.json`: Suggested notebook parameters for Prod.
- `cicd/promotion-checklist.md`: Practical promotion walkthrough.
- `docs/workload-context-geohazard.md`: How geohazard RF-1..RF-10 context maps to this dataset.

## Demo flow

1. Open the notebook in Fabric and attach a Lakehouse.
2. Set parameters (collection, center point, radius, date range).
3. Run notebook to ingest STAC item metadata and write to bronze table.
4. Commit notebook changes via Fabric Git integration.
5. Promote artifacts through Deployment Pipeline stages.

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
