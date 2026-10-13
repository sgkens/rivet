BeforeAll {
    $script:RivetRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..'))
    $script:ScriptsRoot = [System.IO.Path]::Combine($script:RivetRoot, 'scripts')
    foreach ($name in @(
        'asciitokenizer.ps1',
        'lazylog.ps1',
        'Get-RivetProfile.ps1',
        'Get-RivetPSModuleManifest.ps1',
        'Get-RivetConfiguration.ps1',
        'Initialize-RivetRepository.ps1',
        'Test-ReadmeStructure.ps1',
        'ConvertFrom-ConventionalCommit.ps1',
        'Get-ConventionalCommitVersion.ps1',
        'Update-JSLibSemver.ps1',
        'jsheader.ps1',
        'New-MarkdownTOC.ps1',
        'Invoke-RepositoryCommit.ps1',
        'Invoke-RepositoryTag.ps1',
        'Invoke-GitLabMergeRequest.ps1',
        'Update-ReleaseDocumentation.ps1',
        'Update-MergeRequestDocumentation.ps1',
        'smenu.ps1',
        'Show-RivetPager.ps1',
        'Write-PrettyGitLog.ps1',
        'Write-RivetVersionReport.ps1',
        'Write-RivetRepositoryStatus.ps1',
        'Test-RivetRepository.ps1',
        'Show-RivetFlowGraph.ps1',
        'Sync-RivetWorkItems.ps1',
        'Invoke-RivetMenu.ps1',
        'Invoke-Rivet.ps1'
    )) { . ([System.IO.Path]::Combine($script:ScriptsRoot, $name)) }
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'flowgraph', 'private', 'Engine.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'flowgraph', 'public', 'New-FlowNode.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'flowgraph', 'public', 'New-FlowEdge.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'flowgraph', 'public', 'New-FlowGraph.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'flowgraph', 'public', 'Show-FlowGraph.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'data_utils', 'Resolve-RivetPath.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'cache', 'rivet_cache.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'ui', 'Write-RivetReportCard.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'args-completers', 'argumentcompleters.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'string', 'clap.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'ui', 'Format-TuiString.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'ui', 'Get-TerminalUI.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'color', 'terpal.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'ui', 'New-TuiPanel.ps1'))
    . ([System.IO.Path]::Combine($script:ScriptsRoot, 'helpers', 'datetime', 'Get-ElaspedTime.ps1'))

    function Invoke-TestGit {
        param([string]$Root, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        $output = @(& git -C $Root @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join ' ')" }
        return $output
    }

    function New-TestRepository {
        param([string]$Root, [string]$Version = '1.0.0')
        [System.IO.Directory]::CreateDirectory($Root) | Out-Null
        Invoke-TestGit $Root init --initial-branch=main | Out-Null
        Invoke-TestGit $Root config user.name testuser | Out-Null
        Invoke-TestGit $Root config user.email test@example.invalid | Out-Null
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($Root, 'package.json'), "{`"name`":`"@fixture/library`",`"version`":`"$Version`"}")
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($Root, 'jsr.jsonc'), "{`"version`":`"$Version`"}")
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($Root, 'README.md'), '# Test')
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($Root, 'CHANGELOG.md'), "# Changelog`n`n## [Unreleased]`n`n<!-- glmeta:changelog:start -->`n<!-- glmeta:changelog:end -->`n")
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($Root, 'release-notes.md'), "<!-- glmeta:release-notes:start -->`n<!-- glmeta:release-notes:end -->`n")
        Invoke-TestGit $Root add --all | Out-Null
        Invoke-TestGit $Root commit -m 'chore: initialize fixture' | Out-Null
        Invoke-TestGit $Root tag "v$Version" | Out-Null
    }

    function New-TestConfig {
        param(
            [string]$Path,
            [string]$Remote = 'origin',
            [object[]]$RequiredHeadings = @([ordered]@{ level = 1; name = 'Test' })
        )
        $document = [ordered]@{
            project = [ordered]@{ displayName = 'Fixture'; path = 'group/fixture' }
            gitlab = [ordered]@{ baseUri = 'https://gitlab.example'; projectId = ''; tokenEnvironmentVariable = 'RIVET_TEST_TOKEN' }
            requestTimeoutSeconds = 5
            commit = [ordered]@{
                defaultType = 'feat'; defaultScope = 'core'; defaultDescription = 'fixture change'
                types = @([ordered]@{ name = 'feat'; description = 'feature' }, [ordered]@{ name = 'fix'; description = 'fix' })
                scopes = @([ordered]@{ name = 'core'; description = 'core'; paths = @('**') }, [ordered]@{ name = 'none'; description = 'none'; paths = @('**') })
                preview = [ordered]@{ maxDiffLines = 40 }
            }
            authors = [ordered]@{ mappings = @([ordered]@{ email = 'test@example.invalid'; username = 'fixture-user' }) }
            tagging = [ordered]@{ prefix = 'v'; releaseSuffix = '-release'; remote = $Remote }
            readme = [ordered]@{ requiredHeadings = $RequiredHeadings }
        }
        [System.IO.File]::WriteAllText($Path, ($document | ConvertTo-Json -Depth 12))
    }
}

Describe 'Rivet module boundary' {
    It 'has a valid manifest and imports without leaking unreviewed helpers' {
        $manifestPath = Join-Path $script:RivetRoot 'rivet.psd1'
        $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        $manifest.Name | Should -Be 'Rivet'

        $module = Import-Module $manifestPath -Force -DisableNameChecking -PassThru -ErrorAction Stop
        $exported = @($module.ExportedFunctions.Keys)
        $exported | Should -Contain 'Invoke-Rivet'
        $exported | Should -Not -Contain 'Update-ReleaseDocumentation'
        $exported | Should -Not -Contain 'Invoke-UpperCase'
        $exported | Should -Not -Contain 'Invoke-LowerCase'
        $exported | Should -Not -Contain 'New-Spinner'
        (Get-Alias rivet).ResolvedCommandName | Should -Be 'Invoke-Rivet'

        $privateRuntime = @(& $module {
            Get-Command Show-TerminalCursor, Hide-TerminalCursor, Enable-TerminalAltBuffer, Disable-TerminalAltBuffer, Initialize-RivetRepository, Update-ReleaseDocumentation, Invoke-RivetMenu |
                Select-Object -ExpandProperty Name
        })
        $privateRuntime | Should -Contain 'Show-TerminalCursor'
        $privateRuntime | Should -Contain 'Hide-TerminalCursor'
        $privateRuntime | Should -Contain 'Enable-TerminalAltBuffer'
        $privateRuntime | Should -Contain 'Disable-TerminalAltBuffer'
        $privateRuntime | Should -Contain 'Initialize-RivetRepository'
        $privateRuntime | Should -Contain 'Update-ReleaseDocumentation'
        $privateRuntime | Should -Contain 'Invoke-RivetMenu'
    }

    It 'loads the module once instead of dot-sourcing runtime files in the runner' {
        $runnerSource = [System.IO.File]::ReadAllText((Join-Path $script:RivetRoot 'run.ps1'))
        $runnerSource | Should -Match 'Import-Module \$modulePath'
        $runnerSource | Should -Not -Match 'Import-Module \$modulePath -Force'
        $runnerSource | Should -Not -Match '(?m)^\s*\.\s+\(\[System\.IO\.Path\]::Combine\('
    }

    It 'isolates reviewed workflows from the active menu module' {
        $menuSource = [System.IO.File]::ReadAllText((Join-Path $script:ScriptsRoot 'Invoke-RivetMenu.ps1'))
        $menuSource | Should -Match '& pwsh -NoLogo -NoProfile -File \$resolvedRunner'
        $menuSource | Should -Not -Match '(?m)^\s*& \$resolvedRunner -RepositoryRoot'
    }

    It 'routes help output through the responsive pager' {
        $menuSource = [System.IO.File]::ReadAllText((Join-Path $script:ScriptsRoot 'Invoke-RivetMenu.ps1'))
        $menuSource | Should -Match "Show-RivetPager -Title 'RIVET HELP'"
        $pagerSource = [System.IO.File]::ReadAllText((Join-Path $script:ScriptsRoot 'Show-RivetPager.ps1'))
        $pagerSource | Should -Match "'PageUp'"
        $pagerSource | Should -Match "'PageDown'"
        $pagerSource | Should -Match '\[Console\]::WindowWidth'
        $pagerSource | Should -Match 'Split-SMenuText'
    }
}

