function Get-GHActivity {
    <#
    .SYNOPSIS
        Report a user's recent GitHub issue and pull-request activity via search.
    .DESCRIPTION
        Emits one object per issue/PR the user is INVOLVED in (author, assignee,
        commenter, or mentioned) that had a lifecycle event within the look-back
        window, categorized by Kind:

            Issue(opened)  - issue created in the window
            Issue(closed)  - issue closed in the window
            PR(opened)     - pull request created in the window
            PR(merged)     - pull request merged in the window
            PR(closed)     - pull request closed WITHOUT merge in the window

        All data comes from 'gh search', so results span every repository the
        authenticated token can read, including private ones. Because search
        attributes by INVOLVEMENT (not by who performed an action), an item the
        user merely commented on is included, and a pure merge/close the user
        performed with no other involvement may be missed - GitHub search has no
        'merged-by' or 'closed-by' qualifier.

        An item can appear under more than one Kind when it had multiple lifecycle
        events in the window (e.g. a PR both opened and merged the same day is
        emitted as PR(opened) AND PR(merged)). Each Kind is capped at the 100 most
        relevant search results, so a busier window may be truncated.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Hours
        Size of the look-back window, in hours. Defaults to 24.
    .PARAMETER Kind
        Which activity kinds to include. Defaults to all five. Each kind maps to
        one search query, so narrowing this skips the unneeded queries.
    .PARAMETER User
        GitHub login to report on. Defaults to the authenticated user. For any
        login other than yourself, only activity in repositories your token can
        read is visible.
    .PARAMETER Utc
        Emit the 'When' timestamp in UTC. By default 'When' is in the local timezone.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per matched item, with:
            Kind  - one of the five categories above
            Item  - 'owner/repo#number'
            When  - timestamp of THIS Kind's event (created-at for the 'opened'
                    kinds, closed-at for the closed/merged kinds) as a DateTime in
                    local time, or UTC when -Utc is specified
            Title - issue or pull-request title
    .EXAMPLE
        PS C:\> Get-GHActivity | Format-Table -GroupBy Kind -AutoSize
        Show all issue/PR activity involving you from the last 24 hours, grouped by kind.
    .EXAMPLE
        PS C:\> Get-GHActivity -Hours 72 -Kind 'PR(merged)', 'PR(closed)'
        Show only merged and closed-unmerged PRs involving you over the last 3 days.
    .EXAMPLE
        PS C:\> Get-GHActivity -User btrampf | Sort-Object When
        Report another user's issue/PR activity (in repos you can see) over the last 24 hours.
    .NOTES
        Status: Experimental
        Search attributes by involvement, not by action; there is no GitHub search
        qualifier for 'merged-by' or 'closed-by'.
        Searching private repositories requires the 'repo' OAuth scope on the gh
        token; run 'gh auth refresh -h github.com -s repo' if private results are
        missing.
        https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(HelpMessage = 'Look-back window size, in hours')]
        [ValidateRange(1, 8760)]
        [System.Int32] $Hours = 24,

        [Parameter(HelpMessage = 'Activity kinds to include')]
        [ValidateSet('Issue(opened)', 'Issue(closed)', 'PR(opened)', 'PR(merged)', 'PR(closed)')]
        [System.String[]] $Kind = @('Issue(opened)', 'Issue(closed)', 'PR(opened)', 'PR(merged)', 'PR(closed)'),

        [Parameter(HelpMessage = 'GitHub login to report on; defaults to the authenticated user')]
        [ValidateNotNullOrEmpty()]
        [System.String] $User = (gh api user --jq '.login'),

        [Parameter(HelpMessage = 'Emit the When timestamp in UTC instead of local time')]
        [System.Management.Automation.SwitchParameter] $Utc
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        [System.DateTimeOffset] $since = (Get-Date).ToUniversalTime().AddHours(-$Hours)
        $dateFilter = '>={0}' -f $since.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $jsonFields = 'number,title,repository,createdAt,closedAt'

        # PROJECT A SEARCH RESULT SET INTO ACTIVITY ROWS
        $toRows = {
            param(
                [System.Object[]] $Items,
                [System.String] $RowKind,
                [System.String] $DateField,
                [System.Boolean] $AsUtc
            )
            foreach ($x in $Items) {
                $offset = [System.DateTimeOffset] $x.$DateField
                $when = if ($AsUtc) { $offset.UtcDateTime } else { $offset.LocalDateTime }
                [PSCustomObject] @{
                    Kind  = $RowKind
                    Item  = ('{0}#{1}' -f $x.repository.nameWithOwner, $x.number)
                    When  = $when
                    Title = $x.title
                }
            }
        }

        # RUN ONE SEARCH PER SELECTED KIND ($Kind IS AN ARRAY; switch ITERATES IT)
        switch ($Kind) {
            'Issue(opened)' {
                $opened = gh search issues --involves $User --created $dateFilter --json $jsonFields --limit 100 | ConvertFrom-Json
                & $toRows $opened 'Issue(opened)' 'createdAt' $Utc
            }
            'Issue(closed)' {
                $closed = gh search issues --involves $User --state closed --closed $dateFilter --json $jsonFields --limit 100 | ConvertFrom-Json
                & $toRows $closed 'Issue(closed)' 'closedAt' $Utc
            }
            'PR(opened)' {
                $prOpened = gh search prs --involves $User --created $dateFilter --json $jsonFields --limit 100 | ConvertFrom-Json
                & $toRows $prOpened 'PR(opened)' 'createdAt' $Utc
            }
            'PR(merged)' {
                $prMerged = gh search prs --involves $User --merged --merged-at $dateFilter --json $jsonFields --limit 100 | ConvertFrom-Json
                & $toRows $prMerged 'PR(merged)' 'closedAt' $Utc
            }
            'PR(closed)' {
                $prClosed = gh search prs 'is:unmerged' --involves $User --closed $dateFilter --json $jsonFields --limit 100 | ConvertFrom-Json
                & $toRows $prClosed 'PR(closed)' 'closedAt' $Utc
            }
        }
    }
}
