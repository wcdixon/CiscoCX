<#
.SYNOPSIS 
Script to set server LUN queue depth per Path or Max Queue Depth

.DESCRIPTION
Sets the LUN Queue Depth per Path for each host passed.  

.PARAMETER Name
IP Address or comma seperated set if IP Addresses of the CIMC instance/s.  If an IP is entered here the CIMC .csv list will be ignored.

.PARAMETER CsvPath
Full path to a .csv formatted list of CIMC IPs to interact with.  Must be 2 rows with a "CIMC" header in row 1, and a "IP" header in row 2.
For example
CIMC,IP
MyCIMCName,10.10.10.10
MyCIMCName2,10.10.10.15

.PARAMETER DIRECTORY
Directory you want the outputed to.  Defaults to "C:\ESXiPowertoolOut\<RunningScriptName>"
If the directory does not exist, it will be created.

.EXAMPLE
This example will run the script accross ESXi's  10.10.10.1, 10.10.10.2 and 10.10.10.3.
ESXi_Max_QueueDepth.ps1 -Name "10.10.10.1,10.10.10.2,10.10.10.3"

.EXAMPLE
This Example will output to a network share using the "-Directory" switch.
ESXi_Max_QueueDepth.ps1 -CsvPath "C:\zInput\cimcList.csv" -Directory "\\MyDirectory\"
By Default, every script outputs to "C:\PowertToolOut\{ThisScriptsName}\"

.EXAMPLE
This example will run the script using the list of CIMC IP's in the cimcList.csv file.  
As long as the CSV headings for the first two rows is "CIMC,IP".
ESXi_Max_QueueDepth.ps1 -CsvPath "C:\zInput\cimcList.csv"

.NOTES
Author: Willie Dixon, Network Consultant Engineer, Cisco Advance Services
Email: wcdixon@cisco.com

Version: 1.0

.LINK
http://communities.cisco.com
#>

# You can add additional script parameters here, that a user calls with "-ParamName".  Example "$Name" below = ".\ScriptName.ps1 -Name" when executing this script.
[CmdletBinding()]
param(
	[Parameter(Mandatory=$false,Position=0)]
    [string]$Name,
	[Parameter(Mandatory=$false,Position=1,HelpMessage="This must be a valid path to a .csv file.")]
	[ValidateScript({Test-Path $_ })]
    [string]$CsvPath,
	[Parameter(Mandatory=$false,Position=2)]
	[string]$Directory
	)

