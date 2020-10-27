Powershell script to deploy Azure ARM VMs in Availability Set
=============================================================

            

**Version 2 added 20 January 2017**


A few enhancements have been added in this version. Most notably, the ability to deploy Azure RM VMs in Availability Set. The script can work on existing or new VMs, on existing or new Availability Set. It can be used to added existing VMs to noew or existing
 Availability Set. For more information see this port.




 





This script deploys one or many VMs in Azure using the new Azure Resource Manager mode. Before you start you need access to an Azure subscription. 


The script has been tested with Powershell version 5, and requires Azure Powershell which can be downloaded and installed from the [Microsoft Web Platform installer](https://www.microsoft.com/web/downloads/platform.aspx?lang=)



PowerShell
Edit|Remove
powershell
#Requires -Version 5
#Requires -Modules @{ ModuleName = 'Azure'; ModuleVersion = '3.3.0' }
#Requires -RunAsAdministrator


<#
Powershell script/function to provision Azure VM(s) in ARM mode
For more information see 
Sam Boutros - 3 January 2017
#>

#Requires -Version 5 
#Requires -Modules @{ ModuleName = 'Azure'; ModuleVersion = '3.3.0' } 
#Requires -RunAsAdministrator 
 
 
<# 
Powershell script/function to provision Azure VM(s) in ARM mode 
For more information see  
Sam Boutros - 3 January 2017 
#>




The script takes the following parameters:


  *  SubscriptionName: Name of existing Azure subscription 
  *  Location: name of Azure location (datacenter) 
  *  ResourceGroup: To be created if not exist 
  *  StorageAccountName: To be created if not exist, only lower case letters and numbers, must be Azure unique

  *  AdminName: This will be the new VM local administrator  
  *  VMName: Name(s) of VM(s) to be created. Each has 15 charachters maximum 

  *  VMSize: Size of Azure VM which determines its resources 
  *  vNetName: This will be the name of the virtual network to be created/updated if exist  

  *  vNetPrefix: To be created/updated    
  *  SubnetName: This will be the name of the subnet to be created/updated  
  *  SubnetPrefix: Must be subset of vNetPrefix above) 

For more information on [Azure Migration Services](http://www.exigent.net/cloud-services-solutions/azure-consulting-services/) see Exigent's [Azure Consultants](http://www.exigent.net/cloud-services-solutions/azure-consulting-services/) page.


        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
