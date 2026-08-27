Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsRoot = [System.IO.Path]::Combine($PSScriptRoot, 'scripts')
$helperRoot = [System.IO.Path]::Combine($scriptsRoot, 'helpers')

# Explicit loading prevents experimental, duplicate, or foreign helpers from
# entering rivet's runtime merely because they exist below scripts/helpers.
$runtimeFiles = @(
    [System.IO.Path]::Combine($helperRoot, 'args-completers', 'argumentcompleters.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Initialize-Terminal.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Enable-TerminalAltBuffer.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Disable-TerminalAltBuffer.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Hide-TerminalCursor.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Show-TerminalCursor.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Format-TuiString.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Get-TerminalUI.ps1')
    [System.IO.Path]::Combine($helperRoot, 'color', 'terpal.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'New-TuiPanel.ps1')
    [System.IO.Path]::Combine($helperRoot, 'string', 'clap.ps1')
    [System.IO.Path]::Combine($helperRoot, 'datetime', 'Get-ElaspedTime.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'asciitokenizer.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'lazylog.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Get-RivetConfiguration.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Initialize-RivetRepository.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'ConvertFrom-ConventionalCommit.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Get-ConventionalCommitVersion.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Update-JSLibSemver.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'jsheader.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'New-MarkdownTOC.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Update-ReleaseDocumentation.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Update-MergeRequestDocumentation.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Invoke-GitLabMergeRequest.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'smenu.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Show-RivetPager.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Invoke-RepositoryCommit.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Write-PrettyGitLog.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Invoke-RepositoryTag.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Write-RivetVersionReport.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Write-RivetRepositoryStatus.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Test-RivetRepository.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Test-ReadmeStructure.ps1')
    [System.IO.Path]::Combine($helperRoot, 'flowgraph', 'private', 'Engine.ps1')
    [System.IO.Path]::Combine($helperRoot, 'flowgraph', 'public', 'New-FlowNode.ps1')
    [System.IO.Path]::Combine($helperRoot, 'flowgraph', 'public', 'New-FlowEdge.ps1')
    [System.IO.Path]::Combine($helperRoot, 'flowgraph', 'public', 'New-FlowGraph.ps1')
    [System.IO.Path]::Combine($helperRoot, 'flowgraph', 'public', 'Show-FlowGraph.ps1')
    [System.IO.Path]::Combine($helperRoot, 'cache', 'rivet_cache.ps1')
    [System.IO.Path]::Combine($helperRoot, 'data_utils', 'Resolve-RivetPath.ps1')
    [System.IO.Path]::Combine($helperRoot, 'ui', 'Write-RivetReportCard.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Sync-RivetWorkItems.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Show-RivetFlowGraph.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Invoke-RivetMenu.ps1')
    [System.IO.Path]::Combine($scriptsRoot, 'Invoke-Rivet.ps1')
)

foreach ($runtimeFile in $runtimeFiles) {
    if (-not [System.IO.File]::Exists($runtimeFile)) {
        throw "Required rivet runtime file is missing: $runtimeFile"
    }
    . $runtimeFile
}

# A file can exist while Syncthing, an editor, or another writer is replacing
# its contents. Validate the loaded commands now so Rivet fails before entering
# the alternate terminal buffer instead of discovering a missing helper during
# menu cleanup.
$requiredRuntimeFunctions = [ordered]@{
    'Enable-TerminalAltBuffer' = [System.IO.Path]::Combine($helperRoot, 'ui', 'Enable-TerminalAltBuffer.ps1')
    'Disable-TerminalAltBuffer' = [System.IO.Path]::Combine($helperRoot, 'ui', 'Disable-TerminalAltBuffer.ps1')
    'Hide-TerminalCursor' = [System.IO.Path]::Combine($helperRoot, 'ui', 'Hide-TerminalCursor.ps1')
    'Show-TerminalCursor' = [System.IO.Path]::Combine($helperRoot, 'ui', 'Show-TerminalCursor.ps1')
    'Format-TuiString' = [System.IO.Path]::Combine($helperRoot, 'ui', 'Format-TuiString.ps1')
    'Get-TerminalUI' = [System.IO.Path]::Combine($helperRoot, 'ui', 'Get-TerminalUI.ps1')
    'Format-AnsiText' = [System.IO.Path]::Combine($helperRoot, 'color', 'terpal.ps1')
    'New-TuiPanel' = [System.IO.Path]::Combine($helperRoot, 'ui', 'New-TuiPanel.ps1')
    'Clap' = [System.IO.Path]::Combine($helperRoot, 'string', 'clap.ps1')
    'Get-ElapsedTime' = [System.IO.Path]::Combine($helperRoot, 'datetime', 'Get-ElaspedTime.ps1')
    'Show-SMenu' = [System.IO.Path]::Combine($scriptsRoot, 'smenu.ps1')
    'Show-RivetPager' = [System.IO.Path]::Combine($scriptsRoot, 'Show-RivetPager.ps1')
    'Show-RivetFlowGraph' = [System.IO.Path]::Combine($scriptsRoot, 'Show-RivetFlowGraph.ps1')
    'Invoke-RivetMenu' = [System.IO.Path]::Combine($scriptsRoot, 'Invoke-RivetMenu.ps1')
    'Invoke-Rivet' = [System.IO.Path]::Combine($scriptsRoot, 'Invoke-Rivet.ps1')
}

foreach ($functionName in $requiredRuntimeFunctions.Keys) {
    if (-not (Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
        throw "Rivet runtime import is incomplete. Function '$functionName' was not defined by '$($requiredRuntimeFunctions[$functionName])'. The file may be empty or changing during import. Retry after file synchronization completes."
    }
}

# Register dynamic and static argument completers
Register-RivetArgumentCompleters

# Public router cmdlet and aliases
$publicFunctions = @('Invoke-Rivet')

$moduleAliases = @{
    'rivet' = 'Invoke-Rivet'
    'Invoke-Glmeta' = 'Invoke-Rivet'
    'glmeta' = 'Invoke-Rivet'
}

foreach ($aliasName in $moduleAliases.Keys) {
    Set-Alias -Name $aliasName -Value $moduleAliases[$aliasName] -Scope Script
}

$exportedAliasNames = [string[]]$moduleAliases.Keys
Export-ModuleMember -Function $publicFunctions -Alias $exportedAliasNames
