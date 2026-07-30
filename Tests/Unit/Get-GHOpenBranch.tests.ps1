BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Get-GHOpenBranch' -Fixture {
    BeforeAll {
        Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith {
            @(
                [PSCustomObject] @{ name = 'repo-main'; defaultBranchRef = [PSCustomObject] @{ name = 'main' } }
                [PSCustomObject] @{ name = 'repo-master'; defaultBranchRef = [PSCustomObject] @{ name = 'master' } }
                [PSCustomObject] @{ name = 'repo-empty'; defaultBranchRef = $null }
            )
        }
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith {
            @(
                [PSCustomObject] @{ name = 'main' }
                [PSCustomObject] @{ name = 'feature/x' }
                [PSCustomObject] @{ name = 'gh-pages' }
            )
        }
    }
    Context -Name 'normal usage' -Fixture {
        It -Name 'emits non-default branches and excludes each default' -Test {
            $result = Get-GHOpenBranch -Organization PS-MCS
            # repo-main: feature/x, gh-pages (main excluded)
            # repo-master: main, feature/x, gh-pages (master excluded; not present anyway)
            $result | Should -HaveCount 5
            ($result | Where-Object Repository -EQ 'PS-MCS/repo-main').Branch |
                Should -Not -Contain 'main' -Because 'main is repo-main default'
        }
        It -Name 'projects Repository/Branch/Default' -Test {
            $row = Get-GHOpenBranch -Organization PS-MCS | Select-Object -First 1
            $row.Repository | Should -Be 'PS-MCS/repo-main'
            $row.Default | Should -Be 'main'
            $row.Branch | Should -Not -BeNullOrEmpty
        }
        It -Name 'skips repositories with no default branch' -Test {
            Get-GHOpenBranch -Organization PS-MCS | Out-Null
            # Invoke-GHApi (branches) called once per non-empty repo only
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 2 -Exactly
        }
    }
    Context -Name 'exclusions' -Fixture {
        It -Name 'excludes named branches' -Test {
            $result = Get-GHOpenBranch -Organization PS-MCS -ExcludeBranch 'gh-pages'
            $result.Branch | Should -Not -Contain 'gh-pages'
        }
        It -Name 'excludes named repositories' -Test {
            Get-GHOpenBranch -Organization PS-MCS -ExcludeRepo 'repo-master' | Out-Null
            # only repo-main queried for branches (repo-master excluded, repo-empty skipped)
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly
        }
    }
    Context -Name 'repo scope flags' -Fixture {
        It -Name 'lists active repos by default (--no-archived --source)' -Test {
            Get-GHOpenBranch -Organization PS-MCS | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains '--no-archived' -and $Argument -contains '--source' }
        }
        It -Name 'widens scope with -IncludeArchived -IncludeFork' -Test {
            Get-GHOpenBranch -Organization PS-MCS -IncludeArchived -IncludeFork | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -notcontains '--no-archived' -and $Argument -notcontains '--source' }
        }
    }
}
