function Remove-GHStaleCodeScan {
    <#
    .SYNOPSIS
        Remove stale code scanning analyses that block pull requests after a
        scanning workflow is renamed, moved, or deleted.
    .DESCRIPTION
        When a code scanning workflow file is renamed (for example
        `powershell.yml` becomes `psscriptanalyzer.yml`), GitHub identifies the
        analysis configuration by `<workflow-path>:<job>`. The rename creates a
        NEW configuration and orphans the OLD one. If a branch ruleset requires
        code scanning results, merge protection keeps expecting every pull
        request to produce results for the orphaned configuration. Because the
        old workflow no longer runs, nothing is produced and the merge-protection
        check reports "N configuration(s) not found" (a NEUTRAL result), which
        blocks the pull request.

        This function removes the orphaned configuration from a branch by
        deleting every code scanning analysis associated with it, which stops
        merge protection from expecting it. By default it auto-detects stale
        configurations (those whose backing workflow file no longer exists on
        the branch); one or more explicit configuration keys can be supplied
        instead.

        Analyses are deleted newest-to-oldest, which is the order the GitHub API
        requires. The operation is irreversible: it permanently removes the
        code scanning history for the affected configuration. The current,
        renamed configuration continues to cover the scan going forward.

        Authentication uses the GitHub CLI (`gh`), which must already be
        installed and authenticated (`gh auth status`).
    .PARAMETER Owner
        The organization or user that owns the repository.
    .PARAMETER Repository
        The repository name, without the owner prefix.
    .PARAMETER Branch
        The branch to clean. Defaults to the repository's default branch.
    .PARAMETER Configuration
        One or more explicit analysis configuration keys to remove (for example
        `.github/workflows/powershell.yml:build`). When omitted, stale
        configurations are auto-detected by checking whether each configuration's
        backing workflow file still exists on the branch.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem
        Auto-detects stale code scanning configurations on vdem's default branch
        and deletes their analyses after confirmation.
    .EXAMPLE
        PS C:\> Remove-GHStaleCodeScan -Owner PS-MCS -Repository vdem -Configuration '.github/workflows/powershell.yml:build' -WhatIf
        Shows what would be deleted for the named configuration without making
        any changes.
    .NOTES
        Status: Beta
        Comments:
        - Requires the GitHub CLI (`gh`) authenticated with a token that has
          write access to security events on the repository.
        https://docs.github.com/en/rest/code-scanning/code-scanning#delete-a-code-scanning-analysis-from-a-repository
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Organization or user that owns the repository')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Owner,

        [Parameter(Mandatory, HelpMessage = 'Repository name without the owner prefix')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Repository,

        [Parameter(HelpMessage = 'Branch to clean; defaults to the repository default branch')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Branch,

        [Parameter(HelpMessage = 'Explicit analysis configuration key(s) to remove')]
        [ValidateNotNullOrEmpty()]
        [System.String[]] $Configuration
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # RESOLVE THE TARGET BRANCH >> default to the repository default branch
        if ($PSBoundParameters.ContainsKey('Branch')) {
            $branchName = $Branch -replace '^refs/heads/', ''
        }
        else {
            $branchName = (Invoke-GHApi -Path ('repos/{0}/{1}' -f $Owner, $Repository)).default_branch
        }

        # BUILD THE FULLY-QUALIFIED REF
        $ref = 'refs/heads/{0}' -f $branchName
        Write-Verbose -Message ('Target: {0}/{1} @ {2}' -f $Owner, $Repository, $ref)

        # LIST EVERY CODE SCANNING ANALYSIS ON THE REF (ALL PAGES)
        $analyses = @(Invoke-GHApi -Path ('repos/{0}/{1}/code-scanning/analyses?ref={2}&per_page=100' -f $Owner, $Repository, $ref) -Paginate)

        if (-not $analyses) {
            Write-Warning -Message ('No code scanning analyses found on [{0}].' -f $ref)
            return
        }

        # GROUP ANALYSES BY CONFIGURATION KEY
        $byConfig = $analyses | Group-Object -Property analysis_key

        # DETERMINE WHICH CONFIGURATIONS TO REMOVE
        if ($PSBoundParameters.ContainsKey('Configuration')) {

            # EXPLICIT MODE >> only the requested keys that actually exist on the ref
            $targets = $byConfig | Where-Object { $Configuration -contains $_.Name }

            # WARN ABOUT ANY REQUESTED KEY THAT HAS NO ANALYSES ON THE REF
            foreach ($key in $Configuration) {
                if ($byConfig.Name -notcontains $key) {
                    Write-Warning -Message ('Configuration [{0}] has no analyses on [{1}]; skipping.' -f $key, $ref)
                }
            }
        }
        else {

            # AUTO-DETECT MODE >> a configuration is stale when its workflow file no longer exists on the ref
            $wfKeyRegex = '^\.github/workflows/.+\.(yml|yaml):'
            $targets = foreach ($grp in $byConfig) {

                # ONLY WORKFLOW-FILE-BASED KEYS ARE CANDIDATES >> skip default setup and other tools
                if ($grp.Name -notmatch $wfKeyRegex) { continue }

                # DERIVE THE WORKFLOW PATH >> everything before the final ':'
                $wfPath = $grp.Name.Substring(0, $grp.Name.LastIndexOf(':'))

                # STALE WHEN THE WORKFLOW FILE NO LONGER EXISTS ON THE REF (TOLERATED 404)
                $wfFile = Invoke-GHApi -Path ('repos/{0}/{1}/contents/{2}?ref={3}' -f $Owner, $Repository, $wfPath, $ref) -AllowNotFound
                if (-not $wfFile) {
                    Write-Verbose -Message ('Stale configuration detected: {0} (missing {1})' -f $grp.Name, $wfPath)
                    $grp
                }
            }
        }

        if (-not $targets) {
            Write-Information -MessageData ('No stale code scanning configurations found on [{0}].' -f $ref) -InformationAction Continue
            return
        }

        # PROCESS EACH TARGET CONFIGURATION
        foreach ($grp in $targets) {

            # ORDER THIS CONFIGURATION'S ANALYSES NEWEST-FIRST >> deletion must walk newest to oldest
            $ordered = $grp.Group | Sort-Object -Property created_at -Descending

            # BUILD ShouldProcess DESCRIPTORS
            $shouldProcessTarget = '{0}/{1} @ {2} :: {3}' -f $Owner, $Repository, $ref, $grp.Name
            $shouldProcessAction = 'Delete {0} code scanning analyses' -f $ordered.Count

            if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, $shouldProcessAction)) { continue }

            # DELETE EACH ANALYSIS >> confirm_delete=true is required to remove the final analysis in a set
            $deleted = 0
            foreach ($analysis in $ordered) {

                $deletePath = 'repos/{0}/{1}/code-scanning/analyses/{2}?confirm_delete=true' -f $Owner, $Repository, $analysis.id
                try {
                    Invoke-GHApi -Path $deletePath -Method DELETE | Out-Null
                    $deleted++
                }
                catch {
                    # ALREADY GONE >> tolerate transient re-reads and idempotent re-runs
                    if ($PSItem.Exception.Message -match '404') {
                        Write-Verbose -Message ('Analysis [{0}] already deleted.' -f $analysis.id)
                    }
                    else {
                        Write-Error -Message ('Failed to delete analysis [{0}]: {1}' -f $analysis.id, $PSItem.Exception.Message) -ErrorAction Stop
                    }
                }
            }

            # EMIT A PER-CONFIGURATION SUMMARY
            [PSCustomObject] @{
                Repository      = '{0}/{1}' -f $Owner, $Repository
                Branch          = $branchName
                Configuration   = $grp.Name
                AnalysesDeleted = $deleted
            }
        }
    }
}
