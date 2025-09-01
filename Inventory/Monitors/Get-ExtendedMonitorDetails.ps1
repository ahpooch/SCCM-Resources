<#
 # This script reads the EDID information stored in the registry for the currently connected monitors
 # and stores their most important pieces of identification (Name, Size, Serial Number etc) in WMI
 # for later retrieval by SCCM
 #>

# Reads the 4 bytes following $index from $array then returns them as an integer interpreted in little endian
function Get-LittleEndianInt($array, $index) {
    # Create a new temporary array to reverse the endianness in
    $temp = @(0) * 4
    [Array]::Copy($array, $index, $temp, 0, 4)
    [Array]::Reverse($temp)
    
    # Then convert the byte data to an integer
    [System.BitConverter]::ToInt32($temp, 0)
}

# Creates a new class in WMI to store our data
function Create-Wmi-Class() {
    $newClass = New-Object System.Management.ManagementClass("root\cimv2", [String]::Empty, $null); 

    $newClass["__CLASS"] = "MonitorDetails"; 

    $newClass.Qualifiers.Add("Static", $true)
    $newClass.Properties.Add("DeviceID", [System.Management.CimType]::String, $false)
    $newClass.Properties["DeviceID"].Qualifiers.Add("key", $true)
    $newClass.Properties["DeviceID"].Qualifiers.Add("read", $true)
    $newClass.Properties.Add("ManufacturingYear", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["ManufacturingYear"].Qualifiers.Add("read", $true)
    $newClass.Properties.Add("ManufacturingWeek", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["ManufacturingWeek"].Qualifiers.Add("read", $true)
    $newClass.Properties.Add("DiagonalSize", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["DiagonalSize"].Qualifiers.Add("read", $true)
    $newClass.Properties["DiagonalSize"].Qualifiers.Add("Description", "Diagonal size of the monitor in inches")
    $newClass.Properties.Add("Manufacturer", [System.Management.CimType]::String, $false)
    $newClass.Properties["Manufacturer"].Qualifiers.Add("read", $true)
    $newClass.Properties.Add("Name", [System.Management.CimType]::String, $false)
    $newClass.Properties["Name"].Qualifiers.Add("read", $true)
    $newClass.Properties.Add("SerialNumber", [System.Management.CimType]::String, $false)
    $newClass.Properties["SerialNumber"].Qualifiers.Add("read", $true)
    $newClass.Put()
}

# Check whether we already created our custom WMI class on this PC, if not, create it
[void](gwmi MonitorDetails -ErrorAction SilentlyContinue -ErrorVariable wmiclasserror)
if ($wmiclasserror) {
    try { Create-Wmi-Class }
    catch {
        "Could not create WMI class"
        Exit 1
    }
}

# Iterate through the monitors in Device Manager
$monitorInfo = @()
gwmi Win32_PnPEntity -Filter "Service='monitor'" | % { $k=0 } {
    $mi = @{}
    $mi.Caption = $_.Caption
    $mi.DeviceID = $_.DeviceID
    # Then look up its data in the registry
    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $_.DeviceID + "\Device Parameters"
    $edid = (Get-ItemProperty $path EDID -ErrorAction SilentlyContinue).EDID

    # Some monitors, especially those attached to VMs either don't have a Device Parameters key or an EDID value. Skip these
    if ($edid -ne $null) {
        # Collect the information from the EDID array in a hashtable
        $mi.Manufacturer += [char](64 + [Int32]($edid[8] / 4))
        $mi.Manufacturer += [char](64 + [Int32]($edid[8] % 4) * 8 + [Int32]($edid[9] / 32))
        $mi.Manufacturer += [char](64 + [Int32]($edid[9] % 32))
        $mi.ManufacturingWeek = $edid[16]
        $mi.ManufacturingYear = $edid[17] + 1990
        $mi.HorizontalSize = $edid[21]
        $mi.VerticalSize = $edid[22]
        $mi.DiagonalSize = [Math]::Round([Math]::Sqrt($mi.HorizontalSize*$mi.HorizontalSize + $mi.VerticalSize*$mi.VerticalSize) / 2.54)

        # Walk through the four descriptor fields
        for ($i = 54; $i -lt 109; $i += 18) {
            # Check if one of the descriptor fields is either the serial number or the monitor name
            # If yes, extract the 13 bytes that contain the text and append them into a string
            if ((Get-LittleEndianInt $edid $i) -eq 0xff) {
                for ($j = $i+5; $edid[$j] -ne 10 -and $j -lt $i+18; $j++) { $mi.SerialNumber += [char]$edid[$j] }
            }
            if ((Get-LittleEndianInt $edid $i) -eq 0xfc) {
                for ($j = $i+5; $edid[$j] -ne 10 -and $j -lt $i+18; $j++) { $mi.Name += [char]$edid[$j] }
            }
        }
        
        # If the horizontal size of this monitor is zero, it's a purely virtual one (i.e. RDP only) and shouldn't be stored
        if ($mi.HorizontalSize -ne 0) {
            $monitorInfo += $mi
        }
    }
    
}
$monitorInfo

# Clear WMI
Get-WmiObject MonitorDetails | Remove-WmiObject

# And store the data in WMI
$monitorInfo | % { $i=0 } {
    [void](Set-WmiInstance -Path \\.\root\cimv2:MonitorDetails -Arguments @{DeviceID=$_.DeviceID; ManufacturingYear=$_.ManufacturingYear; `
    ManufacturingWeek=$_.ManufacturingWeek; DiagonalSize=$_.DiagonalSize; Manufacturer=$_.Manufacturer; Name=$_.Name; SerialNumber=$_.SerialNumber})
    #"Set-WmiInstance -Path \\.\root\cimv2:MonitorDetails -Arguments @{{DeviceID=`"{0}`"; ManufacturingYear={1}; ManufacturingWeek={2}; DiagonalSize={3}; Manufacturer=`"{4}`"; Name=`"{5}`"; SerialNumber=`"{6}`"}}" -f $_.DeviceID, $_.ManufacturingYear, $_.ManufacturingWeek, $_.DiagonalSize, $_.Manufacturer, $_.Name, $_.SerialNumber
    $i++
}
