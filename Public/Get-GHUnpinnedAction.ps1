function Get-GHUnpinnedAction {
    <#
    .SYNOPSIS
        Report GitHub Actions 'uses:' references that are not pinned to a full
        commit SHA across an organization or an explicit set of repositories.
    .DESCRIPTION
        Scans every workflow file under '.github/workflows' in the active
        (non-archived, non-fork) repositories of an organization and emits one
        row per 'uses:' reference, classified by how it is pinned:

            sha    - pinned to a 40-character commit SHA (the hardened form)
            tag    - pinned to a tag/branch ref, or unpinned (the finding)
            local  - a local action ('uses: ./...'), cannot take a SHA
            docker - a Docker action ('uses: docker://...'), cannot take a SHA

        GitHub recommends pinning third-party actions to a full commit SHA
        because a tag or branch ref is mutable. Rulesets do not cover workflow
        contents and Dependabot only advances already-pinned SHAs, so an
        on-demand org-wide audit fills a genuine gap. The unpinned finding is
        the 'tag' rows: pipe to 'Where-Object Kind -eq tag' or pass '-Kind tag'.

        Repositories are either an explicit -Repository list or every active
        (non-archived, non-fork) repository in an -Organization (from 'gh repo
        list', the Invoke-GHCli lane). Workflow files are discovered and read
        through the contents REST endpoint (the Invoke-GHApi lane), where a
        repository without a workflows directory yields a tolerated 404 and is
        skipped.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Organization
        The organization (or user) whose repositories are scanned.
    .PARAMETER Repository
        An explicit list of repositories in 'owner/name' form to scan instead
        of an organization.
    .PARAMETER Kind
        Emit only references of this kind: 'sha', 'tag', 'local', or 'docker'.
        When omitted, every reference is emitted.
    .PARAMETER IncludeArchived
        Include archived repositories in the scan. Excluded by default. Only
        valid with -Organization.
    .PARAMETER IncludeFork
        Include forked repositories in the scan. Excluded by default. Only
        valid with -Organization.
    .PARAMETER Limit
        Maximum number of repositories to enumerate. Defaults to 1000. Only
        valid with -Organization.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per 'uses:' reference,
        with:
            Repository - 'owner/name'
            Workflow   - the workflow file name
            Line       - the 1-based line number of the reference
            Action     - the action reference (owner/repo, ./path, or docker://)
            Version    - the ref after '@' (empty for local/docker)
            Kind       - 'sha', 'tag', 'local', or 'docker'
    .EXAMPLE
        PS C:\> Get-GHUnpinnedAction -Organization PS-MCS -Kind tag
        Every action across the org that is pinned to a tag/branch rather than a
        commit SHA.
    .EXAMPLE
        PS C:\> Get-GHUnpinnedAction -Organization PS-MCS | Group-Object Kind
        A breakdown of how the org's action references are pinned.
    .EXAMPLE
        PS C:\> Get-GHUnpinnedAction -Repository 'PS-MCS/gh-org', 'PS-MCS/vdem' -Kind tag
        Tag-pinned actions in just the two named repositories.
    .NOTES
        Status: Experimental
        Comments:
        - API-heavy: it reads every workflow file in every active repository.
          For very large orgs, consider narrowing with -Limit.
        - Requires the GitHub CLI ('gh') authenticated with read access to the
          organization's repository contents.
        https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions
    #>
    [CmdletBinding(DefaultParameterSetName = 'Organization')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Organization', HelpMessage = 'Organization or user whose repos are scanned')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Organization,

        [Parameter(Mandatory, ParameterSetName = 'Repository', HelpMessage = "Explicit repositories in 'owner/name' form")]
        [ValidatePattern('^[^/]+/[^/]+$')]
        [System.String[]] $Repository,

        [Parameter(HelpMessage = 'Emit only references of this kind')]
        [ValidateSet('sha', 'tag', 'local', 'docker')]
        [System.String] $Kind,

        [Parameter(ParameterSetName = 'Organization', HelpMessage = 'Include archived repositories in the scan')]
        [System.Management.Automation.SwitchParameter] $IncludeArchived,

        [Parameter(ParameterSetName = 'Organization', HelpMessage = 'Include forked repositories in the scan')]
        [System.Management.Automation.SwitchParameter] $IncludeFork,

        [Parameter(ParameterSetName = 'Organization', HelpMessage = 'Maximum number of repositories to enumerate')]
        [ValidateRange(1, 10000)]
        [System.Int32] $Limit = 1000
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # RESOLVE THE REPO SET >> an explicit list, or an org scan excluding archived/forks by default
        if ($PSCmdlet.ParameterSetName -eq 'Repository') {
            $repos = @($Repository | ForEach-Object { [PSCustomObject] @{ nameWithOwner = $PSItem } })
        }
        else {
            $repoArgs = [System.Collections.Generic.List[System.String]]::new()
            $repoArgs.Add($Organization)
            if (-not $IncludeArchived) { $repoArgs.Add('--no-archived') }
            if (-not $IncludeFork) { $repoArgs.Add('--source') }
            $repoArgs.AddRange([System.String[]] @('--limit', $Limit.ToString(), '--json', 'nameWithOwner'))
            $repos = @(Invoke-GHCli -Argument (@('repo', 'list') + $repoArgs) -AsJson)
        }
        Write-Verbose -Message ('Scanning workflows across {0} repositories' -f $repos.Count)

        foreach ($repo in $repos) {
            try {
                # LIST THE WORKFLOWS DIRECTORY >> a tolerated 404 means the repo has none
                $entries = @(Invoke-GHApi -Path ('repos/{0}/contents/.github/workflows' -f $repo.nameWithOwner) -AllowNotFound)
                if (-not $entries) { continue }

                foreach ($entry in $entries) {
                    if ($entry.type -ne 'file' -or $entry.name -notmatch '\.ya?ml$') { continue }

                    # FETCH AND BASE64-DECODE THE WORKFLOW FILE
                    $file = Invoke-GHApi -Path ('repos/{0}/contents/{1}' -f $repo.nameWithOwner, $entry.path)
                    $bytes = [System.Convert]::FromBase64String(($file.content -replace '\s', ''))
                    $lines = [System.Text.Encoding]::UTF8.GetString($bytes) -split "`n"

                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        $line = $lines[$i]

                        # CLASSIFY THE uses: REFERENCE >> local/docker first (they may contain '@')
                        if ($line -match 'uses:\s*[''"]?(?<action>(?:\.[\\/]|docker://)[^''"\s#]+)') {
                            $action = $Matches['action']
                            $version = ''
                            $refKind = if ($action -like 'docker://*') { 'docker' } else { 'local' }
                        }
                        elseif ($line -match 'uses:\s*[''"]?(?<action>[^''"\s@]+)@(?<version>[^''"\s#]+)') {
                            $action = $Matches['action']
                            $version = $Matches['version']
                            $refKind = if ($version -match '^[0-9a-fA-F]{40}$') { 'sha' } else { 'tag' }
                        }
                        elseif ($line -match 'uses:\s*[''"]?(?<action>[^''"\s#]+)') {
                            # A uses: reference with no version is unpinned (implicit default branch)
                            $action = $Matches['action']
                            $version = ''
                            $refKind = 'tag'
                        }
                        else {
                            continue
                        }

                        if ($PSBoundParameters.ContainsKey('Kind') -and $refKind -ne $Kind) { continue }

                        [PSCustomObject] @{
                            Repository = $repo.nameWithOwner
                            Workflow   = $entry.name
                            Line       = $i + 1
                            Action     = $action
                            Version    = $version
                            Kind       = $refKind
                        }
                    }
                }
            }
            catch {
                Write-Warning -Message ('Scan failed for [{0}]; skipping. {1}' -f $repo.nameWithOwner, $PSItem.Exception.Message)
                continue
            }
        }
    }
}
