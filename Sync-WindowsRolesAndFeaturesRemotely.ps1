<#
    .SYNOPSIS
    Sync Window Server Roles and Features via PS Remoting

    .DESCRIPTION
    Connect to the source server, get its Roles and Features.
    Connect to the target server(s), install or remove Roles and Features
    so all the servers match the source.  All of this is accomplished
    via PS Remoting.  An optional XML output file can be created from the
    source server for later reuse. The target server pre-change configuration
    is saved to a text file in the users temp directory.  Specific features
    can be excluded during the install or removal process.  You can also run 
    a simulation to see what changes would be made or recieve the difference
    between servers.

    .RETURNS
    Array of objects for each target server.  Each object lists a role or
    feature, action performed, and the server name.

    .OUTPUTS
    An optional XML file representing the source server Roles and Features.
    A text file on each target server containing the installed Roles and Features
    prior to any changes being made. The text file location is controled by 
    variable $sTargetInstallArchiveFullPath

    .PARAMETER Source
    String: Roles and Features source server.  To connect to the local
    server use its name.  If input is a previously exported XML file.  The file
    will be used in place of a source server.  

    .PARAMETER Targets
    Array: List of servers that need install/remove to match the source server

    .PARAMETER Simulate
    Boolean: Complete a full run and report but do NOT make any changes
    
    .PARAMETER InstallExclude
    Array: Name of each Role or Feature to exclude during the install process

    .PARAMETER RemoveExclude
    Array: Name of each Role or Feature to exclude during the removal process

    .PARAMETER ExportXml
    Boolean: Export source server Roles and Features to an XML file

    .PARAMETER ExportFileName
    String: Full path with name to export file location.  This should NOT have
    the extention because the extention is automatically added by the script
    for the type of file being exported.  If you use a just a file name without
    path, the current directory is used.    

    .EXAMPLE
    Sync-WindowsRolesAndFeaturesRemotely -Source 'server1' -Targets 'comp1','comp2','etc' `
        -InstallExclude  @('AD-Certificate','ADCS-Cert-Authority') -ExportXml $true 
    Sync target servers to the source server.  Export source servers XML file with
    the default name to the current Powershell path.  Exclude the two AD Certificate
    Authority features.  Results will be returned from each target server.

    .NOTES
    This is intended to be run over PS Remoting.
    Booleans were used instead of switches so the true/false can be set for defaults
    Multiple output file types can be specified simultaneously (if I ever add them)

    Author: Donald Hess
    Version History:
        1.0    2018-06-25    Initial release
#>

param ( 
    [string] $Source = '',
    [array] $Targets = @(),
    [bool] $Simulate = $false,
    [array] $InstallExclude = @(),
    [array] $RemoveExclude = @(),
    [bool] $ExportXml = $false,
    [string] $ExportFileName = 'roles_features'  # No Extension, can be short or full path
)
Set-StrictMode -Version latest -Verbose
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction']='Stop'

if ( Test-Path $Source -PathType Leaf ) { # Import file instead of computername
    Write-Host "Importing XML file as source"
    $aSourceResults = Import-Clixml -Path $Source
    $ExportXml = $false
} else {
    $sSourceComputer = $Source
    $aSourceResults = $null
}
$aTargetComputers = $Targets
$aInstallExclude = $InstallExclude
$aRemoveExclude = $RemoveExclude

$sb1 = {
    Get-WindowsFeature | Select Name,DisplayName,Installed,InstallState,FeatureType,Path,Depth,`
        DependsOn,Parent,ServerComponentDescriptor,SubFeatures,AdditionalInfo
}
if ( $null -eq $aSourceResults ) {
    Write-Host "Getting source computer information"
    $aSourceResults = @(Invoke-Command -ThrottleLimit 1 -ScriptBlock $sb1 -ComputerName $sSourceComputer -ErrorAction Stop)
    if ( $ExportXml ) {
        Export-Clixml -InputObject $aSourceResults -Depth 500 -Path (@($ExportFileName,'.xml') -join '')
    }
}
$sb2 = {
    param( [array] $aSourceRolesAndFeatures, [array] $aInstallExclude=@(), [array] $aRemoveExclude=@(), [bool] $Simulate=$false )
    Set-StrictMode -Version latest -Verbose
    $ErrorActionPreference = 'Stop'
    $PSDefaultParameterValues['*:ErrorAction']='Stop'

    Write-Host "Starting sync on $env:COMPUTERNAME"
    # Log the existing installed roles and features
    $sTargetInstallArchiveFullPath = @($env:TEMP,'\',$env:COMPUTERNAME,'_roles_features_installed_',(Get-Date).Tostring('yyyy-MM-dd_HH_mm_ss'),'.txt') -join ''
    (Get-WindowsFeature | Where-Object {$_.Installed -eq $True}).Name > $sTargetInstallArchiveFullPath

    $aReturned = @()
    # Filter to get just installed
    $aSourceInstalled = @(($aSourceRolesAndFeatures | Where-Object {$_.Installed -eq $True}).Name)
    $bolRefreshTarget = $true
    $aSourceInstalled | ForEach-Object {
        # Need to check after each install in case subfeature was automatically installed
        if ( $bolRefreshTarget ) {
            $aTargetlInstalled = @((Get-WindowsFeature | Where-Object {$_.Installed -eq $True}).Name)
        }
        if ( ($aTargetlInstalled -notcontains $_) -and ($aInstallExclude -notcontains $_) ) {
            if ( $Simulate ) {
                $bolRefreshTarget = $false
            } else {
                Install-WindowsFeature -Name $_ | Out-Null
            }
            $oTemp = '' | Select 'Computername','Feature','Action'
            $oTemp.Feature = $_
            $oTemp.Action = 'Installed'
            $oTemp.Computername = $env:COMPUTERNAME
            $aReturned += $oTemp
        } else {
            $bolRefreshTarget = $false
        }
    }
    # Filter to get just non-installed
    $aSourceRemoved = @(($aSourceRolesAndFeatures | Where-Object {$_.Installed -eq $False}).Name)
    $bolRefreshTarget = $true
    $aSourceRemoved | ForEach-Object {
        # Need to check after each removal in case subfeature was automatically removed
        if ( $bolRefreshTarget ) {
            $aTargetlInstalled = @((Get-WindowsFeature | Where-Object {$_.Installed -eq $True}).Name)
        }
        if ( ($aTargetlInstalled -contains $_) -and ($aRemoveExclude -notcontains $_) ) {
            if ( $Simulate ) {
                $bolRefreshTarget = $false
            } else {
                Remove-WindowsFeature -Name $_ | Out-Null
            }
            $oTemp = '' | Select 'Computername','Feature','Action'
            $oTemp.Feature = $_
            $oTemp.Action = 'Removed'
            $oTemp.Computername = $env:COMPUTERNAME
            $aReturned += $oTemp
        } else {
            $bolRefreshTarget = $false
        }
    }
    return ,$aReturned
}
@(Invoke-Command -ThrottleLimit 5 -ScriptBlock $sb2 -ComputerName $aTargetComputers -ArgumentList $aSourceResults,$aInstallExclude,$aRemoveExclude,$Simulate -ErrorAction Continue)

