function Get-LazyLogLevelConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('inf', 'wrn', 'err', 'suc', 'act', 'fail', 'skip')]
        [string]$Level
    )

    $levels = @{
        inf  = @{ Label = 'INF'; Color = @(0, 200, 255) }
        wrn  = @{ Label = 'WRN'; Color = @(255, 195, 75) }
        err  = @{ Label = 'ERR'; Color = @(255, 90, 105) }
        suc  = @{ Label = 'SUC'; Color = @(80, 220, 150) }
        act  = @{ Label = 'ACT'; Color = @(210, 120, 255) }
        fail = @{ Label = 'FAIL'; Color = @(255, 90, 105) }
        skip = @{ Label = 'SKIP'; Color = @(145, 155, 175) }
    }

    return $levels[$Level]
}

function Format-LazyLog {
    <#
    .SYNOPSIS
        Formats one composable ANSI log line without writing to the host.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('inf', 'wrn', 'err', 'suc', 'act', 'fail', 'skip')]
        [string]$Level,

        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [string]$Context
    )

    $config = Get-LazyLogLevelConfig -Level $Level
    $badgeText = ("[{0}]" -f $config.Label).PadRight(7)
    $titleText = $Title.ToUpperInvariant().PadRight(9)
    $contextText = if ([string]::IsNullOrWhiteSpace($Context)) { '' } else { "[$Context] " }

    $badge = Format-AnsiText -Text $badgeText -Color $config.Color -Bold
    $titleValue = Format-AnsiText -Text $titleText -Color @(225, 230, 240)
    $contextValue = if ($contextText) { Format-AnsiText -Text $contextText -Color @(145, 155, 175) } else { '' }
    $messageValue = Format-AnsiText -Text $Message -Color @(170, 180, 200)
    return "$badge $titleValue $contextValue$messageValue"
}

function Write-LazyLog {
    <#
    .SYNOPSIS
        Writes one ANSI LazyLog message when logging is enabled.
    .EXAMPLE
        Write-LazyLog -Level suc -Title 'README' -Message 'Metadata synchronized.' -Log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('inf', 'wrn', 'err', 'suc', 'act', 'fail', 'skip')]
        [string]$Level,

        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [string]$Context,
        [switch]$Log,
        [switch]$MirrorError
    )

    $globalLogging = Get-Variable -Name '__logging' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if (-not ($globalLogging -or $Log -or $PSBoundParameters.ContainsKey('Verbose'))) { return }

    [Console]::WriteLine((Format-LazyLog -Level $Level -Message $Message -Title $Title -Context $Context))
    if ($MirrorError -and $Level -in @('err', 'fail')) {
        Write-Error "LazyLog: $Message" -ErrorAction Continue
    }
}
