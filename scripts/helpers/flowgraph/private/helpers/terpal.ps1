<#
 _____                   _ 
|_   _|___ _ _ _ __ __ _| |
  | | / -_) '_| '_ Y _` | |
  |_| \___|_| | .__|__,_|_|.ps1
              |_|
___________________________________________________.
Scope: ascii color Interpolation and SGR Generation
Repo Path: phellams-utils/helpers/color/terpal.ps1
----------.
DESCRPTION                         
----------.
Returns A dynamiclly Generated Hastable with custom Propties, and 
functions to appy or parse ascii pallete and RGB True Color
- Returned HashTable has two objects
- parseColor < function - Parses RGB Array @()|string array into SGR string
- paletteObj < [pscustomobject]
    - Functions:
    - Apply(): applies the color to the text takes, string and Ascii SGR
    - GetFillColor(): < 2 modes Conditional and Gradient
    - GetStaticColor(): Returns Static color SGR
#>
# NOTE: Extact this into phellams utils color
# EXAMPLES:
# - $terpal = Get-TerminalPalette -ColorPalette @{fill=@(255,10,100)} -ColorMode solid
# - $terpal.apply.invoke('this value', $terpal.GetFillColor.invoke(10,255))
# ------------------------------------------------------------------------------
function Get-TerminalPalette {
    [cmdletbinding()]
    [alias('terpal')]
    param (
        [hashtable]$ColorPalette,
        [string]$ColorMode,
        [hashtable]$ColorThresholds,
        [int[]]$GradientStart,
        [int[]]$GradientEnd,
        [int]$CurrentValue,
        [int]$MaxValue = 100
    )

    $esc = [char]27
    $reset = "$esc[0m"

    $parseColor = {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [array] -and $Value.Count -ge 3) {
            return "38;2;$([int]$Value[0]);$([int]$Value[1]);$([int]$Value[2])"
        }
        return [string]$Value
    }

    $paletteObj = [PSCustomObject]@{
        # Change Encode, as examples will use palman
        # !NOTE CHANGE FUNCTION NAME TO Terpal
        Apply  = {
            param([string]$Text, [string]$Code)
            if ([string]::IsNullOrWhiteSpace($Code) -or [string]::IsNullOrEmpty($Text)) { return $Text }
            return "$esc[$Code`m$Text$reset"
        }.GetNewClosure()
        
        GetFillColor = {
            param([int]$Index, [int]$TotalFill)
            
            if ($ColorMode -eq 'Conditional') {
                $matchingThreshold = $null
                $minKey = [int]::MaxValue
                foreach ($k in $ColorThresholds.Keys) {
                    if ($k -ge $CurrentValue -and $k -lt $minKey) {
                        $minKey = $k
                        $matchingThreshold = $k
                    }
                }
                if ($null -ne $matchingThreshold) { 
                    return (& $parseColor $ColorThresholds[$matchingThreshold])
                }
                return $null
            }
            
            if ($ColorMode -eq 'Gradient') {
                $ratio = 0
                if ($TotalFill -gt 1) { $ratio = $Index / ($TotalFill - 1) }
                $r = [math]::Round($GradientStart[0] + ($GradientEnd[0] - $GradientStart[0]) * $ratio)
                $g = [math]::Round($GradientStart[1] + ($GradientEnd[1] - $GradientStart[1]) * $ratio)
                $b = [math]::Round($GradientStart[2] + ($GradientEnd[2] - $GradientStart[2]) * $ratio)
                return "38;2;$r;$g;$b"
            }

            # Default Solid
            foreach ($k in $ColorPalette.Keys) {
                if ($k -ieq 'Fill') { 
                    return (& $parseColor $ColorPalette[$k])
                }
            }
            return $null
        }.GetNewClosure()

        GetStaticColor = {
            param([string]$Key)
            foreach ($k in $ColorPalette.Keys) {
                if ($k -ieq $Key) { 
                    return (& $parseColor $ColorPalette[$k])
                }
            }
            return $null
        }.GetNewClosure()
    }
    
    return $paletteObj
}
