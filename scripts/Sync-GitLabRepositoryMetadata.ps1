<#
.SYNOPSIS
    Synchronizes GitLab project topics, description, and labels.

.DESCRIPTION
    Reads repository-root repo_config.json and repo_meta.json. It
    synchronizes project topics, the project description, and project labels
    with their descriptions and visual properties.
    This script does not create Git tags or releases.
    Authentication is read from the configured environment variable, never
    from the non-sensitive JSON configuration.

.PARAMETER ConfigPath
    Path to repository-root repo_config.json.

.PARAMETER AccessToken
    Optional GitLab token. Prefer the configured environment variable.

.PARAMETER DryRun
    Reports create/update/delete operations without changing GitLab.

.PARAMETER DeleteMissing
    Deletes project labels absent from the source catalog. Disabled by default.

.EXAMPLE
    ./tools/glmeta/scripts/Sync-GitLabRepositoryMetadata.ps1 -DryRun

.EXAMPLE
    $env:GITLAB_TOKEN = 'token-from-secure-secret-store'
    ./tools/glmeta/scripts/Sync-GitLabRepositoryMetadata.ps1
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ConfigPath,

    [string]$AccessToken,

    [switch]$DryRun,

    [switch]$DeleteMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([Parameter(Mandatory)][ValidateScript({ [System.IO.File]::Exists($_) })][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($fullPath))
    try {
        return $document.RootElement.Clone()
    } finally {
        $document.Dispose()
    }
}

function Get-JsonProperty {
    param(
        [Parameter(Mandatory)][System.Text.Json.JsonElement]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $property = [System.Text.Json.JsonElement]::new()
    if ($Object.ValueKind -eq [System.Text.Json.JsonValueKind]::Object -and $Object.TryGetProperty($Name, [ref]$property)) {
        return $property
    }

    return $null
}

function Get-JsonString {
    param(
        [Parameter(Mandatory)][System.Text.Json.JsonElement]$Object,
        [Parameter(Mandatory)][string]$Name,
        [string]$Default = ''
    )

    $property = Get-JsonProperty -Object $Object -Name $Name
    if ($null -ne $property -and $property.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
        return $property.GetString()
    }

    return $Default
}

function Resolve-PathFrom {
    param([Parameter(Mandatory)][string]$BasePath, [Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($BasePath, $Path))
}

function Get-AccessToken {
    param([Parameter(Mandatory)][System.Text.Json.JsonElement]$GitLab, [string]$ExplicitToken)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitToken)) { return $ExplicitToken }
    $variableName = Get-JsonString -Object $GitLab -Name 'tokenEnvironmentVariable' -Default 'GITLAB_TOKEN'
    $token = [System.Environment]::GetEnvironmentVariable($variableName)
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "GitLab token not found. Set '$variableName' or pass -AccessToken."
    }
    return $token
}

function Invoke-GitLabRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [hashtable]$Body
    )

    $request = @{
        Method     = $Method
        Uri        = $Uri
        Headers    = $Headers
        TimeoutSec = $script:TimeoutSeconds
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $jsonOptions = [System.Text.Json.JsonSerializerOptions]::new()
        $request.Body = [System.Text.Json.JsonSerializer]::Serialize(
            [object]$Body,
            $Body.GetType(),
            $jsonOptions
        )
    }
    return Invoke-RestMethod @request
}

function Get-ProjectLabels {
    param([Parameter(Mandatory)][string]$ApiRoot, [Parameter(Mandatory)][string]$ProjectKey, [Parameter(Mandatory)][hashtable]$Headers)

    $labels = [System.Collections.Generic.List[object]]::new()
    $page = 1
    do {
        $responseHeaders = $null
        $uri = "$ApiRoot/projects/$ProjectKey/labels?per_page=100&page=$page"
        $pageItems = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec $script:TimeoutSeconds -ResponseHeadersVariable responseHeaders
        foreach ($item in $pageItems) { [void]$labels.Add($item) }
        $nextPage = if ($null -ne $responseHeaders -and $responseHeaders.ContainsKey('X-Next-Page')) { $responseHeaders['X-Next-Page'] } else { '' }
        $page = if ([string]::IsNullOrWhiteSpace($nextPage)) { 0 } else { [int]$nextPage }
    } while ($page -gt 0)
    return $labels
}

