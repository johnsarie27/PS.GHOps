BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Get-GHActivity' -Fixture {
    BeforeAll {
        # -User default resolves through Invoke-GHApi ('user')
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ login = 'me' } }
        Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith {
            @(
                [PSCustomObject] @{
                    number     = 7
                    title      = 'a change'
                    repository = [PSCustomObject] @{ nameWithOwner = 'PS-MCS/gh-org' }
                    createdAt  = '2026-07-01T00:00:00Z'
                    closedAt   = '2026-07-02T00:00:00Z'
                }
            )
        }
    }
    Context -Name 'kind selection' -Fixture {
        It -Name 'runs one search for a single kind and projects the row' -Test {
            $result = Get-GHActivity -User me -Kind 'Issue(opened)'
            $result | Should -HaveCount 1
            $result.Kind | Should -Be 'Issue(opened)'
            $result.Item | Should -Be 'PS-MCS/gh-org#7'
            $result.Title | Should -Be 'a change'
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly
        }
        It -Name 'runs one search per selected kind' -Test {
            $result = Get-GHActivity -User me -Kind 'PR(merged)', 'PR(closed)'
            $result | Should -HaveCount 2
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 2 -Exactly
        }
    }
    Context -Name 'default user' -Fixture {
        It -Name 'resolves the authenticated login via Invoke-GHApi' -Test {
            Get-GHActivity -Kind 'Issue(opened)' | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 `
                -ParameterFilter { $Path -eq 'user' }
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' `
                -ParameterFilter { $Argument -contains 'me' }
        }
    }
    Context -Name 'timezone handling' -Fixture {
        It -Name 'emits When in UTC when -Utc is set' -Test {
            $utc = (Get-GHActivity -User me -Kind 'Issue(opened)' -Utc).When
            $local = (Get-GHActivity -User me -Kind 'Issue(opened)').When
            $utc | Should -Be ([System.DateTimeOffset]'2026-07-01T00:00:00Z').UtcDateTime
            $local | Should -Be ([System.DateTimeOffset]'2026-07-01T00:00:00Z').LocalDateTime
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects an out-of-range Hours value' -Test {
            { Get-GHActivity -User me -Hours 0 } | Should -Throw
        }
        It -Name 'rejects an unknown Kind' -Test {
            { Get-GHActivity -User me -Kind 'Nope' } | Should -Throw
        }
    }
}
