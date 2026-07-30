BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Get-GHRepoFile' -Fixture {
    BeforeAll {
        Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith {
            @(
                [PSCustomObject] @{ nameWithOwner = 'PS-MCS/has-file'; visibility = 'PRIVATE' }
                [PSCustomObject] @{ nameWithOwner = 'PS-MCS/lacks-file'; visibility = 'PUBLIC' }
            )
        }
        # Present repo returns a content object; absent repo yields a tolerated 404 ($null)
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { [PSCustomObject] @{ name = 'CODEOWNERS' } } `
            -ParameterFilter { $Path -like '*has-file*' }
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith { $null } `
            -ParameterFilter { $Path -like '*lacks-file*' }
    }
    Context -Name 'default filter (All)' -Fixture {
        It -Name 'reports presence for every repo' -Test {
            $result = Get-GHRepoFile -Organization PS-MCS -Path '.github/CODEOWNERS'
            $result | Should -HaveCount 2
            ($result | Where-Object Repository -EQ 'PS-MCS/has-file').Present | Should -BeTrue
            ($result | Where-Object Repository -EQ 'PS-MCS/lacks-file').Present | Should -BeFalse
        }
        It -Name 'projects Repository/Path/Present/Visibility' -Test {
            $row = Get-GHRepoFile -Organization PS-MCS -Path '.github/CODEOWNERS' | Where-Object Repository -EQ 'PS-MCS/has-file'
            $row.Path | Should -Be '.github/CODEOWNERS'
            $row.Visibility | Should -Be 'PRIVATE'
        }
        It -Name 'checks presence via -AllowNotFound' -Test {
            Get-GHRepoFile -Organization PS-MCS -Path '.github/CODEOWNERS' | Out-Null
            Should -Invoke -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -Times 2 -Exactly `
                -ParameterFilter { $AllowNotFound.IsPresent }
        }
    }
    Context -Name 'filtering' -Fixture {
        It -Name 'returns only missing repos when Filter is Missing' -Test {
            $result = Get-GHRepoFile -Organization PS-MCS -Path '.github/CODEOWNERS' -Filter Missing
            $result | Should -HaveCount 1
            $result.Repository | Should -Be 'PS-MCS/lacks-file'
        }
        It -Name 'returns only present repos when Filter is Present' -Test {
            $result = Get-GHRepoFile -Organization PS-MCS -Path '.github/CODEOWNERS' -Filter Present
            $result | Should -HaveCount 1
            $result.Repository | Should -Be 'PS-MCS/has-file'
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects an empty Path' -Test {
            { Get-GHRepoFile -Organization PS-MCS -Path '' } | Should -Throw
        }
    }
}
