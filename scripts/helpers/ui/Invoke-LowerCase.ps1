function Invoke-LowerCase {
    param([string]$String)
    if ($null -eq $String) { return $null }
    return $String.ToLower()
}
