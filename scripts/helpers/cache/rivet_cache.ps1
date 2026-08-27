<#
.SYNOPSIS
    High-performance, generic caching library with TTL expiration and metrics for CLI/API applications.
.DESCRIPTION
    Provides memory and disk-backed caching with automatic Time-To-Live (TTL) expiration,
    tag-based eviction, serialized JSON storage, and full operational telemetry (hits, misses,
    read/write latencies, eviction tracking, hit-rate percentage, and byte size totals).

    Designed as a universal, zero-dependency PowerShell caching utility suitable for Rivet
    GitLab API caching as well as standalone PowerShell modules and CLI tooling.
.EXAMPLE
    . ./scripts/helpers/cache/rivet_cache.ps1
    Initialize-RivetCache -CacheDirectory ./.rivet/cache -DefaultTtlSeconds 3600
    Set-RivetCache -Key 'gitlab_user_42' -Value @{ Id = 42; Name = 'Developer' }
    $user = Get-RivetCache -Key 'gitlab_user_42'
    $metrics = Get-RivetCacheMetrics
#>

Set-StrictMode -Version Latest

# Global in-memory cache and metrics state container
if (-not (Get-Variable -Name 'Script:RivetCacheState' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RivetCacheState = [hashtable]::Synchronized(@{
        MemoryCache      = @{}
        CacheDirectory   = $null
        DefaultTtl       = [TimeSpan]::FromMinutes(30)
        EnableDiskCache  = $true
        MaxMemoryEntries = 500
        Metrics          = @{
            Hits                 = [long]0
            Misses               = [long]0
            Writes               = [long]0
            Evictions            = [long]0
            Errors               = [long]0
            TotalReadDurationMs  = [double]0.0
            TotalWriteDurationMs = [double]0.0
            LastCleaned          = [DateTime]::MinValue
        }
    })
}

function Initialize-RivetCache {
    <#
    .SYNOPSIS
        Initializes the cache subsystem settings and storage directories.
    #>
    [CmdletBinding()]
    param(
        [string]$CacheDirectory,
        [int]$DefaultTtlSeconds = 1800,
        [int]$MaxMemoryEntries = 500,
        [switch]$DisableDiskCache,
        [switch]$ResetMetrics
    )

    if (-not [string]::IsNullOrWhiteSpace($CacheDirectory)) {
        $resolvedDir = [System.IO.Path]::GetFullPath($CacheDirectory)
        if (-not [System.IO.Directory]::Exists($resolvedDir)) {
            [System.IO.Directory]::CreateDirectory($resolvedDir) | Out-Null
        }
        $script:RivetCacheState.CacheDirectory = $resolvedDir
    }

    $script:RivetCacheState.DefaultTtl = [TimeSpan]::FromSeconds($DefaultTtlSeconds)
    $script:RivetCacheState.MaxMemoryEntries = $MaxMemoryEntries
    $script:RivetCacheState.EnableDiskCache = (-not $DisableDiskCache)

    if ($ResetMetrics) {
        $script:RivetCacheState.Metrics.Hits = [long]0
        $script:RivetCacheState.Metrics.Misses = [long]0
        $script:RivetCacheState.Metrics.Writes = [long]0
        $script:RivetCacheState.Metrics.Evictions = [long]0
        $script:RivetCacheState.Metrics.Errors = [long]0
        $script:RivetCacheState.Metrics.TotalReadDurationMs = [double]0.0
        $script:RivetCacheState.Metrics.TotalWriteDurationMs = [double]0.0
    }
}

function Get-RivetCacheKeyHash {
    param([string]$Key)
    $cleanKey = $Key.Trim()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanKey)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
        $hashHex = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
        return $hashHex.Substring(0, 24)
    } finally {
        $sha.Dispose()
    }
}

function Get-RivetCacheFilePath {
    param([string]$Key, [string]$CacheDirectory)
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($CacheDirectory)) {
        [System.IO.Path]::GetFullPath($CacheDirectory)
    } elseif (-not [string]::IsNullOrWhiteSpace($script:RivetCacheState.CacheDirectory)) {
        $script:RivetCacheState.CacheDirectory
    } else {
        $null
    }

    if ($null -eq $targetDir) { return $null }
    $hash = Get-RivetCacheKeyHash -Key $Key
    $safeName = [System.Text.RegularExpressions.Regex]::Replace($Key, '[^a-zA-Z0-9_\-]', '_')
    if ($safeName.Length -gt 32) { $safeName = $safeName.Substring(0, 32) }
    $fileName = "${hash}_${safeName}.json"
    return [System.IO.Path]::Combine($targetDir, $fileName)
}

