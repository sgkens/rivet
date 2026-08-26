BeforeAll {
    $script:GlmetaRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..'))
    $script:ScriptsRoot = [System.IO.Path]::Combine($script:GlmetaRoot, 'scripts')
    foreach ($name in @(
        'asciitokenizer.ps1',
        'Get-GlmetaConfiguration.ps1',
        'Initialize-GlmetaRepository.ps1',
        'Test-ReadmeStructure.ps1',
        'ConvertFrom-ConventionalCommit.ps1',
        'Get-ConventionalCommitVersion.ps1',
        'Update-JSLibSemver.ps1',
        'Invoke-RepositoryCommit.ps1',
        'Invoke-RepositoryTag.ps1',
        'Invoke-GitLabMergeRequest.ps1',
        'Update-ReleaseDocumentation.ps1'
    )) { . ([System.IO.Path]::Combine($script:ScriptsRoot, $name)) }

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
            gitlab = [ordered]@{ baseUri = 'https://gitlab.example'; projectId = ''; tokenEnvironmentVariable = 'GLMETA_TEST_TOKEN' }
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

Describe 'Initialize-GlmetaRepository' {
    It 'previews, creates, and preserves repository-root configuration' {
        $repo = Join-Path $TestDrive 'init-repo'
        New-TestRepository -Root $repo
        $templateRoot = Join-Path $script:GlmetaRoot 'templates/js'
        $preview = @(Initialize-GlmetaRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -DryRun)
        $preview.State | Should -Contain 'WOULD CREATE'
        Test-Path (Join-Path $repo 'repo_config.json') | Should -BeFalse
        $created = @(Initialize-GlmetaRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -Confirm:$false)
        $created.State | Should -Contain 'CREATED'
        (Get-GlmetaConfiguration -ConfigPath (Join-Path $repo 'repo_config.json')).project.name | Should -Be 'library'
        $existing = @(Initialize-GlmetaRepository -RepositoryRoot $repo -TemplateRoot $templateRoot -Confirm:$false)
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
        $content | Should -Match '\[.{7}\]\(https://gitlab\.example/group/fixture/-/commit/[0-9a-f]{40}\)'
        $content | Should -Match '@fixture-user'
        $content | Should -Match 'Document fixture feature\.'

        $json = [System.IO.File]::ReadAllText((Join-Path $repo 'docs/data/changelog.json')) | ConvertFrom-Json
        $json.source.history | Should -Be 'git'
        $json.source.canonical_record | Should -Be 'CHANGELOG.md'
        $json.versions[0].version | Should -Be 'unreleased'
        $json.versions[0].included | Should -Be 1
        $json.versions[0].excluded_non_version_bump | Should -Be 1
        $json.versions[0].entries[0].type | Should -Be 'feat'
        $json.versions[0].entries[0].commit.url | Should -Match '/-/commit/[0-9a-f]{40}$'
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
        [System.Environment]::SetEnvironmentVariable('GLMETA_TEST_TOKEN', 'test-token')
        try {
            Mock Invoke-RestMethod { return @() } -ParameterFilter { $Method -eq 'Get' }
            $result = Invoke-GitLabMergeRequest -RepositoryRoot $repo -ConfigPath $config -Mode Create -DryRun
            $result.Applied | Should -BeFalse
            $result.Title | Should -Be 'Release Fixture 1.1.0'
            $result.SourceBranch | Should -Be 'develop'
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Method -eq 'Get' }
            Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Method -in @('Post', 'Put') }
        } finally {
            [System.Environment]::SetEnvironmentVariable('GLMETA_TEST_TOKEN', $null)
        }
    }
}

Describe 'glmeta command-center multi-action labels' {
    It 'marks every compound workflow with the reusable MA attribute' {
        $menuSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/Invoke-GlmetaMenu.ps1'))
        $menuSource | Should -Match '\$displayLabel = if \(\$MultiAction\) \{ "\[MA\] \$Label" \}'

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
        ) | ForEach-Object {
            $escapedLabel = [regex]::Escape($_)
            $menuSource | Should -Match "New-MenuItem '$escapedLabel'[^\r\n]+-MultiAction"
        }
    }
}
