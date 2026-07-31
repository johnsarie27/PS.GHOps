function New-GHLabel {
    <#
    .SYNOPSIS
        Create one or more labels in one or more GitHub repositories.
    .DESCRIPTION
        Stands up the same label (or a set of labels) across a handful of
        repositories in one call. GitHub has no org-level labels, so adding a
        label to N repositories otherwise means N separate API calls; this
        function wraps that loop.

        Each (repository x label) pair is created independently with the labels
        REST endpoint via the private Invoke-GHApi helper. An existing label is
        skipped with a warning (Status 'Exists') unless -Update is supplied, in
        which case its color and description are patched (Status 'Updated'). A
        single failure emits a 'Failed' row and does not halt the batch.

        This is targeted label creation, NOT org-wide label synchronization.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Repository
        One or more target repositories as 'owner/name'.
    .PARAMETER Name
        The label name (parameter set 'Single').
    .PARAMETER Color
        Six hexadecimal characters without a leading '#' (parameter set
        'Single'). Defaults to a neutral gray ('ededed').
    .PARAMETER Description
        Optional label description (parameter set 'Single').
    .PARAMETER Label
        One or more label specifications (parameter set 'Multiple'), each a
        hashtable or object with Name, and optionally Color and Description.
    .PARAMETER Update
        Patch the color and description of a label that already exists instead
        of skipping it.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per (repository, label),
        with:
            Repository - 'owner/name'
            Name       - the label name
            Color      - the label color
            Status     - 'Created', 'Exists', 'Updated', or 'Failed'
    .EXAMPLE
        PS C:\> New-GHLabel -Repository 'PS-MCS/gh-org', 'PS-MCS/vdem' -Name 'security' -Color 'd73a4a' -Description 'Security-related work'
        Creates the 'security' label in both repositories.
    .EXAMPLE
        PS C:\> New-GHLabel -Repository 'PS-MCS/gh-org' -Label @{ Name = 'tech-debt'; Color = 'fbca04' }, @{ Name = 'security' }
        Creates several labels in one repository from a list of specs.
    .EXAMPLE
        PS C:\> New-GHLabel -Repository 'PS-MCS/gh-org' -Name 'security' -Color '0e8a16' -Update
        Recolors an existing 'security' label rather than skipping it.
    .NOTES
        Status: Experimental
        Comments:
        - Requires the GitHub CLI ('gh') authenticated with a token that has
          write access to issues on the target repositories.
        https://docs.github.com/en/rest/issues/labels
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Single')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = "Target repositories as 'owner/name'")]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[^/\s]+/[^/\s]+$')]
        [System.String[]] $Repository,

        [Parameter(Mandatory, ParameterSetName = 'Single', HelpMessage = 'Label name')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Name,

        [Parameter(ParameterSetName = 'Single', HelpMessage = 'Six hex characters without a leading #')]
        [ValidatePattern('^[0-9a-fA-F]{6}$')]
        [System.String] $Color = 'ededed',

        [Parameter(ParameterSetName = 'Single', HelpMessage = 'Label description')]
        [System.String] $Description,

        [Parameter(Mandatory, ParameterSetName = 'Multiple', HelpMessage = 'Label specs, each with Name/Color/Description')]
        [ValidateNotNullOrEmpty()]
        [System.Object[]] $Label,

        [Parameter(HelpMessage = 'Update an existing label instead of skipping it')]
        [System.Management.Automation.SwitchParameter] $Update
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # NORMALIZE INPUT INTO A UNIFORM LIST OF LABEL SPECS >> member access reads both hashtable keys and object properties
        if ($PSCmdlet.ParameterSetName -eq 'Single') {
            $specs = @([PSCustomObject] @{ Name = $Name; Color = $Color; Description = $Description })
        }
        else {
            $specs = foreach ($item in $Label) {
                [PSCustomObject] @{
                    Name        = $item.Name
                    Color       = if ($item.Color) { $item.Color } else { 'ededed' }
                    Description = $item.Description
                }
            }
        }

        foreach ($repo in $Repository) {
            foreach ($spec in $specs) {

                # PER-SPEC VALIDATION >> emit a Failed row rather than halting the batch
                if ([System.String]::IsNullOrWhiteSpace($spec.Name)) {
                    Write-Warning -Message ('Skipping a label with no name for [{0}].' -f $repo)
                    [PSCustomObject] @{ Repository = $repo; Name = $spec.Name; Color = $spec.Color; Status = 'Failed' }
                    continue
                }
                if ($spec.Color -notmatch '^[0-9a-fA-F]{6}$') {
                    Write-Warning -Message ('Label [{0}] has an invalid color [{1}] for [{2}]; expected 6 hex characters.' -f $spec.Name, $spec.Color, $repo)
                    [PSCustomObject] @{ Repository = $repo; Name = $spec.Name; Color = $spec.Color; Status = 'Failed' }
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess(('{0} :: {1}' -f $repo, $spec.Name), 'Create label')) { continue }

                # CREATE >> POST the label; a 422 means it already exists
                $status = 'Created'
                try {
                    $body = @{ name = $spec.Name; color = $spec.Color }
                    if (-not [System.String]::IsNullOrEmpty($spec.Description)) { $body['description'] = $spec.Description }
                    Invoke-GHApi -Path ('repos/{0}/labels' -f $repo) -Method POST -Field $body | Out-Null
                }
                catch {
                    if ($PSItem.Exception.Message -match '422|already[ _]exists') {

                        if ($Update) {
                            # UPDATE >> PATCH the existing label's color/description
                            try {
                                $body = @{ color = $spec.Color }
                                if (-not [System.String]::IsNullOrEmpty($spec.Description)) { $body['description'] = $spec.Description }
                                Invoke-GHApi -Path ('repos/{0}/labels/{1}' -f $repo, [System.Uri]::EscapeDataString($spec.Name)) -Method PATCH -Field $body | Out-Null
                                $status = 'Updated'
                            }
                            catch {
                                Write-Warning -Message ('Failed to update label [{0}] in [{1}]: {2}' -f $spec.Name, $repo, $PSItem.Exception.Message)
                                $status = 'Failed'
                            }
                        }
                        else {
                            Write-Warning -Message ('Label [{0}] already exists in [{1}]; use -Update to change it.' -f $spec.Name, $repo)
                            $status = 'Exists'
                        }
                    }
                    else {
                        Write-Warning -Message ('Failed to create label [{0}] in [{1}]: {2}' -f $spec.Name, $repo, $PSItem.Exception.Message)
                        $status = 'Failed'
                    }
                }

                [PSCustomObject] @{
                    Repository = $repo
                    Name       = $spec.Name
                    Color      = $spec.Color
                    Status     = $status
                }
            }
        }
    }
}
