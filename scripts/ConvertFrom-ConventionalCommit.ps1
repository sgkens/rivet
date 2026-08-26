<#
.SYNOPSIS
    Parses one Conventional Commit subject and body.
.DESCRIPTION
    Returns a normalized type, exact scope, description, breaking-change state,
    release category, and release-note sentence for all rivet consumers.
#>
function ConvertFrom-ConventionalCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subject,
        [AllowEmptyString()][string]$Body = ''
    )

    $match = [regex]::Match($Subject.Trim(), '^(?<type>[a-z][a-z0-9-]*)(?:\((?<scope>[^)]+)\))?(?<breaking>!)?:\s+(?<text>.+)$', 'IgnoreCase')
    $type = if ($match.Success) { $match.Groups['type'].Value.ToLowerInvariant() } else { 'changed' }
    $scope = if ($match.Success -and $match.Groups['scope'].Success) { $match.Groups['scope'].Value.ToLowerInvariant() } else { $null }
    $description = if ($match.Success) { $match.Groups['text'].Value.Trim() } else { $Subject.Trim() }
    $breaking = ($match.Success -and $match.Groups['breaking'].Success) -or $Body -match '(?im)^BREAKING[ -]CHANGE:\s*\S'
    $category = switch ($type) {
        'feat' { 'Added' }
        'fix' { 'Fixed' }
        'security' { 'Security' }
        { $_ -in @('deprecate', 'deprecated') } { 'Deprecated' }
        { $_ -in @('remove', 'removed') } { 'Removed' }
        default { 'Changed' }
    }
    if ($description.Length) { $note = $description.Substring(0, 1).ToUpperInvariant() + $description.Substring(1) } else { $note = $description }
    if ($note -and $note -notmatch '[.!?]$') { $note += '.' }
    if ($breaking) { $note = "Breaking: $note" }
    [pscustomobject]@{
        IsConventional = $match.Success
        Type = $type
        Scope = $scope
        Description = $description
        Breaking = $breaking
        Category = $category
        ReleaseNote = $note
        Subject = $Subject.Trim()
    }
}
