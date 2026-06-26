# Push Notebooks & Lakehouses to Fabric, then Re-run the Pipeline

This runbook walks you through deploying **all** geohazard notebooks and lakehouses
into your Microsoft Fabric workspace and re-running the data pipeline end-to-end
(bronze → silver → gold).

Everything here is **idempotent** — you can run it repeatedly. The setup script
finds-or-creates each item, re-uploads the latest notebook content, and binds every
notebook to its correct medallion lakehouse.

---

## What gets deployed

| Layer | Lakehouse | Notebooks |
| --- | --- | --- |
| Bronze | `bronze_lakehouse` | `bronze_pc_collections`, `bronze_bc_surficial_geology`, `bronze_data_overview`, `bronze_planetary_ingestion` |
| Silver | `silver_lakehouse` | `silver_rf1_soil_susceptibility` |
| Gold | `gold_lakehouse` | `gold_rf1_risk_matrix` |

- **Workspace:** `Englobecorp_Geohazard`
- **Data pipeline:** `pl_bronze_ingestion` (bronze orchestration)
- **Deployment pipeline:** `geohazard-demo-single-pipeline`

Each notebook's **default lakehouse binding is injected automatically** at deploy
time, so `saveAsTable` / `spark.read.table` calls land in the right layer even when
the notebooks are run headless.

---

## Prerequisites

1. **Azure CLI** signed in to the correct tenant:

   ```powershell
   az login --tenant 711a9076-1115-4c36-b7b4-82b4f3a05f6f
   az account show
   ```

2. **PowerShell 7+** (`pwsh`). Check with `$PSVersionTable.PSVersion`.

3. **Fabric capacity is running.** The capacity `cpfabric` (resource group
   `rg-fabric`) must be **Active** — a paused capacity will reject jobs.

   ```powershell
   # Resume the capacity (skip if already running)
   az fabric capacity resume --resource-group rg-fabric --capacity-name cpfabric
   ```

4. Run all commands from the **repo root**:

   ```powershell
   cd "c:\Users\chenalex\OneDrive - Microsoft\Documents\Microsoft Scout\OPS Fabric Workspace\geohazard-demo"
   ```

---

## Step 1 — Push all lakehouses & notebooks

This provisions the workspace, all 3 lakehouses, all 6 notebooks (with their
correct lakehouse bindings), and the deployment pipeline. It writes the resulting
IDs to `cicd/fabric-setup.output.json`.

```powershell
pwsh ./scripts/fabric/setup_fabric_demo.ps1 `
  -ConfigPath ./cicd/fabric-setup.config.json `
  -OutputPath ./cicd/fabric-setup.output.json
```

**Expected output:** each lakehouse and notebook printed as created/updated, plus a
`Bound default lakehouse: <name> (<id>)` line per notebook confirming the binding.

> If you want a clean slate (delete every item in the workspace and rebuild), add
> `-Reset`. This is destructive — only use it for a full re-provision.
>
> ```powershell
> pwsh ./scripts/fabric/setup_fabric_demo.ps1 -Reset
> ```

---

## Step 2 — Re-run the bronze data pipeline

The bronze ingestion pipeline `pl_bronze_ingestion` runs the two ingestion
notebooks in parallel, then builds the overview. Trigger it on demand:

```powershell
# Read the provisioned IDs
$state        = Get-Content ./cicd/fabric-setup.output.json -Raw | ConvertFrom-Json
$workspaceId  = $state.workspace.workspaceId
$token        = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv

# Resolve the data pipeline by name from the workspace
$items    = (Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items" -Headers @{ Authorization = "Bearer $token" }).value
$pipeline = $items | Where-Object { $_.type -eq 'DataPipeline' -and $_.displayName -eq 'pl_bronze_ingestion' } | Select-Object -First 1
if (-not $pipeline) { throw "pl_bronze_ingestion not found in workspace $workspaceId." }

# Start the pipeline run
$runUri = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items/$($pipeline.id)/jobs/instances?jobType=Pipeline"
$resp   = Invoke-WebRequest -Method Post -Uri $runUri -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" -Body "{}"
$jobUrl = $resp.Headers["Location"]; if ($jobUrl -is [array]) { $jobUrl = $jobUrl[0] }
Write-Host "Pipeline run accepted. Tracking: $jobUrl"

# Poll until terminal
do {
    Start-Sleep 15
    $token = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv
    $info  = Invoke-RestMethod -Uri $jobUrl -Headers @{ Authorization = "Bearer $token" }
    Write-Host "  status: $($info.status)"
} while ($info.status -notin @('Completed','Failed','Cancelled','Deduped'))
$info.status
```