Describe 'Initialize-RivetRepository' {
    It 'previews, creates, and preserves repository-root configuration' {
        $repo = Join-Path $TestDrive 'init-repo'
        New-TestRepository -Root $repo
        $templateRoot = Join-Path $script:RivetRoot 'templates/js'
        $preview = @(Initialize-RivetRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -DryRun)
        $preview.State | Should -Contain 'WOULD CREATE'
        Test-Path (Join-Path $repo 'repo_config.json') | Should -BeFalse
        $created = @(Initialize-RivetRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -Confirm:$false)
        $created.State | Should -Contain 'CREATED'
        (Get-RivetConfiguration -ConfigPath (Join-Path $repo 'repo_config.json')).project.name | Should -Be 'library'
        (Get-RivetConfiguration -ConfigPath (Join-Path $repo 'repo_config.json')).project.path | Should -Be 'fixture/library'
        Test-Path (Join-Path $repo 'src/library.js') | Should -BeTrue
        $existing = @(Initialize-RivetRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -Confirm:$false)
        @($existing | Where-Object State -eq 'EXISTS').Count | Should -BeGreaterOrEqual 2
    }

    It 'initializes Bun configuration when -Bun is specified' {
        $repo = Join-Path $TestDrive 'init-bun-repo'
        New-TestRepository -Root $repo
        $templateRoot = Join-Path $script:RivetRoot 'templates/js'
        $created = @(Initialize-RivetRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -Bun -Confirm:$false)
        $created.File | Should -Contain 'bunfig.toml'
        $created.File | Should -Contain 'package.json'
        Test-Path (Join-Path $repo 'bunfig.toml') | Should -BeTrue
        Test-Path (Join-Path $repo 'package.json') | Should -BeTrue
    }

    It 'uses the final remote segment for nested GitLab project paths' {
        $repo = Join-Path $TestDrive 'nested-group-repo'
        [System.IO.Directory]::CreateDirectory($repo) | Out-Null
        Invoke-TestGit $repo init --initial-branch=main | Out-Null
        Invoke-TestGit $repo config user.name testuser | Out-Null
        Invoke-TestGit $repo config user.email test@example.invalid | Out-Null
        Invoke-TestGit $repo remote add origin 'git@gitlab.example:group/subgroup/project.git' | Out-Null

        Initialize-RivetRepository -RepositoryRoot $repo -Profile 11ty -Raw -Confirm:$false | Out-Null
        $config = Get-RivetConfiguration (Join-Path $repo 'repo_config.json')
        $config.project.name | Should -Be 'project'
        $config.project.namespace | Should -Be 'group'
        $config.project.path | Should -Be 'group/subgroup/project'
        $config.gitlab.baseUri | Should -Be 'https://gitlab.example'
        $config.project.documentationUrl | Should -Be 'https://gitlab.example/group/subgroup/project'
        $package = Get-Content (Join-Path $repo 'package.json') -Raw | ConvertFrom-Json
        $package.repository.url | Should -Be 'https://gitlab.example/group/subgroup/project.git'
    }

    It 'uses a neutral namespace when no remote or package identity exists' {
        $repo = Join-Path $TestDrive 'neutral-repo'
        [System.IO.Directory]::CreateDirectory($repo) | Out-Null
        Invoke-TestGit $repo init --initial-branch=main | Out-Null
        Invoke-TestGit $repo config user.name testuser | Out-Null
        Invoke-TestGit $repo config user.email test@example.invalid | Out-Null

        Initialize-RivetRepository -RepositoryRoot $repo -Profile 11ty -Raw -Confirm:$false | Out-Null
        $config = Get-RivetConfiguration (Join-Path $repo 'repo_config.json')
        $config.project.namespace | Should -Be 'local'
        $config.project.path | Should -Be 'local/neutral-repo'
    }

    It 'keeps the generic JavaScript scaffold free of project-specific dependencies' {
        $templateRoot = Join-Path $script:RivetRoot 'templates/js'
        $templateFiles = [System.IO.Directory]::GetFiles($templateRoot, '*', [System.IO.SearchOption]::AllDirectories)
        $content = ($templateFiles | ForEach-Object { [System.IO.File]::ReadAllText($_) }) -join "`n"
        $content | Should -Not -Match '(?i)@staticcanvas|\blume\b|\basciiam\b|\bhawk\b|\btypeflow\b|phellams|\bhugo\b'
        $content | Should -Match 'vitest run --passWithNoTests'
        $content | Should -Match 'if \[ -f package-lock\.json \]; then npm ci; else npm install; fi'
    }

    It 'adds and excludes scaffold files through repository configuration' {
        $repo = Join-Path $TestDrive 'configured-scaffold-repo'
        New-TestRepository -Root $repo
        Initialize-RivetRepository -RepositoryRoot $repo -Profile jsm -Raw -Confirm:$false | Out-Null
        $configPath = Join-Path $repo 'repo_config.json'
        $config = Get-RivetConfiguration $configPath
        $config.scaffold = [pscustomobject]@{
            exclude = @('.prettierrc')
            templates = @([pscustomobject]@{
                file = 'generated/project.txt'
                template = '.rivet/project.txt.template'
                tokenReplace = $true
            })
        }
        [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 32))
        [System.IO.Directory]::CreateDirectory((Join-Path $repo '.rivet')) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo '.rivet/project.txt.template'), 'project={{PROJECT_NAME}}')
        [System.IO.File]::Delete((Join-Path $repo '.prettierrc'))

        Initialize-RivetRepository -RepositoryRoot $repo -Raw -Confirm:$false | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $repo 'generated/project.txt')) | Should -Be 'project=library'
        Test-Path (Join-Path $repo '.prettierrc') | Should -BeFalse
    }
}

Describe 'Test-RivetRepository' {
    It 'validates repository readiness, Git identity, and manifest consistency' {
        $repo = Join-Path $TestDrive 'doctor-repo'
        New-TestRepository -Root $repo -Version '1.0.0'
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        [System.IO.File]::WriteAllText((Join-Path $repo 'repo_meta.json'), '{}')
        $result = Test-RivetRepository -RepositoryRoot $repo -ConfigPath $config
        $result.Ready | Should -BeTrue
        @($result.Checks | Where-Object Name -eq 'Git identity').Passed | Should -BeTrue
        @($result.Checks | Where-Object Name -eq 'Manifest versions').Passed | Should -BeTrue
    }

    It 'fails when manifest versions drift between package.json and jsr.jsonc' {
        $repo = Join-Path $TestDrive 'doctor-drift-repo'
        New-TestRepository -Root $repo -Version '1.0.0'
        [System.IO.File]::WriteAllText((Join-Path $repo 'jsr.jsonc'), '{"version":"1.1.0"}')
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        $result = Test-RivetRepository -RepositoryRoot $repo -ConfigPath $config
        $result.Ready | Should -BeFalse
        @($result.Failures.Name) | Should -Contain 'Manifest versions'
    }
}

Describe 'Test-ReadmeStructure' {
    It 'reports configured headings and ignores headings inside code fences' {
        $repo = Join-Path $TestDrive 'readme-repo'
        New-TestRepository -Root $repo
        $readme = @'
# Test

## **Features**

```md
## API Reference
```
'@
        [System.IO.File]::WriteAllText((Join-Path $repo 'README.md'), $readme)
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config -RequiredHeadings @(
            [ordered]@{ level = 2; name = 'Features' },
            [ordered]@{ level = 2; name = 'API Reference' }
        )
        $result = Test-ReadmeStructure -RepositoryRoot $repo -ConfigPath $config -Quiet
        $result.Ready | Should -BeFalse
        $result.Missing.Heading | Should -Contain 'API Reference'
        $result.Requirements | Where-Object Heading -eq 'Features' | Select-Object -ExpandProperty Passed | Should -BeTrue
    }

    It 'rejects duplicate required sections' {
        $repo = Join-Path $TestDrive 'duplicate-readme-repo'
        New-TestRepository -Root $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'README.md'), "# Test`n`n## Features`n`n## Features`n")
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config -RequiredHeadings @([ordered]@{ level = 2; name = 'Features' })
        $result = Test-ReadmeStructure -RepositoryRoot $repo -ConfigPath $config -Quiet
        $result.Ready | Should -BeFalse
        $result.Missing.Count | Should -Be 0
        $result.Duplicates.Heading | Should -Contain 'Features'
        $result.Duplicates | Select-Object -ExpandProperty Count | Should -Contain 2
    }
}

