# Deploy the Geohazard Demo — Manual (Beginner Guide)

This is the **point-and-click path**. You'll build the demo by clicking through the
Microsoft Fabric website — no commands, no scripts (except one small step to turn the
compute on/off). It's slower than the automated guide but you can *see* every piece as
you create it.

> **Who this is for:** Someone who has never used Microsoft Fabric and would rather
> click buttons in a browser than run terminal commands.
>
> **Time needed:** about 60–90 minutes.
>
> **Want the fast, command-driven version instead?** Use
> [DEPLOY_AUTOMATED.md](DEPLOY_AUTOMATED.md).

---

## Vocabulary (read this once)

| Term | Plain-English meaning |
| --- | --- |
| **Microsoft Fabric** | The online data platform. You use it in your browser at <https://app.fabric.microsoft.com>. |
| **Workspace** | A folder that holds all the demo's pieces. Ours is `Englobecorp_Geohazard`. |
| **Lakehouse** | Where data tables live. We make three: `bronze_lakehouse` (raw), `silver_lakehouse` (cleaned), `gold_lakehouse` (final). |
| **Notebook** | A document of code cells that processes data. You import the `.ipynb` files from the `fabric/notebooks/` folder. |
| **Default lakehouse** | The lakehouse a notebook reads from and writes to. **Setting this correctly is the #1 thing people get wrong.** This guide walks you through it. |
| **Capacity** | The rented compute power. It costs money while **on**, so we turn it off at the end. |

> **The golden rule:** every notebook must have the **right default lakehouse** attached
> before you run it (bronze notebooks → `bronze_lakehouse`, silver → `silver_lakehouse`,
> gold → `gold_lakehouse`). If you skip this, the notebook fails with a "table not found"
> error. Part 4 shows you exactly how.

---

## Before you start — fill in YOUR details

A few values are **different for every person**. Find yours (ask your Azure/Fabric admin
if unsure) and write them here so you can use them in the steps below:

| Placeholder you'll see | Means | Your value (write it here) |
| --- | --- | --- |
| `<YOUR-TENANT-ID>` | Your organization's Azure tenant (directory) ID — looks like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | ____________________ |
| `<YOUR-RESOURCE-GROUP>` | The Azure resource group that holds the Fabric capacity | ____________________ |
| `<YOUR-CAPACITY-NAME>` | The name of the Fabric capacity (compute) | ____________________ |
| `<YOUR-WORKSPACE-NAME>` | What you'll name your workspace. You can keep the demo default `Englobecorp_Geohazard`, or pick your own. | ____________________ |
| `<PATH-TO-PROJECT-FOLDER>` | The full folder path where this project lives on your computer | ____________________ |

> **How to use this:** wherever you see something in `<ANGLE BRACKETS>`, swap in your own
> value (and remove the brackets). If you keep the default workspace name, just use
> `Englobecorp_Geohazard` wherever it says `<YOUR-WORKSPACE-NAME>`.

---

## The pieces you'll build

| Layer | Lakehouse to create | Notebooks to import (from `fabric/notebooks/`) |
| --- | --- | --- |
| Bronze | `bronze_lakehouse` | `bronze_pc_collections`, `bronze_bc_surficial_geology`, `bronze_bc_soil_survey`, `bronze_data_overview`, `bronze_planetary_ingestion` |
| Silver | `silver_lakehouse` | `silver_rf1_soil_susceptibility` |
| Gold | `gold_lakehouse` | `gold_rf1_risk_matrix` |

The notebook files are already on your computer in this folder (yours may differ):

```
<PATH-TO-PROJECT-FOLDER>\fabric\notebooks\
```

---

## Part 1 — Turn the capacity on

Fabric jobs won't run unless the compute power is on. This is the only command step in
the manual guide.

1. Open the **Start menu**, type **PowerShell**, and open **Windows PowerShell**.
2. Paste this and press **Enter** (swap in your own values; sign in via the browser
   pop-up if asked):

   ```powershell
   az login --tenant <YOUR-TENANT-ID>
   az fabric capacity resume --resource-group <YOUR-RESOURCE-GROUP> --capacity-name <YOUR-CAPACITY-NAME>
   ```

