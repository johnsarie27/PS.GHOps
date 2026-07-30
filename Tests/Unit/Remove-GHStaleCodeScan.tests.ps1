BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Remove-GHStaleCodeScan' -Fixture {
    BeforeAll {
        # Default branch lookup (repos/{owner}/{repo})
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ default_branch = 'main' } } `
            -ParameterFilter { $Path -match '^repos/[^/]+/[^/]+$' }
        # Analyses listing: two for a stale workflow (old.yml), one for a current workflow
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith {
            @(
                [PSCustomObject] @{ id = 101; analysis_key = '.github/workflows/old.yml:build'; created_at = '2026-07-02T00:00:00Z' }
                [PSCustomObject] @{ id = 100; analysis_key = '.github/workflows/old.yml:build'; created_at = '2026-07-01T00:00:00Z' }
                [PSCustomObject] @{ id = 200; analysis_key = '.github/workflows/current.yml:build'; created_at = '2026-07-03T00:00:00Z' }
            )
        } -ParameterFilter { $Path -like '*code-scanning/analyses?ref=*' }
        # Contents check: old.yml is gone (tolerated 404 -> $null), current.yml still exists
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { $null } `
            -ParameterFilter { $Path -like '*contents/.github/workflows/old.yml*' }
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ name = 'current.yml' } } `
            -ParameterFilter { $Path -like '*contents/.github/workflows/current.yml*' }
        # Deletion
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { $null } `
            -ParameterFilter { $Method -eq 'DELETE' }
    }
    Context -Name 'auto-detect with -WhatIf' -Fixture {
        It -Name 'does not delete anything' -Test {
            Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem -WhatIf
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 0 -Exactly `
                -ParameterFilter { $Method -eq 'DELETE' }
        }
        It -Name 'does not throw' -Test {
            { Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem -WhatIf } | Should -Not -Throw
        }
    }
    Context -Name 'auto-detect deletion' -Fixture {
        It -Name 'deletes every analysis of the stale configuration only' -Test {
            Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem -Confirm:$false
            # old.yml has two analyses (stale); current.yml is not stale
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 2 -Exactly `
                -ParameterFilter { $Method -eq 'DELETE' }
        }
    }
    Context -Name 'explicit configuration' -Fixture {
        It -Name 'targets the named configuration regardless of staleness' -Test {
            Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem -Configuration '.github/workflows/current.yml:build' -Confirm:$false
            # current.yml has a single analysis
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Method -eq 'DELETE' }
        }
    }
    Context -Name 'explicit branch' -Fixture {
        It -Name 'skips the default-branch lookup when -Branch is supplied' -Test {
            Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem -Branch dev -WhatIf
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 0 -Exactly `
                -ParameterFilter { $Path -match '^repos/[^/]+/[^/]+$' }
        }
    }
    Context -Name 'no analyses present' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { @() } `
                -ParameterFilter { $Path -like '*code-scanning/analyses?ref=*' }
        }
        It -Name 'warns and deletes nothing' -Test {
            Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 0 -Exactly `
                -ParameterFilter { $Method -eq 'DELETE' }
        }
    }
}
