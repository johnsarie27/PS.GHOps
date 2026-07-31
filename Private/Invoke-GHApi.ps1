function Invoke-GHApi {
    <#
    .SYNOPSIS
        Run a GitHub REST call via 'gh api' with consistent error handling.
    .DESCRIPTION
        Private helper for the module's public functions and the REST
        counterpart to Invoke-GHCli. Invokes 'gh api <Path>' and isolates
        $PSNativeCommandUseErrorActionPreference so a value inherited from the
        caller cannot turn the native call into a terminating error before the
        exit code is inspected. Returns the response parsed with
        ConvertFrom-Json.

        -AllowNotFound converts an HTTP 404 into $null (rather than throwing),
        for existence checks. -Paginate follows all pages via 'gh api --paginate
        --slurp' and flattens them into a single object stream. -Field supplies
        a request body for write methods (POST/PATCH/PUT) as one 'gh api -f
        key=value' pair per entry, which gh serializes to a JSON body.

        Keeping this helper local means PS.GHOps depends only on the 'gh' CLI,
        not on another PowerShell module. See docs/adr/0002.
    .PARAMETER Path
        The REST path, e.g. 'repos/PS-MCS/gh-org/branches?per_page=100'.
    .PARAMETER Method
        HTTP method. Defaults to 'GET'.
    .PARAMETER Field
        Request-body fields for a write method, as a hashtable. Each entry is
        passed as 'gh api -f <key>=<value>'; gh serializes them to a JSON body.
    .PARAMETER AllowNotFound
        Return $null on an HTTP 404 instead of throwing.
    .PARAMETER Paginate
        Follow all pages and flatten the results into one object stream.
    .INPUTS
        None.
    .OUTPUTS
        The object(s) produced by ConvertFrom-Json, or $null on a tolerated 404.
    .EXAMPLE
        PS C:\> Invoke-GHApi -Path 'repos/PS-MCS/gh-org/contents/.github/CODEOWNERS' -AllowNotFound
        Returns the file object, or $null if the file does not exist.
    .EXAMPLE
        PS C:\> (Invoke-GHApi -Path 'repos/PS-MCS/gh-org/branches?per_page=100' -Paginate).name
        Returns every branch name across all pages.
    .EXAMPLE
        PS C:\> Invoke-GHApi -Path 'repos/PS-MCS/gh-org/labels' -Method POST -Field @{ name = 'security'; color = 'd73a4a' }
        Creates a label from a JSON request body.
    .NOTES
        Private helper; not exported. REST counterpart to Invoke-GHCli.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The gh api REST path')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Path,

        [Parameter(HelpMessage = 'HTTP method')]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [System.String] $Method = 'GET',

        [Parameter(HelpMessage = 'Request-body fields for a write method, as a hashtable')]
        [ValidateNotNull()]
        [System.Collections.Hashtable] $Field,

        [Parameter(HelpMessage = 'Return $null on an HTTP 404 instead of throwing')]
        [System.Management.Automation.SwitchParameter] $AllowNotFound,

        [Parameter(HelpMessage = 'Follow all pages and flatten the results')]
        [System.Management.Automation.SwitchParameter] $Paginate
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        # ISOLATE AN INHERITED NATIVE-ERROR PREFERENCE >> FLOW IS DECIDED FROM $LASTEXITCODE
        $PSNativeCommandUseErrorActionPreference = $false
    }
    Process {
        $arguments = [System.Collections.Generic.List[System.String]]::new()
        $arguments.AddRange([System.String[]] @('api', $Path))
        if ($Method -ne 'GET') { $arguments.AddRange([System.String[]] @('--method', $Method)) }
        # REQUEST BODY >> ONE -f key=value PER FIELD; gh SERIALIZES TO JSON
        foreach ($key in $Field.Keys) {
            $arguments.AddRange([System.String[]] @('-f', ('{0}={1}' -f $key, $Field[$key])))
        }
        # --slurp COLLECTS PAGES AS AN ARRAY-OF-PAGES; FLATTENED BELOW
        if ($Paginate) { $arguments.AddRange([System.String[]] @('--paginate', '--slurp')) }

        $output = & gh @arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = ($output | Out-String).Trim()
            if ($AllowNotFound -and $detail -match '404|Not Found') { return }
            Write-Error -Message ('gh api {0} failed (exit {1}): {2}' -f $Path, $LASTEXITCODE, $detail) -ErrorAction Stop
        }

        # KEEP ONLY STDOUT (DROP ANY STDERR RECORDS), THEN PARSE
        $stdout = @($output).Where({ $PSItem -isnot [System.Management.Automation.ErrorRecord] })
        if (-not $stdout) { return }
        $parsed = ($stdout -join "`n") | ConvertFrom-Json

        if ($Paginate) {
            # FLATTEN ARRAY-OF-PAGES INTO A SINGLE OBJECT STREAM
            foreach ($page in $parsed) {
                foreach ($item in $page) { $item }
            }
        }
        else {
            $parsed
        }
    }
}
