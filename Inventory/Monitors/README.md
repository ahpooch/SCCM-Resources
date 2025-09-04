# The task of inventorying attached monitors with SCCM

## Implementation Description

To gather inventory data about attached monitors we need to periodically run a script that collects information about connected monitors and write it to custom CIM class `MonitorDetails` located at `ROOT\cimv2`, we will use the method of periodically deploying a Standard Program. The Program itself in SCCM is based on a Package with powershell script `Get-ExtendedMonitorDetails.ps1`.

## Creating Package

In SCCM, create a Package named `ExtendedMonitorDetails`.  
Follow `Software Library -> Packages -> Create Package`.  
Fill in:  

```properties
Name: ExtendedMonitorDetails
Description: This package utilizes the Get-ExtendedMonitorDetails.ps1 script to create a custom CIM Class MonitorDetails.
Manufacturer: Neon Cyber Crutches
Version: 1.1.0
```

Select `This package contains source files`. Click `Browse` and select the folder where the `Get-ExtendedMonitorDetails.ps1` file was saved. The example uses the path `\\<Server>\SMS_SOURCES$\Scripts\ExtendedMonitorDetails\Latest`.
Click `Next >` and select `Standard program`.
Fill in:

```Properties
Name: Get-ExtendedMonitorDetails
Command line: Powershell.exe -ExecutionPolicy Bypass -file "Get-ExtendedMonitorDetails.ps1"
Startup folder:
Run: Hidden
Program can run: Whether or not a user is logged on
Run mode: Run with administrative rights
Drive mode: Runs with UNC name
```

<img src="images/Pasted image 20250904010215.png" alt="Logo" width="100%" height="100%">

Click `Next >`.
Without making changes to Requirements, click `Next >`.
After reviewing the Summary, click `Next >`.
Click `Close`.

## Creating Distribution Collections

The Package, or rather the Program based on the Package, must be deployed to collections limited to physical workstations and servers.
For example:
`WKS - SD - General Required Deploy - Physical Workstations`.

```WQL
select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System   where SMS_R_System.ResourceId not in (select SMS_R_SYSTEM.ResourceID from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_R_System.IsVirtualMachine = 'True') and SMS_R_System.OperatingSystemNameandVersion   like 'Microsoft Windows NT%Server%'
```

`SRV - SD - General Required Deploy - Physical Servers`.

```WQL
select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System   where SMS_R_System.ResourceId not in (select SMS_R_SYSTEM.ResourceID from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_R_System.IsVirtualMachine = 'True') and SMS_R_System.OperatingSystemNameandVersion   like '%Workstation%'
```

## Deploying package

The deployment should occur periodically, for example, daily or preferably every few hours, to update the information in the CIM class. However, ultimately, the data refresh rate in reports will depend on the Hardware Inventory cycle frequency set for the clients.

Chose the collection, invoke the context menu, and select `Deploy -> Program`.  
In Software, find `Get-ExtendedMonitorDetails` via `Browse...` button.
<img src="images/Pasted image 20250904012727.png" alt="Logo" width="100%" height="100%">
Click `Next >`.
Select the necessary Distribution Groups for content distribution.
Click `Next >`.
Action: Install, Purpose: Required.
Click `Next >`.
In `Scheduling`, opposite `Assignment schedule`, select `New...`, then `Schedule...`.
Select `Custom Interval` and the desired frequency for updating information about monitors connected to the device. In this case, 2 hours was chosen.
Click `OK`, `OK`, and set `Rerun behaviour: Always rerun program`.
<img src="images/Pasted image 20250904012657.png" alt="Logo" width="100%" height="100%">
Click `Next >`.
Activate the checkbox `Software installation` so the script runs regardless of maintenance windows.
<img src="images/Pasted image 20250904012812.png" alt="Logo" width="100%" height="100%">
Click `Next >`.
For both Boundary Groups cases, select:
`Deployment options: Download content from distribution point and run locally`
Activate the checkbox `Allow clients to use distribution points from the default site boundary group`.
<img src="images/Pasted image 20250904013001.png" alt="Logo" width="100%" height="100%">
Click `Next >`.
After reviewing the Summary, click `Next >`.
Click `Close`.

## Hardware Inventory Class

