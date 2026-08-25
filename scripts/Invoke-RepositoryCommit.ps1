<#
.SYNOPSIS
    Reviews and creates one file-scoped Conventional Commit.
.DESCRIPTION
    Suggests changed files from configured scope path rules, supports interactive
    file toggling, previews selected and excluded paths, diff statistics, a
    capped patch, and the extracted release note, then stages only approved paths.
#>
function Invoke-RepositoryCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigPath,
        [ValidatePattern('^[a-z][a-z0-9-]*$')][string]$Type,
        [ValidatePattern('^[a-z0-9][a-z0-9._/-]*$|^none$')][string]$Scope,
        [string]$Description,
        [string[]]$Files,
        [switch]$All,
        [switch]$DryRun
    )

    function Read-GitStatusRecord {
        param([string]$Root)

        $gitCommand = Get-Command git -ErrorAction Stop
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $gitCommand.Source
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('-C', $Root, '-c', 'core.quotepath=false', 'status', '--porcelain=v1', '-z', '--untracked-files=all')) {
            $startInfo.ArgumentList.Add($argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { throw 'Git status process did not start.' }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) { throw "Unable to read Git status for '$Root'. $stderr" }
        } finally {
            $process.Dispose()
        }

        $records = $stdout.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)
        $result = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $records.Count; $index++) {
            $record = $records[$index]
            if ($record.Length -lt 4) { continue }
            $status = $record.Substring(0, 2)
            $path = $record.Substring(3)
            $originalPath = $null
            if ($status -match '[RC]') {
                $index++
                if ($index -lt $records.Count) { $originalPath = $records[$index] }
            }
            $result.Add([pscustomobject]@{
                Status = $status
                Path = $path
                OriginalPath = $originalPath
                Display = if ($originalPath) { "$status $originalPath -> $path" } else { "$status $path" }
            })
        }
        return $result.ToArray()
    }

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ($All -and @($Files).Count) { throw '-All and -Files cannot be used together.' }
    $config = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    $commitConfig = $config.commit
    $changes = @(Read-GitStatusRecord -Root $repositoryPath)
    if (-not $changes.Count) { throw 'There are no repository changes to commit.' }

    if ([string]::IsNullOrWhiteSpace($Type)) {
        $items = foreach ($entry in $commitConfig.types) { [pscustomobject]@{ Label = $entry.name; Description = $entry.description; Value = $entry.name } }
        $choice = Show-SMenu -Title 'SELECT COMMIT TYPE' -Items $items -DefaultIndex ([Math]::Max(0, [Array]::IndexOf([string[]]@($commitConfig.types.name), [string]$commitConfig.defaultType)))
        if ($null -eq $choice) { return [pscustomobject]@{ Submitted = $false; Cancelled = $true } }
        $Type = [string]$choice
    }
    if ([string]::IsNullOrWhiteSpace($Scope)) {
        $items = foreach ($entry in $commitConfig.scopes) { [pscustomobject]@{ Label = $entry.name; Description = $entry.description; Value = $entry.name } }
        $choice = Show-SMenu -Title 'SELECT COMMIT SCOPE' -Items $items -DefaultIndex ([Math]::Max(0, [Array]::IndexOf([string[]]@($commitConfig.scopes.name), [string]$commitConfig.defaultScope)))
        if ($null -eq $choice) { return [pscustomobject]@{ Submitted = $false; Cancelled = $true } }
        $Scope = [string]$choice
    }
    $Type = $Type.ToLowerInvariant(); $Scope = $Scope.ToLowerInvariant()
    $scopeConfig = $commitConfig.scopes | Where-Object name -EQ $Scope | Select-Object -First 1
    if ($Type -notin [string[]]@($commitConfig.types.name)) { throw "Commit type '$Type' is not configured." }
    if ($null -eq $scopeConfig) { throw "Commit scope '$Scope' is not configured." }

    $selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($All) {
        foreach ($change in $changes) { [void]$selected.Add($change.Path) }
    } elseif (@($Files).Count) {
        foreach ($path in $Files) {
            if ($path -notin $changes.Path) { throw "Commit file is not changed: $path" }
            [void]$selected.Add($path)
        }
    } else {
        foreach ($change in $changes) {
            foreach ($pattern in @($scopeConfig.paths)) {
                if ($change.Path -like $pattern) { [void]$selected.Add($change.Path); break }
            }
        }
        if (-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
            while ($true) {
                $fileItems = [System.Collections.Generic.List[object]]::new()
                $fileItems.Add([pscustomobject]@{ Label = "Done ($($selected.Count) selected)"; Description = 'continue to commit review'; Value = '__done__' })
                foreach ($change in $changes) {
                    $mark = if ($selected.Contains($change.Path)) { '[x]' } else { '[ ]' }
                    $fileItems.Add([pscustomobject]@{ Label = "$mark $($change.Path)"; Description = $change.Status; Value = $change.Path })
                }
                $choice = Show-SMenu -Title "SELECT FILES FOR $($Scope.ToUpperInvariant())" -Items $fileItems.ToArray()
                if ($null -eq $choice) { return [pscustomobject]@{ Submitted = $false; Cancelled = $true } }
                if ($choice -eq '__done__') { break }
                if (-not $selected.Remove([string]$choice)) { [void]$selected.Add([string]$choice) }
            }
        }
    }
    if (-not $selected.Count) { throw "No files are selected for scope '$Scope'." }

    $defaultDescription = [string]$commitConfig.defaultDescription
    if ([string]::IsNullOrWhiteSpace($Description)) {
        $entered = Read-Host "Description [$defaultDescription]"
        $Description = if ([string]::IsNullOrWhiteSpace($entered)) { $defaultDescription } else { $entered }
    }
    $Description = $Description.Trim().TrimEnd('.')
    $subject = "${Type}$(if ($Scope -eq 'none') { '' } else { "($Scope)" }): $Description"
    if ($subject.Length -gt 100) { throw "Commit subject is $($subject.Length) characters; the limit is 100." }
    $parsed = ConvertFrom-ConventionalCommit -Subject $subject
    $selectedPaths = @($selected | Sort-Object)
    $gitPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($change in $changes) {
        if (-not $selected.Contains($change.Path)) { continue }
        [void]$gitPaths.Add($change.Path)
        if (-not [string]::IsNullOrWhiteSpace([string]$change.OriginalPath)) { [void]$gitPaths.Add($change.OriginalPath) }
    }
    $pathspecs = @($gitPaths | Sort-Object)
    $excluded = @($changes | Where-Object { -not $selected.Contains($_.Path) })

    $diff = @(& git -C $repositoryPath diff --no-color HEAD -- @pathspecs)
    $numstat = @(& git -C $repositoryPath diff --numstat HEAD -- @pathspecs)
    $insertions = 0L; $deletions = 0L
    foreach ($stat in $numstat) {
        $parts = $stat -split "`t", 3
        if ($parts.Count -ge 2 -and $parts[0] -ne '-') { $insertions += [long]$parts[0]; $deletions += [long]$parts[1] }
    }
    $previewProperty = $commitConfig.PSObject.Properties['preview']
    $maxDiffLines = if ($null -ne $previewProperty -and $null -ne $commitConfig.preview.PSObject.Properties['maxDiffLines']) { [int]$commitConfig.preview.maxDiffLines } else { 240 }

    [Console]::WriteLine('')
    [Console]::WriteLine((Format-AnsiText -Text 'COMMIT REVIEW' -Color @(0, 200, 255) -Bold))
    [Console]::WriteLine((Format-AnsiText -Text $subject -Color @(220, 225, 235) -Bold))
    [Console]::WriteLine("  scope      $Scope")
    [Console]::WriteLine("  files      $($selected.Count) selected / $($changes.Count) changed")
    [Console]::WriteLine("  changes    +$insertions / -$deletions")
    [Console]::WriteLine("  release    $($parsed.ReleaseNote)")
    [Console]::WriteLine((Format-AnsiText -Text 'SELECTED FILES' -Color @(80, 220, 150) -Bold))
    foreach ($path in $selectedPaths) { [Console]::WriteLine("  $path") }
    if ($excluded.Count) {
        [Console]::WriteLine((Format-AnsiText -Text 'EXCLUDED FILES' -Color @(145, 155, 175) -Bold))
        foreach ($change in $excluded) { [Console]::WriteLine("  $($change.Path)") }
    }
    [Console]::WriteLine((Format-AnsiText -Text "PATCH PREVIEW  first $maxDiffLines lines" -Color @(210, 120, 255) -Bold))
    foreach ($line in @($diff | Select-Object -First $maxDiffLines)) { [Console]::WriteLine($line) }
    if ($diff.Count -gt $maxDiffLines) { [Console]::WriteLine("  ... $($diff.Count - $maxDiffLines) additional diff lines omitted") }
    $untracked = @($changes | Where-Object { $_.Status -eq '??' -and $selected.Contains($_.Path) })
    foreach ($change in $untracked) {
        $fullPath = [System.IO.Path]::Combine($repositoryPath, $change.Path)
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        if ($bytes -contains 0) {
            [Console]::WriteLine("  [binary untracked file] $($change.Path) ($($bytes.Length) bytes)")
            continue
        }
        [Console]::WriteLine("--- /dev/null")
        [Console]::WriteLine("+++ b/$($change.Path)")
        foreach ($line in @([System.IO.File]::ReadLines($fullPath) | Select-Object -First $maxDiffLines)) { [Console]::WriteLine("+$line") }
    }

    $result = [pscustomobject]@{ Submitted = $false; Cancelled = $false; Subject = $subject; Scope = $Scope; Files = $selectedPaths; ReleaseNote = $parsed.ReleaseNote }
    if ($DryRun) { return $result }
    $null = & git -C $repositoryPath diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'The index already contains staged changes. Commit or unstage them before scoped staging.' }
    if ((Read-Host 'Stage only these files and submit? [y/N]') -notmatch '^(?i:y|yes)$') { $result.Cancelled = $true; return $result }
    $null = & git -C $repositoryPath add -- @pathspecs
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stage the selected files.' }
    $commitOutput = @(& git -C $repositoryPath commit --message $subject)
    if ($LASTEXITCODE -ne 0) { throw 'Git did not create the scoped commit; selected files remain staged for inspection.' }
    foreach ($line in $commitOutput) { [Console]::WriteLine($line) }
    $result.Submitted = $true
    return $result
}
