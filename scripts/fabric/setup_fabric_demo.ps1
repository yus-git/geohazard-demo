param(
    [string]$ConfigPath = ".\cicd\fabric-setup.config.json",
    [string]$OutputPath = ".\cicd\fabric-setup.output.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AzAccessTokenValue {
    param([string]$Resource)

    $tokenObj = az account get-access-token --resource $Resource --output json | ConvertFrom-Json
    if (-not $tokenObj.accessToken) {
        throw "Failed to acquire access token for resource: $Resource"
    }
    return $tokenObj.accessToken
}

function Invoke-RestJson {
    param(
        [string]$Method,
        [string]$Url,
        [string]$AccessToken,
        [object]$Body = $null,
        [int]$TimeoutSec = 120
    )

    $headers = @{ Authorization = "Bearer $AccessToken" }
    $responseHeaders = $null

    if ($null -ne $Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 50
        $result = Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -ContentType "application/json" -Body $jsonBody -TimeoutSec $TimeoutSec -ResponseHeadersVariable responseHeaders
    }
    else {
        $result = Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -TimeoutSec $TimeoutSec -ResponseHeadersVariable responseHeaders
    }

    return @{
        Body = $result
        Headers = $responseHeaders
    }
}

function Wait-LroIfNeeded {
    param(
        [hashtable]$Response,
        [string]$AccessToken,
        [int]$MaxAttempts = 80
    )

    $location = $null
    if ($Response.Headers -and $Response.Headers.ContainsKey("Location")) {
        $location = $Response.Headers["Location"]
    }

    if (-not $location) {
        return $Response.Body
    }

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Start-Sleep -Seconds 3
        $poll = Invoke-RestJson -Method "GET" -Url $location -AccessToken $AccessToken
        $status = $null
        if ($poll.Body.PSObject.Properties.Name -contains "status") {
            $status = $poll.Body.status
        }

        if (-not $status) {
            if (($poll.Body.PSObject.Properties.Name -contains "id") -or ($poll.Body.PSObject.Properties.Name -contains "displayName")) {
                return $poll.Body
            }
            continue
        }

        if ($status -eq "Succeeded") {
            return $poll.Body
        }
        if ($status -eq "Failed") {
            throw "Long running operation failed. Poll body: $($poll.Body | ConvertTo-Json -Depth 20)"
        }
    }

    throw "Long running operation did not complete within polling limit."
}

function Get-Active-CapacityId {
    param([string]$FabricToken)

    $caps = Invoke-RestJson -Method "GET" -Url "https://api.fabric.microsoft.com/v1/capacities" -AccessToken $FabricToken
    $active = @($caps.Body.value) | Where-Object { $_.state -eq "Active" }
    if (-not $active -or $active.Count -eq 0) {
        return ""
    }

    $preferred = $active | Where-Object { $_.sku -like "F*" } | Select-Object -First 1
    if ($preferred) {
        return [string]$preferred.id
    }

    return [string]($active | Select-Object -First 1).id
}

function Get-OrCreate-Workspace {
    param(
        [string]$DisplayName,
        [string]$Description,
        [string]$CapacityId,
        [string]$FabricToken
    )

    $list = Invoke-RestJson -Method "GET" -Url "https://api.fabric.microsoft.com/v1/workspaces" -AccessToken $FabricToken
    $existing = @($list.Body.value) | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1

    if ($existing) {
        return $existing
    }

    $payload = @{
        displayName = $DisplayName
        description = $Description
    }

    if ($CapacityId) {
        $payload.capacityId = $CapacityId
    }

    try {
        $created = Invoke-RestJson -Method "POST" -Url "https://api.fabric.microsoft.com/v1/workspaces" -AccessToken $FabricToken -Body $payload
    }
    catch {
        $msg = $_.Exception.Message
        if ($CapacityId -and ($msg -match "CapacityNotInActiveState" -or $msg -match "Target capacity is not in active state")) {
            Write-Warning "CapacityId $CapacityId was rejected as inactive. Retrying workspace creation without explicit capacity assignment."
            $payload.Remove("capacityId")
            $created = Invoke-RestJson -Method "POST" -Url "https://api.fabric.microsoft.com/v1/workspaces" -AccessToken $FabricToken -Body $payload
        }
        else {
            throw
        }
    }

    $result = Wait-LroIfNeeded -Response $created -AccessToken $FabricToken

    if ($result.id) {
        return $result
    }

    # Fallback lookup after async creation.
    $refresh = Invoke-RestJson -Method "GET" -Url "https://api.fabric.microsoft.com/v1/workspaces" -AccessToken $FabricToken
    $found = @($refresh.Body.value) | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if (-not $found) {
        throw "Workspace creation response did not include id and workspace could not be found by name: $DisplayName"
    }
    return $found
}