Describe 'Update-JSHeader README variants' {
    It 'updates repository and npm headers from one release version' {
        $repo = Join-Path $TestDrive 'header-repo'
        New-TestRepository -Root $repo -Version '1.0.0'
        [System.IO.File]::WriteAllText((Join-Path $repo 'package.json'), '{"name":"@group/fixture","version":"1.2.3"}')
        [System.IO.File]::WriteAllText((Join-Path $repo 'repo_meta.json'), '{"project":{"description":"A reusable test package."}}')
        $configDocument = [ordered]@{
            project = [ordered]@{
                name = 'fixture'; displayName = 'Fixture'; path = 'group/fixture'; artifactPath = 'group/fixture'
                defaultBranch = 'main'; npmPackage = '@group/fixture'; jsrPackage = '@group/fixture'
                bannerUrl = 'https://example.invalid/banner.svg'; documentationUrl = 'https://example.invalid/docs'
            }
            readmeHeader = [ordered]@{
                alignment = 'left'; badgeStyle = 'flat-square'; badgeColor = '#0087af'
                labelColor = '#1c1c1c'; logoColor = '#ffffff'; codecovToken = 'TOKEN'
            }
            tagging = [ordered]@{ prefix = 'v'; releaseSuffix = '-release'; remote = 'origin' }
            gitlab = [ordered]@{ baseUri = 'https://gitlab.example' }
            metadataSource = 'repo_meta.json'
        }
        [System.IO.File]::WriteAllText((Join-Path $repo 'repo_config.json'), ($configDocument | ConvertTo-Json -Depth 8))
        [System.IO.File]::WriteAllText((Join-Path $repo 'README.md'), "<div align=`"center`">`nold`n</div>`n`nMAIN BODY")
        [System.IO.File]::WriteAllText((Join-Path $repo 'README-npm.md'), "old npm header`n`n---`n`nNPM BODY")

        Update-JSHeader -RepositoryRoot $repo

        $main = [System.IO.File]::ReadAllText((Join-Path $repo 'README.md'))
        $npm = [System.IO.File]::ReadAllText((Join-Path $repo 'README-npm.md'))
        $main | Should -Match 'branch/v1\.2\.3-release/graph/badge\.svg'
        $npm | Should -Match 'branch/v1\.2\.3-release/graph/badge\.svg'
        $main | Should -Match 'artifacts/v1\.0\.0/raw/runtime-badge-flat\.svg'
        $main | Should -Match 'MAIN BODY'
        $npm | Should -Match 'NPM BODY'
        $npm | Should -Match '# \*\*@group/fixture\*\*'
        $main | Should -Match '> A reusable test package\.'
        $npm | Should -Match "A reusable test package\.`n`n---"

        $eleventyTemplate = Join-Path $script:RivetRoot 'templates/11ty/README.header.md.template'
        Update-JSHeader -RepositoryRoot $repo -TemplatePath $eleventyTemplate
        $eleventy = [System.IO.File]::ReadAllText((Join-Path $repo 'README.md'))
        $eleventy | Should -Match '> A reusable test package\.'
        $eleventy | Should -Not -Match '\{\{DESCRIPTION_SUFFIX\}\}'
    }
}

Describe 'ConvertFrom-ConventionalCommit' {
    It 'parses exact scopes and breaking changes' {
        $result = ConvertFrom-ConventionalCommit -Subject 'feat(core)!: add workflow'
        $result.Scope | Should -Be 'core'
        $result.Category | Should -Be 'Added'
        $result.Breaking | Should -BeTrue
    }
}

Describe 'Get-ConventionalCommitVersion' {
    It 'applies every bump in sequence from the nearest reachable tag' {
        $repo = Join-Path $TestDrive 'version-repo'
        New-TestRepository -Root $repo -Version '1.2.3'
        Invoke-TestGit $repo tag --delete v1.2.3 | Out-Null
        Invoke-TestGit $repo tag v1.2.3-release | Out-Null
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nfix")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'fix(core): correct fixture' | Out-Null
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nfeat")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(core): extend fixture' | Out-Null
        $result = Get-ConventionalCommitVersion -RepositoryRoot $repo
        $result.Version | Should -Be '1.3.1'
        $result.LastTag | Should -Be 'v1.2.3-release'
        $result.BumpType | Should -Be 'minor'
    }
}

Describe 'Update-JSLibSemver' {
    It 'synchronizes both root package-lock identities' {
        $repo = Join-Path $TestDrive 'manifest-repo'
        New-TestRepository -Root $repo
        $lock = @'
{
  "name": "@fixture/library",
  "version": "0.1.0",
  "lockfileVersion": 3,
  "packages": {
    "": {
      "name": "@fixture/library",
      "version": "0.1.0",
      "license": "MIT"
    }
  }
}
'@
        [System.IO.File]::WriteAllText((Join-Path $repo 'package-lock.json'), $lock)
        Update-JSLibSemver -RepositoryRoot $repo -Version 1.2.0 -Confirm:$false | Out-Null
        $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText((Join-Path $repo 'package-lock.json')))
        try {
            $document.RootElement.GetProperty('version').GetString() | Should -Be '1.2.0'
            $document.RootElement.GetProperty('packages').GetProperty('').GetProperty('version').GetString() | Should -Be '1.2.0'
        } finally { $document.Dispose() }
    }

    It 'updates package.json when the optional JSR manifest is absent' {
        $repo = Join-Path $TestDrive 'npm-only-manifest-repo'
        New-TestRepository -Root $repo
        [System.IO.File]::Delete((Join-Path $repo 'jsr.jsonc'))

        Update-JSLibSemver -RepositoryRoot $repo -Version 1.2.0 -Confirm:$false | Out-Null

        $package = Get-Content (Join-Path $repo 'package.json') -Raw | ConvertFrom-Json
        $package.version | Should -Be '1.2.0'
    }
}

Describe 'Invoke-RepositoryCommit' {
    It 'selects a changed filename containing spaces without staging it in dry-run mode' {
        $repo = Join-Path $TestDrive 'commit-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        $path = 'file with spaces.txt'
        [System.IO.File]::WriteAllText((Join-Path $repo $path), 'content')
        $result = Invoke-RepositoryCommit -RepositoryRoot $repo -ConfigPath $config -Type feat -Scope core -Description 'add spaced file' -Files $path -DryRun
        $result.Files | Should -Contain $path
        (Invoke-TestGit $repo diff --cached --name-only) | Should -BeNullOrEmpty
    }
}

Describe 'Update-ReleaseDocumentation' {
    It 'generates GitLab commit links and mapped author mentions' {
        $repo = Join-Path $TestDrive 'release-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nfeature")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(core): add fixture feature' | Out-Null
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`ndocs")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'docs(core): document fixture feature' | Out-Null
        Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.0.0 -Version 1.1.0 -WriteChangelogJson -Confirm:$false | Out-Null
        $content = [System.IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))
        $content | Should -Match '<!-- rivet:changelog:start -->'
        $content | Should -Not -Match '<!-- glmeta:changelog:start -->'
        $content | Should -Match '\[.{7}\]\(https://gitlab\.example/group/fixture/-/commit/[0-9a-f]{40}\)'
        $content | Should -Match '@fixture-user'
        $content | Should -Match 'Document fixture feature\.'

        $json = [System.IO.File]::ReadAllText((Join-Path $repo 'docs/data/changelog.json')) | ConvertFrom-Json
        $json.source.history | Should -Be 'git'
        $json.source.canonical_record | Should -Be 'CHANGELOG.md'
        $json.versions[0].version | Should -Be 'unreleased'
        $json.schema_version | Should -Be 2
        $json.versions[0].included | Should -Be 2
        $json.versions[0].excluded_non_version_bump | Should -Be 1
        ($json.versions[0].entries | Where-Object type -eq 'feat').commit.url | Should -Match '/-/commit/[0-9a-f]{40}$'
        ($json.versions[0].entries | Where-Object text -eq 'Document fixture feature.').type | Should -BeNullOrEmpty
        $json.versions[0].to | Should -Match '^[0-9a-f]{40}$'
    }

    It 'freezes prior generated notes when finalizing the next version and is idempotent' {
        $repo = Join-Path $TestDrive 'release-history-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config

        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nfirst")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(core): add first release feature' | Out-Null
        Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.0.0 -Version 1.1.0 -Finalize -WriteChangelogJson -Confirm:$false | Out-Null
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'chore(release): prepare 1.1.0' | Out-Null
        Invoke-TestGit $repo tag v1.1.0-release | Out-Null

        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nsecond")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'fix(core): correct second release behavior' | Out-Null
        Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.1.0-release -Version 1.1.1 -Finalize -WriteChangelogJson -Confirm:$false | Out-Null

        $changelogPath = Join-Path $repo 'CHANGELOG.md'
        $firstPass = [System.IO.File]::ReadAllText($changelogPath)
        $firstPass | Should -Match '(?s)## \[1\.1\.1\].*?Correct second release behavior\.'
        $firstPass | Should -Match '(?s)## \[1\.1\.0\].*?Add first release feature\.'
        ([regex]::Matches($firstPass, '<!-- rivet:changelog:start -->')).Count | Should -Be 1

        $json = [System.IO.File]::ReadAllText((Join-Path $repo 'docs/data/changelog.json')) | ConvertFrom-Json
        @($json.versions.version) | Should -Be @('1.1.1', '1.1.0', 'unreleased')
        ($json.versions | Where-Object version -eq '1.1.0').entries.text | Should -Contain 'Add first release feature.'

        Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.1.0-release -Version 1.1.1 -Finalize -WriteChangelogJson -Confirm:$false | Out-Null
        [System.IO.File]::ReadAllText($changelogPath) | Should -BeExactly $firstPass
    }

    It 'rejects finalizing post-tag commits under an already released version' {
        $repo = Join-Path $TestDrive 'released-version-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nmaintenance")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'docs: update usage notes' | Out-Null

        {
            Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.0.0 -Version 1.0.0 -Finalize -Confirm:$false
        } | Should -Throw '*already tagged*'
    }

    It 'moves managed markers back to Unreleased without deleting finalized notes' {
        $repo = Join-Path $TestDrive 'draft-marker-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nreleased")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(core): add released behavior' | Out-Null
        Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.0.0 -Version 1.1.0 -Finalize -Confirm:$false | Out-Null
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'chore(release): prepare 1.1.0' | Out-Null
        Invoke-TestGit $repo tag v1.1.0-release | Out-Null
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`ndraft")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'docs: document next release' | Out-Null

        Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.1.0-release -Confirm:$false | Out-Null
        $content = [System.IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))
        $content | Should -Match '(?s)## \[Unreleased\].*?<!-- rivet:changelog:start -->.*?Document next release\.'
        $content | Should -Match '(?s)## \[1\.1\.0\].*?Add released behavior\.'
        ([regex]::Matches($content, '<!-- rivet:changelog:start -->')).Count | Should -Be 1
    }

    It 'rebuilds changelog across multiple historical tags and produces valid JSON' {
        $repo = Join-Path $TestDrive 'rebuild-changelog-repo'
        New-TestRepository -Root $repo -Version '1.0.0'
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config

        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nfirst")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(core): first feature' | Out-Null
        Invoke-TestGit $repo tag v1.1.0-release | Out-Null

        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nsecond")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'fix(core): second fix' | Out-Null
        Invoke-TestGit $repo tag v1.1.1-release | Out-Null

        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nunreleased")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(ui): unreleased feature' | Out-Null

        Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $config -Rebuild -WriteChangelogJson -Confirm:$false | Out-Null
        $changelog = [System.IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))
        $changelog | Should -Match '## \[Unreleased\]'
        $changelog | Should -Match 'Unreleased feature\.'
        $changelog | Should -Match '## \[1\.1\.1-release\]'
        $changelog | Should -Match 'Second fix\.'
        $changelog | Should -Match '## \[1\.1\.0-release\]'
        $changelog | Should -Match 'First feature\.'

        $json = [System.IO.File]::ReadAllText((Join-Path $repo 'docs/data/changelog.json')) | ConvertFrom-Json
        $json.versions.Count | Should -Be 4 # unreleased, 1.1.1-release, 1.1.0-release, 1.0.0
        ($json.versions | Where-Object version -eq 'unreleased').entries.text | Should -Contain 'Unreleased feature.'
        ($json.versions | Where-Object version -eq '1.1.1-release').entries.text | Should -Contain 'Second fix.'
    }
}

Describe 'Invoke-RepositoryTag' {
    It 'reports dirty worktree blockers during dry-run' {
        $repo = Join-Path $TestDrive 'tag-repo'
        $remote = Join-Path $TestDrive 'tag-remote.git'
        New-TestRepository -Root $repo
        & git init --bare $remote | Out-Null
        Invoke-TestGit $repo remote add origin $remote | Out-Null
        Invoke-TestGit $repo push --set-upstream origin main | Out-Null
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`ndirty")
        $result = Invoke-RepositoryTag -RepositoryRoot $repo -ConfigPath $config -Version 1.0.0 -Snapshot -DryRun
        $result.Tag | Should -Be 'v1.0.0'
        $result.Ready | Should -BeFalse
        $result.Blockers -join ' ' | Should -Match 'worktree must be clean'
    }

    It 'atomically publishes an ahead branch and its tag to a bare remote' {
        $repo = Join-Path $TestDrive 'publish-repo'
        $remote = Join-Path $TestDrive 'publish-remote.git'
        New-TestRepository -Root $repo
        & git init --bare $remote | Out-Null
        Invoke-TestGit $repo remote add origin $remote | Out-Null
        Invoke-TestGit $repo push --set-upstream origin main | Out-Null
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        [System.IO.File]::WriteAllText((Join-Path $repo 'package.json'), '{"version":"1.1.0"}')
        [System.IO.File]::WriteAllText((Join-Path $repo 'jsr.jsonc'), '{"version":"1.1.0"}')
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(core): prepare publication' | Out-Null
        $head = (Invoke-TestGit $repo rev-parse HEAD).Trim()
        $result = Invoke-RepositoryTag -RepositoryRoot $repo -ConfigPath $config -Version 1.1.0 -Force
        $result.Pushed | Should -BeTrue
        (Invoke-TestGit $repo ls-remote origin refs/heads/main) | Should -Match $head
        (Invoke-TestGit $repo ls-remote origin refs/tags/v1.1.0-release) | Should -Not -BeNullOrEmpty
        $retry = Invoke-RepositoryTag -RepositoryRoot $repo -ConfigPath $config -Version 1.1.0 -DryRun
        $retry.Ready | Should -BeFalse
        $retry.Blockers -join ' ' | Should -Match 'already exists on remote'
    }
}