function Get-RivetCache {
    <#
    .SYNOPSIS
        Retrieves a cached item if present and unexpired.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [string]$CacheDirectory,
        [object]$DefaultValue = $null
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $now = [DateTime]::UtcNow

    # 1. Check in-memory cache
    if ($script:RivetCacheState.MemoryCache.ContainsKey($Key)) {
        $memEntry = $script:RivetCacheState.MemoryCache[$Key]
        if ($memEntry.ExpiresAt -gt $now) {
            $sw.Stop()
            $script:RivetCacheState.Metrics.Hits++
            $script:RivetCacheState.Metrics.TotalReadDurationMs += $sw.Elapsed.TotalMilliseconds
            return $memEntry.Value
        } else {
            # Expired in memory
            $script:RivetCacheState.MemoryCache.Remove($Key)
            $script:RivetCacheState.Metrics.Evictions++
        }
    }

    # 2. Check disk cache if enabled
    if ($script:RivetCacheState.EnableDiskCache) {
        $filePath = Get-RivetCacheFilePath -Key $Key -CacheDirectory $CacheDirectory
        if ($null -ne $filePath -and [System.IO.File]::Exists($filePath)) {
            try {
                $rawJson = [System.IO.File]::ReadAllText($filePath)
                $doc = [System.Text.Json.JsonDocument]::Parse($rawJson)
                try {
                    $root = $doc.RootElement
                    $expiresAtStr = $root.GetProperty('expiresAt').GetString()
                    $expiresAt = [DateTime]::Parse($expiresAtStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)

                    if ($expiresAt -gt $now) {
                        $valueJson = $root.GetProperty('value').GetRawText()
                        $deserializedValue = $valueJson | ConvertFrom-Json

                        # Promote to memory cache
                        if ($script:RivetCacheState.MemoryCache.Count -lt $script:RivetCacheState.MaxMemoryEntries) {
                            $script:RivetCacheState.MemoryCache[$Key] = @{
                                Value     = $deserializedValue
                                ExpiresAt = $expiresAt
                                Tags      = @()
                            }
                        }

                        $sw.Stop()
                        $script:RivetCacheState.Metrics.Hits++
                        $script:RivetCacheState.Metrics.TotalReadDurationMs += $sw.Elapsed.TotalMilliseconds
                        return $deserializedValue
                    } else {
                        # Expired on disk
                        [System.IO.File]::Delete($filePath)
                        $script:RivetCacheState.Metrics.Evictions++
                    }
                } finally {
                    $doc.Dispose()
                }
            } catch {
                $script:RivetCacheState.Metrics.Errors++
            }
        }
    }

    $sw.Stop()
    $script:RivetCacheState.Metrics.Misses++
    $script:RivetCacheState.Metrics.TotalReadDurationMs += $sw.Elapsed.TotalMilliseconds
    return $DefaultValue
}

function Set-RivetCache {
    <#
    .SYNOPSIS
        Stores an item in cache with a TTL expiration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Mandatory, Position = 1)][object]$Value,
        [int]$TtlSeconds = 0,
        [TimeSpan]$TtlTimeSpan = [TimeSpan]::Zero,
        [string[]]$Tags = @(),
        [string]$CacheDirectory
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $now = [DateTime]::UtcNow

    $effectiveTtl = if ($TtlSeconds -gt 0) {
        [TimeSpan]::FromSeconds($TtlSeconds)
    } elseif ($TtlTimeSpan -gt [TimeSpan]::Zero) {
        $TtlTimeSpan
    } else {
        $script:RivetCacheState.DefaultTtl
    }

    $expiresAt = $now.Add($effectiveTtl)

    # 1. Update in-memory cache
    if ($script:RivetCacheState.MemoryCache.Count -ge $script:RivetCacheState.MaxMemoryEntries) {
        # Evict oldest entry
        $oldestKey = $null
        $oldestExp = [DateTime]::MaxValue
        foreach ($k in $script:RivetCacheState.MemoryCache.Keys) {
            if ($script:RivetCacheState.MemoryCache[$k].ExpiresAt -lt $oldestExp) {
                $oldestExp = $script:RivetCacheState.MemoryCache[$k].ExpiresAt
                $oldestKey = $k
            }
        }
        if ($oldestKey) {
            $script:RivetCacheState.MemoryCache.Remove($oldestKey)
            $script:RivetCacheState.Metrics.Evictions++
        }
    }

    $script:RivetCacheState.MemoryCache[$Key] = @{
        Value     = $Value
        ExpiresAt = $expiresAt
        Tags      = $Tags
    }

    # 2. Persist to disk if enabled
    if ($script:RivetCacheState.EnableDiskCache) {
        $filePath = Get-RivetCacheFilePath -Key $Key -CacheDirectory $CacheDirectory
        if ($null -ne $filePath) {
            try {
                $dir = [System.IO.Path]::GetDirectoryName($filePath)
                if (-not [System.IO.Directory]::Exists($dir)) {
                    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
                }

                $record = [ordered]@{
                    key       = $Key
                    createdAt = $now.ToString('o')
                    expiresAt = $expiresAt.ToString('o')
                    tags      = $Tags
                    value     = $Value
                }
                $json = ConvertTo-Json -InputObject $record -Depth 10 -Compress
                [System.IO.File]::WriteAllText($filePath, $json, [System.Text.UTF8Encoding]::new($false))
            } catch {
                $script:RivetCacheState.Metrics.Errors++
            }
        }
    }

    $sw.Stop()
    $script:RivetCacheState.Metrics.Writes++
    $script:RivetCacheState.Metrics.TotalWriteDurationMs += $sw.Elapsed.TotalMilliseconds
    return $Value
}

