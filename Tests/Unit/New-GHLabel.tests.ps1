BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'New-GHLabel' -Fixture {
    Context -Name 'create' -Fixture {
        BeforeAll {
            # Create succeeds
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ name = 'security' } } `
                -ParameterFilter { $Method -eq 'POST' }
        }
        It -Name 'issues one create per (repository x label)' -Test {
            New-GHLabel -Repository 'PS-MCS/gh-org', 'PS-MCS/vdem' -Name 'security' -Color 'd73a4a' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 2 -Exactly `
                -ParameterFilter { $Method -eq 'POST' -and $Path -like '*/labels' }
        }
        It -Name 'sends name and color in the request body' -Test {
            New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Description 'Security work' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Field['name'] -eq 'security' -and $Field['color'] -eq 'd73a4a' -and $Field['description'] -eq 'Security work' }
        }
        It -Name 'projects Repository/Name/Color/Status' -Test {
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Confirm:$false
            $row.Repository | Should -Be 'PS-MCS/gh-org'
            $row.Name | Should -Be 'security'
            $row.Color | Should -Be 'd73a4a'
            $row.Status | Should -Be 'Created'
        }
        It -Name 'defaults color to a neutral gray' -Test {
            New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Field['color'] -eq 'ededed' }
        }
    }
    Context -Name 'multiple labels' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ name = 'x' } } `
                -ParameterFilter { $Method -eq 'POST' }
        }
        It -Name 'creates each label in the spec list' -Test {
            $result = New-GHLabel -Repository 'PS-MCS/gh-org' -Label @{ Name = 'tech-debt'; Color = 'fbca04' }, @{ Name = 'security' } -Confirm:$false
            $result | Should -HaveCount 2
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 2 -Exactly `
                -ParameterFilter { $Method -eq 'POST' }
        }
    }
    Context -Name 'WhatIf' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ name = 'x' } }
        }
        It -Name 'creates nothing' -Test {
            New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -WhatIf | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 0 -Exactly
        }
    }
    Context -Name 'existing label' -Fixture {
        BeforeAll {
            # POST fails with a 422 already_exists
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { throw 'gh api repos/PS-MCS/gh-org/labels failed (exit 1): HTTP 422 already_exists' } `
                -ParameterFilter { $Method -eq 'POST' }
            # PATCH succeeds
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ name = 'security' } } `
                -ParameterFilter { $Method -eq 'PATCH' }
        }
        It -Name 'skips with Status Exists by default' -Test {
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Confirm:$false -WarningAction SilentlyContinue
            $row.Status | Should -Be 'Exists'
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 0 -Exactly `
                -ParameterFilter { $Method -eq 'PATCH' }
        }
        It -Name 'patches with Status Updated when -Update is supplied' -Test {
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Update -Confirm:$false
            $row.Status | Should -Be 'Updated'
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Method -eq 'PATCH' }
        }
    }
    Context -Name 'create failure' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { throw 'gh api ... failed (exit 1): HTTP 403 Forbidden' } `
                -ParameterFilter { $Method -eq 'POST' }
        }
        It -Name 'emits a Failed row and does not throw' -Test {
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Confirm:$false -WarningAction SilentlyContinue
            $row.Status | Should -Be 'Failed'
        }
    }
    Context -Name 'validation' -Fixture {
        It -Name 'rejects a malformed repository' -Test {
            { New-GHLabel -Repository 'not-a-repo' -Name 'security' -Confirm:$false } | Should -Throw
        }
        It -Name 'rejects a non-hex color in the Single set' -Test {
            { New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'ZZZ' -Confirm:$false } | Should -Throw
        }
        It -Name 'emits a Failed row for an invalid color in a label spec' -Test {
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Label @{ Name = 'security'; Color = 'nothex' } -Confirm:$false -WarningAction SilentlyContinue
            $row.Status | Should -Be 'Failed'
        }
    }
}
