##########################################################################################################
### This script reads the EDID information stored in the registry for the currently connected monitors ###
### and stores their most important pieces of identification (Name, Size, Serial Number etc) in WMI    ###
### for later retrieval by SCCM                                                                        ###
##########################################################################################################

# This script creates new CIM class MonitorDitails in root\cimv2 to store information about monitors attached to a device.

# Attention:
# If CIM Class properties need to be extended or changed then expectedProperties hashtable
# in Compare-CimClassProperties function should be changed accordingly

# Manufacturers codes and their corresponding names
$ManufacturersHash = @{ 
    "AAC" =	"AcerView"
    "ACR" = "Acer"
    "ADR" = "Acer"
    "AOC" = "AOC"
    "AIC" = "AG Neovo"
    "APP" = "Apple Computer"
    "AST" = "AST Research"
    "AUO" = "Asus"
    "AVS" = "Asus"
    "BNQ" = "BenQ"
    "CMO" = "Acer"
    "CMN" = "Chimei Innolux Corporation"
    "CPL" = "Compal Electronics Inc"
    "CPQ" = "Compaq"
    "CPT" = "Chunghwa Pciture Tubes, Ltd.";
    "CTX" = "CTX";
    "DEC" = "DEC";
    "DEL" = "Dell";
    "DPC" = "Delta";
    "DWE" = "Daewoo";
    "EIZ" = "EIZO";
    "ELS" = "ELSA";
    "ENC" = "EIZO";
    "EPI" = "Envision";
    "FCM" = "Funai";
    "FUJ" = "Fujitsu";
    "FUS" = "Fujitsu-Siemens";
    "GSM" = "LG Electronics";
    "GWY" = "Gateway 2000";
    "HEI" = "Hyundai";
    "HIT" = "Hyundai";
    "HSL" = "Hansol";
    "HTC" = "Hitachi/Nissei";
    "HWP" = "HP";
    "HXP" = "HP";
    "IBM" = "IBM";
    "ICL" = "Fujitsu ICL";
    "IVM" = "Iiyama";
    "KDS" = "Korea Data Systems";
    "LEN" = "Lenovo";
    "LGD" = "Asus";
    "LPL" = "Fujitsu";
    "MAX" = "Belinea"; 
    "MEI" = "Panasonic";
    "MEL" = "Mitsubishi Electronics";
    "MS_" = "Panasonic";
    "NAN" = "Nanao";
    "NEC" = "NEC";
    "NOK" = "Nokia Data";
    "NVD" = "Fujitsu";
    "OPT" = "Optoma";
    "PHL" = "Philips";
    "REL" = "Relisys";
    "SAN" = "Samsung";
    "SAM" = "Samsung";
    "SBI" = "Smarttech";
    "SGI" = "SGI";
    "SNY" = "Sony";
    "SRC" = "Shamrock";
    "SUN" = "Sun Microsystems";
    "SEC" = "Hewlett-Packard";
    "TAT" = "Tatung";
    "TOS" = "Toshiba";
    "TSB" = "Toshiba";
    "VSC" = "ViewSonic";
    "ZCM" = "Zenith";
    "UNK" = "Unknown";
    "_YV" = "Fujitsu";
}

#region --- Private functions

# This function reads the 4 bytes following $index from $array then returns them as an integer interpreted in little endian
function Get-LittleEndianInt($array, $index) {
    # Create a new temporary array to reverse the endianness in
    $temp = @(0) * 4
    #.Net Array Copy method Signature (Array sourceArray, long sourceIndex, Array destinationArray, long destinationIndex, long length)
    [Array]::Copy($array, $index, $temp, 0, 4)
    [Array]::Reverse($temp)
    # Then convert the byte data to an integer
    [System.BitConverter]::ToInt32($temp, 0)
}
function Get-GreatestCommonDivisor {
    param (
        [int]$a,
        [int]$b
    )
    while ($b -ne 0) {
        $temp = $b
        $b = $a % $b
        $a = $temp
    }
    return $a
}

