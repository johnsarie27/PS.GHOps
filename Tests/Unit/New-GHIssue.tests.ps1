BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'New-GHIssue' -Fixture {
    Context -Name 'create' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith {
                [PSCustomObject] @{
                    number   = 42
                    title    = 'Rotate the signing key'
                    state    = 'open'
                    html_url = 'https://github.com/PS-MCS/gh-org/issues/42'
                }
            }
        }
        It -Name 'posts to the repository issues endpoint' -Test {
            New-GHIssue -Owner 'PS-MCS' -Repository 'gh-org' -Title 'Rotate the signing key' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Path -eq 'repos/PS-MCS/gh-org/issues' -and $Method -eq 'POST' }
        }
        It -Name 'sends only the title when nothing else is supplied' -Test {
            New-GHIssue -Owner 'PS-MCS' -Repository 'gh-org' -Title 'Rotate the signing key' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter {
                $Field['title'] -eq 'Rotate the signing key' -and
                -not $Field.ContainsKey('body') -and -not $Field.ContainsKey('labels') -and
                -not $Field.ContainsKey('assignees') -and -not $Field.ContainsKey('milestone')
            }
        }
        It -Name 'passes body, labels, assignees, and milestone' -Test {
            $params = @{
                Owner      = 'PS-MCS'
                Repository = 'gh-org'
                Title      = 'Whitelist request'
                Body       = 'Please review.'
                Label      = 'security', 'triage'
                Assignee   = 'octocat'
                Milestone  = 3
                Confirm    = $false
            }
            New-GHIssue @params | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter {
                $Field['body'] -eq 'Please review.' -and
                $Field['labels'] -contains 'security' -and $Field['labels'] -contains 'triage' -and
                $Field['assignees'] -contains 'octocat' -and
                $Field['milestone'] -eq 3
            }
        }
        It -Name 'projects Repository/Number/Title/State/Url' -Test {
            $row = New-GHIssue -Owner 'PS-MCS' -Repository 'gh-org' -Title 'Rotate the signing key' -Confirm:$false
            $row.Repository | Should -Be 'PS-MCS/gh-org'
            $row.Number | Should -Be 42
            $row.Title | Should -Be 'Rotate the signing key'
            $row.State | Should -Be 'open'
            $row.Url | Should -Be 'https://github.com/PS-MCS/gh-org/issues/42'
        }
        It -Name 'accepts OwnerName and RepositoryName aliases' -Test {
            New-GHIssue -OwnerName 'PS-MCS' -RepositoryName 'gh-org' -Title 'Rotate the signing key' -Confirm:$false | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Path -eq 'repos/PS-MCS/gh-org/issues' }
        }
    }
    Context -Name 'WhatIf' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { $null }
        }
        It -Name 'creates nothing' -Test {
            New-GHIssue -Owner 'PS-MCS' -Repository 'gh-org' -Title 'Rotate the signing key' -WhatIf | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 0 -Exactly
        }
    }
    Context -Name 'validation' -Fixture {
        It -Name 'rejects an empty title' -Test {
            { New-GHIssue -Owner 'PS-MCS' -Repository 'gh-org' -Title '' -Confirm:$false } | Should -Throw
        }
        It -Name 'rejects a milestone below 1' -Test {
            { New-GHIssue -Owner 'PS-MCS' -Repository 'gh-org' -Title 'x' -Milestone 0 -Confirm:$false } | Should -Throw
        }
    }
}
