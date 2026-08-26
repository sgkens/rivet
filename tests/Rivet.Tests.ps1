BeforeAll {
    $script:RivetRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..'))
    $script:ScriptsRoot = [System.IO.Path]::Combine($script:RivetRoot, 'scripts')
    foreach ($name in @(
        'asciitokenizer.ps1',
        'lazylog.ps1',
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
        'Invoke-RivetMenu.ps1',
        'Invoke-Rivet.ps1'
    )) { . ([System.IO.Path]::Combine($script:ScriptsRoot, $name)) }
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
        $existing = @(Initialize-RivetRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -Confirm:$false)
        @($existing | Where-Object State -eq 'EXISTS').Count | Should -BeGreaterOrEqual 2
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
}

Describe 'rivet command-center multi-action labels' {
    It 'retains raw titles and renders MA after the menu title' {
        $menuSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/Invoke-RivetMenu.ps1'))
        $menuSource | Should -Not -Match '"\[MA\] \$Label"'
        $rendererSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/smenu.ps1'))
        $rendererSource | Should -Match 'return "\$label \[MA\]"'

        @(
            'Initialize repository'
            'Prep Release'
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
    }
}

