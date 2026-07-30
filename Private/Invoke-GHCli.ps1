function Invoke-GHCli {
    <#
    .SYNOPSIS
        Run a GitHub CLI ('gh') subcommand with consistent error handling.
    .DESCRIPTION
        Private helper for the module's public functions. Invokes 'gh' with the
        supplied argument list and isolates $PSNativeCommandUseErrorActionPreference
        so a value inherited from the caller (for example a workflow 'run' block
        that set it to $true) cannot turn the native call into a terminating
        error before the exit code is inspected. On a non-zero exit it throws a
        terminating error that includes the captured 'gh' output. With -AsJson
        the standard output is parsed with ConvertFrom-Json and returned as
        objects.

        This wraps 'gh' SUBCOMMANDS (for example 'repo list', 'search issues').
        REST calls should use PS.GitHub's Invoke-GhApi instead, which already
        handles silent-404, empty-204, pagination, and string[] normalization.
    .PARAMETER Argument
        The 'gh' argument list, e.g. @('repo', 'list', 'PS-MCS', '--json', 'name').
    .PARAMETER AsJson
        Parse standard output with ConvertFrom-Json and return the objects.
    .INPUTS
        None.
    .OUTPUTS
        System.String when -AsJson is omitted; otherwise the objects produced by
        ConvertFrom-Json.
    .EXAMPLE
        PS C:\> Invoke-GHCli -Argument 'repo', 'list', 'PS-MCS', '--limit', '100', '--json', 'name' -AsJson
        Returns the organization's repositories as objects.
    .EXAMPLE
        PS C:\> Invoke-GHCli -Argument 'search', 'issues', '--owner', 'PS-MCS', '--json', 'number,title' -AsJson
        Returns matching issues as objects.
    .NOTES
        Private helper; not exported. Wraps subcommands only -- use Invoke-GhApi
        (PS.GitHub) for REST calls.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The gh argument list')]
        [ValidateNotNullOrEmpty()]
        [System.String[]] $Argument,

        [Parameter(HelpMessage = 'Parse standard output as JSON and return objects')]
        [System.Management.Automation.SwitchParameter] $AsJson
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        # ISOLATE AN INHERITED NATIVE-ERROR PREFERENCE >> FLOW IS DECIDED FROM $LASTEXITCODE
        $PSNativeCommandUseErrorActionPreference = $false
    }
    Process {
        # MERGE STDERR SO A FAILURE MESSAGE IS AVAILABLE; SEPARATE THE STREAMS AFTER
        $output = & gh @Argument 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = ($output | Out-String).Trim()
            Write-Error -Message ('gh {0} failed (exit {1}): {2}' -f ($Argument -join ' '), $LASTEXITCODE, $detail) -ErrorAction Stop
        }

        # KEEP ONLY STDOUT (DROP ANY STDERR ERROR RECORDS) BEFORE RETURNING
        $stdout = @($output).Where({ $PSItem -isnot [System.Management.Automation.ErrorRecord] })
        if ($AsJson) {
            $stdout | ConvertFrom-Json
        }
        else {
            $stdout
        }
    }
}