function Get-OrCreate-Lakehouse {
    param(
        [string]$WorkspaceId,
        [string]$DisplayName,
        [string]$Description,
        [string]$FabricToken
    )

    $items = Invoke-RestJson -Method "GET" -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" -AccessToken $FabricToken
    $existing = @($items.Body.value) | Where-Object { $_.type -eq "Lakehouse" -and $_.displayName -eq $DisplayName } | Select-Object -First 1

    if ($existing) {
        return $existing
    }

    $payload = @{
        displayName = $DisplayName
        description = $Description
        type = "Lakehouse"
        creationPayload = @{
            enableSchemas = $true
        }
    }

    $created = Invoke-RestJson -Method "POST" -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" -AccessToken $FabricToken -Body $payload
    $result = Wait-LroIfNeeded -Response $created -AccessToken $FabricToken

    if ($result.id) {
        return $result
    }

    $refresh = Invoke-RestJson -Method "GET" -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" -AccessToken $FabricToken
    $found = @($refresh.Body.value) | Where-Object { $_.type -eq "Lakehouse" -and $_.displayName -eq $DisplayName } | Select-Object -First 1
    if (-not $found) {
        throw "Lakehouse creation response did not include id and item could not be found by name: $DisplayName"
    }
    return $found
}

function Get-OrCreate-DeploymentPipeline {
    param(
        [string]$DisplayName,
        [string]$Description,
        [string]$PowerBiToken
    )

    $list = Invoke-RestJson -Method "GET" -Url "https://api.powerbi.com/v1.0/myorg/pipelines" -AccessToken $PowerBiToken
    $existing = @($list.Body.value) | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($existing) {
        return $existing
    }

    $payload = @{
        displayName = $DisplayName
        description = $Description
    }

    $created = Invoke-RestJson -Method "POST" -Url "https://api.powerbi.com/v1.0/myorg/pipelines" -AccessToken $PowerBiToken -Body $payload
    return $created.Body
}

function Assign-Workspace-To-PipelineStage {
    param(
        [string]$PipelineId,
        [int]$StageOrder,
        [string]$WorkspaceId,
        [string]$PowerBiToken
    )

    $stages = Invoke-RestJson -Method "GET" -Url "https://api.powerbi.com/v1.0/myorg/pipelines/$PipelineId/stages" -AccessToken $PowerBiToken
    $targetStage = @($stages.Body.value) | Where-Object { $_.order -eq $StageOrder } | Select-Object -First 1
    if ($targetStage -and ($targetStage.PSObject.Properties.Name -contains "workspaceId") -and $targetStage.workspaceId) {
        if ([string]$targetStage.workspaceId -eq [string]$WorkspaceId) {
            return "already_assigned"
        }
        return "stage_occupied"
    }

    $payload = @{ workspaceId = $WorkspaceId }

    try {
        Invoke-RestJson -Method "POST" -Url "https://api.powerbi.com/v1.0/myorg/pipelines/$PipelineId/stages/$StageOrder/assignWorkspace" -AccessToken $PowerBiToken -Body $payload | Out-Null
        return "assigned"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match "already" -or $msg -match "Conflict" -or $msg -match "409" -or $msg -match "StageAlreadyHasWorkspace" -or $msg -match "Alm_InvalidRequest_StageAlreadyHasWorkspace") {
            return "already_assigned"
        }
        throw
    }
}