function Remove-RivetCache {
    <#
    .SYNOPSIS
        Removes a cached item by key or tag pattern.
    #>
    [CmdletBinding()]
    param(
        [string]$Key,
        [string]$Tag,
        [string]$CacheDirectory
    )

    if ($Key) {
        if ($script:RivetCacheState.MemoryCache.ContainsKey($Key)) {
            $script:RivetCacheState.MemoryCache.Remove($Key)
            $script:RivetCacheState.Metrics.Evictions++
        }
        $filePath = Get-RivetCacheFilePath -Key $Key -CacheDirectory $CacheDirectory
        if ($null -ne $filePath -and [System.IO.File]::Exists($filePath)) {
            [System.IO.File]::Delete($filePath)
            $script:RivetCacheState.Metrics.Evictions++
        }
    }

    if ($Tag) {
        $keysToRemove = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $script:RivetCacheState.MemoryCache.Keys) {
            $entry = $script:RivetCacheState.MemoryCache[$k]
            if ($entry.Tags -contains $Tag) {
                $keysToRemove.Add($k)
            }
        }
        foreach ($k in $keysToRemove) {
            $script:RivetCacheState.MemoryCache.Remove($k)
            $script:RivetCacheState.Metrics.Evictions++
        }

        # Clear tagged disk files
        $targetDir = if (-not [string]::IsNullOrWhiteSpace($CacheDirectory)) {
            $CacheDirectory
        } else {
            $script:RivetCacheState.CacheDirectory
        }
        if ($targetDir -and [System.IO.Directory]::Exists($targetDir)) {
            $files = [System.IO.Directory]::GetFiles($targetDir, '*.json')
            foreach ($file in $files) {
                try {
                    $json = [System.IO.File]::ReadAllText($file)
                    if ($json.Contains("""$Tag""")) {
                        [System.IO.File]::Delete($file)
                        $script:RivetCacheState.Metrics.Evictions++
                    }
                } catch {}
            }
        }
    }
}

function Clear-RivetCache {
    <#
    .SYNOPSIS
        Clears all cache entries or only expired entries.
    #>
    [CmdletBinding()]
    param(
        [switch]$ExpiredOnly,
        [string]$CacheDirectory
    )

    $now = [DateTime]::UtcNow

    if ($ExpiredOnly) {
        $expiredMemKeys = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $script:RivetCacheState.MemoryCache.Keys) {
            if ($script:RivetCacheState.MemoryCache[$k].ExpiresAt -le $now) {
                $expiredMemKeys.Add($k)
            }
        }
        foreach ($k in $expiredMemKeys) {
            $script:RivetCacheState.MemoryCache.Remove($k)
            $script:RivetCacheState.Metrics.Evictions++
        }
    } else {
        $evictedCount = $script:RivetCacheState.MemoryCache.Count
        $script:RivetCacheState.MemoryCache.Clear()
        $script:RivetCacheState.Metrics.Evictions += $evictedCount
    }

    $targetDir = if (-not [string]::IsNullOrWhiteSpace($CacheDirectory)) {
        $CacheDirectory
    } else {
        $script:RivetCacheState.CacheDirectory
    }

    if ($targetDir -and [System.IO.Directory]::Exists($targetDir)) {
        $files = [System.IO.Directory]::GetFiles($targetDir, '*.json')
        foreach ($file in $files) {
            if ($ExpiredOnly) {
                try {
                    $raw = [System.IO.File]::ReadAllText($file)
                    $doc = [System.Text.Json.JsonDocument]::Parse($raw)
                    try {
                        $expStr = $doc.RootElement.GetProperty('expiresAt').GetString()
                        $exp = [DateTime]::Parse($expStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                        if ($exp -le $now) {
                            [System.IO.File]::Delete($file)
                            $script:RivetCacheState.Metrics.Evictions++
                        }
                    } finally { $doc.Dispose() }
                } catch {
                    [System.IO.File]::Delete($file)
                }
            } else {
                [System.IO.File]::Delete($file)
                $script:RivetCacheState.Metrics.Evictions++
            }
        }
    }

    $script:RivetCacheState.Metrics.LastCleaned = $now
}