> **Don't have the `az` tool?** Install it from <https://aka.ms/installazurecliwindows>,
> then reopen PowerShell and try again. (Or ask whoever manages your Fabric capacity to
> make sure it's **Active**, and skip this command entirely.)

---

## Part 2 — Create the workspace

1. Go to <https://app.fabric.microsoft.com> and sign in with your work account.
2. On the far left, click **Workspaces**, then **+ New workspace**.
3. **Name** it `<YOUR-WORKSPACE-NAME>` (the demo default is `Englobecorp_Geohazard`).
4. Expand **Advanced**, choose **Fabric capacity** (pick `<YOUR-CAPACITY-NAME>` if
   listed), and click **Apply**.

You now have an empty workspace. Everything else goes inside it.

---

## Part 3 — Create the three lakehouses

Do this **three times**, once for each lakehouse name in the table above.

1. Inside the workspace, click **+ New item** (top-left).
2. Search for and choose **Lakehouse**.
3. Type the name (`bronze_lakehouse`), then click **Create**.
4. Repeat for `silver_lakehouse` and `gold_lakehouse`.

When done, your workspace lists three lakehouses.

---

## Part 4 — Import the notebooks and attach their lakehouses

You'll import all **7 notebooks**, then attach the correct default lakehouse to each.

### 4.1 Import a notebook

1. In the workspace, click **+ New item → Import notebook** (or **Import → Notebook**).
2. Click **Upload**, browse to the `fabric\notebooks\` folder, and pick one `.ipynb`
   file (for example `bronze_pc_collections.ipynb`).
3. Click **Open / Import**. The notebook appears in the workspace.
4. Repeat until all **7** notebooks are imported.

### 4.2 Attach the right default lakehouse (do this for every notebook)

This is the critical step. For **each** notebook:

1. Open the notebook by clicking its name.
2. On the left edge of the notebook, find the **Lakehouses** panel (a small database/
   stack icon). Click it to expand.
3. Click **Add** (or **+**), choose **Existing lakehouse**, and pick the lakehouse that
   matches the notebook's layer:
   - Notebook name starts with `bronze_` → pick **`bronze_lakehouse`**
   - Notebook name starts with `silver_` → pick **`silver_lakehouse`**
   - Notebook name starts with `gold_` → pick **`gold_lakehouse`**
4. Make sure it shows as the **pinned / default** lakehouse (there's a pin or star icon —
   the default has it filled in). If you added the wrong one, remove it and add the
   correct one.

> **Double-check:** When a notebook is open, the lakehouse shown in the panel must match
> its name prefix. Bronze with `silver_lakehouse` attached = it will fail.

---

## Part 5 — Run the notebooks in the correct order

Order matters: **bronze first, then silver, then gold.** Each stage needs the tables the
previous stage created.

### 5.1 Run the bronze notebooks

Open and run each of these (in any order among themselves):

1. `bronze_pc_collections`
2. `bronze_bc_surficial_geology`
3. `bronze_bc_soil_survey`
4. `bronze_data_overview`

To run a notebook: open it, then click **Run all** at the top. Wait until every cell
shows a green check. The first run is slow (it starts a Spark session) — that's normal.

> `bronze_planetary_ingestion` is an optional standalone example — you don't need it for
> the main flow, but you can run it the same way if you'd like.

**Confirm bronze worked:** open `bronze_lakehouse` → **Tables**. You should see several
new tables. If so, continue.

### 5.2 Run the silver notebook

1. Open `silver_rf1_soil_susceptibility`.
2. Click **Run all** and wait for all green checks.
3. Confirm: open `silver_lakehouse` → **Tables** → you should see
   `silver_rf1_soil_susceptibility`.

### 5.3 Run the gold notebook

1. Open `gold_rf1_risk_matrix`.
2. Click **Run all** and wait for all green checks.
3. Confirm: open `gold_lakehouse` → **Tables** → you should see
   `gold_rf1_risk_pixels`, `gold_rf1_risk_matrix`, and `gold_rf1_band_summary`.

If those three gold tables exist, **the demo is fully deployed.** 🎉

---

## Part 6 — (Optional) Import the pipeline

The bronze notebooks can also be run together by a pipeline. To set it up:

1. In the workspace, click **+ New item → Data pipeline**, name it `pl_bronze_ingestion`,
   and click **Create**.
2. Use **Import** if your Fabric version offers it, and select
   `fabric\pipelines\pl_bronze_ingestion.json`. Otherwise, this step is optional —
   running the notebooks by hand (Part 5) produces the same result.

---

## Part 7 — Turn the capacity off (important — saves money)

When finished, return to PowerShell and run (with your own values):

```powershell
az fabric capacity suspend --resource-group <YOUR-RESOURCE-GROUP> --capacity-name <YOUR-CAPACITY-NAME>
```

---

## Troubleshooting

| What you see | What it means | What to do |
| --- | --- | --- |
| `Table or view not found` | The notebook has the wrong (or no) default lakehouse | Redo **Part 4.2** for that notebook — attach the lakehouse matching its name prefix. |
| Cells never finish / "waiting for Spark" | Capacity is off, or the first session is just slow | Confirm Part 1 ran. The very first run per session takes a couple minutes — wait it out. |
| A bronze table is missing in silver/gold | Bronze didn't fully run | Go back and re-run the bronze notebooks (Part 5.1) until all cells are green. |
| A red error in one cell | That step failed | Read the red message at the bottom of the failed cell; it usually names the missing table or a connection issue. Re-run that notebook. |
| Can't find the workspace | Wrong account or it wasn't created | Make sure you're signed in with the same work account and that Part 2 completed. |

---

## Why the order matters (optional reading)

The demo is a **medallion architecture**: raw data lands in **bronze**, gets cleaned and
scored in **silver**, and becomes the final risk answers in **gold**. Each layer reads
the tables the previous layer wrote, which is why you run them bronze → silver → gold and
why each notebook must point at its own lakehouse.
