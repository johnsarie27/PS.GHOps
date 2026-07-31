function New-GHIssue {
    <#
    .SYNOPSIS
        Create a GitHub issue in a repository.
    .DESCRIPTION
        Opens a new issue with a title and, optionally, a body, labels,
        assignees, and a milestone. This is the creation counterpart to the
        read-only Get-GHIssue and gives downstream automation a first-class home
        for issue creation instead of an ad-hoc 'gh api' call.

        The issue is created with a single POST to the repository issues REST
        endpoint through the private Invoke-GHApi helper, which returns the
        created issue as an object. Labels and assignees are sent as JSON arrays
        and the milestone as its numeric identifier.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Owner
        The organization or user that owns the repository.
    .PARAMETER Repository
        The repository name, without the owner prefix.
    .PARAMETER Title
        The issue title.
    .PARAMETER Body
        Optional issue body (Markdown).
    .PARAMETER Label
        Optional label name(s) to apply. Each label must already exist in the
        repository.
    .PARAMETER Assignee
        Optional login(s) to assign. Each user must have access to the
        repository; unknown logins are silently dropped by GitHub.
    .PARAMETER Milestone
        Optional milestone number to associate with the issue. Setting a
        milestone requires push access; it is silently dropped otherwise.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with:
            Repository - 'owner/name'
            Number     - the created issue number
            Title      - the issue title
            State      - the issue state
            Url        - the issue HTML URL
    .EXAMPLE
        PS C:\> New-GHIssue -Owner PS-MCS -Repository gh-org -Title 'Rotate the signing key'
        Opens a minimal issue with only a title.
    .EXAMPLE
        PS C:\> New-GHIssue -Owner PS-MCS -Repository gh-org -Title 'Whitelist request' -Body 'Please review.' -Label 'security', 'triage' -Assignee 'octocat'
        Opens an issue with a body, two labels, and an assignee.
    .NOTES
        Status: Experimental
        Comments:
        - Requires the GitHub CLI ('gh') authenticated with a token that has
          write access to issues on the target repository.
        https://docs.github.com/en/rest/issues/issues#create-an-issue
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Organization or user that owns the repository')]
        [ValidateNotNullOrEmpty()]
        [Alias('OwnerName')]
        [System.String] $Owner,

        [Parameter(Mandatory, HelpMessage = 'Repository name without the owner prefix')]
        [ValidateNotNullOrEmpty()]
        [Alias('RepositoryName')]
        [System.String] $Repository,

        [Parameter(Mandatory, HelpMessage = 'Issue title')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Title,

        [Parameter(HelpMessage = 'Issue body (Markdown)')]
        [System.String] $Body,

        [Parameter(HelpMessage = 'Label name(s) to apply; each must already exist')]
        [ValidateNotNullOrEmpty()]
        [System.String[]] $Label,

        [Parameter(HelpMessage = 'Login(s) to assign')]
        [ValidateNotNullOrEmpty()]
        [System.String[]] $Assignee,

        [Parameter(HelpMessage = 'Milestone number to associate with the issue')]
        [ValidateRange(1, [System.Int32]::MaxValue)]
        [System.Int32] $Milestone
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # BUILD THE REQUEST BODY >> title is required; the rest are optional
        $field = @{ title = $Title }
        if ($PSBoundParameters.ContainsKey('Body')) { $field['body'] = $Body }
        if ($Label) { $field['labels'] = $Label }
        if ($Assignee) { $field['assignees'] = $Assignee }
        if ($PSBoundParameters.ContainsKey('Milestone')) { $field['milestone'] = $Milestone }

        $target = '{0}/{1}' -f $Owner, $Repository
        if (-not $PSCmdlet.ShouldProcess($target, ('Create issue: {0}' -f $Title))) { return }

        # CREATE THE ISSUE >> POST returns the created issue as an object
        $created = Invoke-GHApi -Path ('repos/{0}/{1}/issues' -f $Owner, $Repository) -Method POST -Field $field

        # PROJECT THE CREATED ISSUE INTO A REPORT ROW
        [PSCustomObject] @{
            Repository = $target
            Number     = $created.number
            Title      = $created.title
            State      = $created.state
            Url        = $created.html_url
        }
    }
}
