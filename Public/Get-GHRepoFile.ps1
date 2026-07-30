function Get-GHRepoFile {
    <#
    .SYNOPSIS
        Report whether a given file path exists in each repository of a GitHub
        organization.
    .DESCRIPTION
        Enumerates the active (non-archived, non-fork) repositories in an
        organization and checks each for a repository-relative file path on its
        default branch. Useful for auditing coverage of a governance file
        (CODEOWNERS, SECURITY.md, dependabot.yml, ...) across an org.

        Repositories come from 'gh repo list'; presence is checked with the
        contents REST endpoint via 'gh api' -- there is no first-class 'gh'
        subcommand for file existence -- where a 404 means the file is absent.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Organization
        The organization (or user) whose repositories are scanned.
    .PARAMETER Path
        Repository-relative path to check, e.g. '.github/CODEOWNERS'.
    .PARAMETER Filter
        Which repositories to emit: 'All' (default), 'Present', or 'Missing'.
    .PARAMETER IncludeArchived
        Include archived repositories in the scan. Excluded by default.
    .PARAMETER IncludeFork
        Include forked repositories in the scan. Excluded by default.
    .PARAMETER Limit
        Maximum number of repositories to enumerate. Defaults to 1000.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per repository, with:
            Repository - 'owner/name'
            Path       - the checked path
            Present    - $true when the file exists on the default branch
            Visibility - repository visibility
    .EXAMPLE
        PS C:\> Get-GHRepoFile -Organization PS-MCS -Path '.github/CODEOWNERS' -Filter Missing
        Active PS-MCS repositories that lack a CODEOWNERS file.
    .EXAMPLE
        PS C:\> Get-GHRepoFile -Organization PS-MCS -Path 'SECURITY.md' | Group-Object Present
        Coverage summary for SECURITY.md across the org.
    .NOTES
        Status: Experimental
        Presence is checked on each repository's default branch via the contents
        endpoint; use an org where the token has read access.
        https://docs.github.com/en/rest/repos/contents
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Organization or user whose repos are scanned')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Organization,

        [Parameter(Mandatory, HelpMessage = "Repository-relative path to check, e.g. '.github/CODEOWNERS'")]
        [ValidateNotNullOrEmpty()]
        [System.String] $Path,

        [Parameter(HelpMessage = 'Which repositories to emit')]
        [ValidateSet('All', 'Present', 'Missing')]
        [System.String] $Filter = 'All',

        [Parameter(HelpMessage = 'Include archived repositories in the scan')]
        [System.Management.Automation.SwitchParameter] $IncludeArchived,

        [Parameter(HelpMessage = 'Include forked repositories in the scan')]
        [System.Management.Automation.SwitchParameter] $IncludeFork,

        [Parameter(HelpMessage = 'Maximum number of repositories to enumerate')]
        [ValidateRange(1, 10000)]
        [System.Int32] $Limit = 1000
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # LIST REPOS >> EXCLUDE ARCHIVED/FORKS BY DEFAULT
        $repoArgs = [System.Collections.Generic.List[System.String]]::new()
        $repoArgs.Add($Organization)
        if (-not $IncludeArchived) { $repoArgs.Add('--no-archived') }
        if (-not $IncludeFork) { $repoArgs.Add('--source') }
        $repoArgs.AddRange([System.String[]] @('--limit', $Limit.ToString(), '--json', 'nameWithOwner,visibility'))
        $repos = @(Invoke-GHCli -Argument (@('repo', 'list') + $repoArgs) -AsJson)
        Write-Verbose -Message ('Checking [{0}] across {1} repositories in [{2}]' -f $Path, $repos.Count, $Organization)

        # CHECK EACH REPO >> A TOLERATED 404 FROM THE CONTENTS ENDPOINT MEANS ABSENT
        foreach ($repo in $repos) {
            try {
                $present = $null -ne (Invoke-GHApi -Path ('repos/{0}/contents/{1}' -f $repo.nameWithOwner, $Path) -AllowNotFound)
            }
            catch {
                Write-Warning -Message ('Presence check failed for [{0}]; skipping' -f $repo.nameWithOwner)
                continue
            }

            if (($Filter -eq 'Present' -and -not $present) -or ($Filter -eq 'Missing' -and $present)) { continue }

            [PSCustomObject] @{
                Repository = $repo.nameWithOwner
                Path       = $Path
                Present    = $present
                Visibility = $repo.visibility
            }
        }
    }
}