Describe 'Update-MergeRequestDocumentation' {
    It 'calculates merge request type in title and updates table template' {
        $repo = Join-Path $TestDrive 'update-mr-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config

        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nnew feature")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat(core): add shiny feature' | Out-Null

        Update-MergeRequestDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.0.0 -Version 1.1.0 -Confirm:$false | Out-Null

        $mrContent = [System.IO.File]::ReadAllText((Join-Path $repo 'mr.md'))
        $mrContent | Should -Match 'Title:\s*\|\s*`Release \(minor\) Fixture 1\.1\.0`'
        $mrContent | Should -Match 'Source branch:\s*\|\s*`main`'
        $mrContent | Should -Match 'Target branch:\s*\|\s*`main`'
        $mrContent | Should -Match '(?:\*\*)?Commit logs parsed(?::?\*\*|\*\*:?|:)?\s*\|\s*`1`'
        $mrContent | Should -Match 'Add shiny feature\.'
        $mrContent | Should -Match 'Update configured JavaScript package manifests to `1\.1\.0`\.'
    }

    It 'calculates patch bump type when only fixes exist' {
        $repo = Join-Path $TestDrive 'patch-mr-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config

        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nfix bug")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'fix(core): correct edge case' | Out-Null

        Update-MergeRequestDocumentation -RepositoryRoot $repo -ConfigPath $config -FromTag v1.0.0 -Version 1.0.1 -Confirm:$false | Out-Null

        $mrContent = [System.IO.File]::ReadAllText((Join-Path $repo 'mr.md'))
        $mrContent | Should -Match 'Title:\s*\|\s*`Release \(patch\) Fixture 1\.0\.1`'
    }
}

Describe 'Invoke-GitLabMergeRequest' {
    It 'previews creation from mr.md without sending a write request' {
        $repo = Join-Path $TestDrive 'merge-request-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        $mr = @'
# Merge Request

## Title

Release Fixture 1.1.0

## Source branch

`develop`

## Target branch

`main`

## Change range

Fixture changes.

## Summary

- Add fixture behavior.
'@
        [System.IO.File]::WriteAllText((Join-Path $repo 'mr.md'), $mr)
        [System.Environment]::SetEnvironmentVariable('RIVET_TEST_TOKEN', 'test-token')
        try {
            Mock Invoke-RestMethod { return @() } -ParameterFilter { $Method -eq 'Get' }
            $result = Invoke-GitLabMergeRequest -RepositoryRoot $repo -ConfigPath $config -Mode Create -DryRun
            $result.Applied | Should -BeFalse
            $result.Title | Should -Be 'Release Fixture 1.1.0'
            $result.SourceBranch | Should -Be 'develop'
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Method -eq 'Get' }
            Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Method -in @('Post', 'Put') }
        } finally {
            [System.Environment]::SetEnvironmentVariable('RIVET_TEST_TOKEN', $null)
        }
    }

    It 'creates merge request from table format and writes back IID and link to mr.md' {
        $repo = Join-Path $TestDrive 'table-mr-create-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        $templatePath = Join-Path $script:RivetRoot 'templates/mr.md'
        $mrTemplate = [System.IO.File]::ReadAllText($templatePath)
        $mr = $mrTemplate -replace '`Merge Request Title`', '`Release (minor) Fixture 1.1.0`' `
                          -replace '`source-branch`', '`develop`' `
                          -replace '`target-branch`', '`main`'
        [System.IO.File]::WriteAllText((Join-Path $repo 'mr.md'), $mr)
        [System.Environment]::SetEnvironmentVariable('RIVET_TEST_TOKEN', 'test-token')
        try {
            Mock Invoke-RestMethod { return @() } -ParameterFilter { $Method -eq 'Get' }
            Mock Invoke-RestMethod {
                return [pscustomobject]@{
                    iid = 42
                    web_url = 'https://gitlab.example/group/fixture/-/merge_requests/42'
                }
            } -ParameterFilter { $Method -eq 'Post' }

            $result = Invoke-GitLabMergeRequest -RepositoryRoot $repo -ConfigPath $config -Mode Create
            $result.Applied | Should -BeTrue
            $result.Iid | Should -Be 42
            $result.Title | Should -Be 'Release (minor) Fixture 1.1.0'

            $updatedMr = [System.IO.File]::ReadAllText((Join-Path $repo 'mr.md'))
            $updatedMr | Should -Match '(?:\*\*)?Gitlab Merge Request IID(?::?\*\*|\*\*:?|:)?\s*\|\s*`!42`'
            $updatedMr | Should -Match '(?:\*\*)?Gitlab Merge Link(?::?\*\*|\*\*:?|:)?\s*\|\s*`https://gitlab\.example/group/fixture/-/merge_requests/42`'
        } finally {
            [System.Environment]::SetEnvironmentVariable('RIVET_TEST_TOKEN', $null)
        }
    }

    It 'updates merge request using existing IID in mr.md' {
        $repo = Join-Path $TestDrive 'table-mr-update-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        $templatePath = Join-Path $script:RivetRoot 'templates/mr.md'
        $mrTemplate = [System.IO.File]::ReadAllText($templatePath)
        $mr = $mrTemplate -replace '`Merge Request Title`', '`Release (patch) Fixture 1.1.1`' `
                          -replace '`source-branch`', '`develop`' `
                          -replace '`target-branch`', '`main`' `
                          -replace '`id here`', '`!42`'
        [System.IO.File]::WriteAllText((Join-Path $repo 'mr.md'), $mr)
        [System.Environment]::SetEnvironmentVariable('RIVET_TEST_TOKEN', 'test-token')
        try {
            Mock Invoke-RestMethod {
                return [pscustomobject]@{
                    iid = 42
                    web_url = 'https://gitlab.example/group/fixture/-/merge_requests/42'
                }
            } -ParameterFilter { $Method -eq 'Put' }

            $result = Invoke-GitLabMergeRequest -RepositoryRoot $repo -ConfigPath $config -Mode Update
            $result.Applied | Should -BeTrue
            $result.Iid | Should -Be 42
            $result.Title | Should -Be 'Release (patch) Fixture 1.1.1'
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Method -eq 'Put' -and $Uri -match '/42$' }
        } finally {
            [System.Environment]::SetEnvironmentVariable('RIVET_TEST_TOKEN', $null)
        }
    }
}

Describe 'rivet command-center multi-action labels' {
    It 'renders multi-action titles with an orange-to-blue gradient and single actions in white' {
        $menuSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/Invoke-RivetMenu.ps1'))
        $menuSource | Should -Not -Match '"\[MA\] \$Label"'
        $rendererSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/smenu.ps1'))
        $rendererSource | Should -Match 'return "\$label \[MA\]"'
        $rendererSource | Should -Match 'Format-GradientString -Text \$Text -Start @\(255, 130, 0\) -End @\(0, 120, 255\)'
        $rendererSource | Should -Match 'Single\s*=\s*"\$esc\[1;38;2;255;255;255m"'

        $routerSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/Invoke-Rivet.ps1'))
        $routerSource | Should -Match 'StartColor @\(255, 130, 0\) -EndColor @\(0, 120, 255\)'
        $routerSource | Should -Match 'Rivet repository command center'
        $routerSource | Should -Not -Match 'StaticCanvas repository command center'

        @(
            'Initialize repository'
            'Prep Release'
            'Release documents'
            'Tag and publish'
            'Configuration and GitLab'
            'Preview release preparation'
            'Apply release preparation'
            'Apply and commit'
            'Preview all'
            'Apply all'
            'Generate and create on GitLab'
            'Generate and update on GitLab'
            'Metadata and commit'
            'Rebuild changelog'
        ) | ForEach-Object {
            $escapedLabel = [regex]::Escape($_)
            $menuSource | Should -Match "New-MenuItem '$escapedLabel'[^\r\n]+-MultiAction"
        }
    }

    It 'publishes CLI command guidance in actionable menu details' {
        $menuSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/Invoke-RivetMenu.ps1'))
        $rendererSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/smenu.ps1'))
        $menuSource | Should -Match "New-MenuItem 'Repository status'[^\r\n]+-Command './rivet\.ps1 status'"
        $menuSource | Should -Match "New-MenuItem 'Apply and commit'[^\r\n]+-Command './rivet\.ps1 prep-release -Commit"
        $menuSource | Should -Match "New-MenuItem 'Push to GitLab'[^\r\n]+-Command './rivet\.ps1 work-items -PushIssues"
        $rendererSource | Should -Match 'CLI  \$\(\[string\]\$selectedCommandProperty\.Value\)'
    }
}

Describe 'responsive rivet menu layout' {
    It 'uses columns on wide terminals and stacked detail on narrow terminals' {
        $wide = Get-SMenuLayout -TerminalWidth 140 -TerminalHeight 40 -ItemCount 14
        $narrow = Get-SMenuLayout -TerminalWidth 60 -TerminalHeight 24 -ItemCount 14
        $wide.Wide | Should -BeTrue
        $narrow.Wide | Should -BeFalse
        $wide.DescriptionWidth | Should -BeGreaterThan 20
        $narrow.FrameWidth | Should -Be 58
    }

    It 'reduces the viewport when terminal height shrinks without hiding item access' {
        $large = Get-SMenuLayout -TerminalWidth 100 -TerminalHeight 40 -ItemCount 20
        $small = Get-SMenuLayout -TerminalWidth 100 -TerminalHeight 14 -ItemCount 20
        $large.VisibleItems | Should -BeGreaterThan $small.VisibleItems
        $small.VisibleItems | Should -BeGreaterOrEqual 1
    }

    It 'wraps detail at word boundaries and preserves all text' {
        $text = 'update manifests, release documents, readmes, and merge request metadata'
        $lines = @(Split-SMenuText -Text $text -Width 24)
        $lines.Count | Should -BeGreaterThan 1
        ($lines -join ' ') | Should -Be $text
        @($lines | Where-Object Length -gt 24).Count | Should -Be 0
    }

    It 'renders intentional blank rows in command-review panels' {
        $panel = New-TuiPanel -Content @('Release documentation', '', 'COMMAND', './rivet.ps1 -UpdateReleaseDocs') -Title 'COMMAND REVIEW' -Width 60 -BorderStyle Rounded
        $plainPanel = $panel -replace "`e\[[0-9;]*[a-zA-Z]", ''
        $rows = @($plainPanel -split '\r?\n')
        $rows.Count | Should -Be 6
        $rows[1] | Should -Match 'Release documentation'
        $rows[2] | Should -Match '^\s*│\s+│$'
        $rows[3] | Should -Match 'COMMAND'
    }
}

