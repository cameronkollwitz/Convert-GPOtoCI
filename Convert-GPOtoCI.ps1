﻿<#
	.SYNOPSIS
		Converts Group Policy Objects to Configuration Manager Configuration Items (CI).

	.COMPONENT
		Configuration Manager
		Windows Group Policy

	.DESCRIPTION
		Uses both the Configuration Manager and Active Directory PowerShell modules to query for registry keys associated with Group Policies then create the Configuration Items for each of the registry values.

	.FUNCTIONALITY
		Converts Group Policy Objects to Configuration Manager Configuration Items (CI).

	.PARAMETER GroupPolicy
		This is enabled by default and will make the script query only for one specified group policy.

	.PARAMETER GpoTarget
		Name of Group Policy Object.

	.PARAMETER ResultantSetOfPolicy
		Utilizes a resultant set of policy to determine the set of applied GPOs. Cannot be used in conjunction with the GroupPolicy option.

	.PARAMETER ComputerName
		Name of the device to run RSOP against.

	.PARAMETER DomainTarget
		Fully qualified domain name.

	.PARAMETER SiteCode
		Configuration Manager Site Code (###)

	.PARAMETER Remediate
		Enable Configuration Item to Remediate All Non-Compliant Settings.

	.PARAMETER Severity
		Sets the severity of non-compliant items. (None, Informational, Warning or Critical)

	.PARAMETER ExportOnly
		Exports the Configuration Item(s) to a CAB file to be manually imported to Configuration Manager.

	.PARAMETER Log
		Writes all discovered registry keys and their related GPO name to a log file.

	.EXAMPLE
		.\Convert-GPOtoCI.ps1 -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ

	.EXAMPLE
		.\Convert-GPOtoCI.ps1 -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ -Remediate

	.EXAMPLE
		.\Convert-GPOtoCI.ps1 -GroupPolicy -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ -Severity Warning

	.EXAMPLE
		.\Convert-GPOtoCI.ps1 -ResultantSetOfPolicy -ComputerName MyDevice01 -DomainTarget kollwitz.local -SiteCode KWZ

	.EXAMPLE
		.\Convert-GPOtoCI.ps1 -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ -ExportOnly

	.INPUTS
		None.

	.OUTPUTS

	.NOTES
		Credit: Originally created by Sam M. Roberts <https://github.com/SamMRoberts/Convert-GPOtoCI/>

	.NOTES
		Date Forked:    2021-05-06
		Maintainer:     Cameron Kollwitz
		Last Updated:   2021-05-06

	.LINK
		https://github.com/cameronkollwitz/Convert-GPOtoCI/

#>

## Set Script Run Requirements
#Requires -Version 2.0

[CmdletBinding(DefaultParameterSetName = 'GpoMode')]
Param(
	[Parameter(
		ParameterSetName = 'GpoMode',
		Mandatory = $true)]
	[String]$GpoTarget, # Name of GPO
	[Parameter(
		Mandatory = $true)]
	[String]$DomainTarget, # Domain name
	[Parameter(
		Mandatory = $true)]
	[String]$SiteCode, # ConfigMgr Site Code
	[Parameter(
		Mandatory = $false)]
	[Switch]$ExportOnly, # Switch to disable the creation of CIs and only export to a CAB file
	[Parameter(
		Mandatory = $false)]
	[Switch]$Remediate, # Set remediate non-compliant settings
	[Parameter(
		Mandatory = $false)]
	[ValidateSet('None', 'Informational', 'Warning', 'Critical')]
	[String]$Severity = 'Informational', # Rule severity
	[Parameter(
		ParameterSetName = 'RsopMode',
		Mandatory = $false)]
	[Switch]$ResultantSetOfPolicy, # Uses Resultant Set of Policy instead of specific GPO for values
	[Parameter(
		ParameterSetName = 'GpoMode',
		Mandatory = $false)]
	[Switch]$GroupPolicy, #  Uses a single GPO for values
	[Parameter(
		ParameterSetName = 'RsopMode',
		Mandatory = $true)]
	[String]$ComputerName, # Computer name to be used for RSOP
	[Parameter(
		ParameterSetName = 'RsopMode',
		Mandatory = $false)]
	[Switch]$LocalPolicy, # Switch to enable capturing local group policy when using RSOP mode
	[Parameter(
		Mandatory = $false)]
	[Switch]$Log    # Switch to enable logging all registry keys and their GPOs to a file
)

##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VariableDeclaration

$MAX_NAME_LENGTH = 255

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir = Split-Path -Parent $scriptPath
$startingDrive = (Get-Location).Drive.Name + ':'
$Global:ouPath = $null

If (($GroupPolicy -eq $false) -and ($ResultantSetOfPolicy -eq $false)) {
	$GroupPolicy = $true
}

#endregion
##*=============================================
##* END VARIABLE DECLARATION
##*=============================================

##*=============================================
##* FUNCTION LISTINGS
##*=============================================
#region FunctionListings

<#
	Utilizes native GroupPolicy module to query for registry keys assocaited with a given Group Policy
#>

Function Get-GPOKeys {
	Param(
		[String]$PolicyName, # Name of group policy
		[String]$Domain    # Domain name
	)

	If ((Get-Module).Name -contains 'GroupPolicy') {
		Write-Verbose 'GroupPolicy module already imported.'
	} Else {
		Try {
			Import-Module GroupPolicy    # Imports native GroupPolicy PowerShell module
		} Catch [Exception] {
			Write-Host 'Error trying to import GroupPolicy module.' -ForegroundColor Red
			Write-Host 'Script will exit.' -ForegroundColor Red
			Pause
			Exit
		}
	}

	Write-Host "Querying for registry keys associated with $PolicyName..."

	$gpoKeys = @('HKLM\Software', 'HKLM\System', 'HKCU\Software', 'HKCU\System')    # Sets registry hives to extract from Group Policy
	$values = @()
	$keyList = @()
	$newKeyList = @()
	$keyCount = 0
	$prevCount = 0
	$countUp = $true

	# While key count does not increment up
	While ($countUp) {
		$prevCount = $keyCount
		$newKeyList = @()
		ForEach ($gpoKey in $gpoKeys) {
			Try {
				$newKeys = (Get-GPRegistryValue -Name $PolicyName -Domain $Domain -Key $gpoKey -ErrorAction Stop).FullKeyPath    # Gets registry keys
			} Catch [Exception] {
				If ($_.Exception.Message -notlike '*The following Group Policy registry setting was not found:*') {
					Write-Host $_.Exception.Message -ForegroundColor Red
					Break
				}
			}
			# For each key in list of registry keys
			ForEach ($nKey in $newKeys) {
				# If key is not already in list
				If ($keyList -notcontains $nKey) {
					#Write-Verbose $nKey
					$keyList += $nKey
					$keyCount++
				}
				If ($newKeyList -notcontains $nKey) {
					$newKeyList += $nKey
				}
			}
		}
		[array]$gpoKeys = $newKeyList
		# If previous key count equals current key count.  (No new keys found; end of list)
		If ($prevCount -eq $keyCount) {
			$countUp = $false
		}
	}

	If ($null -ne $newKeys) {
		ForEach ($key in $keyList) {
			$values += Get-GPRegistryValue -Name $PolicyName -Domain $Domain -Key $key -ErrorAction SilentlyContinue | Select-Object FullKeyPath, ValueName, Value, Type | Where-Object { ($null -ne $_.Value) -and ($_.Value.Length -gt 0) }
		}
		If ($Log) {
			ForEach ($value in $values) {
				Write-Log -RegistryKey $value -GPOName $PolicyName
			}
		}
	}

	$valueCount = $values.Count

	Write-Host "`t$keyCount keys found."
	Write-Host "`t$valueCount values found."

	$values
}

<#
	Utilizes the ConfigurationManager PowerShell module to create Configuration Item settings based on registry keys
#>
Function New-CMConfigurationItemsetting {
	[CmdletBinding()]
	Param(
		[Parameter(
			Mandatory = $true)]
		[String]$DisplayName,
		[Parameter(
			Mandatory = $false)]
		[String]$Description = '',
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('Int64', 'Double', 'String', 'DateTime', 'Version', 'StringArray')]
		[String]$DataType,
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('HKEY_CLASSES_ROOT', 'HKEY_CURRENT_USER', 'HKEY_LOCAL_MACHINE', 'HKEY_USERS')]
		[String]$Hive,
		[Parameter(
			Mandatory = $true)]
		[bool]$Is64Bit,
		[Parameter(
			Mandatory = $true)]
		[String]$Key,
		[Parameter(
			Mandatory = $true)]
		[String]$ValueName,
		[Parameter(
			Mandatory = $true)]
		[String]$LogicalName
	)

	If ($DisplayName.Length -gt $MAX_NAME_LENGTH) {
		$DisplayName = $DisplayName.Substring(0, $MAX_NAME_LENGTH)
	}

	Write-Verbose "`tCreating setting $DisplayName..."

	$templatePath = "$scriptPath\xmlTemplates"

	$settingXml = [xml](Get-Content $templatePath\setting.xml)
	$settingXml.SimpleSetting.LogicalName = $LogicalName
	$settingXml.SimpleSetting.DataType = $DataType
	$settingXml.SimpleSetting.Annotation.DisplayName.Text = $DisplayName
	$settingXml.SimpleSetting.Annotation.Description.Text = $Description
	$settingXml.SimpleSetting.RegistryDiscoverySource.Hive = $Hive
	$settingXml.SimpleSetting.RegistryDiscoverySource.Is64Bit = $Is64Bit.ToString().ToLower()
	$settingXml.SimpleSetting.RegistryDiscoverySource.Key = $Key
	$settingXml.SimpleSetting.RegistryDiscoverySource.ValueName = $ValueName

	$settingXml.Save('c:\users\public\test1.xml')
	$settingXml
}