# Function to check if WMI class properties match the expected schema
function Compare-CimClassProperties {
    param (
        [string]$ClassName = "MonitorDetails"
    )
    
    try {
        # Get the existing class
        $existingClass = New-Object System.Management.ManagementClass("root\cimv2", $ClassName, $null)
        
        # Define the expected properties and their types
        $expectedProperties = @{
            "DeviceID"          = [System.Management.CimType]::String
            "Name"              = [System.Management.CimType]::String
            "ManufacturerCode"  = [System.Management.CimType]::String
            "Manufacturer"      = [System.Management.CimType]::String
            "Model"             = [System.Management.CimType]::String
            "SerialNumber"      = [System.Management.CimType]::String
            "EdidString"        = [System.Management.CimType]::String
            "HorizontalSize"    = [System.Management.CimType]::UInt32
            "VerticalSize"      = [System.Management.CimType]::UInt32
            "DiagonalSize"      = [System.Management.CimType]::UInt32
            "MaxHorizontalRes"  = [System.Management.CimType]::UInt32
            "MaxVerticalRes"    = [System.Management.CimType]::UInt32
            "AspectRatio"       = [System.Management.CimType]::String
            "ManufacturingYear" = [System.Management.CimType]::UInt32
            "ManufacturingWeek" = [System.Management.CimType]::UInt32
            "LastSeenDate"      = [System.Management.CimType]::DateTime
        }
        
        # Check if all expected properties exist with correct types
        foreach ($propName in $expectedProperties.Keys) {
            if (-not $existingClass.Properties[$propName] -or 
                $existingClass.Properties[$propName].Type -ne $expectedProperties[$propName]) {
                Write-Verbose "Property mismatch found: $propName"
                return $false
            }
        }
        
        # Check if there are any extra properties in the existing class
        foreach ($prop in $existingClass.Properties) {
            if ($prop.Name -ne "__CLASS" -and $prop.Name -ne "__GENUS" -and 
                $prop.Name -ne "__SUPERCLASS" -and $prop.Name -ne "__DYNASTY" -and 
                $prop.Name -ne "__RELPATH" -and $prop.Name -ne "__PROPERTY_COUNT" -and 
                $prop.Name -ne "__DERIVATION" -and $prop.Name -ne "__SERVER" -and 
                $prop.Name -ne "__NAMESPACE" -and $prop.Name -ne "__PATH" -and 
                -not $expectedProperties.ContainsKey($prop.Name)) {
                Write-Verbose "Extra property found: $($prop.Name)"
                return $false
            }
        }
        
        # Check key property
        if (-not $existingClass.Properties["DeviceID"].Qualifiers["key"]) {
            Write-Verbose "DeviceID is not marked as a key property"
            return $false
        }
        
        # All checks passed
        return $true
    }
    catch {
        # Class doesn't exist or other error
        Write-Verbose "Error comparing WMI class: $_"
        return $false
    }
}

# Removes CIM Class MonitorDetails
function Remove-CIMClass_MonitorDetails {
    try {
        # Check if class exists
        $classExists = (Get-CimClass MonitorDetails -ErrorAction SilentlyContinue) -as [bool]
        
        if ($classExists) {
            # Compare properties with expected schema
            $propertiesMatch = Compare-CimClassProperties -ClassName "MonitorDetails"
            
            if (-not $propertiesMatch) {
                Write-Verbose "CIM class properties don't match expected schema. Removing class."
                $MonitorDetailsCIMClass = New-Object System.Management.ManagementClass("root\cimv2", "MonitorDetails", $null)
                $MonitorDetailsCIMClass.Delete()
                return $true
            }
            else {
                Write-Verbose "CIM class properties match expected schema. Keeping class."
                return $false
            }
        }
        return $false
    }
    catch {
        Write-Error "Error in Remove-CIMClass_MonitorDetails: $_"
        return $false
    }
}