function Test-RivetCacheItem {
    <#
    .SYNOPSIS
        Tests whether a key exists in cache and is valid.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [string]$CacheDirectory
    )

    $now = [DateTime]::UtcNow
    if ($script:RivetCacheState.MemoryCache.ContainsKey($Key)) {
        if ($script:RivetCacheState.MemoryCache[$Key].ExpiresAt -gt $now) {
            return $true
        }
    }

    if ($script:RivetCacheState.EnableDiskCache) {
        $filePath = Get-RivetCacheFilePath -Key $Key -CacheDirectory $CacheDirectory
        if ($null -ne $filePath -and [System.IO.File]::Exists($filePath)) {
            try {
                $raw = [System.IO.File]::ReadAllText($filePath)
                $doc = [System.Text.Json.JsonDocument]::Parse($raw)
                try {
                    $expStr = $doc.RootElement.GetProperty('expiresAt').GetString()
                    $exp = [DateTime]::Parse($expStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                    return ($exp -gt $now)
                } finally { $doc.Dispose() }
            } catch { return $false }
        }
    }

    return $false
}

function Get-RivetCacheMetrics {
    <#
    .SYNOPSIS
        Returns operational metrics and telemetry for the cache subsystem.
    #>
    [CmdletBinding()]
    param()

    $totalRequests = $script:RivetCacheState.Metrics.Hits + $script:RivetCacheState.Metrics.Misses
    $hitRate = if ($totalRequests -gt 0) {
        [Math]::Round(($script:RivetCacheState.Metrics.Hits / [double]$totalRequests) * 100.0, 2)
    } else { 0.0 }

    $avgReadMs = if ($totalRequests -gt 0) {
        [Math]::Round($script:RivetCacheState.Metrics.TotalReadDurationMs / [double]$totalRequests, 3)
    } else { 0.0 }

    $avgWriteMs = if ($script:RivetCacheState.Metrics.Writes -gt 0) {
        [Math]::Round($script:RivetCacheState.Metrics.TotalWriteDurationMs / [double]$script:RivetCacheState.Metrics.Writes, 3)
    } else { 0.0 }

    # Calculate disk usage
    $totalSizeBytes = [long]0
    $diskCount = 0
    if ($script:RivetCacheState.CacheDirectory -and [System.IO.Directory]::Exists($script:RivetCacheState.CacheDirectory)) {
        $files = [System.IO.Directory]::GetFiles($script:RivetCacheState.CacheDirectory, '*.json')
        $diskCount = @($files).Count
        foreach ($f in $files) {
            $totalSizeBytes += (Get-Item $f).Length
        }
    }

    [PSCustomObject]@{
        Hits                 = $script:RivetCacheState.Metrics.Hits
        Misses               = $script:RivetCacheState.Metrics.Misses
        TotalRequests        = $totalRequests
        HitRatePercentage    = $hitRate
        Writes               = $script:RivetCacheState.Metrics.Writes
        Evictions            = $script:RivetCacheState.Metrics.Evictions
        Errors               = $script:RivetCacheState.Metrics.Errors
        AverageReadMs        = $avgReadMs
        AverageWriteMs       = $avgWriteMs
        MemoryEntries        = $script:RivetCacheState.MemoryCache.Count
        DiskEntries          = $diskCount
        TotalSizeBytes       = $totalSizeBytes
        LastCleaned          = $script:RivetCacheState.Metrics.LastCleaned
    }
}

function Invoke-RivetCachedOperation {
    <#
    .SYNOPSIS
        Executes a scriptblock with caching. If cached, returns cached result; otherwise computes and caches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Mandatory, Position = 1)][scriptblock]$ScriptBlock,
        [int]$TtlSeconds = 0,
        [TimeSpan]$TtlTimeSpan = [TimeSpan]::Zero,
        [switch]$ForceRefresh,
        [string[]]$Tags = @(),
        [string]$CacheDirectory
    )

    if (-not $ForceRefresh) {
        $cached = Get-RivetCache -Key $Key -CacheDirectory $CacheDirectory
        if ($null -ne $cached) {
            return $cached
        }
    }

    $result = & $ScriptBlock
    if ($null -ne $result) {
        $null = Set-RivetCache -Key $Key -Value $result -TtlSeconds $TtlSeconds -TtlTimeSpan $TtlTimeSpan -Tags $Tags -CacheDirectory $CacheDirectory
    }
    return $result
}
