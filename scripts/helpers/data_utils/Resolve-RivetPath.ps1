function Resolve-RivetPath {
    <#
    .SYNOPSIS
        Resolves canonical .rivet/ artifact and configuration file paths with fallback to repository root.
    .DESCRIPTION
        Checks if the item exists within the .rivet/ subdirectory first. If present, returns
        the .rivet/ path. If present in the repository root, returns the root path for backwards
        compatibility. If neither exists, returns the .rivet/ path by default (ensuring new files
        are placed cleanly inside .rivet/).
    .PARAMETER RepositoryRoot
        Root path of the Git repository.
    .PARAMETER ItemName
        Name of the file or directory (e.g. 'repo_config.json', 'repo_meta.json', 'mr.md', 'work-items').
    .PARAMETER ForceRoot
        Forces returning the repository root path regardless of .rivet/ presence.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$RepositoryRoot,
        [Parameter(Mandatory, Position = 1)][string]$ItemName,
        [switch]$ForceRoot
    )

    $repoPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $cleanItemName = $ItemName.TrimStart('/', '\')

    if ($ForceRoot) {
        return [System.IO.Path]::Combine($repoPath, $cleanItemName)
    }

    $dotRivetDir = [System.IO.Path]::Combine($repoPath, '.rivet')
    $dotRivetItem = [System.IO.Path]::Combine($dotRivetDir, $cleanItemName)
    $rootItem = [System.IO.Path]::Combine($repoPath, $cleanItemName)

    if ([System.IO.File]::Exists($dotRivetItem) -or [System.IO.Directory]::Exists($dotRivetItem)) {
        return $dotRivetItem
    }

    if ([System.IO.File]::Exists($rootItem) -or [System.IO.Directory]::Exists($rootItem)) {
        return $rootItem
    }

    if ([System.IO.Directory]::Exists($dotRivetDir) -or $cleanItemName -eq 'work-items') {
        return $dotRivetItem
    }

    # Fallback to root for legacy structures
    return $rootItem
}
