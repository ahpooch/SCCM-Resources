<#
    Provide Wi-Fi profile after this comment block:
    e.g.:
    [xml]$wfProfile = @'
    __Content of Wi-Fi Profile file previously exported__
    '@

    Or you could provide array of profiles:
    $wfProfiles = @()
    $wfProfiles += [xml]@'
    __Content of Wi-Fi Profile1 file previously exported__
    @'
    $wfProfiles += [xml]@'
    __Content of Wi-Fi Profile2 file previously exported__
    @'
#>

[xml]$wfProfile = @'
'@

function Test-WifiProfile_ConfigItem {
    <#
    .SYNOPSIS
    Helper function for deploying Wi-Fi Profiles using SCCM Baselines.
    
    .DESCRIPTION
    This function is meant for deploying Wi-Fi Profiles using SCCM Baselines.
    The function itself should be in Discovery and Remediation Script.
    Optionaly you could only use Discovery script and always remediate profile at discovery.
    
    .NOTES
    Author: ahpooch
    Created: 01.07.2025
    Updated: 17.07.2025

    .PARAMETER Profile
    Mandatory parameter for providing previously exmported profile in form of [xml]$wfProfile.

    .PARAMETER Interface
    Optional parameter if targeted inteface name not like "wireless*".

    .PARAMETER Scope
    Optional parameter for selecting desired scope for profile.
    Could be 'all' (for all users) or 'current' (for current user only).
    Default is 'all'.

    .PARAMETER Remediate
    Switch to run Remediation mode. Without it function run in Discovery mode and returns Boolean,
    which reperesent compliance with provided profiles or profiles array.

    .INPUTS
    Exported previously Wi-Fi profile casted to [xml] type. Or aray [xml[]]

    .OUTPUTS
    If -Remediate swith is not provided than $true if compliant,
    $false if not compliant with provided profiles.
    If -Remediate swith is provided than no output provided.

    .EXAMPLE
    To deploy a Wi-Fi profile across devices, manually create the profile on one device and export it to a file.
    Use the following commands to export created profile:
    
    ```Powershell
    $Interface = Get-NetAdapter | Where-Object -FilterScript { $_.InterfaceName -like "wireless*"} | Select-Object -First 1
    $ProfileName = "<YOUR PROFILE NAME>"
    $ExportFolder = "C:\Temp\"
    netsh wlan export profile $ProfileName key-clear interface="$($Interface.Name)" folder="$ExportFolder\"
    ```

    Then provide profile at the begining of Discovery/Remediation scripts as [xml]$wfProfile of [xml[]]$wfProfiles.
    After profiles declaration, Test-WifiProfile_ConfigItem function should be declared (pasted) in scripts.
    At the end of Discovery/Remediation scripts use appropriate call to Test-WifiProfile_ConfigItem function,
    providing profile (using -wfProfile parameter) or array of profiles (using pipeline input).
    Examples of calls provided at the end of file.
    #>

    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline )]
        [System.Xml.XmlDocument]$wfProfile,
        [Parameter(Mandatory = $false)]
        [string]$Interface,
        [Parameter(Mandatory = $false)]
        [ValidateSet('all', 'current')]
        [string]$Scope = "all",
        [switch]$Remediate
    )
    
    Begin {
        <#
        .SYNOPSIS
        Internal function Get-InstalledProfiles returns xml files with profiles installed for specified Network Adapter Interface.
        #>
        function Get-InstalledProfiles {
            param (
                [string]$Interface
            )
            $NetAdapter = Get-NetAdapter -Name $Interface
            $InterfaceGUID = $NetAdapter.interfaceGUID
            $InterfacePath = Join-Path -Path $env:ProgramData -ChildPath "Microsoft\Wlansvc\Profiles\Interfaces\$InterfaceGUID"
            $wfProfilesInstalled = Get-ChildItem -Path $InterfacePath -Filter "*.xml" -Recurse
            return $wfProfilesInstalled
        }

        <#
        .SYNOPSIS
        Internal function Get-ProfileXML returns target profile in XML format from array of installed profiles, based on specified SSID Hex.
        #>
        function Get-ProfileXML {
            param (
                [object[]]$wfProfiles,
                [string]$SSIDHex
            )
            foreach ($wfProfile in $wfProfiles) {
                [xml]$wfProfileXML = Get-Content -Path $wfProfile.fullname
                if ($wfProfileXML.WLANProfile.SSIDConfig.SSID.hex -eq $SSIDHex) {
                    return $wfProfileXML
                }
            }
        }

        # Array to store paths of temporary files, if created during remediation.
        $TemporaryFiles = @()

        # Boolean with compliance result that should be return.
        $Compliance = $true

        Write-Debug "Source Profile Name: $($wfProfile.WLANProfile.name)"
        Write-Debug "Source SSIDName: $($wfProfile.WLANProfile.SSIDConfig.SSID.name)"
    }
    
    Process {
        # Define SSID Hex from provided profile.
        $SSIDHex = $wfProfile.WLANProfile.SSIDConfig.SSID.hex

        # Define Wireless Interface name if not provided.
        if (-not $InterfaceName) {
            Write-Debug "No InterfaceName Provided. Using Interface with name like `"wireless*`""
            $NetAdapter = Get-NetAdapter | Where-Object -FilterScript { $_.InterfaceName -like "wireless*" } | Select-Object -First 1
            $Interface = $NetAdapter.Name
        }

        # Get target profile using SSID Hex from provided source profile.
        $InstalledProfiles = Get-InstalledProfiles -Interface $Interface
        if ($InstalledProfiles) {
            $TargetProfile = Get-ProfileXML -wfProfiles $InstalledProfiles -SSIDHex $SSIDHex
        }
    
        # If remediation is not needed then only setting Boolean compliance status. It will be returned at the end.
        # Removing non-compliant profile if remediation will follow.
        if ($null -ne $TargetProfile) {
            # Exporting unencrypted profile to be able to compare passwords in plaintext. We can chose only folder to export, not the name.
            $Command = "netsh wlan export profile name=`"$($TargetProfile.WLANProfile.name)`" folder=`"$($env:TEMP)`" key=clear"
            Invoke-Expression -Command $Command | Out-Null
            # Store temporary file path for removing after import.
            $UnencryptedTargetProfile = Join-Path -Path $env:TEMP -ChildPath "$Interface-$($TargetProfile.WLANProfile.name).xml"
            [xml]$UnencryptedTargetProfile_XML = Get-Content -Path $UnencryptedTargetProfile
            # Removing unencrypted target profile
            Remove-Item -Path $UnencryptedTargetProfile
            # Comparing provided profile with target profile.
            $SourceProfileComparable = $wfProfile.OuterXml
            $TargetProfileCompareble = $UnencryptedTargetProfile_XML.OuterXml
            $Compliant = $null -eq (Compare-Object -ReferenceObject $SourceProfileComparable -DifferenceObject $TargetProfileCompareble)
            if ($Compliant) {
                return
            }
            else {
                if (-not $Remediate) {
                    $Compliance = $false
                    return
                }
                else {
                    # Removing target profile if not in a compliant state.
                    $Command = "netsh wlan delete profile $($TargetProfile.WLANProfile.name)"
                    Invoke-Expression -Command $Command | Out-Null
                }
            }
        }
        else {
            if (-not $Remediate) {
                $Compliance = $false
                return
            }
        }

        # Creating new GUID for temporary profile file that will be imported.
        $Guid = New-Guid
        # Creating path of temporary profile for importing.
        $TempFile = Join-Path -Path $env:TEMP -ChildPath "$Guid.xml"
        # Store temporary file path for removing after import.
        $TemporaryFiles += $TempFile
        # Setting content of termporary profile path.
        Set-Content -Path $TempFile -Value $wfProfile.OuterXml
    
        # Importing profile from temporary file.
        $Command = "netsh wlan add profile filename=`"$TempFile`" interface=`"$Interface`" user=$Scope"
        Invoke-Expression -Command $Command | Out-Null
    }

    End {
        # Removing temporary profile file.
        foreach ($TemporaryFile in $TemporaryFiles) {
            Remove-Item -Path $TemporaryFile
        }
        if (-not $Remediate) {
            return $Compliance
        }
    }
}

# Uncomment appropriate Test-WifiProfile_ConfigItem command line based on your needs:
#
#    For Discovery:
#
#        If one profile provided:
# Test-WifiProfile_ConfigItem -wfProfile $wfProfile
#
#        If array of profiles provided:
# $wfProfiles | Test-WifiProfile_ConfigItem
#
#
#    For Remediation: 
#
#        If one profile provided: 
# Test-WifiProfile_ConfigItem -wfProfile $wfProfile -Remediate
#
#        If array of profiles provided:
# $wfProfiles | Test-WifiProfile_ConfigItem -Remediate
