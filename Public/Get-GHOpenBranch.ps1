function Get-GHOpenBranch {
    <#
    .SYNOPSIS
        List non-default branches across every repository in a GitHub organization.
    .DESCRIPTION
        Enumerates the active (non-archived, non-fork) repositories in an
        organization and reports every branch that is NOT the repository's own
        default branch, optionally excluding named branches and repositories.
        Useful for spotting stale or forgotten working branches across an org.

        Repositories come from 'gh repo list', which supplies each repo's real
        default branch, so there is no need to guess 'main' versus 'master' --
        each repository's OWN default branch is excluded automatically. Branch
        names come from the REST branches endpoint, paginated.

        Archived repositories and forks are excluded by default; use
        -IncludeArchived and/or -IncludeFork to widen the scan.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Organization
        The GitHub organization (or user) whose repositories are scanned.
    .PARAMETER ExcludeBranch
        Branch names to exclude in addition to each repository's default branch.
    .PARAMETER ExcludeRepo
        Repository names (without owner) to skip entirely.
    .PARAMETER Limit
        Maximum number of repositories to enumerate. Defaults to 1000.
    .PARAMETER IncludeArchived
        Include archived repositories in the scan. Excluded by default.
    .PARAMETER IncludeFork
        Include forked repositories in the scan. Excluded by default.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per open branch, with:
            Repository - 'owner/name'
            Branch     - the branch name
            Default    - the repository's default branch name
    .EXAMPLE
        PS C:\> Get-GHOpenBranch -Organization PS-MCS | Format-Table -AutoSize
        List every non-default branch across all active PS-MCS repositories.
    .EXAMPLE
        PS C:\> Get-GHOpenBranch -Organization PS-MCS -ExcludeBranch 'gh-pages', 'tva'
        Also skip the 'gh-pages' and 'tva' branches in the report.
    .EXAMPLE
        PS C:\> Get-GHOpenBranch -Organization PS-MCS -ExcludeRepo 'census-ofb', 'fido-aaguid'
        Skip the named repositories entirely.
    .EXAMPLE
        PS C:\> Get-GHOpenBranch -Organization PS-MCS -IncludeArchived -IncludeFork
        Widen the scan to include archived repositories and forks.
    .NOTES
        Status: Experimental
        Requires the 'gh' CLI authenticated with read access to the org's repos;
        private repositories additionally need the 'repo' OAuth scope.
        https://cli.github.com/manual/gh_repo_list
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Organization or user whose repos are scanned')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Organization,

        [Parameter(HelpMessage = 'Branch names to exclude in addition to each default branch')]
        [System.String[]] $ExcludeBranch = @(),

        [Parameter(HelpMessage = 'Repository names to skip entirely')]
        [System.String[]] $ExcludeRepo = @(),

        [Parameter(HelpMessage = 'Maximum number of repositories to enumerate')]
        [ValidateRange(1, 10000)]
        [System.Int32] $Limit = 1000,

        [Parameter(HelpMessage = 'Include archived repositories in the scan')]
        [System.Management.Automation.SwitchParameter] $IncludeArchived,

        [Parameter(HelpMessage = 'Include forked repositories in the scan')]
        [System.Management.Automation.SwitchParameter] $IncludeFork
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # LIST REPOS WITH THEIR DEFAULT BRANCH >> EXCLUDE ARCHIVED/FORKS BY DEFAULT
        $repoArgs = [System.Collections.Generic.List[System.String]]::new()
        $repoArgs.Add($Organization)
        if (-not $IncludeArchived) { $repoArgs.Add('--no-archived') }
        if (-not $IncludeFork) { $repoArgs.Add('--source') }
        $repoArgs.AddRange([System.String[]] @('--limit', $Limit.ToString(), '--json', 'name,defaultBranchRef'))
        $reposJson = gh repo list @repoArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error -Message ('Failed to list repositories for organization [{0}]' -f $Organization) -ErrorAction Stop
        }

        $repos = @($reposJson | ConvertFrom-Json)
        Write-Verbose -Message ('Enumerating branches across {0} repositories in [{1}]' -f $repos.Count, $Organization)

        # EVALUATE EACH REPO
        foreach ($repo in $repos) {

            # SKIP EXCLUDED REPOS AND EMPTY REPOS (NO DEFAULT BRANCH)
            if ($repo.name -in $ExcludeRepo -or -not $repo.defaultBranchRef) { continue }

            $default = $repo.defaultBranchRef.name

            # LIST ALL BRANCH NAMES >> --paginate + '.[].name' FLATTENS PAGES TO string[]
            $branchPath = 'repos/{0}/{1}/branches?per_page=100' -f $Organization, $repo.name
            $names = gh api --paginate $branchPath --jq '.[].name'
            if ($LASTEXITCODE -ne 0) {
                Write-Warning -Message ('Failed to list branches for [{0}/{1}]; skipping' -f $Organization, $repo.name)
                continue
            }

            # EMIT EACH NON-DEFAULT, NON-EXCLUDED BRANCH
            foreach ($name in $names) {
                if ($name -eq $default -or $name -in $ExcludeBranch) { continue }
                [PSCustomObject] @{
                    Repository = '{0}/{1}' -f $Organization, $repo.name
                    Branch     = $name
                    Default    = $default
                }
            }
        }
    }
}
