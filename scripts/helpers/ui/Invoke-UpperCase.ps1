function Invoke-UpperCase {
    param([string]$String)
    if ($null -eq $String) { return $null }
    return $String.ToUpper()
}