<#
	Utilizes the ConfigurationManager PowerShell module to create Configuration Item rules for previously created CI settings
#>
Function New-CMConfigurationItemRule {
	[CmdletBinding()]
	Param(
		[Parameter(
			Mandatory = $true)]
		[String]$DisplayName,
		[Parameter(
			Mandatory = $false)]
		[String]$Description = '',
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('None', 'Informational', 'Warning', 'Critical')]
		[String]$Severity,
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('Equals', 'NotEquals', 'GreaterThan', 'LessThan', 'Between', 'GreaterEquals', 'LessEquals', 'BeginsWith', `
				'NotBeginsWith', 'EndsWith', 'NotEndsWith', 'Contains', 'NotContains', 'AllOf', 'OneOf', 'NoneOf')]
		[String]$Operator,
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('Registry', 'IisMetabase', 'WqlQuery', 'Script', 'XPathQuery', 'ADQuery', 'File', 'Folder', 'RegistryKey', 'Assembly')]
		[String]$SettingSourceType,
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('String', 'Boolean', 'DateTime', 'Double', 'Int64', 'Version', 'FileSystemAccessControl', 'RegistryAccessControl', `
				'FileSystemAttribute', 'StringArray', 'Int64Array', 'FileSystemAccessControlArray', 'RegistryAccessControlArray', 'FileSystemAttributeArray')]
		[String]$DataType,
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('Value', 'Count')]
		[String]$Method,
		[Parameter(
			Mandatory = $true)]
		[bool]$Changeable,
		[Parameter(
			Mandatory = $true)]
		$Value,
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('String', 'Boolean', 'DateTime', 'Double', 'Int64', 'Version', 'FileSystemAccessControl', 'RegistryAccessControl', `
				'FileSystemAttribute', 'StringArray', 'Int64Array', 'FileSystemAccessControlArray', 'RegistryAccessControlArray', 'FileSystemAttributeArray')]
		[String]$ValueDataType,
		[Parameter(
			Mandatory = $true)]
		[String]$AuthoringScope,
		[Parameter(
			Mandatory = $true)]
		[String]$SettingLogicalName,
		[Parameter(
			Mandatory = $true)]
		[String]$LogicalName
	)

	If ($DisplayName.Length -gt $MAX_NAME_LENGTH) {
		$DisplayName = $DisplayName.Substring(0, $MAX_NAME_LENGTH)
	}

	Write-Verbose "`tCreating rule $DisplayName..."

	$templatePath = "$scriptPath\xmlTemplates"
	$id = "Rule_$([guid]::NewGuid())"
	$resourceID = "ID-$([guid]::NewGuid())"
	#$logicalName = "OperatingSystem_$([guid]::NewGuid())"

	If ($DataType -eq 'StringArray') {
		$ruleXml = [xml](Get-Content $templatePath\ruleSA.xml)
	} Else {
		$ruleXml = [xml](Get-Content $templatePath\rule.xml)
	}

	$ruleXml.Rule.Id = $id
	$ruleXml.Rule.Severity = $Severity
	$ruleXml.Rule.Annotation.DisplayName.Text = $DisplayName
	$ruleXml.Rule.Annotation.Description.Text = $Description
	$ruleXml.Rule.Expression.Operator = $Operator
	$ruleXml.Rule.Expression.Operands.SettingReference.AuthoringScopeId = $AuthoringScope
	$ruleXml.Rule.Expression.Operands.SettingReference.LogicalName = $LogicalName
	$ruleXml.Rule.Expression.Operands.SettingReference.SettingLogicalName = $SettingLogicalName
	$ruleXml.Rule.Expression.Operands.SettingReference.SettingSourceType = $SettingSourceType
	$ruleXml.Rule.Expression.Operands.SettingReference.DataType = $ValueDataType
	$ruleXml.Rule.Expression.Operands.SettingReference.Method = $Method
	$ruleXml.Rule.Expression.Operands.SettingReference.Changeable = $Changeable.ToString().ToLower()

	# If registry value type is StringArray
	If ($DataType -eq 'StringArray') {
		$ruleXml.Rule.Expression.Operands.ConstantValueList.DataType = 'StringArray'
		$valueIndex = 0
		# For each value in array of values
		ForEach ($v in $Value) {
			# if not first value in array add new nodes; else just set the one value
			If ($valueIndex -gt 0) {
				# if only one index do not specifiy index to copy; else specify the index to copy
				If ($valueIndex -le 1) {
					$newNode = $ruleXml.Rule.Expression.Operands.ConstantValueList.ConstantValue.Clone()
				} Else {
					$newNode = $ruleXml.Rule.Expression.Operands.ConstantValueList.ConstantValue[0].Clone()
				}
				$ruleXml.Rule.Expression.Operands.ConstantValueList.AppendChild($newNode)
				$ruleXml.Rule.Expression.Operands.ConstantValueList.ConstantValue[$valueIndex].DataType = 'String'
				$ruleXml.Rule.Expression.Operands.ConstantValueList.ConstantValue[$valueIndex].Value = $v

			} Else {
				$ruleXml.Rule.Expression.Operands.ConstantValueList.ConstantValue.DataType = 'String'
				$ruleXml.Rule.Expression.Operands.ConstantValueList.ConstantValue.Value = $v
			}
			$valueIndex++
		}
	} Else {
		$ruleXml.Rule.Expression.Operands.ConstantValue.DataType = $ValueDataType
		$ruleXml.Rule.Expression.Operands.ConstantValue.Value = $Value
	}
	$ruleXml
}

