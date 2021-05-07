# CHANGELOG

## New Maintainer

### v1.3.0 (2021/05/06)

* Forked from Sam's Repo. Thanks, Sam!
* Update repo information all over the place.
* Move Change Log to dedicated CHANGELOG.md.
* General linting all across files.
* Add header information to Convert-GPOtoCI.ps1
* Update nomenclature from "SCCM" to "CM" as necessary.
  * New-SCCMConfigurationItemsetting -> New-CMConfigurationItemsetting
  * New-SCCMConfigurationItemRule -> New-CMConfigurationItemRule
  * New-SCCMConfigurationItems -> New-CMConfigurationItems
* Add regions to script structure for readablity.

---

## Old Maintainer

### v 1.2.7 (12/15/2018)

* Fixed an issue where multi string values did not work

### v 1.2.6 (11/6/2017)

* Bug fixes.
* Allow for creation of User Policy based CIs.

### v 1.2.4 (9/18/2017)

* Fixed bug where registry values were always being logged to file even when the -Log switch was not set.

### v 1.2.3 (9/18/2017)

* Added the -Log switch that will log all discovered registry keys and their related Group Policy object to a file named gpo_registry_discovery_mmddyyyy.log in the scripts root directory.

### v 1.2.1 (7/17/2017)

* Added -ResultantSetOfPolicy parameter to enable to script to run RSOP against a system to determine the applied group policies then query for all registry keys associated with the applicable policies and settings.

### v 1.1.1 (7/12/2017)

* Added -ExportOnly switch that will export the Configuration Item data to a .CAB file instead of automatically creating the CIs. This file can be used to import the CI into ConfigMgr.
