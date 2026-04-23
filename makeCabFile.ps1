<#
.SYNOPSIS
    Packages DLL files into a cabinet (.cab) file for Power Automate Desktop custom actions.

.DESCRIPTION
    Creates a .cab file from all .dll files in the source directory,
    EXCLUDING the SDK DLL (Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK.dll).
    Uses the built-in Windows makecab.exe utility.

    Based on the official Microsoft documentation:
    https://learn.microsoft.com/en-us/power-automate/desktop-flows/create-custom-actions#packaging-everything-in-a-cabinet-file

.PARAMETER sourceDir
    The directory containing the .dll files to package (e.g., bin\Release\net472).

.PARAMETER cabOutputDir
    The directory where the .cab file will be created.

.PARAMETER cabFilename
    The name of the .cab file to create (e.g., MyCustomAction.cab).

.EXAMPLE
    .\makeCabFile.ps1 ".\Modules.SampleActions\bin\Release\net472" ".\Output" "Modules.SampleActions.cab"
#>

param(
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$sourceDir,

    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$cabOutputDir,

    [string]$cabFilename
)

$ddf = ".OPTION EXPLICIT
.Set CabinetName1=$cabFilename
.Set DiskDirectory1=$cabOutputDir
.Set CompressionType=LZX
.Set Cabinet=on
.Set Compress=on
.Set CabinetFileCountThreshold=0
.Set FolderFileCountThreshold=0
.Set FolderSizeThreshold=0
.Set MaxCabinetSize=0
.Set MaxDiskFileCount=0
.Set MaxDiskSize=0
"

$ddfpath = ($env:TEMP + "\customModule.ddf")
$sourceDirLength = $sourceDir.Length

$ddf += (Get-ChildItem $sourceDir -Filter "*.dll" |
    Where-Object { (!$_.PSIsContainer) -and ($_.Name -ne "Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK.dll") } |
    Select-Object -ExpandProperty FullName |
    ForEach-Object { '"' + $_ + '" "' + ($_.Substring($sourceDirLength)) + '"' }) -join "`r`n"

$ddf | Out-File -Encoding UTF8 $ddfpath
makecab.exe /F $ddfpath
Remove-Item $ddfpath
