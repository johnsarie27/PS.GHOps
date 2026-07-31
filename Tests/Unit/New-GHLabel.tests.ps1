BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'New-GHLabel' -Fixture {
    Context -Name 'create' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith { $null }
        }
        It -Name 'issues one create per (repository x label)' -Test {
            New-GHLabel -Repository 'PS-MCS/gh-org', 'PS-MCS/vdem' -Name 'security' -Color 'd73a4a' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 2 -Exactly `
                -ParameterFilter { $Argument -contains 'create' }
        }
        It -Name 'passes name, color, and description to gh label create' -Test {
            New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Description 'Security work' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter {
                $Argument -contains 'create' -and $Argument -contains 'security' -and
                $Argument -contains '--repo' -and $Argument -contains 'PS-MCS/gh-org' -and
                $Argument -contains '--color' -and $Argument -contains 'd73a4a' -and
                $Argument -contains '--description' -and $Argument -contains 'Security work'
            }
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
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains '--color' -and $Argument -contains 'ededed' }
        }
    }
    Context -Name 'multiple labels' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith { $null }
        }
        It -Name 'creates each hashtable spec in the list' -Test {
            $result = New-GHLabel -Repository 'PS-MCS/gh-org' -Label @{ Name = 'tech-debt'; Color = 'fbca04' }, @{ Name = 'security' } -Confirm:$false
            $result | Should -HaveCount 2
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 2 -Exactly `
                -ParameterFilter { $Argument -contains 'create' }
        }
        It -Name 'accepts PSCustomObject specs' -Test {
            $spec = [PSCustomObject] @{ Name = 'tech-debt'; Color = 'fbca04'; Description = 'Debt' }
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Label $spec -Confirm:$false
            $row.Name | Should -Be 'tech-debt'
            $row.Color | Should -Be 'fbca04'
            $row.Status | Should -Be 'Created'
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains 'tech-debt' -and $Argument -contains 'fbca04' -and $Argument -contains 'Debt' }
        }
    }
    Context -Name 'WhatIf' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith { $null }
        }
        It -Name 'creates nothing' -Test {
            New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -WhatIf | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 0 -Exactly
        }
    }
    Context -Name 'existing label' -Fixture {
        BeforeAll {
            # create fails because the label already exists
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith { throw 'gh label create failed (exit 1): HTTP 422 already exists' } `
                -ParameterFilter { $Argument -contains 'create' }
            # edit succeeds
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith { $null } `
                -ParameterFilter { $Argument -contains 'edit' }
        }
        It -Name 'skips with Status Exists by default' -Test {
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Confirm:$false -WarningAction SilentlyContinue
            $row.Status | Should -Be 'Exists'
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 0 -Exactly `
                -ParameterFilter { $Argument -contains 'edit' }
        }
        It -Name 'edits with Status Updated when -Update is supplied' -Test {
            $row = New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color 'd73a4a' -Update -Confirm:$false
            $row.Status | Should -Be 'Updated'
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains 'edit' }
        }
    }
    Context -Name 'create failure' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith { throw 'gh label create failed (exit 1): HTTP 403 Forbidden' } `
                -ParameterFilter { $Argument -contains 'create' }
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