if ((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null)
{
    Add-PsSnapin VMware.VimAutomation.Core
}

#_______________________________________________________________________________
#__________________ GLOBALS_____________________________________________________
#_______________________________________________________________________________
$ReportErrorShowExceptionClass = $true
# It is not necessary to change any of these settings.
$Error.Clear()
$Global:SCRIPTNAME = $MyInvocation.MyCommand.Name.Trim(".ps1")
$Global:cred = $null
#_______________________________________________________________________________
#__________________ LIBRARY FUNCTIONS __________________________________________
#__________________ DO NOT MODIFY ______________________________________________
#_______________________________________________________________________________
Function Set-ESXiScriptEnvironment ()
{
	$GLOBAL:cred = $null
	Try
	{
		[array]$esxiList = Get-ESXiList
		$Global:rootDir = Set-OutputDirectory $DIRECTORY
		foreach ($inputHandle in $esxiList)
		{
			$working = Validate-EsxiConnect -esxi $inputHandle
			if ($working)
			{
				[array]$ESXiListOut += $working
			}
		}
		return $ESXiListOut
	}
	catch
	{
		Handle-ScriptError -InputError $_ -ScriptLocals $MyInvocation
	}
}

Function Get-ESXiList ()
{
	Try	
	{
		if (!($Name) -and !($CsvPath))
		{
			Write-Host "Error: No ESXi instance specified or CSV of ESXi instances specified."
			Write-Host 'Use -Name "YourIP,YourIP,YourIP", or -CsvPath "{csvPath}" to specify a ESXi instance'
			Write-Host "Exiting..."
			exit 1
		}
		if ($Name)
		{
			$ipsIn = $Name.Split(",")
			foreach ($IP in $ipsIn)
			{
		    	[array]$mgrList += $IP
			}
		}
	    if ($CsvPath)
	    {
	        if (Get-Item $CsvPath -ErrorAction SilentlyContinue)
	        {
	            $global:csvImport = Import-Csv $CsvPath
				$global:csvin = $true
				foreach ($esxi in $csvImport)
				{
			    	[array]$mgrList += $esxi.IP
				}
	        }
	        else
	        {
	              Write-Host "Error: CSV File not found at $CsvPath. Please check the path"
	              Write-Host "Exiting...."
	              exit 1
	        }
	    }
	}
	catch
	{
		Handle-ScriptError -InputError $_ -ScriptLocals $MyInvocation
	}
    return [array]$mgrList
}

Function Validate-EsxiConnect ([string]$esxi,[switch]$RunningCheck)
{
	Try
	{
		$esxiSession = {}
		if ($cred -eq $null)
		{
				Write-Host "Global: Enter your ESXi Credentials: " -NoNewline
				$GLOBAL:CRED = Get-Credential -Message "Enter your ESXi Credentials" -ErrorAction SilentlyContinue
				if ($GLOBAL:cred)
				{
					Write-Host -ForegroundColor Green "Passed"	
				}
				else
				{
					Write-Host -ForegroundColor Red "Failed: Password entered is blank or null, Exiting..."
					exit 1
				}
				
		}
		$esxi = $esxi.Replace(" ","")
		$ping = new-object system.net.networkinformation.ping
		Write-Host "Global: ESXi Connect: Ping Test: $($esxi): " -NoNewline
		if (($result = ($ping.send($esxi))).Status -ne "Success" )
		{
			Write-Host -ForegroundColor Red "Failed. Removing from ESXi List"
			Continue
		}
		else
		{
			Write-Host -ForegroundColor Green "Passed, RTT = $($result.RoundtripTime)"
			Write-Host "Global: ESXi Connect: Authentication: " -NoNewline
			
			$esxiSession = Connect-VIServer -Server $esxi -Credential $GLOBAL:cred -ErrorAction SilentlyContinue
			
			if (!($esxiSession))
			{
				$esxiSession = Connect-VIServer -Server $esxi -Credential $GLOBAL:cred -NotDefault -ErrorAction SilentlyContinue
			}
		
		if ($RunningCheck)
			{
				if (!($esxiSession))
				{
					Write-Host -ForegroundColor Red "Failed, ESXi host has not come online yet."
					continue
				}
			}
			elseif ($esxiSession)
			{
				
				Write-Host -ForegroundColor Green "Passed"
				return $esxiSession
			}
			else
			{
				Write-Host -ForegroundColor Red "Failed, Bad Password"
				continue
			}
		}
	}
	catch
	{
		Handle-ScriptError -InputError $_ -ScriptLocals $MyInvocation
	}
}

Function Set-OutputDirectory ([string]$DIRECTORY)
{
	Try
	{
		Write-Host "GLOBAL: Validation: Output Directory: " -NoNewline
		if (!($DIRECTORY))
		{
			$DIRECTORY = "C:\ESXiPowertoolOut\" + $scriptName + "\"
		}
		if (!($DIRECTORY.EndsWith("\")))
		{
			$DIRECTORY = $DIRECTORY + "\"
			
		}
		if (!(Test-Path $DIRECTORY -ErrorAction SilentlyContinue))
		{
			Write-Host -ForegroundColor Red "Does not Exist: Creating... " -NoNewline
			md -Path $DIRECTORY -Force | Out-Null
			if (!(Test-Path $DIRECTORY -ErrorAction SilentlyContinue))
			{
				Write-Host ""
				Write-Host "Could not create destination directory.  Most likely permissions."
				Write-Host "Exiting..."
				exit
			}
			else
			{
				Write-host -ForegroundColor Green "Created"
				RETURN $Directory
			}
		}
		else
		{
			Write-Host -ForegroundColor Green "Verified"
			RETURN $Directory
		}
	}
	catch
	{
		Handle-ScriptError -InputError $_ -ScriptLocals $MyInvocation
	}
}


Function Handle-ScriptError ([Object]$InputError, [Object]$ScriptLocals)
{
	Write-Host ""
	Write-Host -ForegroundColor Red "____________________________________________________________"
	Write-Host "There was a code error with " -NoNewline
	If ($ScriptLocals.MyCommand.Name)
	{
		$localOutput = "Function: $($ScriptLocals.MyCommand.Name)"
	}
	else
	{
		$localOutput = "the Main Program Area"
	}
	Write-Host -ForegroundColor Red "$($localOutput)"
	Write-Host -ForegroundColor Red "____________________________________________________________"
	Write-Host "Please email wcdixon@cisco.com with the below output:"
	Write-Host -ForegroundColor Red "____________________________________________________________"
	Write-Host "Powershell Version: $($PSVersionTable.PSVersion.Major)"
	Write-Host "Error Brief: " -NoNewline
	Write-Host -ForegroundColor Red $InputError
	Write-Host "Code Block: " -NoNewline
	Write-Host -ForegroundColor Blue $InputError.InvocationInfo.Line.replace("`n","").replace("`r"," ").Trim()
	Write-Host "Code Block Location: " -NoNewline
	Write-Host -ForegroundColor Magenta "At Line:" -NoNewline
	Write-host -ForegroundColor Blue " $($InputError.InvocationInfo.ScriptLineNumber) " -NoNewline
	Write-host -ForegroundColor Magenta "/ Entering here From:" -NoNewline
	Write-Host -ForegroundColor Blue " $($ScriptLocals.ScriptLineNumber)"
	Write-Host "Script Stack Trace: "
	Write-Host -ForegroundColor Magenta $InputError.ScriptStackTrace
	Write-Host -ForegroundColor Red "____________________________________________________________"
	Write-Host -ForegroundColor Red "Exiting..."
	if 	(($ScriptLocals.MyCommand.Name) -eq "Cleanup-EsxiScriptEnvironment")
	{
		exit 1
	}
	else
	{
		Cleanup-EsxiScriptEnvironment
		exit 1
	}
}

Function Cleanup-EsxiScriptEnvironment 
{
	Try
	{	
		Write-Host "Global: Cleanup: " 
		foreach ($handle in $ESXIHANDLELIST)
		{
			Write-Host "Global: Cleanup: $($handle.esxi): " -NoNewline
			Disconnect-VIServer -Server $handle -Confirm:$false
            if ($handle.Priv -eq $null)
			{
				Write-Host -ForegroundColor Green "Disconnected..."
			}
			else
			{
				Write-Host -ForegroundColor Red "Failed to Disconnect..."
			}
		}
		Write-Host "Global: Cleanup: Variables: " -NoNewline
		#Remove-Variable -Scope "script" -Name * -ErrorAction SilentlyContinue
		Write-Host -ForegroundColor Green "Cleaned"
		Write-Host "Global: Cleanup: " -NoNewline
		Write-Host -ForegroundColor Green "Complete"
	}
	catch
	{
		Handle-ScriptError -InputError $_ -ScriptLocals $MyInvocation
	}
}

#_____________________________________________________________________________
#__________________ MY FUNCTIONS __________________________________________________
#_______________________________________________________________________________
# Make Modification to this function to include Queue Depth settings.  Select and uncomment out the
# esxcli command for the module you want to change
Function ESXi_QueueDepth ($esxiHandlelist)
{
   	Try
	{
		foreach($handle in $esxiHandlelist)
		{
			Write-Output "Queue Depth Setting for $handle"
			$esxcli = Get-VMHost $handle | Get-EsxCli
			$esxcli.system.module.parameters.set($null,$null,'nfnic','lun_queue_depth_per_path=128')
		#	$esxcli.system.module.parameters.set($null,$null,'fnic','fnic_max_qdepth=128')
	    }
		
	}
	catch
	{
		Handle-ScriptError -InputError $_ -ScriptLocals $MyInvocation
	}
}
#_______________________________________________________________________
#__________________MAIN PROGRAM ________________________________________________
#_______________________________________________________________________________
. {
	Try
	{
		[array]$ESXIHANDLELIST = Set-EsxiScriptEnvironment
		$ESXIHANDLELIST = $ESXIHANDLELIST | where {$_ -ne $null} 
		if ($ESXIHANDLELIST)
		{ # CALL YOUR FUNCTION SCRIPTS HERE THAT YOU CREATE UNDER THE "MY FUNCTIONS" SECTION
        ESXi_QueueDepth $ESXIHANDLELIST  # $ESXIHANDLELIST is the array of CIMC Instances that have been logged into through "Set-UcsScriptEnvironment"
		}
		Cleanup-EsxiScriptEnvironment -esxiHandleList $esxiHandleList
	}
	catch
	{
		Handle-ScriptError -InputError $_ -ScriptLocals $MyInvocation
	}
}