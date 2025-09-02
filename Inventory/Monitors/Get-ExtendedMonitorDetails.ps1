##########################################################################################################
### This script reads the EDID information stored in the registry for the currently connected monitors ###
### and stores their most important pieces of identification (Name, Size, Serial Number etc) in WMI    ###
### for later retrieval by SCCM                                                                        ###
##########################################################################################################

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

# Removes wmi class MonitorDetails
# TODO: Remove WMI Class MonitorDetails only when properties of class differs from existing wmi class on computer.
function Remove-WMIClass_MonitorDetails {
    $MonitorDetailsWmiClass = New-Object System.Management.ManagementClass("root\cimv2","MonitorDetails",$null)
    if ($MonitorDetailsWmiClass) {
        $MonitorDetailsWmiClass.Delete()
    }
}

# Creates a new class in WMI to store our data
function Register-WmiClass_MonitorDetails {
    $newClass = New-Object System.Management.ManagementClass("root\cimv2", [String]::Empty, $null);
    $newClass["__CLASS"] = "MonitorDetails";
    $newClass.Qualifiers.Add("Static", $true)
    # DeviceID Property (key)
    $newClass.Properties.Add("DeviceID", [System.Management.CimType]::String, $false)
    $newClass.Properties["DeviceID"].Qualifiers.Add("key", $true)
    $newClass.Properties["DeviceID"].Qualifiers.Add("read", $true)
    # Name Property
    $newClass.Properties.Add("Name", [System.Management.CimType]::String, $false)
    $newClass.Properties["Name"].Qualifiers.Add("read", $true)
    # ManufacturerCode Property
    $newClass.Properties.Add("ManufacturerCode", [System.Management.CimType]::String, $false)
    $newClass.Properties["ManufacturerCode"].Qualifiers.Add("read", $true)
    # Manufacturer Property
    $newClass.Properties.Add("Manufacturer", [System.Management.CimType]::String, $false)
    $newClass.Properties["Manufacturer"].Qualifiers.Add("read", $true)
    # Model Property
    $newClass.Properties.Add("Model", [System.Management.CimType]::String, $false)
    $newClass.Properties["Model"].Qualifiers.Add("read", $true)
    # SerialNumber Property
    $newClass.Properties.Add("SerialNumber", [System.Management.CimType]::String, $false)
    $newClass.Properties["SerialNumber"].Qualifiers.Add("read", $true)
    # EdidString Property
    $newClass.Properties.Add("EdidString", [System.Management.CimType]::String, $false)
    $newClass.Properties["EdidString"].Qualifiers.Add("read", $true)
    # HorizontalSize Property
    $newClass.Properties.Add("HorizontalSize", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["HorizontalSize"].Qualifiers.Add("read", $true)
    # VerticalSize Property
    $newClass.Properties.Add("VerticalSize", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["VerticalSize"].Qualifiers.Add("read", $true)
    # DiagonalSize Property
    $newClass.Properties.Add("DiagonalSize", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["DiagonalSize"].Qualifiers.Add("read", $true)
    $newClass.Properties["DiagonalSize"].Qualifiers.Add("Description", "Diagonal size of the monitor in inches")
    # MaxHorizontalRes Property
    $newClass.Properties.Add("MaxHorizontalRes", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["MaxHorizontalRes"].Qualifiers.Add("read", $true)
    # MaxVerticalRes Property
    $newClass.Properties.Add("MaxVerticalRes", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["MaxVerticalRes"].Qualifiers.Add("read", $true)
    # AspectRatio Property
    $newClass.Properties.Add("AspectRatio", [System.Management.CimType]::String, $false)
    $newClass.Properties["AspectRatio"].Qualifiers.Add("read", $true)
    $newClass.Properties["AspectRatio"].Qualifiers.Add("Description", "Aspect Ratio of the monitor e.g. 4:3 or 1:1")
    # ManufacturingYear Property
    $newClass.Properties.Add("ManufacturingYear", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["ManufacturingYear"].Qualifiers.Add("read", $true)
    # ManufacturingWeek Property
    $newClass.Properties.Add("ManufacturingWeek", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["ManufacturingWeek"].Qualifiers.Add("read", $true)
    # LastSeenDate Property
    $newClass.Properties.Add("LastSeenDate", [System.Management.CimType]::DateTime, $false)
    $newClass.Properties["LastSeenDate"].Qualifiers.Add("read", $true)
    # Update wmi Class
    $newClass.Put() | Out-Null
}

# Remove Wmi Class MonitorDetails if it exist as a workaround to update Wmi Class Signature if it changes.
Remove-WMIClass_MonitorDetails

try {
        # Create MonitorDetails WMI Class
        Register-WmiClass_MonitorDetails
    }
catch {
        # Trhow Error if Wmi class can not be created
        Write-Error "Could not create WMI class: $_"
        throw "WMI class creation failed."
}

# Variable for storing monitor data in array
$MonitorsInfo = @()
$Monitors = Get-CimInstance -ClassName Win32_PnPEntity -Filter "Service='monitor'"
# Processing detected monitors
foreach ($Monitor in $Monitors) {
    $CurrentMonitorInfo = @{
        DeviceID = $Monitor.DeviceID
        Name = $Monitor.Name
    }
    # Then look up its data in the registry
    $RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $Monitor.DeviceID + "\Device Parameters"
    $EdidString = (Get-ItemProperty -Path $RegistryPath -Name EDID -ErrorAction SilentlyContinue).EDID
    $CurrentMonitorInfo.EdidString = $EdidString -join " "
    
    # Getting current DateTime in Wmi format (A date or time value, represented in a string in DMTF date/time format: yyyymmddHHMMSS.mmmmmmsUUU, where yyyymmdd is the date in year/month/day; HHMMSS is the time in hours/minutes/seconds; mmmmmm is the number of microseconds in 6 digits; and sUUU is a sign (+ or -) and a 3-digit UTC offset. This value maps to the DateTime type.)
    $currentDateTime = Get-Date
    # Formatting Date as DMTF
    $dmtfString = $currentDateTime.ToString("yyyyMMddHHmmss.ffffff") + "+" + ([DateTimeOffset]($currentDateTime)).Offset.TotalMinutes

    # Some monitors, especially those attached to VMs either don't have a Device Parameters key or an EDID value. Skip these
    if ($null -ne $EdidString) {
        # Collect the information from the EDID array in a hashtable
        $CurrentMonitorInfo.ManufacturerCode += [char](64 + [Int32][math]::floor(($EdidString[8] / 4)))
        $CurrentMonitorInfo.ManufacturerCode += [char](64 + [Int32][math]::floor(($EdidString[8] % 4) * 8 + [Int32]($EdidString[9] / 32)))
        $CurrentMonitorInfo.ManufacturerCode += [char](64 + [Int32][math]::floor(($EdidString[9] % 32)))
        $ManufacturerName = $ManufacturersHash.$($CurrentMonitorInfo.ManufacturerCode)
        If ($null -eq $ManufacturerName) {
            $ManufacturerName = $CurrentMonitorInfo.ManufacturerCode
            $CurrentMonitorInfo.Manufacturer = $CurrentMonitorInfo.ManufacturerCode
        } else {
            $CurrentMonitorInfo.Manufacturer = $ManufacturerName
        }
        $CurrentMonitorInfo.ManufacturingWeek = $EdidString[16]
        $CurrentMonitorInfo.ManufacturingYear = $EdidString[17] + 1990
        $CurrentMonitorInfo.HorizontalSize = $EdidString[21]
        $CurrentMonitorInfo.VerticalSize = $EdidString[22]
        $CurrentMonitorInfo.DiagonalSize = [Math]::Round([Math]::Sqrt($CurrentMonitorInfo.HorizontalSize * $CurrentMonitorInfo.HorizontalSize + $CurrentMonitorInfo.VerticalSize * $CurrentMonitorInfo.VerticalSize) / 2.54)
        $CurrentMonitorInfo.LastSeenDate = $dmtfString
        
        # Getting maximum available resolution
        $MaximumAvailableResolution = Get-CimInstance -ClassName CIM_VideoControllerResolution | Select-Object HorizontalResolution,VerticalResolution | Sort-Object -Property HorizontalResolution,VerticalResolution | Select-Object -Last 1
        $CurrentMonitorInfo.MaxHorizontalRes = $MaximumAvailableResolution.HorizontalResolution
        $CurrentMonitorInfo.MaxVerticalRes = $MaximumAvailableResolution.VerticalResolution

        # Calculating AspectRatio
        if($CurrentMonitorInfo.HorizontalSize -gt 0 -and $CurrentMonitorInfo.VerticalSize -gt 0){
            $gcd = Get-GreatestCommonDivisor -a $CurrentMonitorInfo.MaxHorizontalRes -b $CurrentMonitorInfo.MaxVerticalRes
            $aspectRatioHorizontal = $CurrentMonitorInfo.MaxHorizontalRes / $gcd
            $aspectRatioVertical   = $CurrentMonitorInfo.MaxVerticalRes / $gcd
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
            '115648*'    { $CurrentMonitorInfo.Model = 'ProLite XB2483HSU' }
            '11565*'     { $CurrentMonitorInfo.Model = 'ProLite X2483HSU' }
            '4YMDT8*'    { $CurrentMonitorInfo.Model = 'DELL E2318H' }
            'KKMMW63C*'  { $CurrentMonitorInfo.Model = 'DELL P2414H' }
            'AU12227*'   { $CurrentMonitorInfo.Model = 'Philips 240B7QPTEB' }
            '117862*'    { $CurrentMonitorInfo.Model = 'ProLite XUB2492HSN' }
            '11510*'     { $CurrentMonitorInfo.Model = 'ProLite XU2492HSU' }
            '11750*'     { $CurrentMonitorInfo.Model = 'ProLite XUB2493HSU' }
            '11878*'     { $CurrentMonitorInfo.Model = 'ProLite XUB2493HS' }
            '12081*'     { $CurrentMonitorInfo.Model = 'ProLite XU2494HSU' }
            '116511*'    { $CurrentMonitorInfo.Model = 'ProLite GB2730HSU' }
            '11663*'     { $CurrentMonitorInfo.Model = 'ProLite XUB2792HSU' }
            '116691*'    { $CurrentMonitorInfo.Model = 'ProLite XB2474HS' }
            '11551*'     { $CurrentMonitorInfo.Model = 'ProLite XB3270QS' }
            '121143*'    { $CurrentMonitorInfo.Model = 'ProLite XUB2493HS' }
            default      { $CurrentMonitorInfo.Model = ''}
        }

        # If the horizontal size of this monitor is zero, it's a purely virtual one (i.e. RDP only) and shouldn't be stored
        # Also excluding monitor with name "Integrated Monitor"
        if ($CurrentMonitorInfo.HorizontalSize -ne 0 -and $CurrentMonitorInfo.Name -ne "Integrated Monitor" -and $CurrentMonitorInfo.Name -ne "Generic PnP Monitor") {
            $MonitorsInfo += $CurrentMonitorInfo
        }
    }
}

# Show Objects that will be registered (debug)
$ParametersOrder = "DeviceID","Name","ManufacturerCode","Manufacturer","Model","SerialNumber","EdidString","HorizontalSize","VerticalSize","DiagonalSize","MaxHorizontalRes","MaxVerticalRes","AspectRatio","ManufacturingYear","ManufacturingWeek","LastSeenDate"
Write-Output "Objects that will be registered:"
foreach ($hashtable in $MonitorInfo) { foreach ($key in $ParametersOrder) { if ($hashtable.ContainsKey($key)){ Write-Output "$key = $($hashtable[$key])" }}}

# Store gathered data in WMI class MonitorDetails
foreach ($MonitorInfo in $MonitorsInfo) {
    Set-WmiInstance -Path "\\.\root\cimv2:MonitorDetails" -Arguments @{
        DeviceID          = $MonitorInfo.DeviceID
        Name              = $MonitorInfo.Name
        ManufacturerCode  = $MonitorInfo.ManufacturerCode
        Manufacturer      = $MonitorInfo.Manufacturer
        Model             = $MonitorInfo.Model
        SerialNumber      = $MonitorInfo.SerialNumber
        EdidString        = $MonitorInfo.EdidString
        HorizontalSize    = $MonitorInfo.HorizontalSize
        VerticalSize      = $MonitorInfo.VerticalSize
        DiagonalSize      = $MonitorInfo.DiagonalSize
        MaxHorizontalRes  = $MonitorInfo.MaxHorizontalRes
        MaxVerticalRes    = $MonitorInfo.MaxVerticalRes
        AspectRatio       = $MonitorInfo.AspectRatio
        ManufacturingYear = $MonitorInfo.ManufacturingYear
        ManufacturingWeek = $MonitorInfo.ManufacturingWeek
        LastSeenDate      = $MonitorInfo.LastSeenDate
    } | Out-Null
}

# Show Registered Objects
Write-Output "Registered Objects:"
Get-cimInstance -Class MonitorDetails | Select-Object -Property $ParametersOrder