function Get-OrCreate-Notebook {
    param(
        [string]$WorkspaceId,
        [string]$LakehouseId,
        [string]$NotebookPath,
        [string]$NotebookDisplayName,
        [string]$FabricToken
    )

    if (-not (Test-Path $NotebookPath)) {
        Write-Warning "Notebook file not found at: $NotebookPath. Skipping notebook creation."
        return $null
    }

    $items = Invoke-RestJson -Method "GET" -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" -AccessToken $FabricToken
    $existing = @($items.Body.value) | Where-Object { $_.type -eq "Notebook" -and $_.displayName -eq $NotebookDisplayName } | Select-Object -First 1
    
    $notebookItem = $null
    if ($existing) {
        Write-Host "Notebook already exists: $NotebookDisplayName (ID: $($existing.id))" -ForegroundColor Green
        $notebookItem = $existing
    }
    else {
        $payload = @{
            displayName = $NotebookDisplayName
            description = "Bronze ingestion notebook for Fabric CI/CD demo - Lakehouse: $LakehouseId"
            type = "Notebook"
        }

        $created = Invoke-RestJson -Method "POST" -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items" -AccessToken $FabricToken -Body $payload
        $notebookItem = $created.Body

        if ($notebookItem -and $notebookItem.id) {
            Write-Host "Notebook created: $($notebookItem.displayName) (ID: $($notebookItem.id))" -ForegroundColor Green
        }
        else {
            Write-Warning "Notebook creation response did not include expected fields."
            return $null
        }
    }

    try {
        $notebookContent = Get-Content $NotebookPath -Raw
        $notebookJson = $notebookContent | ConvertFrom-Json
        
        $updatePayload = @{
            definition = @{
                format = "ipynb"
                parts = @(
                    @{
                        path = "notebook-content.ipynb"
                        payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                        payloadType = "InlineBase64"
                    }
                )
            }
        }

        $updateUrl = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$($notebookItem.id)/updateDefinition"
        Invoke-RestJson -Method "POST" -Url $updateUrl -AccessToken $FabricToken -Body $updatePayload | Out-Null
        Write-Host "Notebook content imported successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Note: Notebook content import not yet supported via this API version. Notebook item created but is empty." -ForegroundColor Yellow
        Write-Host "Please manually add cells or use Fabric UI to import the notebook file." -ForegroundColor Yellow
    }

    return $notebookItem
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$fabricToken = Get-AzAccessTokenValue -Resource "https://api.fabric.microsoft.com"
$powerBiToken = Get-AzAccessTokenValue -Resource "https://analysis.windows.net/powerbi/api"

$capacityId = [string]$config.capacityId
if ([string]::IsNullOrWhiteSpace($capacityId)) {
    $capacityId = Get-Active-CapacityId -FabricToken $fabricToken
}

if ([string]::IsNullOrWhiteSpace($capacityId)) {
    Write-Warning "No active capacity was auto-detected. Workspace creation will proceed without explicit capacityId."
}
else {
    Write-Output "Using capacityId: $capacityId"
}

$workspaceName = [string]$config.workspaceName
if ([string]::IsNullOrWhiteSpace($workspaceName)) {
    $workspacePrefix = [string]$config.workspacePrefix
    if (-not [string]::IsNullOrWhiteSpace($workspacePrefix)) {
        $workspaceName = "$workspacePrefix-dev"
    }
}

if ([string]::IsNullOrWhiteSpace($workspaceName)) {
    throw "Config must provide workspaceName (or legacy workspacePrefix)."
}

$workspaceDescription = [string]$config.workspaceDescription
$workspace = Get-OrCreate-Workspace -DisplayName $workspaceName -Description $workspaceDescription -CapacityId $capacityId -FabricToken $fabricToken

$lakehouseResults = @()
$primaryLakehouseId = ""
foreach ($lh in $config.lakehouses) {
    $lakehouse = Get-OrCreate-Lakehouse -WorkspaceId $workspace.id -DisplayName ([string]$lh.displayName) -Description ([string]$lh.description) -FabricToken $fabricToken
    $lakehouseResults += [PSCustomObject]@{
        displayName = $lakehouse.displayName
        id = $lakehouse.id
        type = $lakehouse.type
    }
    if ([string]::IsNullOrWhiteSpace($primaryLakehouseId)) {
        $primaryLakehouseId = $lakehouse.id
    }
}

$notebookResults = @()
if ($config.PSObject.Properties.Name -contains "notebooks" -and $config.notebooks -and $primaryLakehouseId) {
    foreach ($nb in $config.notebooks) {
        $notebookPath = [string]$nb.localPath
        $notebookName = [string]$nb.displayName
        $absolutePath = Join-Path (Get-Location) $notebookPath
        $notebook = Get-OrCreate-Notebook -WorkspaceId $workspace.id -LakehouseId $primaryLakehouseId -NotebookPath $absolutePath -NotebookDisplayName $notebookName -FabricToken $fabricToken
        if ($notebook -and ($notebook.PSObject.Properties.Name -contains "displayName")) {
            $notebookResults += [PSCustomObject]@{
                displayName = [string]$notebook.displayName
                id = [string]$notebook.id
                type = [string]$notebook.type
            }
        }
    }
}

$workspaceResult = [PSCustomObject]@{
    workspaceName = $workspace.displayName
    workspaceId = $workspace.id
    capacityId = $workspace.capacityId
    lakehouses = $lakehouseResults
    notebooks = $notebookResults
}

$pipelineCfg = $config.deploymentPipeline
$pipeline = Get-OrCreate-DeploymentPipeline -DisplayName ([string]$pipelineCfg.displayName) -Description ([string]$pipelineCfg.description) -PowerBiToken $powerBiToken

$stage0State = Assign-Workspace-To-PipelineStage -PipelineId $pipeline.id -StageOrder 0 -WorkspaceId $workspaceResult.workspaceId -PowerBiToken $powerBiToken

$output = [PSCustomObject]@{
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    workspaceName = $workspaceName
    capacityId = $capacityId
    deploymentPipeline = [PSCustomObject]@{
        id = $pipeline.id
        displayName = $pipeline.displayName
    }
    workspace = $workspaceResult
    stage0Assignment = [PSCustomObject]@{
        stageOrder = 0
        workspaceName = $workspaceResult.workspaceName
        workspaceId = $workspaceResult.workspaceId
        status = $stage0State
    }
    note = "Single-workspace demo mode: stage 0 is assigned. To perform actual cross-stage deployment, assign additional workspaces to later stages."
}

$output | ConvertTo-Json -Depth 50 | Set-Content -Path $OutputPath
Write-Output "Fabric setup completed. Output saved to: $OutputPath"
Write-Output ($output | ConvertTo-Json -Depth 50)
