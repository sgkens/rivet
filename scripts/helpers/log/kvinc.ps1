<#
.SYNOPSIS
    Creates a string with a key-value pair in a specific format.
.DESCRIPTION
    Creates a string with a key-value pair in a specific format.
.PARAMETER keyName
    The name of the key.
.PARAMETER KeyValue
    The value of the key.
.PARAMETER type
    The type of the key-value pair.
.EXAMPLE
    New-kvstring -message "This is a test message with a {kv:username=JohnDoe}"
    New-KvString -message "This is a test message with a {kv:username=JohnDoe} and a {prop:kv:userid=12345}"
    New-KvString -message "This is a test message with a {kv:username=JohnDoe} and a {prop:kv:userid=12345} and a {meta:kv:session=abcde"
#>
function New-Kvinc {
    [CmdletBinding()]
    [alias('kvinc')]
    param(
        [parameter(Mandatory, Position = 0)]
        [string]$keyName,

        [parameter(Mandatory, Position = 1)]
        [string]$KeyValue,

        [parameter(Mandatory = $false, Position = 2)]
        [ValidateSet(
            'inf',
            'err',
            'wrn',
            'prop',
            'property',
            'api',
            'git',
            'value',
            'type',
            'key',
            'meta',
            'metadata',
            'confval',
            'none'
        )]
        [string]$type
    )
    
    [string]$string = ''
    
    if (!$type) {
        $type = 'none'
    }

    $utility = @{
        kvinc_bracket_color  = "95"
        kvinc_bracket_format = ";1"
        kvinc_type_color     = "90"
        kvinc_type_format    = ";1"
        kvinc_key_color      = "94"
        kvinc_key_format     = ";1"
        kvinc_value_color    = "90"
        kvinc_value_format   = ";1"
    }
    
    if ($type -eq 'none') {
        
        $string += "`e[$($utility.kvinc_bracket_color)$($utility.kvinc_bracket_format)m{`e[0m"
      
        $string += " `e[$($utility.kvinc_key_color)$($utility.kvinc_key_format)m$keyName`e[0m"
        $string += " `e[$($utility.kvinc_bracket_color)$($utility.kvinc_bracket_format)m:`e[0m"
        $string += " `e[$($utility.kvinc_value_color)$($utility.kvinc_value_format)m$KeyValue`e[0m"
      
        $string += "`e[$($utility.kvinc_bracket_color)$($utility.kvinc_bracket_format)m }`e[0m"
      
        return $string.replace("^\{", "")
    
    }
    else {

        $string += "`e[$($utility.kvinc_bracket_color)$($utility.kvinc_bracket_format)m{`e[0m "

        switch ($type) {
            # NOTE: Add in more options
            'inf'  { $string += "`e[37$($utility.kvinc_type_format)mINF`e[0m ≡" }
            'wrn'  { $string += "`e[33$($utility.kvinc_type_format)mWRN`e[0m ≡" }
            'err'  { $string += "`e[31$($utility.kvinc_type_format)mERR`e[0m ≡" }
            'prop' { $string += "`e[31$($utility.kvinc_type_format)mPROP`e[0m ≡" }
            'property' { $string += "`e[31$($utility.kvinc_type_format)mPROPERTY`e[0m ≡" }
            'api'  { $string += "`e[31$($utility.kvinc_type_format)mAPI`e[0m ≡" } 
            'git'  { $string += "`e[31$($utility.kvinc_type_format)mGIT`e[0m ≡" }
            'value'{ $string += "`e[31$($utility.kvinc_type_format)mVALUE`e[0m ≡" }
            'key'  { $string += "`e[31$($utility.kvinc_type_format)mKEY`e[0m ≡" }
            'type' { $string += "`e[31$($utility.kvinc_type_format)mTYPE`e[0m ≡" }
            'meta' { $string += "`e[31$($utility.kvinc_type_format)mMETA`e[0m ≡" }
            'metadata' { $string += "`e[31$($utility.kvinc_type_format)mMETADATA`e[0m ≡" }
            'confval' { $string += "`e[31$($utility.kvinc_type_format)mCONFVAL`e[0m ≡" }
            'none' { $string = "" }
            default {  }
        }
        $string += " `e[$($utility.kvinc_key_color)$($utility.kvinc_key_format)m$keyName`e[0m"
        $string += " `e[$($utility.kvinc_bracket_color)$($utility.kvinc_bracket_format)m:`e[0m"
        $string += " `e[$($utility.kvinc_value_color)$($utility.kvinc_value_format)m$KeyValue`e[0m"
       
        $string += " `e[$($utility.kvinc_bracket_color)$($utility.kvinc_bracket_format)m}`e[0m"

        return $string
    }
}

# Example usage:

# $message = "This is a test message with a {kv:username=JohnDoe} and a {prop:kv:userid=12345} and a {meta:kv:session=abcde"
# $result = New-kvstring -message $message