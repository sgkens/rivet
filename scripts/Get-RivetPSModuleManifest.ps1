function Get-RivetPSModuleManifest {
    <#
    .SYNOPSIS
        Reads a module manifest and locates its literal top-level ModuleVersion.
    .DESCRIPTION
        Uses the PowerShell parser to preserve comments, formatting, and unrelated
        version fields when updating a manifest. Does not execute the manifest.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$Manifest)

    $Manifest = $Manifest.Replace('\', [System.IO.Path]::DirectorySeparatorChar).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    if ([System.IO.Path]::IsPathRooted($Manifest)) { throw 'psm.manifest must be relative to the repository root.' }
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, $Manifest))
    $relative = [System.IO.Path]::GetRelativePath($root, $path)
    if ($relative -eq '..' -or $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)")) { throw 'psm.manifest must stay inside the repository.' }
    if ([System.IO.Path]::GetExtension($path) -ine '.psd1') { throw 'psm.manifest must name a .psd1 file.' }
    $content = [System.IO.File]::ReadAllText($path)
    $parseTokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Invalid PowerShell manifest: $($parseErrors[0].Message)" }
    $tables = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false))
    if (-not $tables.Count) { throw 'Module manifest must contain a data hashtable.' }
    $entries = @($tables[0].KeyValuePairs | Where-Object { $_.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Item1.Value -ieq 'ModuleVersion' })
    if ($entries.Count -ne 1) { throw 'Manifest requires exactly one top-level ModuleVersion.' }
    $value = $entries[0].Item2
    $literal = $value.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $false)
    if ($null -eq $literal -or $value.Extent.Text.Trim() -ne $literal.Extent.Text) { throw 'ModuleVersion must be a quoted literal version.' }
    $data = Import-PowerShellDataFile -LiteralPath $path -ErrorAction Stop
    $version = [version]$data.ModuleVersion
    [pscustomobject]@{ Path = $path; RelativePath = $relative.Replace('\', '/'); Content = $content; Version = $version.ToString(); Start = $literal.Extent.StartOffset; End = $literal.Extent.EndOffset; Data = $data }
}
