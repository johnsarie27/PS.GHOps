function Get-GHIssue {
    <#
    .SYNOPSIS
        Report issues across a GitHub organization, a repo name prefix, or an
        explicit set of repositories.
    .DESCRIPTION
        Lists issues (pull requests excluded) scoped one of three ways:

            -Organization <org>            every repository in the org
            -Organization <org> -Prefix p  org repos whose name starts with 'p'
            -Repository owner/name[, ...]   an explicit set of repositories

        Data comes from 'gh search issues', so one call covers the whole scope
        and results span every repository the authenticated token can read. The
        prefix form filters the org-wide result set by repository name client
        side, so it remains a single search.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Organization
        The organization (or user) whose repositories are searched.
    .PARAMETER Prefix
        Restrict the organization scan to repositories whose name begins with
        this string. Only valid with -Organization.
    .PARAMETER Repository
        An explicit list of repositories in 'owner/name' form.
    .PARAMETER State
        Issue state to include: 'open', 'closed', or 'all'. Defaults to 'open'.
    .PARAMETER Limit
        Maximum number of issues to return. Defaults to 200; the GitHub search
        API caps this at 1000.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per issue, with:
            Repository - 'owner/name'
            Number     - issue number
            Title      - issue title
            State      - issue state
            Updated    - last-updated timestamp in local time
            Author     - issue author login
            Assignees  - comma-separated assignee logins
            Url        - issue URL
    .EXAMPLE
        PS C:\> Get-GHIssue -Organization PS-MCS | Format-Table -AutoSize
        Every open issue across all PS-MCS repositories.
    .EXAMPLE
        PS C:\> Get-GHIssue -Organization esri-codehub -Prefix appsec -State all
        Open and closed issues in esri-codehub repos whose name starts with 'appsec'.
    .EXAMPLE
        PS C:\> Get-GHIssue -Repository 'PS-MCS/gh-org', 'PS-MCS/vdem' -State open
        Open issues in the two named repositories.
    .NOTES
        Status: Experimental
        Uses 'gh search issues', which returns at most 1000 results and only
        indexed (searchable) issues; for an exhaustive per-repo listing use
        'gh issue list --repo owner/name' instead.
        Searching private repositories requires the 'repo' OAuth scope on the gh
        token; run 'gh auth refresh -h github.com -s repo' if results are missing.
        https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests
    #>
    [CmdletBinding(DefaultParameterSetName = 'Organization')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Organization', HelpMessage = 'Organization or user to search')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Organization,

        [Parameter(ParameterSetName = 'Organization', HelpMessage = 'Restrict to repos whose name starts with this string')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Prefix,

        [Parameter(Mandatory, ParameterSetName = 'Repository', HelpMessage = "Explicit repositories in 'owner/name' form")]
        [ValidatePattern('^[^/]+/[^/]+$')]
        [System.String[]] $Repository,

        [Parameter(HelpMessage = 'Issue state to include')]
        [ValidateSet('open', 'closed', 'all')]
        [System.String] $State = 'open',

        [Parameter(HelpMessage = 'Maximum number of issues to return (search caps at 1000)')]
        [ValidateRange(1, 1000)]
        [System.Int32] $Limit = 200
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # BUILD THE SEARCH SCOPE >> --owner FOR AN ORG, REPEATED --repo FOR A LIST
        $searchArgs = [System.Collections.Generic.List[System.String]]::new()
        if ($State -ne 'all') { $searchArgs.AddRange([System.String[]] @('--state', $State)) }
        if ($PSCmdlet.ParameterSetName -eq 'Organization') {
            $searchArgs.AddRange([System.String[]] @('--owner', $Organization))
        }
        else {
            foreach ($repo in $Repository) { $searchArgs.AddRange([System.String[]] @('--repo', $repo)) }
        }
        $jsonFields = 'number,title,state,updatedAt,repository,author,assignees,url'
        $searchArgs.AddRange([System.String[]] @('--limit', $Limit.ToString(), '--json', $jsonFields))

        # RUN THE SEARCH
        $raw = gh search issues @searchArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Error -Message 'gh search issues failed' -ErrorAction Stop
        }
        $issues = @($raw | ConvertFrom-Json)

        # FILTER THE ORG RESULT SET BY REPO-NAME PREFIX (SINGLE-SEARCH PREFIX SCOPE)
        if ($Prefix) {
            $issues = $issues.Where({ $PSItem.repository.nameWithOwner.Split('/')[-1].StartsWith($Prefix) })
        }

        Write-Verbose -Message ('Returning {0} issues' -f $issues.Count)

        # PROJECT EACH ISSUE INTO A REPORT ROW
        foreach ($issue in $issues) {
            [PSCustomObject] @{
                Repository = $issue.repository.nameWithOwner
                Number     = $issue.number
                Title      = $issue.title
                State      = $issue.state
                Updated    = ([System.DateTimeOffset] $issue.updatedAt).LocalDateTime
                Author     = $issue.author.login
                Assignees  = ($issue.assignees.login -join ', ')
                Url        = $issue.url
            }
        }
    }
}