# Creates a new CIM class to store data
function Register-CIMClass_MonitorDetails {
    $newClass = New-Object System.Management.ManagementClass("root\cimv2", [String]::Empty, $null)
    $newClass["__CLASS"] = "MonitorDetails"
    $newClass.Qualifiers.Add("Static", $true)
    # DeviceID Property (key)
    $newClass.Properties.Add("DeviceID", [System.Management.CimType]::String, $false)
    $newClass.Properties["DeviceID"].Qualifiers.Add("key", $true)
    $newClass.Properties["DeviceID"].Qualifiers.Add("read", $true)
    $newClass.Properties["DeviceID"].Qualifiers.Add("write", $true)
    # Name Property
    $newClass.Properties.Add("Name", [System.Management.CimType]::String, $false)
    $newClass.Properties["Name"].Qualifiers.Add("read", $true)
    $newClass.Properties["Name"].Qualifiers.Add("write", $true)
    # ManufacturerCode Property
    $newClass.Properties.Add("ManufacturerCode", [System.Management.CimType]::String, $false)
    $newClass.Properties["ManufacturerCode"].Qualifiers.Add("read", $true)
    $newClass.Properties["ManufacturerCode"].Qualifiers.Add("write", $true)
    # Manufacturer Property
    $newClass.Properties.Add("Manufacturer", [System.Management.CimType]::String, $false)
    $newClass.Properties["Manufacturer"].Qualifiers.Add("read", $true)
    $newClass.Properties["Manufacturer"].Qualifiers.Add("write", $true)
    # Model Property
    $newClass.Properties.Add("Model", [System.Management.CimType]::String, $false)
    $newClass.Properties["Model"].Qualifiers.Add("read", $true)
    $newClass.Properties["Model"].Qualifiers.Add("write", $true)
    # SerialNumber Property
    $newClass.Properties.Add("SerialNumber", [System.Management.CimType]::String, $false)
    $newClass.Properties["SerialNumber"].Qualifiers.Add("read", $true)
    $newClass.Properties["SerialNumber"].Qualifiers.Add("write", $true)
    # EdidString Property
    $newClass.Properties.Add("EdidString", [System.Management.CimType]::String, $false)
    $newClass.Properties["EdidString"].Qualifiers.Add("read", $true)
    $newClass.Properties["EdidString"].Qualifiers.Add("write", $true)
    # HorizontalSize Property
    $newClass.Properties.Add("HorizontalSize", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["HorizontalSize"].Qualifiers.Add("read", $true)
    $newClass.Properties["HorizontalSize"].Qualifiers.Add("write", $true)
    # VerticalSize Property
    $newClass.Properties.Add("VerticalSize", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["VerticalSize"].Qualifiers.Add("read", $true)
    $newClass.Properties["VerticalSize"].Qualifiers.Add("write", $true)
    # DiagonalSize Property
    $newClass.Properties.Add("DiagonalSize", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["DiagonalSize"].Qualifiers.Add("read", $true)
    $newClass.Properties["DiagonalSize"].Qualifiers.Add("write", $true)
    $newClass.Properties["DiagonalSize"].Qualifiers.Add("Description", "Diagonal size of the monitor in inches")
    # MaxHorizontalRes Property
    $newClass.Properties.Add("MaxHorizontalRes", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["MaxHorizontalRes"].Qualifiers.Add("read", $true)
    $newClass.Properties["MaxHorizontalRes"].Qualifiers.Add("write", $true)
    # MaxVerticalRes Property
    $newClass.Properties.Add("MaxVerticalRes", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["MaxVerticalRes"].Qualifiers.Add("read", $true)
    $newClass.Properties["MaxVerticalRes"].Qualifiers.Add("write", $true)
    # AspectRatio Property
    $newClass.Properties.Add("AspectRatio", [System.Management.CimType]::String, $false)
    $newClass.Properties["AspectRatio"].Qualifiers.Add("read", $true)
    $newClass.Properties["AspectRatio"].Qualifiers.Add("write", $true)
    $newClass.Properties["AspectRatio"].Qualifiers.Add("Description", "Aspect Ratio of the monitor e.g. 4:3 or 1:1")
    # ManufacturingYear Property
    $newClass.Properties.Add("ManufacturingYear", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["ManufacturingYear"].Qualifiers.Add("read", $true)
    $newClass.Properties["ManufacturingYear"].Qualifiers.Add("write", $true)
    # ManufacturingWeek Property
    $newClass.Properties.Add("ManufacturingWeek", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["ManufacturingWeek"].Qualifiers.Add("read", $true)
    $newClass.Properties["ManufacturingWeek"].Qualifiers.Add("write", $true)
    # LastSeenDate Property
    $newClass.Properties.Add("LastSeenDate", [System.Management.CimType]::DateTime, $false)
    $newClass.Properties["LastSeenDate"].Qualifiers.Add("read", $true)
    $newClass.Properties["LastSeenDate"].Qualifiers.Add("write", $true)
    # Update CIM Class
    $newClass.Put() | Out-Null
}

#endregion --- Private functions

##########################################################################################################
### Main script                                                                                        ###
##########################################################################################################

# Remove CIM Class MonitorDetails only if properties differ
$classRemoved = Remove-CIMClass_MonitorDetails
$classExists = [bool] (Get-CimInstance -ClassName MonitorDetails -Namespace root\cimv2 -ErrorAction SilentlyContinue)
# Only create the class if it was removed or doesn't exist
if ($classRemoved -or -not $classExists) {
    try {
        # Create CIM Class
        Register-CIMClass_MonitorDetails
        Write-Verbose "CIM class created successfully"
    }
    catch {
        # Throw Error if CIM class can not be created
        Write-Error "Could not create CIM class: $_"
        throw "CIM class creation failed."
    }
}

# Variable for storing monitor data in array
$MonitorsInfo = @()
$Monitors = Get-CimInstance -ClassName Win32_PnPEntity -Namespace root\cimv2 -Filter "Service='monitor'"
# Processing detected monitors
foreach ($Monitor in $Monitors) {
    $CurrentMonitorInfo = @{
        DeviceID = $Monitor.DeviceID
        Name     = $Monitor.Name
    }
    # Then look up its data in the registry
    $RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $Monitor.DeviceID + "\Device Parameters"
    $EdidString = (Get-ItemProperty -Path $RegistryPath -Name EDID -ErrorAction SilentlyContinue).EDID
    $CurrentMonitorInfo.EdidString = $EdidString -join " "

    # Some monitors, especially those attached to VMs either don't have a Device Parameters key or an EDID value. Skipping these.
    if ($null -ne $EdidString) {
        # Collect the information from the EDID array in a hashtable
        $CurrentMonitorInfo.ManufacturerCode += [char](
            64 + [Int32][math]::floor(($EdidString[8] / 4))
        )
        $CurrentMonitorInfo.ManufacturerCode += [char](
            64 + [Int32][math]::floor(($EdidString[8] % 4) * 8 + [Int32]($EdidString[9] / 32))
        )
        $CurrentMonitorInfo.ManufacturerCode += [char](
            64 + [Int32][math]::floor(($EdidString[9] % 32))
        )
        $ManufacturerName = $ManufacturersHash.$($CurrentMonitorInfo.ManufacturerCode)
        If ($null -eq $ManufacturerName) {
            $ManufacturerName = $CurrentMonitorInfo.ManufacturerCode
            $CurrentMonitorInfo.Manufacturer = $CurrentMonitorInfo.ManufacturerCode
        }
        else {
            $CurrentMonitorInfo.Manufacturer = $ManufacturerName
        }
        $CurrentMonitorInfo.ManufacturingWeek = $EdidString[16]
        $CurrentMonitorInfo.ManufacturingYear = $EdidString[17] + 1990
        $CurrentMonitorInfo.HorizontalSize = $EdidString[21]
        $CurrentMonitorInfo.VerticalSize = $EdidString[22]
        $CurrentMonitorInfo.DiagonalSize = [Math]::Round(
            [Math]::Sqrt(
                $CurrentMonitorInfo.HorizontalSize * $CurrentMonitorInfo.HorizontalSize + `
                    $CurrentMonitorInfo.VerticalSize * $CurrentMonitorInfo.VerticalSize
            ) / 2.54
        )
        $CurrentMonitorInfo.LastSeenDate = Get-Date
        
        # Getting maximum available resolution
        $MaximumAvailableResolution = Get-CimInstance -ClassName CIM_VideoControllerResolution -Namespace root\cimv2 | `
            Select-Object HorizontalResolution, VerticalResolution | `
            Sort-Object -Property HorizontalResolution, VerticalResolution | `
            Select-Object -Last 1
        $CurrentMonitorInfo.MaxHorizontalRes = $MaximumAvailableResolution.HorizontalResolution
        $CurrentMonitorInfo.MaxVerticalRes = $MaximumAvailableResolution.VerticalResolution

        # Calculating AspectRatio
        if ($CurrentMonitorInfo.HorizontalSize -gt 0 -and $CurrentMonitorInfo.VerticalSize -gt 0) {
            $gcd = Get-GreatestCommonDivisor -a $CurrentMonitorInfo.MaxHorizontalRes -b $CurrentMonitorInfo.MaxVerticalRes
            $aspectRatioHorizontal = $CurrentMonitorInfo.MaxHorizontalRes / $gcd
            $aspectRatioVertical = $CurrentMonitorInfo.MaxVerticalRes / $gcd
            $aspectRatio = "$($aspectRatioHorizontal):$($aspectRatioVertical)"
            $CurrentMonitorInfo.AspectRatio = $aspectRatio
        }

        # Walk through the four descriptor fields
        for ($i = 54; $i -lt 109; $i += 18) {
            # Check if one of the descriptor fields is either the serial number or the monitor name
            # If yes, extract the 13 bytes that contain the text and append them into a string
            if ((Get-LittleEndianInt $EdidString $i) -eq 0xff) {
                for ($j = $i + 5; $EdidString[$j] -ne 10 -and $j -lt $i + 18; $j++) { $CurrentMonitorInfo.SerialNumber += [char]$EdidString[$j] }
            }
            if ((Get-LittleEndianInt $EdidString $i) -eq 0xfc) {
                for ($j = $i + 5; $EdidString[$j] -ne 10 -and $j -lt $i + 18; $j++) { $CurrentMonitorInfo.Name += [char]$EdidString[$j] }
            }
        }
        
        # Match serialNumber with known monitor models
        switch -Wildcard ($CurrentMonitorInfo.SerialNumber) {
            '115648*' { $CurrentMonitorInfo.Model = 'ProLite XB2483HSU' }
            '11565*' { $CurrentMonitorInfo.Model = 'ProLite X2483HSU' }
            '4YMDT8*' { $CurrentMonitorInfo.Model = 'DELL E2318H' }
            'KKMMW63C*' { $CurrentMonitorInfo.Model = 'DELL P2414H' }
            'AU12227*' { $CurrentMonitorInfo.Model = 'Philips 240B7QPTEB' }
            '117862*' { $CurrentMonitorInfo.Model = 'ProLite XUB2492HSN' }
            '11510*' { $CurrentMonitorInfo.Model = 'ProLite XU2492HSU' }
            '11750*' { $CurrentMonitorInfo.Model = 'ProLite XUB2493HSU' }
            '11878*' { $CurrentMonitorInfo.Model = 'ProLite XUB2493HS' }
            '12081*' { $CurrentMonitorInfo.Model = 'ProLite XU2494HSU' }
            '116511*' { $CurrentMonitorInfo.Model = 'ProLite GB2730HSU' }
            '11663*' { $CurrentMonitorInfo.Model = 'ProLite XUB2792HSU' }
            '116691*' { $CurrentMonitorInfo.Model = 'ProLite XB2474HS' }
            '11551*' { $CurrentMonitorInfo.Model = 'ProLite XB3270QS' }
            '121143*' { $CurrentMonitorInfo.Model = 'ProLite XUB2493HS' }
            default { $CurrentMonitorInfo.Model = '' }
        }

        # If the horizontal size of this monitor is zero, it's a purely virtual one (i.e. RDP only) and shouldn't be stored
        # Also excluding monitors with name "Integrated Monitor" and "Generic PnP Monitor"
        if ($CurrentMonitorInfo.HorizontalSize -ne 0 -and $CurrentMonitorInfo.Name -ne "Integrated Monitor" -and $CurrentMonitorInfo.Name -ne "Generic PnP Monitor") {
            $MonitorsInfo += $CurrentMonitorInfo
        }
    }
}

# Show Objects that will be registered (debug)
$ParametersOrder = "DeviceID", "Name", "ManufacturerCode", "Manufacturer", "Model", "SerialNumber", "EdidString", "HorizontalSize", "VerticalSize", "DiagonalSize", "MaxHorizontalRes", "MaxVerticalRes", "AspectRatio", "ManufacturingYear", "ManufacturingWeek", "LastSeenDate"
Write-Verbose "Objects that will be registered:"
foreach ($hashtable in $MonitorInfo) { foreach ($key in $ParametersOrder) { if ($hashtable.ContainsKey($key)) { Write-Output "$key = $($hashtable[$key])" } } }

# Store gathered data in CIM class MonitorDetails
foreach ($MonitorInfo in $MonitorsInfo) {
    # Create a hashtable of properties for the CIM instance
    $cimProperties = @{
        DeviceID          = [string]$MonitorInfo.DeviceID
        Name              = [string]$MonitorInfo.Name
        ManufacturerCode  = [string]$MonitorInfo.ManufacturerCode
        Manufacturer      = [string]$MonitorInfo.Manufacturer
        Model             = [string]$MonitorInfo.Model
        SerialNumber      = [string]$MonitorInfo.SerialNumber
        EdidString        = [string]$MonitorInfo.EdidString
        HorizontalSize    = [uint32]$MonitorInfo.HorizontalSize
        VerticalSize      = [uint32]$MonitorInfo.VerticalSize
        DiagonalSize      = [uint32]$MonitorInfo.DiagonalSize
        MaxHorizontalRes  = [uint32]$MonitorInfo.MaxHorizontalRes
        MaxVerticalRes    = [uint32]$MonitorInfo.MaxVerticalRes
        AspectRatio       = [string]$MonitorInfo.AspectRatio
        ManufacturingYear = [uint32]$MonitorInfo.ManufacturingYear
        ManufacturingWeek = [uint32]$MonitorInfo.ManufacturingWeek
        LastSeenDate      = [datetime]$MonitorInfo.LastSeenDate
    }
    
    # Check if an instance with this DeviceID already exists
    $DeviceIdFilter = "DeviceID='$($MonitorInfo.DeviceID)'".Replace("\", "\\")
    $existingInstance = Get-CimInstance -Namespace "root/cimv2" -ClassName "MonitorDetails" -Filter $DeviceIdFilter -ErrorAction SilentlyContinue
    
    if ($existingInstance) {
        # Update existing instance
        $existingInstance | Set-CimInstance -Property $cimProperties -ErrorAction Stop
    }
    else {
        # Create new instance
        try {
            New-CimInstance -Namespace "root/cimv2" -ClassName "MonitorDetails" -Property $cimProperties -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Error "Could not create CIM instance of a class: $_"
            $cimProperties
            throw "CIM class creation failed."
        }
    }
}

# Show Registered Objects
Write-Verbose "Registered Objects:"
Get-CimInstance -ClassName MonitorDetails -Namespace "root\cimv2" | Select-Object -Property $ParametersOrder