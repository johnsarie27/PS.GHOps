BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Get-GHIssue' -Fixture {
    BeforeAll {
        Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith {
            @(
                [PSCustomObject] @{
                    number     = 1
                    title      = 'first'
                    state      = 'open'
                    updatedAt  = '2026-07-01T12:00:00Z'
                    repository = [PSCustomObject] @{ nameWithOwner = 'PS-MCS/aws-lambda'; name = 'aws-lambda' }
                    author     = [PSCustomObject] @{ login = 'octo' }
                    assignees  = @([PSCustomObject] @{ login = 'octo' }, [PSCustomObject] @{ login = 'hubot' })
                    url        = 'https://github.com/PS-MCS/aws-lambda/issues/1'
                }
                [PSCustomObject] @{
                    number     = 2
                    title      = 'second'
                    state      = 'closed'
                    updatedAt  = '2026-07-02T12:00:00Z'
                    repository = [PSCustomObject] @{ nameWithOwner = 'PS-MCS/web-app'; name = 'web-app' }
                    author     = [PSCustomObject] @{ login = 'octo' }
                    assignees  = @()
                    url        = 'https://github.com/PS-MCS/web-app/issues/2'
                }
            )
        }
    }
    Context -Name 'organization scope' -Fixture {
        It -Name 'returns one projected row per issue' -Test {
            $result = Get-GHIssue -Organization PS-MCS
            $result | Should -HaveCount 2
        }
        It -Name 'projects the expected properties' -Test {
            $row = Get-GHIssue -Organization PS-MCS | Where-Object Number -EQ 1
            $row.Repository | Should -Be 'PS-MCS/aws-lambda'
            $row.Title | Should -Be 'first'
            $row.Author | Should -Be 'octo'
            $row.Assignees | Should -Be 'octo, hubot'
            $row.Updated | Should -BeOfType [System.DateTime]
        }
        It -Name 'searches by --owner' -Test {
            Get-GHIssue -Organization PS-MCS | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains 'search' -and $Argument -contains '--owner' -and $Argument -contains 'PS-MCS' }
        }
    }
    Context -Name 'prefix filtering' -Fixture {
        It -Name 'keeps only repos whose name matches the prefix' -Test {
            $result = Get-GHIssue -Organization PS-MCS -Prefix aws
            $result | Should -HaveCount 1
            $result.Repository | Should -Be 'PS-MCS/aws-lambda'
        }
    }
    Context -Name 'repository scope' -Fixture {
        It -Name 'searches with repeated --repo arguments' -Test {
            Get-GHIssue -Repository 'PS-MCS/web-app', 'PS-MCS/aws-lambda' | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains '--repo' -and $Argument -notcontains '--owner' }
        }
    }
    Context -Name 'state handling' -Fixture {
        It -Name 'omits --state when State is all' -Test {
            Get-GHIssue -Organization PS-MCS -State all | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -notcontains '--state' }
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects a repository not in owner/name form' -Test {
            { Get-GHIssue -Repository 'not-a-valid-repo' } | Should -Throw
        }
    }
}
