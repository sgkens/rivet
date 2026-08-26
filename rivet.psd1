@{
    RootModule = 'rivet.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'd2df54f7-d5e0-4690-bfc8-4e28c519e109'
    Author = 'StaticCanvas'
    CompanyName = 'StaticCanvas'
    Copyright = '(c) StaticCanvas. MIT License.'
    Description = 'Reusable GitLab metadata, release, and JavaScript library automation.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Invoke-Rivet'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @(
        'rivet',
        'Invoke-Glmeta',
        'glmeta'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('gitlab', 'javascript', 'release', 'automation')
            LicenseUri = 'https://opensource.org/license/mit'
            ProjectUri = 'https://gitlab.com/staticcanvas/rivet'
        }
    }
}
