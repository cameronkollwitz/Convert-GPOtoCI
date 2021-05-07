# Convert-GPOtoCI

This script uses both the Configuration Manager and Active Directory PowerShell modules to query for registry keys associated with Group Policies then create the Configuration Items for each of the registry values.

The script will either query for a single group policy or utilize a Resultant Set of Policy to determine applicable policies for a specified system.

To enable the Resultant Set of Policy (RSOP) option include the `ResultantSetOfPolicy` parameter and specify the system to run RSOP against using the `ComputerName` parameter. Leveraging the Active Directory PowerShell module and the Get-GPResultantSetOfPolicy command the script will run an RSOP on a specified system and export the results to a temporary file. The file is then searched to determine what group policies are applied to the system and what the link order is for those policies. This will be used to determine what order the group policy data is queried to simulate their link order. If the `ResultantSetOfPolicy` option is not used this step is skipped and the script will query only for the one group policy specified.

To get a list of registry keys associated with the group policies the Get-GPRegistryValue command is used to query for the specified group policies. The full key path, key name, value and data type are all stored in an array. When the 'ResultantSetOfPolicy' option is used the group policies will be queried starting with the policy that would be applied last. As each additional policy is queried the script will check to see if that registry key has already been stored with another value. If the registry key is already present, the additional occurrence of that key will be skipped since the policy that is last applied would over write the lower policies. If the 'ResultantSetOfPolicy' option is not used the script will only query for the one policy specified.

When the script has successfully queried for all the associated registry keys and values it utilized the Configuration Manager PowerShell module to create the Configuration Item definition files in xml format. This will include a setting and rule for each of the registry keys of supported data type (binary values are not supported by DCM). You can specify the severity of non-compliant settings as well as remediation of non-compliant items using command line parameters.

Finally, the script will import the Configuration Item definition file into Configuration Manager. By default, this is done automatically, creating a CI with settings and rules for all associated registry values. If you do not wish to have this automatically created you can use the `ExportOnly` parameter which will save the data to a .cab file which can later be manually imported into Configuration Manager.

## Instructions

This script must be executed from a system that has access to both the GroupPolicy and ConfigurationManager PowerShell modules. The GroupPolicy module is installed with the Remote Admin Tools and the ConfigurationManager module is installed with the ConfigMgr Admin Console. Additionally, if the `ResultantSetOfPolicy` option is used the user must have remote admin access to that system. Extract the .ZIP file and execute the PowerShell script via a PS console.

### Parameters

**GroupPolicy** _[optional]_ - This is enabled by default and will make the script query only for one specified group policy.

**GpoTarget** _[required unless ResultantSetOfPolicy option is used]_ - Name of group policy object

**ResultantSetOfPolicy** _[optional]_ - Utilizes a resultant set of policy to determine the set of applied GPOs. Cannot be used in conjunction with the GroupPolicy option.

**ComputerName** _[required when ResultantSetOfPolicy is used]_ - Name of system to run RSOP on.

**DomainTarget** _[required]_ - Fully qualified domain name

**SiteCode** _[required]_ - ConfigMgr site code

**Remediate** _[optional]_ - Enable configuration item to remediate non-compliant settings

**Severity** _[optional]_ - Sets the severity of non-compliant items. (None, Informational, Warning or Critical)

**ExportOnly** _[optional]_ - Exports the Configuration Item to a CAB file to be manually imported

**Log** _[optional]_ - Writes all discovered registry keys and their related GPO name to a file.

#### Example 1

.\Convert-GPOtoCI.ps1 -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ

#### Example 2

.\Convert-GPOtoCI.ps1 -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ -Remediate

#### Example 3

.\Convert-GPOtoCI.ps1 -GroupPolicy -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ -Severity Warning

#### Example 4

.\Convert-GPOtoCI.ps1 -ResultantSetOfPolicy -ComputerName MyDevice01 -DomainTarget kollwitz.local -SiteCode KWZ

#### Example 5

.\Convert-GPOtoCI.ps1 -GpoTarget "Windows 10 Settings" -DomainTarget kollwitz.local -SiteCode KWZ -ExportOnly

### Tested With

Configuration Manager 2103, Configuration Manager 2104 (Technical Preview)