function New-LabelBody {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [string]$Color = '#808080',
        [string]$TextColor = '#FFFFFF'
    )

    return @{
        name        = $Name
        description = $Description
        color       = $Color
        text_color  = $TextColor
    }
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $gitRoot = @(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $gitRoot.Count) { throw 'Unable to resolve the consuming Git repository root.' }
    $ConfigPath = [System.IO.Path]::Combine(([string]$gitRoot[0]).Trim(), 'repo_config.json')
}
$configFullPath = [System.IO.Path]::GetFullPath($ConfigPath)
$config = Read-JsonFile -Path $configFullPath
$configDirectory = [System.IO.Path]::GetDirectoryName($configFullPath)
$gitlab = Get-JsonProperty -Object $config -Name 'gitlab'
$projectConfig = Get-JsonProperty -Object $config -Name 'project'
$metadataSource = Resolve-PathFrom -BasePath $configDirectory -Path (Get-JsonString -Object $config -Name 'metadataSource' -Default 'repo_meta.json')
$metadata = Read-JsonFile -Path $metadataSource
$projectMetadata = Get-JsonProperty -Object $metadata -Name 'project'
$labels = Get-JsonProperty -Object $metadata -Name 'labels'
$topics = Get-JsonProperty -Object $projectMetadata -Name 'topics'
$labelScope = Get-JsonString -Object $config -Name 'labelScope' -Default 'project'
if ($labelScope -ne 'project') { throw "Only project-scoped labels are supported; configured scope was '$labelScope'." }
$metadataScope = Get-JsonString -Object $metadata -Name 'scope' -Default 'project'
if ($metadataScope -ne 'project') { throw "Repository metadata must declare scope 'project'; configured scope was '$metadataScope'." }
$baseUri = (Get-JsonString -Object $gitlab -Name 'baseUri' -Default 'https://gitlab.com').TrimEnd('/')
$projectId = Get-JsonString -Object $gitlab -Name 'projectId'
$projectPath = Get-JsonString -Object $projectConfig -Name 'path'
if ([string]::IsNullOrWhiteSpace($projectId) -and [string]::IsNullOrWhiteSpace($projectPath)) {
    throw 'Configure gitlab.projectId or project.path before running the generator.'
}
$projectKey = if ([string]::IsNullOrWhiteSpace($projectId)) { [Uri]::EscapeDataString($projectPath) } else { $projectId }
$script:TimeoutSeconds = [int](Get-JsonString -Object $config -Name 'requestTimeoutSeconds' -Default '30')
$defaultTextColor = Get-JsonString -Object $config -Name 'defaultTextColor' -Default '#FFFFFF'
$headers = @{ 'PRIVATE-TOKEN' = (Get-AccessToken -GitLab $gitlab -ExplicitToken $AccessToken); Accept = 'application/json' }
$apiRoot = "$baseUri/api/v4"
$project = Invoke-GitLabRequest -Method Get -Uri "$apiRoot/projects/$projectKey" -Headers $headers
$desiredTopics = [System.Collections.Generic.List[string]]::new()
foreach ($topic in $topics.EnumerateArray()) {
    $topicName = if ($topic.ValueKind -eq [System.Text.Json.JsonValueKind]::String) { $topic.GetString() } else { '' }
    if ([string]::IsNullOrWhiteSpace($topicName)) { throw 'Every topic must be a non-empty string.' }
    if (-not $desiredTopics.Contains($topicName)) { [void]$desiredTopics.Add($topicName) }
}
$currentTopics = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($topic in @($project.topics)) { [void]$currentTopics.Add([string]$topic) }
$topicsChanged = $currentTopics.Count -ne $desiredTopics.Count
if (-not $topicsChanged) {
    foreach ($topicName in $desiredTopics) {
        if (-not $currentTopics.Contains($topicName)) { $topicsChanged = $true; break }
    }
}
$projectUpdate = @{}
if ($topicsChanged) { $projectUpdate.topics = $desiredTopics.ToArray() }
$projectDescription = Get-JsonString -Object $projectMetadata -Name 'description'
if (-not [string]::IsNullOrWhiteSpace($projectDescription) -and [string]$project.description -ne $projectDescription) {
    $projectUpdate.description = $projectDescription
}
if ($projectUpdate.Count -gt 0) {
    $projectAction = 'Synchronize project topics and description'
    if ($DryRun) {
        if ($topicsChanged) { Write-Output "DRY-RUN: Synchronize $($desiredTopics.Count) project topics" }
        if ($projectUpdate.ContainsKey('description')) { Write-Output 'DRY-RUN: Update project description' }
    } elseif ($PSCmdlet.ShouldProcess("GitLab project $projectPath", $projectAction)) {
        [void](Invoke-GitLabRequest -Method Put -Uri "$apiRoot/projects/$projectKey" -Headers $headers -Body $projectUpdate)
        if ($topicsChanged) { Write-Output "Synchronized $($desiredTopics.Count) project topics" }
        if ($projectUpdate.ContainsKey('description')) { Write-Output 'Updated project description' }
    }
}
$existing = Get-ProjectLabels -ApiRoot $apiRoot -ProjectKey $projectKey -Headers $headers
$existingByName = @{}
foreach ($label in $existing) { $existingByName[[string]$label.name] = $label }
$sourceNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($label in $labels.EnumerateArray()) {
    $name = Get-JsonString -Object $label -Name 'name'
    if ([string]::IsNullOrWhiteSpace($name)) { throw 'Every label must have a non-empty name.' }
    $description = Get-JsonString -Object $label -Name 'description'
    $color = Get-JsonString -Object $label -Name 'color' -Default '#808080'
    $textColor = Get-JsonString -Object $label -Name 'textColor' -Default $defaultTextColor
    $body = New-LabelBody -Name $name -Description $description -Color $color -TextColor $textColor
    [void]$sourceNames.Add($name)
    $uri = "$apiRoot/projects/$projectKey/labels"

    if ($existingByName.ContainsKey($name)) {
        # GitLab requires name or label_id to identify the label on update.
        # The catalog currently preserves names, so use the stable name key.
        $action = "Update project label '$name'"
        if ($DryRun) { Write-Output "DRY-RUN: $action"; continue }
        if ($PSCmdlet.ShouldProcess("GitLab project $projectPath", $action)) {
            [void](Invoke-GitLabRequest -Method Put -Uri $uri -Headers $headers -Body $body)
            Write-Output "Updated: $name"
        }
    } else {
        $action = "Create project label '$name'"
        if ($DryRun) { Write-Output "DRY-RUN: $action"; continue }
        if ($PSCmdlet.ShouldProcess("GitLab project $projectPath", $action)) {
            [void](Invoke-GitLabRequest -Method Post -Uri $uri -Headers $headers -Body $body)
            Write-Output "Created: $name"
        }
    }
}

if ($DeleteMissing) {
    foreach ($label in $existing) {
        if (-not $sourceNames.Contains([string]$label.name)) {
            $encodedName = [Uri]::EscapeDataString([string]$label.name)
            $uri = "$apiRoot/projects/$projectKey/labels/$encodedName"
            $action = "Delete project label '$($label.name)'"
            if ($DryRun) { Write-Output "DRY-RUN: $action"; continue }
            if ($PSCmdlet.ShouldProcess("GitLab project $projectPath", $action)) {
                [void](Invoke-GitLabRequest -Method Delete -Uri $uri -Headers $headers)
                Write-Output "Deleted: $($label.name)"
            }
        }
    }
}
