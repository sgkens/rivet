function Get-RivetProfile {
    <#
    .SYNOPSIS
        Resolves an installed repository profile, defaulting legacy configuration to jsm.
    .DESCRIPTION
        Loads only profiles/<name>/profile.ps1 from the Rivet installation and
        validates the handler contract. Repository configuration never supplies code paths.
    #>
    [CmdletBinding()]
    param([string]$Name, [AllowNull()][object]$Config)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $property = if ($null -ne $Config) { $Config.PSObject.Properties['profile'] } else { $null }
        $Name = if ($null -ne $property) { [string]$property.Value } else { 'jsm' }
    }
    if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]*$') { throw "Invalid repository profile '$Name'. Use a lowercase profile name." }
    $path = [System.IO.Path]::Combine($PSScriptRoot, '..', 'profiles', $Name, 'profile.ps1')
    if (-not [System.IO.File]::Exists($path)) { throw "Unknown repository profile '$Name'. Install profiles/$Name/profile.ps1 in Rivet." }
    $definition = & $path
    if ($definition -isnot [hashtable]) { throw "Profile '$Name' must return one hashtable." }
    foreach ($handler in @('ValidateConfig', 'Identity', 'Templates', 'UpdateVersion', 'ReadVersion', 'UpdateHeader', 'Checks', 'ReleaseFiles', 'ReviewVersions', 'ReleaseChecklist')) {
        if ($definition[$handler] -isnot [scriptblock]) { throw "Profile '$Name' requires a $handler scriptblock." }
    }
    if (-not $definition.ContainsKey('TemplateRoot') -or -not [System.IO.Directory]::Exists([string]$definition.TemplateRoot)) {
        throw "Profile '$Name' requires an existing TemplateRoot directory."
    }
    $definition.Name = $Name
    return $definition
}