<#
	Utilizes the ConfigurationManager PowerShell module to create Configuration Items based on previously created settings and rules
#>

Function New-CMConfigurationItems {
	[CmdletBinding()]
	Param(
		[Parameter(
			Mandatory = $true)]
		[String]$Name,
		[Parameter(
			Mandatory = $false)]
		[String]$Description = '',
		[Parameter(
			Mandatory = $true)]
		[ValidateSet('MacOS', 'MobileDevice', 'None', 'WindowsApplication', 'WindowsOS')]
		[String]$CreationType,
		[Parameter(
			Mandatory = $true)]
		[array]$RegistryKeys,
		[Parameter(
			Mandatory = $false)]
		[ValidateSet('None', 'Informational', 'Warning', 'Critical')]
		[String]$Severity = 'Informational'    # Rule severity
	)

	If ((Get-Module).Name -contains 'ConfigurationManager') {
		Write-Verbose 'ConfigurationManager module already loaded.'
	} Else {
		Try {
			Import-Module "$(Split-Path $env:SMS_ADMIN_UI_PATH)\ConfigurationManager"    # Imports ConfigMgr PowerShell module
		} Catch [Exception] {
			Write-Host 'Error trying to import ConfigurationManager module.' -ForegroundColor Red
			Write-Host 'Script will exit.' -ForegroundColor Red
			Pause
			Exit
		}
	}

	If ($Name.Length -gt $MAX_NAME_LENGTH) {
		$Name = $Name.Substring(0, $MAX_NAME_LENGTH)
	}

	Write-Host 'Creating Configuration Item...'

	Set-Location "$SiteCode`:"

	$origName = $Name
	#$tmpFileCi = [System.IO.Path]::GetTempFileName()
	# If ResultantSetOfPolicy option is used use the OU path to name the CI xml
	If ($ResultantSetOfPolicy) {
		$ouNoSpace = $Global:ouPath.Replace(' ', '_')
		$ouNoSpace = $ouNoSpace.Replace('/', '_')
		$ciFile = "$scriptPath\$ouNoSpace.xml"
	}
	# If ResultantSetOfPolicy option is not used use the GPO nane to name the CI xml
	Else {
		$gpoNoSpace = $GpoTarget.Replace(' ', '_')
		$ciFile = "$scriptPath\$gpoNoSpace.xml"
	}

	For ($i = 1; $i -le 99; $i++) {
		$testCI = Get-CMConfigurationItem -Name $Name -Fast
		If ($null -eq $testCI) {
			Break
		} Else {
			$Name = $origName + " ($i)"
		}
	}

	$ci = New-CMConfigurationItem -Name $Name -Description $Description -CreationType $CreationType
	$ciXml = [xml]($ci.SDMPackageXML.Replace('<RootComplexSetting/></Settings>', '<RootComplexSetting><SimpleSetting></SimpleSetting></RootComplexSetting></Settings><Rules><Rule></Rule></Rules>'))

	$ciXml.Save($ciFile)

	ForEach ($Key in $RegistryKeys) {
		$len = ($Key.FullKeyPath.Split('\')).Length
		$keyName = ($Key.FullKeyPath.Split('\'))[$len - 1]
		$valueName = $Key.ValueName
		$value = $Key.Value
		$value = $value -replace '[^\u0030-\u0039\u0041-\u005A\u0061-\u007A]\Z', ''
		$type = $Key.Type
		$dName = $keyName + ' - ' + $valueName
		$hive = ($Key.FullKeyPath.Split('\'))[0]
		$subKey = ($Key.FullKeyPath).Replace("$hive\", '')
		$logicalNameS = "RegSetting_$([guid]::NewGuid())"
		$ruleLogName = $ciXml.DesiredConfigurationDigest.OperatingSystem.LogicalName
		$authScope = $ciXml.DesiredConfigurationDigest.OperatingSystem.AuthoringScopeId

		If ($Key.Type -eq 'Binary') {
			Continue
		}
		If ($Key.Type -eq 'ExpandString') {
			$dataType = 'String'
		} ElseIf ($Key.Type -eq 'MultiString') {
			$dataType = 'StringArray'
		} ElseIf ($Key.Type -eq 'DWord') {
			$dataType = 'Int64'
		} Else {
			$dataType = $Key.Type
		}

		If ($value.Length -gt 0) {
			$settingXml = New-CMConfigurationItemsetting -DisplayName $dName -Description ("$keyName - $valueName") -DataType $dataType -Hive $hive -Is64Bit $false `
				-Key $subKey -ValueName $valueName -LogicalName $logicalNameS

			If ($dataType -eq 'StringArray') {
				$operator = 'AllOf'
			} Else {
				$operator = 'Equals'
			}

			$ruleXml = New-CMConfigurationItemRule -DisplayName ("$valueName - $value - $type") -Description '' -Severity $Severity -Operator $operator -SettingSourceType Registry -DataType $dataType -Method Value -Changeable $Remediate `
				-Value $value -ValueDataType $dataType -AuthoringScope $authScope -SettingLogicalName $logicalNameS -LogicalName $ruleLogName

			# If array returned search arrary for XmlDocument
			If ($ruleXml.count -gt 1) {
				For ($i = 0; $i -lt ($ruleXml.Count); $i++) {
					If ($ruleXml[$i].GetType().ToString() -eq 'System.Xml.XmlDocument') {
						$ruleXml = $ruleXml[$i]
						Continue
					}
				}
			}
			$importS = $ciXml.ImportNode($settingXml.SimpleSetting, $true)
			$ciXml.DesiredConfigurationDigest.OperatingSystem.Settings.RootComplexSetting.AppendChild($importS) | Out-Null
			$importR = $ciXml.ImportNode($ruleXml.Rule, $true)

			$ciXml.DesiredConfigurationDigest.OperatingSystem.Rules.AppendChild($importR) | Out-Null
			$ciXml = [xml] $ciXml.OuterXml.Replace(" xmlns=`"`"", '')
			$ciXml.Save($ciFile)
		}
	}

	If ($ExportOnly) {
		Write-Host 'Deleting Empty Configuration Item...'
		Remove-CMConfigurationItem -Id $ci.CI_ID -Force
		Write-Host 'Creating CAB File...'
		If ($ResultantSetOfPolicy) {
			Export-CAB -Name $Global:ouPath -Path $ciFile
		} Else {
			Export-CAB -Name $GpoTarget -Path $ciFile
		}
	} Else {
		Write-Host 'Setting DCM Digest...'
		Set-CMConfigurationItem -DesiredConfigurationDigestPath $ciFile -Id $ci.CI_ID
		Remove-Item -Path $ciFile -Force
	}
}

Function Export-CAB {
	Param(
		[String]$Name,
		[String]$Path
	)

	$fileName = $Name.Replace(' ', '_')
	$fileName = $fileName.Replace('/', '_')
	$ddfFile = Join-Path -Path $scriptPath -ChildPath temp.ddf

	$ddfHeader = @"
;*** MakeCAB Directive file
;
.OPTION EXPLICIT
.Set CabinetNameTemplate=$fileName.cab
.set DiskDirectory1=$scriptPath
.Set MaxDiskSize=CDROM
.Set Cabinet=on
.Set Compress=on
"$Path"
"@

	$ddfHeader | Out-File -FilePath $ddfFile -Force -Encoding ASCII
	makecab /f $ddfFile | Out-Null

	#Remove temporary files
	Remove-Item ($scriptPath + '\temp.ddf') -ErrorAction SilentlyContinue
	Remove-Item ($scriptPath + '\setup.inf') -ErrorAction SilentlyContinue
	Remove-Item ($scriptPath + '\setup.rpt') -ErrorAction SilentlyContinue
	Remove-Item ($scriptPath + '\' + $fileName + '.xml') -ErrorAction SilentlyContinue
}

Function Get-RSOP {
	[CmdletBinding()]
	Param(
		[Parameter(
			Mandatory = $true)]
		[String]$ComputerName
	)

	$tmpXmlFile = [System.IO.Path]::GetTempFileName()    # Creates temp file for rsop results

	try {
		Write-Host "Processing Resultant Set of Policy for $ComputerName"
		Get-GPResultantSetOfPolicy -Computer $ComputerName -ReportType xml -Path $tmpXmlFile
	} catch [Exception] {
		Write-Host 'Unable to process Resultant Set of Policy' -ForegroundColor Red
		Pause
		Exit
	}

	$rsop = [xml](Get-Content -Path $tmpXmlFile)
	$domainName = $rsop.Rsop.ComputerResults.Domain
	$rsopKeys = @()

	# Loop through all applied GPOs starting with the last applied
	For ($x = $rsop.Rsop.ComputerResults.Gpo.Name.Count; $x -ge 1; $x--) {
		$rsopTemp = @()
		# Get GPO name
		$gpoResults = ($rsop.Rsop.ComputerResults.Gpo | Where-Object { ($_.Link.AppliedOrder -eq $x) -and ($_.Name -ne 'Local Group Policy') } | Select-Object Name).Name
		If ($null -ne $gpoResults) {
			# If name is not null gets registry keys for that GPO and assign to temp value
			$rsopTemp = Get-GpoKeys -PolicyName $gpoResults -Domain $domainName
			If ($null -eq $Global:ouPath) {
				$Global:ouPath = ($rsop.Rsop.ComputerResults.SearchedSom | Where-Object { $_.Order -eq $x } | Select-Object Path).path
			}
		}
		# foreach registry key value in gpo results
		ForEach ($key in $rsopTemp) {
			# if a value is not already stored with that FullKeyPath and ValueName store that value
			If ($null -eq ($rsopKeys | Where-Object { ($_.FullKeyPath -eq $key.FullKeyPath) -and ($_.ValueName -eq $key.ValueName) })) {
				$rsopKeys += $key
			}
		}
	}

	Remove-Item -Path $tmpXmlFile -Force   # Deletes temp file

	$rsopKeys
}

Function Write-Log {
	[CmdletBinding()]
	Param(
		[Parameter(
			Mandatory = $true)]
		[array]$RegistryKey,
		[Parameter(
			Mandatory = $true)]
		[String]$GPOName
	)

	[String]$logPath = 'gpo_registry_discovery_' + (Get-Date -Format MMddyyyy) + '.log'
	[String]$outString = $GPOName + "`t" + $RegistryKey.FullKeyPath + "`t" + $RegistryKey.ValueName + "`t" + $RegistryKey.Value + "`t" + $RegistryKey.Type
	Out-File -FilePath .\$logPath -InputObject $outString -Force -Append
}

Function WriteXmlToScreen ([xml]$xml) {
	$StringWriter = New-Object System.IO.StringWriter;
	$XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
	$XmlWriter.Formatting = 'indented';
	$xml.WriteTo($XmlWriter);
	$XmlWriter.Flush();
	$StringWriter.Flush();
	Write-Output $StringWriter.ToString();
}

#endregion
##*=============================================
##* END FUNCTION LISTINGS
##*=============================================

##*=============================================
##* SCRIPT BODY
##*=============================================
#region ScriptBody

If ($GroupPolicy) {
	$gpo = Get-GpoKeys -PolicyName $GpoTarget -Domain $DomainTarget
}
# If ResultantSetOfPolicy option is used remove the first index of the array that contains RSOP information
If ($ResultantSetOfPolicy) {
	$gpo = Get-Rsop -ComputerName $ComputerName
	If ($null -ne $gpo[0].RsopMode) {
		$gpo = $gpo[1..($gpo.Length - 1)]
	}
}

If ($null -ne $gpo) {
	# If ResultantSetOfPolicy option is used use the OU path to name the CI
	If ($ResultantSetOfPolicy -eq $true) {
		$ciName = $Global:ouPath
	}
	# If ResultantSetOfPolicy option is not used use the target GPO to name the CI
	ElseIf ($GroupPolicy -eq $true) {
		$ciName = $GpoTarget
	}

	New-CMConfigurationItems -Name $ciName -Description 'This is a GPO compliance settings that was automatically created via PowerShell.' -CreationType 'WindowsOS' -Severity $Severity -RegistryKeys $gpo

	Set-Location $startingDrive

	Write-Host 'Complete'
} Else {
	Write-Host '** ERROR! The script will terminate. **' -ForegroundColor Red
}

#endregion
##*=============================================
##* END SCRIPT BODY
##*=============================================