Describe 'Invoke-Rivet router execution' {
    It 'routes status command to repository status inspection' {
        $repo = Join-Path $TestDrive 'router-status-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        { Invoke-Rivet -RepositoryRoot $repo -ConfigPath $config -Status } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -ConfigPath $config -Command 'status' } | Should -Not -Throw
    }

    It 'routes version report command' {
        $repo = Join-Path $TestDrive 'router-version-repo'
        New-TestRepository -Root $repo
        { Invoke-Rivet -RepositoryRoot $repo -VersionReport } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -Command 'version' } | Should -Not -Throw
    }

    It 'routes readme validation command' {
        $repo = Join-Path $TestDrive 'router-readme-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        { Invoke-Rivet -RepositoryRoot $repo -ConfigPath $config -ValidateReadme } | Should -Not -Throw
    }

    It 'routes init command in dry-run mode' {
        $repo = Join-Path $TestDrive 'router-init-repo'
        New-TestRepository -Root $repo
        { Invoke-Rivet -RepositoryRoot $repo -Init -DryRun } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -Command 'init' -DryRun } | Should -Not -Throw
    }

    It 'routes local metadata execution in dry-run mode' {
        $repo = Join-Path $TestDrive 'router-local-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        { Invoke-Rivet -RepositoryRoot $repo -ConfigPath $config -SkipReadmeMetadata -SkipTableOfContents -SkipReadmeValidation -DryRun } | Should -Not -Throw
    }

    It 'routes rebuild-changelog command in dry-run mode' {
        $repo = Join-Path $TestDrive 'router-rebuild-repo'
        New-TestRepository -Root $repo
        $config = Join-Path $repo 'repo_config.json'
        New-TestConfig -Path $config
        { Invoke-Rivet -RepositoryRoot $repo -ConfigPath $config -Command 'rebuild-changelog' -DryRun } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -ConfigPath $config -RebuildChangelog -DryRun } | Should -Not -Throw
    }

        It 'routes flow and pipeline commands to Show-RivetFlowGraph' {
        $repo = Join-Path $TestDrive 'router-flow-repo'
        New-TestRepository -Root $repo
        { Invoke-Rivet -RepositoryRoot $repo -FlowGraph } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -Command 'flow' } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -Command 'pipeline' } | Should -Not -Throw
    }

    It 'routes work-items and issues commands' {
        $repo = Join-Path $TestDrive 'router-workitems-repo'
        New-TestRepository -Root $repo
        { Invoke-Rivet -RepositoryRoot $repo -WorkItems -Raw } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -Command 'work-items' -Raw } | Should -Not -Throw
        { Invoke-Rivet -RepositoryRoot $repo -Command 'issues' -Raw } | Should -Not -Throw
    }
}

Describe 'Resolve-RivetPath' {
    It 'resolves items in .rivet/ directory when present' {
        $repo = Join-Path $TestDrive 'resolve-dotrivet-repo'
        New-TestRepository -Root $repo
        $dotRivet = Join-Path $repo '.rivet'
        [System.IO.Directory]::CreateDirectory($dotRivet) | Out-Null
        $dotConfig = Join-Path $dotRivet 'repo_config.json'
        [System.IO.File]::WriteAllText($dotConfig, '{}')

        $resolved = Resolve-RivetPath -RepositoryRoot $repo -ItemName 'repo_config.json'
        $resolved | Should -Be $dotConfig
    }

    It 'falls back to root file when not present in .rivet/' {
        $repo = Join-Path $TestDrive 'resolve-root-repo'
        New-TestRepository -Root $repo
        $rootConfig = Join-Path $repo 'repo_config.json'
        [System.IO.File]::WriteAllText($rootConfig, '{}')

        $resolved = Resolve-RivetPath -RepositoryRoot $repo -ItemName 'repo_config.json'
        $resolved | Should -Be $rootConfig
    }

    It 'defaults to .rivet/ when .rivet directory exists' {
        $repo = Join-Path $TestDrive 'resolve-new-repo'
        New-TestRepository -Root $repo
        $dotRivet = Join-Path $repo '.rivet'
        [System.IO.Directory]::CreateDirectory($dotRivet) | Out-Null
        $resolved = Resolve-RivetPath -RepositoryRoot $repo -ItemName 'mr.md'
        $resolved | Should -Be (Join-Path $dotRivet 'mr.md')
    }

    It 'defaults to root when .rivet directory does not exist' {
        $repo = Join-Path $TestDrive 'resolve-legacy-repo'
        New-TestRepository -Root $repo
        $resolved = Resolve-RivetPath -RepositoryRoot $repo -ItemName 'mr.md'
        $resolved | Should -Be (Join-Path $repo 'mr.md')
    }
}

Describe 'Write-RivetReportCard' {
    It 'generates non-tear gradient panel report card with PassThru' {
        $rows = @(
            @{ State = 'OK'; Label = 'VERSION'; Detail = 'Calculated SemVer 1.1.0 using minor bump.' }
            @{ State = 'SKIP'; Label = 'HEADER'; Detail = 'Disabled by command switch.' }
        )
        $lines = Write-RivetReportCard -Title 'TEST REPORT' -Mode 'APPLY' -ProjectName 'Fixture' -Version '1.1.0' -Branch 'main' -Head 'abc1234' -Rows $rows -PassThru
        $lines.Count | Should -BeGreaterThan 5
        $plain = $lines -replace "`e\[[0-9;]*[a-zA-Z]", ''
        ($plain -join "`n") | Should -Match 'TEST REPORT'
        ($plain -join "`n") | Should -Match 'PROJECT'
        ($plain -join "`n") | Should -Match 'VERSION'
        ($plain -join "`n") | Should -Match 'RESULT: SUCCESS'
    }

    It 'returns structured report data when -Raw is specified' {
        $rows = @(
            @{ State = 'OK'; Label = 'VERSION'; Detail = '1.0.0' }
        )
        $report = Write-RivetReportCard -Title 'RAW REPORT' -Mode 'DRY RUN' -ProjectName 'Fixture' -Rows $rows -Raw
        $report | Should -Not -BeNullOrEmpty
        $report.Title | Should -Be 'RAW REPORT'
        $report.Mode | Should -Be 'DRY RUN'
        $report.Success | Should -BeTrue
    }
}

Describe 'Sync-RivetWorkItems' {
    It 'scaffolds a new local work item markdown file in .rivet/work-items/' {
        $repo = Join-Path $TestDrive 'workitem-scaffold-repo'
        New-TestRepository -Root $repo
        $result = Sync-RivetWorkItems -RepositoryRoot $repo -Action 'New' -Title 'Implement report card' -Labels @('feature', 'tui') -Raw
        $result.Success | Should -BeTrue
        $workItemsDir = Join-Path $repo '.rivet/work-items'
        (Test-Path $workItemsDir) | Should -BeTrue
        $files = @(Get-ChildItem -Path $workItemsDir -Filter '*.md')
        $files.Count | Should -Be 1
        $content = Get-Content $files[0].FullName -Raw
        $content | Should -Match '\|\s*Title:\s*\|\s*`Implement report card`\s*\|'
        $content | Should -Match '\|\s*\*\*Labels:\*\*\s*\|\s*`feature, tui`\s*\|'
    }

    It 'lists local work items with metadata' {
        $repo = Join-Path $TestDrive 'workitem-list-repo'
        New-TestRepository -Root $repo
        $workItemsDir = Join-Path $repo '.rivet/work-items'
        [System.IO.Directory]::CreateDirectory($workItemsDir) | Out-Null
        $itemPath = Join-Path $workItemsDir '042-fix-parser.md'
        [System.IO.File]::WriteAllText($itemPath, "---\niid: 42\ntitle: `"Fix parser error`"\nstate: opened\nlabels: [ `"bug`" ]\n---\n\nBody details.")

        $result = Sync-RivetWorkItems -RepositoryRoot $repo -Action 'List' -Raw
        $result.Success | Should -BeTrue
        $result.Rows.Count | Should -BeGreaterThan 0
    }
}