> If `pl_bronze_ingestion` is not found, open the workspace in the Fabric portal and
> click **Run** on the pipeline manually, or import it from
> `fabric/pipelines/pl_bronze_ingestion.json` first.

---

## Step 3 — Run the silver and gold notebooks (in order)

The data pipeline only covers bronze. Run the curation and analytics layers next.
Each notebook binds to its own lakehouse automatically.

```powershell
# Silver first (depends on bronze tables)
pwsh ./scripts/fabric/run_notebooks.ps1 -Notebooks silver_rf1_soil_susceptibility

# Gold next (depends on silver tables)
pwsh ./scripts/fabric/run_notebooks.ps1 -Notebooks gold_rf1_risk_matrix
```

`run_notebooks.ps1` submits each run, then polls to a terminal state and prints the
final status. A non-zero exit code means at least one notebook did not complete.

> To run **every** notebook on demand (bronze + silver + gold) instead of using the
> pipeline, just call the script with no `-Notebooks` filter:
>
> ```powershell
> pwsh ./scripts/fabric/run_notebooks.ps1
> ```

---

## Step 4 — Promote with the deployment pipeline (optional)

`geohazard-demo-single-pipeline` promotes whatever is currently in the workspace
stage. Because Steps 1–3 already pushed the latest notebooks and lakehouses into the
workspace, the deployment pipeline will pick them up. Trigger or review it in the
Fabric portal under **Workspace → Deployment pipelines**, or via the Power BI
pipelines REST API if you automate promotion between stages.

---

## Step 5 — Validate

- **Portal:** open each lakehouse and confirm the expected Delta tables exist
  (bronze raw tables → silver curated tables → gold risk matrix).
- **Notebook bindings:** open any notebook → the **Lakehouses** panel should show
  the matching default lakehouse (bronze/silver/gold) already pinned.
- **Job history:** Workspace → **Monitor** shows the pipeline run and notebook runs
  as Completed.

---

## Step 6 — Pause the capacity when finished

To stop incurring capacity cost after the demo:

```powershell
az fabric capacity suspend --resource-group rg-fabric --capacity-name cpfabric
```

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `401 / token` errors | Re-run `az login --tenant 711a9076-1115-4c36-b7b4-82b4f3a05f6f`. |
| Jobs rejected / stuck `NotStarted` | Capacity is paused — run the `az fabric capacity resume` command in Prerequisites. |
| Spark session cancelled, table not found | The notebook lost its lakehouse binding. Re-run **Step 1** — it re-injects the correct default lakehouse into every notebook. |
| Silver/gold wrote to the wrong lakehouse | Confirm the `lakehouse` field for that notebook in `cicd/fabric-setup.config.json`, then re-run Step 1. |
| `pl_bronze_ingestion not found` | Import the pipeline from `fabric/pipelines/pl_bronze_ingestion.json` (or run it once from the portal) so it exists in the workspace. |

---

## One-shot sequence (copy/paste)

```powershell
cd "c:\Users\chenalex\OneDrive - Microsoft\Documents\Microsoft Scout\OPS Fabric Workspace\geohazard-demo"
az fabric capacity resume --resource-group rg-fabric --capacity-name cpfabric

# 1. Push everything
pwsh ./scripts/fabric/setup_fabric_demo.ps1 -ConfigPath ./cicd/fabric-setup.config.json -OutputPath ./cicd/fabric-setup.output.json

# 2. Re-run bronze pipeline (see Step 2 block for the full polling script)

# 3. Run silver then gold
pwsh ./scripts/fabric/run_notebooks.ps1 -Notebooks silver_rf1_soil_susceptibility
pwsh ./scripts/fabric/run_notebooks.ps1 -Notebooks gold_rf1_risk_matrix
```
