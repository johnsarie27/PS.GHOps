BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Get-GHUnpinnedAction' -Fixture {
    BeforeAll {
        $workflow = @'
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      - uses: actions/setup-node@v4
      - uses: ./.github/actions/local
      - uses: docker://alpine:3.18
'@
        $b64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($workflow))

        # Directory listing: one workflow file plus a non-yaml file that must be ignored
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith {
            @(
                [PSCustomObject] @{ type = 'file'; name = 'ci.yml'; path = '.github/workflows/ci.yml' }
                [PSCustomObject] @{ type = 'file'; name = 'README.md'; path = '.github/workflows/README.md' }
            )
        } -ParameterFilter { $Path -match 'contents/\.github/workflows$' }
        # File content
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ content = $b64 } } `
            -ParameterFilter { $Path -match 'contents/\.github/workflows/ci\.yml$' }
    }
    Context -Name 'organization scan' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith {
                @(
                    [PSCustomObject] @{ nameWithOwner = 'PS-MCS/has-workflows' }
                    [PSCustomObject] @{ nameWithOwner = 'PS-MCS/no-workflows' }
                )
            }
            # no-workflows returns a tolerated 404 (null) for its workflows directory
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { $null } `
                -ParameterFilter { $Path -like '*no-workflows*' }
        }
        It -Name 'classifies each uses: reference by kind' -Test {
            $result = Get-GHUnpinnedAction -Organization PS-MCS
            ($result | Where-Object Action -EQ 'actions/checkout').Kind | Should -Be 'sha'
            ($result | Where-Object Action -EQ 'actions/setup-node').Kind | Should -Be 'tag'
            ($result | Where-Object Kind -EQ 'local').Action | Should -Be './.github/actions/local'
            ($result | Where-Object Kind -EQ 'docker').Action | Should -Be 'docker://alpine:3.18'
        }
        It -Name 'skips a repository without a workflows directory (tolerated 404)' -Test {
            $result = Get-GHUnpinnedAction -Organization PS-MCS
            $result.Repository | Should -Not -Contain 'PS-MCS/no-workflows'
            ($result | Select-Object -Unique Repository).Repository | Should -Be 'PS-MCS/has-workflows'
        }
        It -Name 'projects Repository/Workflow/Line/Action/Version/Kind' -Test {
            $row = Get-GHUnpinnedAction -Organization PS-MCS | Where-Object Action -EQ 'actions/setup-node'
            $row.Repository | Should -Be 'PS-MCS/has-workflows'
            $row.Workflow | Should -Be 'ci.yml'
            $row.Version | Should -Be 'v4'
            $row.Line | Should -BeGreaterThan 0
        }
        It -Name 'ignores non-yaml files in the workflows directory' -Test {
            Get-GHUnpinnedAction -Organization PS-MCS | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 0 -Exactly `
                -ParameterFilter { $Path -like '*workflows/README.md*' }
        }
    }
    Context -Name 'kind filter' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith {
                @([PSCustomObject] @{ nameWithOwner = 'PS-MCS/has-workflows' })
            }
        }
        It -Name 'returns only the requested kind' -Test {
            $result = Get-GHUnpinnedAction -Organization PS-MCS -Kind tag
            $result | Should -HaveCount 1
            $result.Action | Should -Be 'actions/setup-node'
        }
    }
    Context -Name 'explicit repository targeting' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith { throw 'repo list should not be called' }
        }
        It -Name 'scans the named repositories without listing the org' -Test {
            $result = Get-GHUnpinnedAction -Repository 'PS-MCS/has-workflows'
            ($result | Select-Object -Unique Repository).Repository | Should -Be 'PS-MCS/has-workflows'
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 0 -Exactly
        }
        It -Name 'accepts multiple repositories' -Test {
            $result = Get-GHUnpinnedAction -Repository 'PS-MCS/has-workflows', 'PS-MCS/has-workflows'
            ($result | Where-Object Action -EQ 'actions/checkout').Count | Should -Be 2
        }
    }
    Context -Name 'validation' -Fixture {
        It -Name 'rejects a malformed repository' -Test {
            { Get-GHUnpinnedAction -Repository 'not-a-repo' } | Should -Throw
        }
    }
}
