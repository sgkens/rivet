function Assert-RivetProjectDescription {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Description,

        [int]$MaximumLength = 160
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        throw 'repo_meta.json project.description must be a non-empty string.'
    }
    if ($Description.IndexOfAny([char[]]@("`r", "`n")) -ge 0) {
        throw 'repo_meta.json project.description must be a single line.'
    }
    if ($Description.Length -gt $MaximumLength) {
        throw "repo_meta.json project.description must not exceed $MaximumLength characters; received $($Description.Length)."
    }

    return $Description
}
