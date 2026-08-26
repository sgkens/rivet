# -----------------------------------------------------------------------------
# STATEFUL SPINNER HELPER
# -----------------------------------------------------------------------------

# Initialize script-scope counter (persists as long as module is imported)
$script:PwslSpinnerIdx = 0

function New-Spinner {
    <#
    .SYNOPSIS
        Returns the next character in a spinner sequence.
        Maintains state automatically using a script-level variable.
    #>
    [CmdletBinding()]
    param(
        # The animation frames. Defaults to standard ASCII.
        [parameter(mandatory=$true)]
        [string[]]$Steps,
        [switch]$Reset
    )

    begin {
        if(!$steps){
            $steps = @('-', '\', '|', '/')
        }
        if($steps.count -lt 2){
            return "String array <= 2 please expand the array length";
        }
        if($reset){
            $script:PwslSpinnerIdx = 0
            return
        }
    }

    process {

        # 1. Calculate current frame based on script-level index
        $currentIndex = $script:PwslSpinnerIdx % $Steps.Count
        $char = $Steps[$currentIndex]

        # 2. Increment global index for the next call
        $script:PwslSpinnerIdx++

        # 3. Return the raw string/char
        return $char
    }
}

$cmdlet_config = @{
    function = @( 
        'New-Spinner'
    )
    alias  =@()
}

Export-ModuleMember @cmdlet_config