Describe 'Show-RivetFlowGraph lifecycle rendering' {
    It 'generates and returns rendered flow graph lines with PassThru' {
        $lines = Show-RivetFlowGraph -PassThru
        $lines.Count | Should -BeGreaterThan 5
        $plain = $lines -replace "`e\[[0-9;]*[a-zA-Z]", ''
        ($plain -join "`n") | Should -Match 'Git Worktree'
        ($plain -join "`n") | Should -Match 'SemVer Engine'
        ($plain -join "`n") | Should -Match 'GitLab Release'
    }

    It 'keeps the Pipeline layout within the terminal-width fallback' {
        $lines = Show-RivetFlowGraph -Layout Pipeline -PassThru
        $plain = $lines -replace "`e\[[0-9;]*[a-zA-Z]", ''
        ($plain | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 100
        ($plain -join "`n") | Should -Match 'pipeline continues'
    }
}

Describe 'TUI gradient border formatting' {
    It 'interpolates RGB values between orange and off-black' {
        $start = @(255, 130, 0)
        $end = @(40, 44, 54)
        $mid = Get-InterpolatedRgb -Start $start -End $end -T 0.5
        $mid[0] | Should -Be 148
        $mid[1] | Should -Be 87
        $mid[2] | Should -Be 27
    }

    It 'applies gradient truecolor sequences to strings' {
        $grad = Format-GradientString -Text '┌────┐' -Start @(255, 130, 0) -End @(40, 44, 54)
        $grad | Should -Match "`e\[38;2;255;130;0m┌"
        $grad | Should -Match "`e\[38;2;40;44;54m┐"
    }
}

Describe 'Rivet argument completers' {
    It 'completes commands with tooltips' {
        $completer = [RivetCommandCompleter]::new()
        $results = @($completer.CompleteArgument('Invoke-Rivet', 'Command', 'st', $null, $null))
        $results.Count | Should -BeGreaterThan 0
        $results[0].CompletionText | Should -Be 'status'
        $results[0].ToolTip | Should -Match 'Show repository and release state'

        $rebuildResults = @($completer.CompleteArgument('Invoke-Rivet', 'Command', 'reb', $null, $null))
        $rebuildResults.Count | Should -BeGreaterThan 0
        $rebuildResults[0].CompletionText | Should -Be 'rebuild-changelog'

        $flowResults = @($completer.CompleteArgument('Invoke-Rivet', 'Command', 'fl', $null, $null))
        $flowResults.Count | Should -BeGreaterThan 0
        $flowResults[0].CompletionText | Should -Be 'flow'

        $pipelineResults = @($completer.CompleteArgument('Invoke-Rivet', 'Command', 'pipe', $null, $null))
        $pipelineResults.Count | Should -BeGreaterThan 0
        $pipelineResults[0].CompletionText | Should -Be 'pipeline'

        $workResults = @($completer.CompleteArgument('Invoke-Rivet', 'Command', 'work', $null, $null))
        $workResults.Count | Should -BeGreaterThan 0
        $workResults[0].CompletionText | Should -Be 'work-items'
    }

    It 'completes commit types' {
        $completer = [RivetCommitTypeCompleter]::new()
        $results = @($completer.CompleteArgument('Invoke-Rivet', 'CommitType', 'fe', $null, $null))
        $results.Count | Should -BeGreaterThan 0
        $results[0].CompletionText | Should -Be 'feat'
    }

    It 'completes commit scopes' {
        $completer = [RivetCommitScopeCompleter]::new()
        $results = @($completer.CompleteArgument('Invoke-Rivet', 'CommitScope', 'co', $null, $null))
        $results.Count | Should -BeGreaterThan 0
        $results[0].CompletionText | Should -Be 'core'
    }

    It 'completes help parameters' {
        $completer = [RivetHelpParamCompleter]::new()
        $results = @($completer.CompleteArgument('Invoke-Rivet', 'Param', 'Com', $null, $null))
        $results.CompletionText | Should -Contain 'Command'
        $results.CompletionText | Should -Contain 'Commit'

        $rebuildParam = @($completer.CompleteArgument('Invoke-Rivet', 'Param', 'Reb', $null, $null))
        $rebuildParam.CompletionText | Should -Contain 'RebuildChangelog'
        $rebuildParam.CompletionText | Should -Contain 'Rebuild'

        $flowParam = @($completer.CompleteArgument('Invoke-Rivet', 'Param', 'Flow', $null, $null))
        $flowParam.CompletionText | Should -Contain 'FlowGraph'
        $flowParam.CompletionText | Should -Contain 'Flow'

        $workParam = @($completer.CompleteArgument('Invoke-Rivet', 'Param', 'Work', $null, $null))
        $workParam.CompletionText | Should -Contain 'WorkItems'

        $rawParam = @($completer.CompleteArgument('Invoke-Rivet', 'Param', 'Raw', $null, $null))
        $rawParam.CompletionText | Should -Contain 'Raw'

        $templateParam = @($completer.CompleteArgument('Invoke-Rivet', 'Param', 'Temp', $null, $null))
        $templateParam.CompletionText | Should -Contain 'Template'
    }
}

Describe 'Rivet generic cache engine' {
    BeforeAll {
        $script:TestCacheDir = Join-Path $TestDrive 'rivet-cache-test'
        Initialize-RivetCache -CacheDirectory $script:TestCacheDir -DefaultTtlSeconds 60 -ResetMetrics
    }

    It 'stores and retrieves items from memory and disk' {
        Set-RivetCache -Key 'test_key_1' -Value @{ Message = 'hello rivet cache' } -TtlSeconds 60 -Tags @('test_tag')
        $cached = Get-RivetCache -Key 'test_key_1'
        $cached | Should -Not -BeNullOrEmpty
        $cached.Message | Should -Be 'hello rivet cache'

        # Verify disk file was created
        $files = @(Get-ChildItem -Path $script:TestCacheDir -Filter '*.json')
        $files.Count | Should -BeGreaterThan 0
    }

    It 'reports cache hit, miss, and performance metrics' {
        $metricsBefore = Get-RivetCacheMetrics
        $metricsBefore.Hits | Should -BeGreaterThan 0

        # Cache miss
        $missVal = Get-RivetCache -Key 'non_existent_key' -DefaultValue 'fallback'
        $missVal | Should -Be 'fallback'

        $metricsAfter = Get-RivetCacheMetrics
        $metricsAfter.Misses | Should -BeGreaterThan 0
        $metricsAfter.TotalRequests | Should -Be ($metricsAfter.Hits + $metricsAfter.Misses)
        $metricsAfter.HitRatePercentage | Should -BeGreaterThan 0
        $metricsAfter.TotalSizeBytes | Should -BeGreaterThan 0
    }

    It 'executes scriptblock once with Invoke-RivetCachedOperation' {
        $script:cachedCounter = 0
        $fetchBlock = {
            $script:cachedCounter++
            [pscustomobject]@{ Id = 99; Count = $script:cachedCounter }
        }

        $res1 = Invoke-RivetCachedOperation -Key 'cached_calc' -TtlSeconds 30 -ScriptBlock $fetchBlock
        $res1.Count | Should -Be 1

        $res2 = Invoke-RivetCachedOperation -Key 'cached_calc' -TtlSeconds 30 -ScriptBlock $fetchBlock
        $res2.Count | Should -Be 1
        $script:cachedCounter | Should -Be 1

        # Force refresh
        $res3 = Invoke-RivetCachedOperation -Key 'cached_calc' -TtlSeconds 30 -ForceRefresh -ScriptBlock $fetchBlock
        $res3.Count | Should -Be 2
        $script:cachedCounter | Should -Be 2
    }

    It 'removes items by key and tag' {
        Set-RivetCache -Key 'tagged_item_1' -Value 'val1' -Tags @('cleanup_tag')
        Set-RivetCache -Key 'tagged_item_2' -Value 'val2' -Tags @('cleanup_tag')
        Test-RivetCacheItem -Key 'tagged_item_1' | Should -Be $true

        Remove-RivetCache -Tag 'cleanup_tag'
        Test-RivetCacheItem -Key 'tagged_item_1' | Should -Be $false
        Test-RivetCacheItem -Key 'tagged_item_2' | Should -Be $false
    }
}

Describe 'Rivet Work Items table template & targeted sync' {
    BeforeAll {
        $script:TestWorkItemRepo = Join-Path $TestDrive 'workitem-table-repo'
        [System.IO.Directory]::CreateDirectory($script:TestWorkItemRepo) | Out-Null
        $gitInit = Start-Process git -ArgumentList @('-C', $script:TestWorkItemRepo, 'init') -NoNewWindow -Wait -PassThru
        $gitInit.ExitCode | Should -Be 0
    }

    It 'scaffolds work item template matching mr.md metadata table' {
        $result = Sync-RivetWorkItems `
            -RepositoryRoot $script:TestWorkItemRepo `
            -Action 'Template' `
            -Iid 42 `
            -Title 'Support dynamic table layout' `
            -Labels @('feature', 'ui') `
            -Milestone 'v1.2.0' `
            -Raw

        $result.Success | Should -Be $true
        $workFile = Join-Path $script:TestWorkItemRepo '.rivet/work-items/042-support-dynamic-table-layout.md'
        [System.IO.File]::Exists($workFile) | Should -Be $true

        $content = [System.IO.File]::ReadAllText($workFile)
        $content | Should -Match '\|\s*\*\*Gitlab Issue IID:\*\*\s*\|\s*`42`\s*\|'
        $content | Should -Match '\|\s*\*\*Sync Action:\*\*\s*\|\s*`pull`\s*\|'
        $content | Should -Match '\|\s*\*\*Status:\*\*\s*\|\s*`opened`\s*\|'
        $content | Should -Match '\|\s*\*\*Milestone:\*\*\s*\|\s*`v1.2.0`\s*\|'
        $content | Should -Match '\|\s*\*\*Labels:\*\*\s*\|\s*`feature, ui`\s*\|'
        $content | Should -Match '## \*\*Description\*\*'
        $content | Should -Match '## \*\*Acceptance Criteria\*\*'
    }

    It 'lists local work items with status badges and sync tags' {
        $listReport = Sync-RivetWorkItems `
            -RepositoryRoot $script:TestWorkItemRepo `
            -Action 'List' `
            -Raw

        $listReport.Success | Should -Be $true
        @($listReport.Rows).Count | Should -BeGreaterThan 1
        $listReport.Rows[1].Detail | Should -Match '\[OPEN\].*Support dynamic table layout'
    }

    It 'generates aggregated workitems-list.md dashboard index' {
        $genReport = Sync-RivetWorkItems `
            -RepositoryRoot $script:TestWorkItemRepo `
            -Action 'GenerateList' `
            -Raw

        $genReport.Success | Should -Be $true
        $dashPath = Join-Path $script:TestWorkItemRepo '.rivet/workitems-list.md'
        (Test-Path $dashPath) | Should -Be $true

        $dashContent = Get-Content $dashPath -Raw
        $dashContent | Should -Match '<!--rivet: generated Tasklist-->'
        $dashContent | Should -Match '### 🎯 \*\*Support dynamic table layout\*\*'
        $dashContent | Should -Match '🟢 open'
        $dashContent | Should -Match '\[#42\]'
    }

    It 'closes a work item and flags for push sync' {
        $closeReport = Sync-RivetWorkItems `
            -RepositoryRoot $script:TestWorkItemRepo `
            -Action 'Close' `
            -Iid 42 `
            -Raw

        $closeReport.Success | Should -Be $true
        $itemFile = Join-Path $script:TestWorkItemRepo '.rivet/work-items/042-support-dynamic-table-layout.md'
        $content = Get-Content $itemFile -Raw
        $content | Should -Match '\|\s*\*\*Status:\*\*\s*\|\s*`closed`\s*\|'
        $content | Should -Match '\|\s*\*\*Sync Action:\*\*\s*\|\s*`push`\s*\|'

        # Check dashboard also reflected closed status
        $dashPath = Join-Path $script:TestWorkItemRepo '.rivet/workitems-list.md'
        $dashContent = Get-Content $dashPath -Raw
        $dashContent | Should -Match '✅ closed'
    }

    It 'reopens a work item and views details' {
        $reopenReport = Sync-RivetWorkItems `
            -RepositoryRoot $script:TestWorkItemRepo `
            -Action 'Reopen' `
            -Iid 42 `
            -Raw

        $reopenReport.Success | Should -Be $true
        $itemFile = Join-Path $script:TestWorkItemRepo '.rivet/work-items/042-support-dynamic-table-layout.md'
        $content = Get-Content $itemFile -Raw
        $content | Should -Match '\|\s*\*\*Status:\*\*\s*\|\s*`opened`\s*\|'

        $viewReport = Sync-RivetWorkItems `
            -RepositoryRoot $script:TestWorkItemRepo `
            -Action 'View' `
            -Iid 42 `
            -Raw

        $viewReport.Success | Should -Be $true
        $viewReport.Rows[0].Detail | Should -Match 'Support dynamic table layout'
    }
}

Describe 'SMenu description display modes' {
    It 'calculates Card layout on wide terminal' {
        $layout = Get-SMenuLayout -TerminalWidth 120 -TerminalHeight 30 -ItemCount 10 -DescriptionDisplay 'Card'
        $layout.Wide | Should -Be $true
        $layout.DescriptionDisplay | Should -Be 'Card'
        $layout.CardWidth | Should -BeGreaterThan 20
        $layout.LabelWidth | Should -BeGreaterThan 20
    }

    It 'calculates Inline layout on wide terminal' {
        $layout = Get-SMenuLayout -TerminalWidth 120 -TerminalHeight 30 -ItemCount 10 -DescriptionDisplay 'Inline'
        $layout.Wide | Should -Be $true
        $layout.DescriptionDisplay | Should -Be 'Inline'
        $layout.DescriptionWidth | Should -BeGreaterThan 20
    }

    It 'calculates Minimal layout' {
        $layout = Get-SMenuLayout -TerminalWidth 120 -TerminalHeight 30 -ItemCount 10 -DescriptionDisplay 'Minimal'
        $layout.DescriptionDisplay | Should -Be 'Minimal'
        $layout.LabelWidth | Should -BeGreaterThan 80
    }

    It 'calculates Pager layout on wide terminal' {
        $layout = Get-SMenuLayout -TerminalWidth 120 -TerminalHeight 30 -ItemCount 10 -DescriptionDisplay 'Pager'
        $layout.Wide | Should -Be $true
        $layout.DescriptionDisplay | Should -Be 'Pager'
        $layout.CardWidth | Should -BeGreaterThan 20
    }
}

Describe 'Repository profiles' {
    BeforeAll {
        function New-PSProfileRepository {
            param([string]$Root)
            [System.IO.Directory]::CreateDirectory($Root) | Out-Null
            Invoke-TestGit $Root init --initial-branch=main | Out-Null
            Invoke-TestGit $Root config user.name testuser | Out-Null
            Invoke-TestGit $Root config user.email test@example.invalid | Out-Null
            Initialize-RivetRepository -RepositoryRoot $Root -Profile psm -Manifest 'src/Fixture.psd1' -Raw -Confirm:$false | Out-Null
            Invoke-TestGit $Root add --all | Out-Null
            Invoke-TestGit $Root commit -m 'chore: initialize module' | Out-Null
            Invoke-TestGit $Root tag v0.1.0 | Out-Null
            return Resolve-RivetPath -RepositoryRoot $Root -ItemName 'repo_config.json'
        }
    }

    It 'defaults legacy configuration to jsm and rejects unknown or empty profiles' {
        (Get-RivetProfile).Name | Should -Be 'jsm'
        (Get-RivetProfile -Config ([pscustomobject]@{})).Name | Should -Be 'jsm'
        (Get-RivetProfile -Name '11ty').Name | Should -Be '11ty'
        { Get-RivetProfile -Name 'missing-profile' } | Should -Throw '*Unknown repository profile*'
        { Get-RivetProfile -Name '../psm' } | Should -Throw '*Invalid repository profile*'
        { Get-RivetProfile -Config ([pscustomobject]@{ profile = '' }) } | Should -Throw '*Invalid repository profile*'
    }

    It 'previews psm initialization without creating files and respects WhatIf' {
        $repo = Join-Path $TestDrive 'psm-preview'
        [System.IO.Directory]::CreateDirectory($repo) | Out-Null
        Invoke-TestGit $repo init --initial-branch=main | Out-Null
        $preview = @(Initialize-RivetRepository -RepositoryRoot $repo -Profile psm -Manifest 'Fixture.psd1' -DryRun -Raw)
        $preview.File | Should -Contain 'Fixture.psd1'
        $preview.File | Should -Not -Contain 'package.json'
        @([System.IO.Directory]::GetFiles($repo)).Count | Should -Be 0
        Initialize-RivetRepository -RepositoryRoot $repo -Profile psm -WhatIf -Raw | Out-Null
        Test-Path (Join-Path $repo '.rivet') | Should -BeFalse
    }

    It 'initializes a nested PowerShell module and preserves existing files on repeat initialization' {
        $repo = Join-Path $TestDrive 'psm-init'
        $configPath = New-PSProfileRepository $repo
        $config = Get-RivetConfiguration $configPath
        $config.profile | Should -Be 'psm'
        $config.psm.manifest | Should -Be 'src/Fixture.psd1'
        Test-Path (Join-Path $repo 'package.json') | Should -BeFalse
        Test-Path (Join-Path $repo 'src/Fixture.psm1') | Should -BeTrue
        $before = [System.IO.File]::ReadAllText((Join-Path $repo 'src/Fixture.psd1'))
        Initialize-RivetRepository -RepositoryRoot $repo -Raw -Confirm:$false | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $repo 'src/Fixture.psd1')) | Should -BeExactly $before
        (Test-RivetRepository -RepositoryRoot $repo -ConfigPath $configPath).Ready | Should -BeTrue
    }

    It 'requires an explicit manifest when root module manifests are ambiguous' {
        $repo = Join-Path $TestDrive 'psm-ambiguous'
        [System.IO.Directory]::CreateDirectory($repo) | Out-Null
        Invoke-TestGit $repo init --initial-branch=main | Out-Null
        foreach ($name in @('One', 'Two')) { [System.IO.File]::WriteAllText((Join-Path $repo "$name.psd1"), "@{ ModuleVersion = '1.0.0' }") }
        { Initialize-RivetRepository -RepositoryRoot $repo -Profile psm -Raw } | Should -Throw '*Multiple module manifests*'
        { Initialize-RivetRepository -RepositoryRoot $repo -Profile psm -Manifest '../Outside.psd1' -Raw } | Should -Throw '*inside the repository*'
        Test-Path (Join-Path $repo 'repo_config.json') | Should -BeFalse
    }

    It 'rejects profile changes and invalid profile configuration before repository writes' {
        $repo = Join-Path $TestDrive 'psm-invalid'
        $configPath = New-PSProfileRepository $repo
        { Initialize-RivetRepository -RepositoryRoot $repo -Profile jsm -Raw } | Should -Throw '*cannot change*'
        $config = Get-RivetConfiguration $configPath
        $config.profile = 'missing-profile'
        [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20))
        $before = [System.IO.File]::ReadAllText((Join-Path $repo 'src/Fixture.psd1'))
        { Invoke-Rivet -RepositoryRoot $repo -Raw } | Should -Throw '*Unknown repository profile*'
        [System.IO.File]::ReadAllText((Join-Path $repo 'src/Fixture.psd1')) | Should -BeExactly $before
        $config.profile = 'psm'
        $config.psm.manifest = '../Outside.psd1'
        [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20))
        { Get-RivetConfiguration $configPath } | Should -Throw '*repository-relative*'
    }

    It 'updates only the literal top-level ModuleVersion and preserves other data and CRLF' {
        $repo = Join-Path $TestDrive 'psm-version'
        $configPath = New-PSProfileRepository $repo
        $config = Get-RivetConfiguration $configPath
        $profile = Get-RivetProfile -Config $config
        $path = Join-Path $repo 'src/Fixture.psd1'
        $original = "@{`r`n    # ModuleVersion = '9.9.9'`r`n    ModuleVersion = '0.1.0' # retained`r`n    PrivateData = @{ ModuleVersion = '8.8.8' }`r`n}`r`n"
        [System.IO.File]::WriteAllText($path, $original)
        & $profile.UpdateVersion $repo $config '1.2.3' $true | Out-Null
        [System.IO.File]::ReadAllText($path) | Should -BeExactly $original
        & $profile.UpdateVersion $repo $config '1.2.3' $false | Out-Null
        [System.IO.File]::ReadAllText($path) | Should -BeExactly ($original.Replace("ModuleVersion = '0.1.0'", "ModuleVersion = '1.2.3'"))
        (& $profile.ReadVersion $repo $config) | Should -Be '1.2.3'
        { & $profile.UpdateVersion $repo $config '1.2.3-beta' $false } | Should -Throw '*stable*'
    }

    It 'runs the complete local psm workflow in a repository with JavaScript tooling' {
        $repo = Join-Path $TestDrive 'psm-mixed'
        $configPath = New-PSProfileRepository $repo
        [System.IO.File]::WriteAllText((Join-Path $repo 'package.json'), '{"name":"docs","version":"9.0.0"}')
        [System.IO.File]::WriteAllText((Join-Path $repo 'bunfig.toml'), '')
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat: add documentation tools' | Out-Null
        { Invoke-Rivet -RepositoryRoot $repo -Raw } | Should -Not -Throw
        (Get-RivetPSModuleManifest -RepositoryRoot $repo -Manifest 'src/Fixture.psd1').Version | Should -Be '0.2.0'
        [System.IO.File]::ReadAllText((Join-Path $repo 'package.json')) | Should -BeExactly '{"name":"docs","version":"9.0.0"}'
        [System.IO.File]::ReadAllText((Join-Path $repo 'README.md')) | Should -Match 'Version 0.2.0'
        $doctor = Test-RivetRepository -RepositoryRoot $repo -ConfigPath $configPath
        $doctor.Ready | Should -BeTrue
        $doctor.Checks.Name | Should -Not -Contain 'Bun runtime'
    }

    It 'prepares psm release documents and merge requests without JavaScript manifests' {
        $repo = Join-Path $TestDrive 'psm-release'
        $configPath = New-PSProfileRepository $repo
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nNew feature.`n")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat: add feature' | Out-Null
        $before = @(& git -C $repo status --porcelain) -join "`n"
        { Invoke-Rivet -RepositoryRoot $repo -Command prep-release -FromTag v0.1.0 -DryRun -Raw } | Should -Not -Throw
        (@(& git -C $repo status --porcelain) -join "`n") | Should -BeExactly $before
        { Invoke-Rivet -RepositoryRoot $repo -Command prep-release -FromTag v0.1.0 -Raw } | Should -Not -Throw
        [System.IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md')) | Should -Match '0.2.0'
        $mr = [System.IO.File]::ReadAllText((Resolve-RivetPath -RepositoryRoot $repo -ItemName 'mr.md'))
        $mr | Should -Match 'repository manifest versions to `0.2.0`'
        $mr | Should -Not -Match 'npm|jsr.jsonc'
        # Standalone helpers must also resolve the profile, without an explicit Version.
        { Update-MergeRequestDocumentation -RepositoryRoot $repo -FromTag v0.1.0 -DryRun } | Should -Not -Throw
        { Update-ReleaseDocumentation -RepositoryRoot $repo -ConfigPath $configPath -FromTag v0.1.0 -DryRun } | Should -Not -Throw
        $config = Get-RivetConfiguration $configPath
        $profile = Get-RivetProfile -Config $config
        @(& $profile.ReleaseFiles $repo $config) | Should -Contain 'src/Fixture.psd1'
        @(& $profile.ReviewVersions $repo $config) | Should -Contain 'src/Fixture.psd1=0.2.0'
    }

    It 'blocks a PowerShell tag when the module version differs from the proposed tag' {
        $repo = Join-Path $TestDrive 'psm-tag'
        $configPath = New-PSProfileRepository $repo
        $remote = Join-Path $TestDrive 'psm-tag-remote.git'
        & git init --bare $remote | Out-Null
        Invoke-TestGit $repo remote add origin $remote | Out-Null
        Invoke-TestGit $repo push --set-upstream origin main | Out-Null
        $result = Invoke-RepositoryTag -RepositoryRoot $repo -ConfigPath $configPath -Version 0.2.0 -DryRun
        $result.Ready | Should -BeFalse
        $result.Blockers -join ' ' | Should -Match 'src/Fixture.psd1=0.1.0'
        $ready = Invoke-RepositoryTag -RepositoryRoot $repo -ConfigPath $configPath -Version 0.1.0 -DryRun
        $ready.Ready | Should -BeTrue
    }

    It 'selects the PowerShell manifest and shared release files for release commit review' {
        $repo = Join-Path $TestDrive 'psm-release-selection'
        $configPath = New-PSProfileRepository $repo
        [System.IO.File]::AppendAllText((Join-Path $repo 'README.md'), "`nNew feature.`n")
        Invoke-TestGit $repo add --all | Out-Null
        Invoke-TestGit $repo commit -m 'feat: add feature' | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'package.json'), '{"version":"9.0.0"}')
        Mock Invoke-RepositoryCommit { [pscustomobject]@{ Submitted = $false; Subject = 'fixture' } }
        Invoke-Rivet -RepositoryRoot $repo -Command prep-release -FromTag v0.1.0 -Commit -Raw | Out-Null
        Should -Invoke Invoke-RepositoryCommit -Times 1 -Exactly -ParameterFilter {
            'src/Fixture.psd1' -in $Files -and 'CHANGELOG.md' -in $Files -and 'package.json' -notin $Files
        }
    }

    It 'loads an added profile and dispatches its handler without router edits' {
        $repo = Join-Path $TestDrive 'additional-profile'
        $configPath = New-PSProfileRepository $repo
        $name = 'fixture-' + [guid]::NewGuid().ToString('N')
        $folder = Join-Path $script:RivetRoot "profiles/$name"
        try {
            [System.IO.Directory]::CreateDirectory($folder) | Out-Null
            $baseProfile = (Join-Path $script:RivetRoot 'profiles/psm/profile.ps1').Replace("'", "''")
            $source = @'
$definition = & '__BASE__'
$definition.UpdateVersion = {
    param($RepositoryRoot, $Config, $Version, $DryRun)
    if (-not $DryRun) { [System.IO.File]::WriteAllText([System.IO.Path]::Combine($RepositoryRoot, 'custom-version.txt'), $Version) }
}
$definition
'@.Replace('__BASE__', $baseProfile)
            [System.IO.File]::WriteAllText((Join-Path $folder 'profile.ps1'), $source)
            $config = Get-RivetConfiguration $configPath
            $config.profile = $name
            [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20))
            { Invoke-Rivet -RepositoryRoot $repo -SkipReadmeMetadata -SkipTableOfContents -SkipReadmeValidation -Raw } | Should -Not -Throw
            [System.IO.File]::ReadAllText((Join-Path $repo 'custom-version.txt')) | Should -Be '0.1.0'
        } finally {
            if ([System.IO.Directory]::Exists($folder)) { [System.IO.Directory]::Delete($folder, $true) }
        }
    }

    It 'initializes an 11ty theme repository, updates version, and passes doctor checks' {
        $repo = Join-Path $TestDrive '11ty-init'
        [System.IO.Directory]::CreateDirectory($repo) | Out-Null
        Invoke-TestGit $repo init --initial-branch=main | Out-Null
        Invoke-TestGit $repo config user.name testuser | Out-Null
        Invoke-TestGit $repo config user.email test@example.invalid | Out-Null
        $items = @(Initialize-RivetRepository -RepositoryRoot $repo -Profile 11ty -Raw -Confirm:$false)
        $items.File | Should -Contain 'eleventy.config.js'
        $items.File | Should -Contain 'package.json'
        Test-Path (Join-Path $repo 'eleventy.config.js') | Should -BeTrue
        Test-Path (Join-Path $repo 'package.json') | Should -BeTrue
        Test-Path (Join-Path $repo 'README.md') | Should -BeTrue

        $configPath = Resolve-RivetPath -RepositoryRoot $repo -ItemName 'repo_config.json'
        $config = Get-RivetConfiguration $configPath
        $config.profile | Should -Be '11ty'

        $profile = Get-RivetProfile -Config $config
        $profile.Name | Should -Be '11ty'
        (& $profile.ReadVersion $repo $config) | Should -Be '0.1.0'

        & $profile.UpdateVersion $repo $config '0.2.0' $false | Out-Null
        (& $profile.ReadVersion $repo $config) | Should -Be '0.2.0'
        (& $profile.ReviewVersions $repo $config) | Should -Contain 'package.json=0.2.0'

        $doctor = Test-RivetRepository -RepositoryRoot $repo -ConfigPath $configPath
        $doctor.Ready | Should -BeTrue
    }

    It 'propagates shared 11ty header rendering errors' {
        $repo = Join-Path $TestDrive '11ty-header-error'
        [System.IO.Directory]::CreateDirectory($repo) | Out-Null
        Invoke-TestGit $repo init --initial-branch=main | Out-Null
        Invoke-TestGit $repo config user.name testuser | Out-Null
        Invoke-TestGit $repo config user.email test@example.invalid | Out-Null
        Initialize-RivetRepository -RepositoryRoot $repo -Profile 11ty -Raw -Confirm:$false | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'repo_meta.json'), '{"project":{}}')

        $configPath = Join-Path $repo 'repo_config.json'
        $config = Get-RivetConfiguration $configPath
        $profile = Get-RivetProfile -Config $config
        { & $profile.UpdateHeader $repo $config $configPath $false } | Should -Throw
    }
}
