function Invoke-GitLabMergeRequest {
    <#
    .SYNOPSIS
        Creates or updates a GitLab merge request from repository-root mr.md.
    .DESCRIPTION
        Parses the generated title, source branch, target branch, and complete
        Markdown body. Update mode selects the matching open merge request by
        source and target branch. Tokens are read from repository configuration
        and are never written to output.
    .EXAMPLE
        Invoke-GitLabMergeRequest -RepositoryRoot $PWD -ConfigPath ./repo_config.json -Mode Create -DryRun
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][ValidateSet('Create', 'Update')][string]$Mode,
        [switch]$DryRun
    )

    $config = Get-RivetConfiguration -ConfigPath $ConfigPath
    $documentPath = [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($RepositoryRoot), 'mr.md')
    if (-not [System.IO.File]::Exists($documentPath)) { throw "Merge-request document not found: $documentPath" }
    $content = [System.IO.File]::ReadAllText($documentPath)

    function Read-MrSection([string]$Name) {
        $match = [regex]::Match($content, "(?ms)^## $([regex]::Escape($Name))\s*\r?\n\s*(.+?)(?=\r?\n## |\z)")
        if (-not $match.Success) { throw "mr.md is missing the '## $Name' section." }
        return $match.Groups[1].Value.Trim()
    }

    $title = Read-MrSection 'Title'
    $sourceBranch = (Read-MrSection 'Source branch').Trim('`').Trim()
    $targetBranch = (Read-MrSection 'Target branch').Trim('`').Trim()
    if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($sourceBranch) -or [string]::IsNullOrWhiteSpace($targetBranch)) {
        throw 'mr.md must define non-empty Title, Source branch, and Target branch sections.'
    }
    $description = [regex]::Replace($content, '(?ms)^# Merge Request\s*.*?(?=^## Change range)', '').Trim()

    $baseUri = ([string]$config.gitlab.baseUri).TrimEnd('/')
    $projectId = [string]$config.gitlab.projectId
    $projectPath = [string]$config.project.path
    $projectKey = if ([string]::IsNullOrWhiteSpace($projectId)) { [uri]::EscapeDataString($projectPath) } else { $projectId }
    $tokenVariable = [string]$config.gitlab.tokenEnvironmentVariable
    if ([string]::IsNullOrWhiteSpace($tokenVariable)) { $tokenVariable = 'GITLAB_API_KEY' }
    $token = [System.Environment]::GetEnvironmentVariable($tokenVariable)
    if ([string]::IsNullOrWhiteSpace($token)) { throw "GitLab token not found. Set '$tokenVariable'." }
    $headers = @{ 'PRIVATE-TOKEN' = $token; Accept = 'application/json' }
    $apiRoot = "$baseUri/api/v4/projects/$projectKey/merge_requests"
    $timeout = [int]$config.requestTimeoutSeconds
    if ($timeout -lt 1) { $timeout = 30 }

    $query = "state=opened&source_branch=$([uri]::EscapeDataString($sourceBranch))&target_branch=$([uri]::EscapeDataString($targetBranch))"
    $matches = @(Invoke-RestMethod -Method Get -Uri "$apiRoot`?$query" -Headers $headers -TimeoutSec $timeout)
    if ($Mode -eq 'Create' -and $matches.Count) {
        throw "An open merge request already exists for '$sourceBranch' into '$targetBranch' (iid $($matches[0].iid)); use update mode."
    }
    if ($Mode -eq 'Update' -and $matches.Count -eq 0) {
        throw "No open merge request exists for '$sourceBranch' into '$targetBranch'; use create mode."
    }
    if ($matches.Count -gt 1) { throw "More than one open merge request matches '$sourceBranch' into '$targetBranch'." }

    $operation = if ($Mode -eq 'Create') { 'create' } else { "update iid $($matches[0].iid)" }
    if ($DryRun) {
        [Console]::WriteLine("Would $operation merge request '$title' from $sourceBranch into $targetBranch.")
        return [pscustomobject]@{ Mode = $Mode; Title = $title; SourceBranch = $sourceBranch; TargetBranch = $targetBranch; Applied = $false; Iid = if ($matches.Count) { $matches[0].iid } else { $null } }
    }

    $body = @{ title = $title; description = $description; source_branch = $sourceBranch; target_branch = $targetBranch; remove_source_branch = $true }
    $uri = if ($Mode -eq 'Create') { $apiRoot } else { "$apiRoot/$($matches[0].iid)" }
    $method = if ($Mode -eq 'Create') { 'Post' } else { 'Put' }
    $response = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 4 -Compress) -TimeoutSec $timeout
    [Console]::WriteLine("GitLab merge request !$($response.iid) $($Mode.ToLowerInvariant())d: $($response.web_url)")
    return [pscustomobject]@{ Mode = $Mode; Title = $title; SourceBranch = $sourceBranch; TargetBranch = $targetBranch; Applied = $true; Iid = $response.iid; WebUrl = $response.web_url }
}
