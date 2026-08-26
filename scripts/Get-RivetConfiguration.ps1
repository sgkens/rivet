function Get-RivetConfiguration {
    <#
    .SYNOPSIS
        Loads and validates reusable rivet repository configuration.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    $fullPath = [System.IO.Path]::GetFullPath($ConfigPath)
    if (-not [System.IO.File]::Exists($fullPath)) { throw "rivet configuration not found: $fullPath" }
    try { $config = [System.IO.File]::ReadAllText($fullPath) | ConvertFrom-Json -Depth 32 } catch { throw "Invalid rivet JSON configuration: $($_.Exception.Message)" }
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($requirement in @(
        @{ Path = 'project.displayName'; Value = $config.project.displayName },
        @{ Path = 'project.path'; Value = $config.project.path },
        @{ Path = 'gitlab.baseUri'; Value = $config.gitlab.baseUri },
        @{ Path = 'tagging.remote'; Value = $config.tagging.remote },
        @{ Path = 'tagging.releaseSuffix'; Value = $config.tagging.releaseSuffix },
        @{ Path = 'commit.defaultType'; Value = $config.commit.defaultType },
        @{ Path = 'commit.defaultScope'; Value = $config.commit.defaultScope }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$requirement.Value)) { $errors.Add("Missing $($requirement.Path)") }
    }
    if (-not @($config.commit.types).Count) { $errors.Add('commit.types must contain at least one entry') }
    if (-not @($config.commit.scopes).Count) { $errors.Add('commit.scopes must contain at least one entry') }
    if (-not @($config.readme.requiredHeadings).Count) { $errors.Add('readme.requiredHeadings must contain at least one entry') }
    foreach ($heading in @($config.readme.requiredHeadings)) {
        if ([int]$heading.level -lt 1 -or [int]$heading.level -gt 6 -or [string]::IsNullOrWhiteSpace([string]$heading.name)) {
            $errors.Add('Each readme.requiredHeadings entry requires level 1-6 and a non-empty name')
            break
        }
    }
    if ($errors.Count) { throw "Invalid rivet configuration:`n - $($errors -join "`n - ")" }
    return $config
}

function Resolve-GitLabAuthorReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Email = ''
    )

    $authorProperty = $Config.PSObject.Properties['authors']
    $mappings = if ($null -ne $authorProperty -and $null -ne $Config.authors.PSObject.Properties['mappings']) { @($Config.authors.mappings) } else { @() }
    foreach ($mapping in $mappings) {
        if (-not [string]::IsNullOrWhiteSpace($Email) -and [string]$mapping.email -ieq $Email) {
            $username = ([string]$mapping.username).TrimStart('@')
            if ($username -match '^[A-Za-z0-9_.-]+$') { return "@$username" }
        }
    }
    if ($Name -match '^[A-Za-z0-9_.-]+$') { return "@$Name" }
    return $Name
}
