#Requires -Module VSSetup

<#PSScriptInfo

.VERSION 1.0

.GUID a4d671ee-3603-418e-8a70-17dbac5cec5e

.AUTHOR Christos Gkantsidis

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


#>

# adapted from
# http://www.tavaresstudios.com/Blog/post/The-last-vsvars32ps1-Ill-ever-need.aspx and
# https://github.com/Iristyle/Posh-VsVars
$script:rootVsKey = if ([IntPtr]::size -eq 8)
  { "HKLM:\SOFTWARE\Wow6432Node\Microsoft\VisualStudio" }
else
  { "HKLM:\SOFTWARE\Microsoft\VisualStudio" }

<#

.DESCRIPTION
 Discovers the versions of VisualStudio installed in the machine

#>
function Get-VsVersions
{
    [CmdletBinding()]
    param(
        [switch]
        $Managed
    )

    # Below we ignore the registry entries for 15.0; this has been deprecated for VS15
    # it may exist in some systems as a leftover of early beta versions
    $oldversion = @{}

    Get-ChildItem $script:rootVsKey |
    Where-Object -FilterScript { $_.PSChildName -match '^\d+\.\d+$' } |
    Sort-Object -Property @{ Expression = { $_.PSChildName -as [int] } } |
    Where-Object -Property Name -NotMatch "15.0$" |
    ForEach-Object -Process {
        $version = $_.Name.Replace("HKEY_LOCAL_MACHINE", "HKLM:")
        $versionid = [System.Version]::new($version.Substring($version.LastIndexOf('\')+1))
        $path = $version
        $VsKey = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        Write-Debug -Message "For version $version key is $VsKey in path $path"

        if (($null -ne $VsKey) -and
            (Get-Member -InputObject $VsKey -Name "InstallDir" -MemberType Properties) -and
            (-not [System.String]::IsNullOrWhiteSpace($VsKey.InstallDir)))
        {
            $VsRootDir = Split-Path $VsKey.InstallDir `
                       | Split-Path

            if ($Managed) {
                $BatchFile = Join-Path -Path $VsRootDir -ChildPath "Common7" | `
                             Join-Path -ChildPath "Tools" | `
                             Join-Path -ChildPath "VsDevCmd.bat"
            } else {
                $BatchFile = Join-Path -Path $VsRootDir -ChildPath VC | `
                             Join-Path -ChildPath "vcvarsall.bat"
            }

            if (Test-Path -Path $BatchFile -PathType Leaf) {
                $oldversion.Add($versionid, $BatchFile)
            } else {
                Write-Verbose -Message "Cannot find setup script for version $version in $BatchFile"
            }
        }
    }

    [Microsoft.VisualStudio.Setup.Instance[]] $newinstallations = Get-VSSetupInstance -All
    $newversion = @{}

    if ($newinstallations) {
        $newinstallations |
        ForEach-Object -Process {
            $version = $_.InstallationVersion
            $path = $_.InstallationPath

            if ($Managed) {
                $BatchFile = Join-Path -Path $path -ChildPath "Common7" |
                            Join-Path -ChildPath "Tools" |
                            Join-Path -ChildPath "VsDevCmd.bat"
            } else {
                $BatchFile = Join-Path -Path $path -ChildPath "VC" |
                            Join-Path -ChildPath "Auxiliary" |
                            Join-Path -ChildPath "Build" |
                            Join-Path -ChildPath "vcvarsall.bat"
            }

            if (Test-Path -Path $BatchFile -PathType Leaf) {
                $newversion.Add($Version, $BatchFile)
            } else {
                Write-Warning -Message "Cannot find setup script for version $version in $BatchFile"
            }
        }
    }

    $version = $oldversion + $newversion
    return ( $version.GetEnumerator() | Sort-Object -Property @{Expression={$_.Name}} )
}

function Get-VsVarsScript
{
    [CmdletBinding()]
    param(
        [string]
        [ValidateSet('7.1', '8.0', '9.0', '10.0', '11.0', '12.0', '14.0', '15', '15.0', '15.1', '15.2', '15.3', '15.4', '15.5', '15.6', '15.7', 'latest')]
        $Version = 'latest',

        [switch]
        $Managed
    )

    $versions = Get-VsVersions -Managed:$Managed

    if ($version -eq 'latest') {
        $versions | Select-Object -ExpandProperty Value -Last 1
    } else {
        $versions |
        Where-Object -FilterScript {
            $fullname = $_.Name.ToString()
            $fullname.StartsWith($Version)
        } |
        Select-Object -ExpandProperty Value -Last 1
    }
}