Next, we configure the collection of information from the CIM class `ROOT\cimv2\MonitorDetails` into the SCCM database using the Hardware Inventory mechanism.

### Creating a Hardware Inventory Class

Custom class MonitorDetailes can be added in two ways:

- **Import from a .mof file.**
  Importing from a .mof file is convenient if an existing file with an exported class is available. In our case, the file `MonitorDetails.mof` can be used.
- **Adding based on a CIM class already registered on one of the devices.**
  This method allows adding any CIM class that has been created on any device. To use it, the script `Get-ExtendedMonitorDetails.ps1` must first be run on one of the devices.

>When working with Hardware Inventory, remember to use the `Default Client Settings` object. When using other manually created `Client Settings` objects, some classes and their parameters may be unavailable for editing (classes inherited from `Default Client Setting` are displayed grayed out), which can be surprising at the first time.

#### Option 1 - Import from a .mof file

Follow `Administration -> Overview -> Client Settings` and open the properties of `Default Client Settings`. Then click `Set Classes...`, which will open the `Hardware Inventory Classes` window. Click `Import...`
Specify the location of `MonitorDetails.mof`, click `Open...`
Leave `Import both hardware inventory classes and hardware inventory class settings` selected.
<img src="images/Pasted image 20250904075008.png" alt="Logo" width="100%" height="100%">
Click `Import...`.

#### Option 2 - Adding based on a CIM class already registered on one of the devices

Follow `Administration -> Overview -> Client Settings` and open the properties of `Default Client Settings`. Then click `Set Classes...`, which will open the `Hardware Inventory Classes` window. Click `Add...`
Then, in the `Connect to Windows Management Instrumentation (WMI)` window, enter the necessary connection values and click `Connect`
<img src="images/Pasted image 20250904080628.png" alt="Logo" width="100%" height="100%">
Activate the checkbox for `MonitorDetails`
<img src="images/Pasted image 20250904084353.png" alt="Logo" width="100%" height="100%">
If you click `Edit...`, you can set some additional parameters for the CIM class properties.
<img src="images/Pasted image 20250904084608.png" alt="Logo" width="100%" height="100%">
Click `OK`, `OK`.

### Verifying the Hardware Inventory Class

To verify that the Hardware Inventory class is created and used, open `Administration -> Overview -> Client Settings` and open the properties of `Default Client Settings`. Then click `Set Classes...`, which will open the `Hardware Inventory Classes` window. It features search and filtering, which greatly simplifies the task of finding `MonitorDetails` class.

<img src="images/Pasted image 20250904072212.png" alt="Logo" width="100%" height="100%">

After implementation and completing data collection from endpoint devices, the data from the SCCM database can be used. For this, use the view `[CM_XXX].[dbo].[v_GS_MONITORDETAILS]`.
An additional view with historical data will also be created: `[CM_XXX].[dbo].[v_HS_MONITORDETAILS]`
<img src="images/Pasted image 20250901224204.png" alt="Logo" width="100%" height="100%">
Reports can be created in SSRS based on this data.

## SSRS Report Import

Connect to SSRS, in the desired folder click `Upload` and specify the path to `MonitorDetails.rdl`.
After import, click on the three dots next to the report icon and select `Manage`.
Go to `Data sources` and specify your SCCM `Shared data source`.
After this, the report can be used in the standard way.

In the current version, the MonitorDetails.rdl report is very simplified and does not include all possible monitor data available in the original CIM class.
<img src="images/Pasted image 20250904100344.png" alt="Logo" width="100%" height="100%">

## Links to resources this guide is inspired and powered by

[https://exar.ch/collecting-monitor-serial-numbers-with-sccm/](https://exar.ch/collecting-monitor-serial-numbers-with-sccm/)
Describes where monitor information is located in the registry.
Also contains a (broken!) link to a script that creates a new WMI class for retrieving data about connected monitors.

[https://exar.ch/collecting-custom-wmi-classes-with-sccm/](https://exar.ch/collecting-custom-wmi-classes-with-sccm/)
Describes how to collect information from a custom class using SCCM.

[https://exar.ch/creating-a-custom-sccm-report/](https://exar.ch/creating-a-custom-sccm-report/)
An example of creating a report using the data via Report Server.
