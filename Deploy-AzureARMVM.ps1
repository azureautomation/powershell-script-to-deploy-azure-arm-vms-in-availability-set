#Requires -Version 5
#Requires -Modules @{ ModuleName = 'Azure'; ModuleVersion = '3.0.0' }
#Requires -RunAsAdministrator


<#
Powershell script/function to provision Azure VM(s) in ARM mode
For more information see http://www.exigent.net/blog/microsoft-azure/provisioning-and-tearing-down-azure-virtual-machines/
Sam Boutros      3 January 2017 - v1.0 - Initial release
                19 January 2017 - v2.0 
                    Updated parameters - set to mandatory
                    Updated Storage Account creation region, create a separate storage account for each VM
                    Updated Initialize region; removing subscription login, adding input echo, adding error handling
                    Added functionality to configure VMs in availability set
#>


#region Input
[CmdletBinding(ConfirmImpact='Low')] 
Param(
    [Parameter(Mandatory=$true)][String]$SubscriptionName         , # Example: 'Sam Test 1'      # Name of existing Azure subscription
    [Parameter(Mandatory=$true)][String]$Location                 , # Example: 'eastus'          # Get-AzureRmLocation | sort Location | Select Location
    [Parameter(Mandatory=$true)][String]$ResourceGroup            , # Example: 'VMGroup17'       # To be created if not exist
    [Parameter(Mandatory=$false)][String]$AvailabilitySetName     , # Example: 'Availability17'  # To be created if not exist
    [Parameter(Mandatory=$false)][Switch]$ConfirmShutdown = $false, # If adding existing VMs to Availaibility set, the script must shut down the VMs
    [Parameter(Mandatory=$false)][String]$StorageAccountPrefix    , # To be created if not exist, only lower case letters and numbers, must be Azure unique 
    [Parameter(Mandatory=$true)][String]$AdminName                , # Example: 'myAdmin17'       # This will be the new VM local administrator 
    [Parameter(Mandatory=$true)][String[]]$VMName                 , # Example: ('vm01','vm02')   # Name(s) of VM(s) to be created. Each is 15 characters maximum. If VMs exist, they will be added to Availability Set
    [Parameter(Mandatory=$true)][String]$VMSize                   , # Example: 'Standard_A1_v2'  # (Get-AzureRoleSize).RoleSizeLabel to see available sizes in this Azure location 
    [Parameter(Mandatory=$true)][String]$vNetName                 , # Example: 'Seventeen'       # This will be the name of the virtual network to be created/updated if exist
    [Parameter(Mandatory=$true)][String]$vNetPrefix               , # Example: '10.17.0.0/16'    # To be created/updated
    [Parameter(Mandatory=$true)][String]$SubnetName               , # Example: 'vmSubnet'        # This will be the name of the subnet to be created/updated
    [Parameter(Mandatory=$true)][String]$SubnetPrefix               # Example: '10.17.0.0/24'    # Must be subset of vNetPrefix above - to be created/updated
)
#endregion


#region Initialize
Write-Output 'Input received:'
Write-Output "    SubscriptionName:     '$SubscriptionName'"
Write-Output "    Location:             '$Location'"
Write-Output "    ResourceGroup:        '$ResourceGroup'"
Write-Output "    AvailabilitySetName:  '$AvailabilitySetName'"
Write-Output "    ConfirmShutdown:      '$ConfirmShutdown'"
Write-Output "    StorageAccountPrefix: '$StorageAccountPrefix'"
Write-Output "    AdminName:            '$AdminName'"
Write-Output "    VMName(s):            '$($VMName -join ', ')'"
Write-Output "    VMSize:               '$VMSize'"
Write-Output "    vNetName:             '$vNetName'"
Write-Output "    vNetPrefix:           '$vNetPrefix'"
Write-Output "    SubnetName:           '$SubnetName'"
Write-Output "    SubnetPrefix:         '$SubnetPrefix'" 

#region Connect to Azure subscription
try { 
        Get-AzureRmSubscription –SubscriptionName $SubscriptionName -ErrorAction Stop | Select-AzureRmSubscription
        Write-Output "Connected to Azure Subscription '$SubscriptionName'"
    } catch {
        throw "unable to get Azure Subscription '$SubscriptionName'"
    }
#endregion

#region Create/Update Resource group
try {
    New-AzureRmResourceGroup -Name $ResourceGroup -Location $Location -Force -ErrorAction Stop
    Write-Output "Created/Updated Resource Group '$ResourceGroup'"
} catch {
    throw "Failed to create Resource Group '$ResourceGroup'"
}
#endregion 

#region Get VM Admin credentials
function Get-SBCredential {
<# 
 .SYNOPSIS
  Function to get AD credential, save encrypted password to file for future automation

 .DESCRIPTION
  Function to get AD credential, save encrypted password to file for future automation
  The function will use saved password if the password file exists
  The function will prompt for the password if the password file does not exist, 
    or the -Refresh switch is used
  Note that the function does not validate whether the UserName exists in any directory,
  or that the password entered is valid. It merely creates a Credential object to be used 
  securely for future automation, eleminating the need to type in the password everytime
  the function is needed, or the need to type in password in clear text in scripts.

 .PARAMETER UserName
  This can be in the format 'myusername' or 'domain\username'
  If not provided, the function assumes username under which the function is executed
  
 .PARAMETER Refresh
  This switch will force the function to prompt for the password and over-write the password file

 .OUTPUTS 
  The function returns a PSCredential object that can be used with other cmdlets that use the -Credential parameter

 .EXAMPLE
  $MyCred = Get-SBCredential

 .EXAMPLE
  $Cred2 = Get-SBCredential -UserName 'sboutros' -Verbose -Refresh

 .EXAMPLE
  $Cred3 = 'domain2\ADSuperUser' | Get-SBCredential
  Disable-ADAccount -Identity 'Someone' -Server 'MyDomainController' -Credential $Cred3
  This example obtains and saves credential of 'domain2\ADSuperUser' in $Cred3 varialble
  Second line uses that credential to disable an AD account of 'Someone' 

 .NOTES
  Sam Boutros - 5 August 2016 - v1.0
  For more information see
  https://superwidgets.wordpress.com/2016/08/05/powershell-script-to-provide-a-ps-credential-object-saving-password-securely/

#>

    [CmdletBinding(ConfirmImpact='Low')] 
    Param(
        [Parameter(Mandatory=$false,
                   ValueFromPipeLine=$true,
                   ValueFromPipeLineByPropertyName=$true,
                   Position=0)]
            [String]$UserName = "$env:USERDOMAIN\$env:USERNAME", 
        [Parameter(Mandatory=$false,
                   Position=1)]
            [Switch]$Refresh = $false
    )

    $CredPath = "$env:Temp\$($UserName.Replace('\','_')).txt"
    if ($Refresh) { 
        try {
            Remove-Item -Path $CredPath -Force -Confirm:$false -ErrorAction Stop
            Write-Verbose "Deleted password file '$CredPath'"
        } catch {
             Write-Error "Failed to delete password file '$CredPath'"
        }
    } 
    if (!(Test-Path -Path $CredPath)) {
        $Temp = Read-Host "Enter the pwd for $UserName" -AsSecureString | ConvertFrom-SecureString 
        try {
            $Temp | Out-File $CredPath -ErrorAction Stop
            Write-Verbose "Wrote to password file '$CredPath'"
        } catch {
            Write-Error "Failed to write to password file '$CredPath'"
        }
    }
    $Pwd = Get-Content $CredPath | ConvertTo-SecureString 
    try {
        New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, $Pwd -ErrorAction Stop
        Write-Verbose "'$UserName' crednetial obtained successfully"
    } catch {
        Write-Error "Failed to obtain credential for $UserName"
    }
}
$Cred = Get-SBCredential -UserName $AdminName 
#endregion

#region Create/Update Subnet and vNet
Write-Output "Creating/updating vNet '$vNetName' '$vNetPrefix' and subnet '$SubnetName' '$SubnetPrefix'"
$Subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetPrefix
$vNet = New-AzureRmVirtualNetwork -Name $vNetName -ResourceGroupName $ResourceGroup -Location $Location -AddressPrefix $vNetPrefix -Subnet $Subnet -Force
#endregion

#endregion


foreach ($Name in $VMName) { # Provision Azure VM(s)

#region Create Storage Account if it does not exist in this Resource Group
    $StorageAccountName = "stor$($StorageAccountPrefix.ToLower())$($Name.ToLower())"
    if ($StorageAccountName.Length -gt 20) { 
        Write-Output "Storage account name '$StorageAccountName' is too long, using first 20 characters only.."
        $StorageAccountName = $StorageAccountName.Substring(0,19) 
    }  
    Write-output "Creating Storage Account '$StorageAccountName'"
    try {
        $StorageAccount = Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup -ErrorAction Stop
        Write-Output "Using existing storage account '$StorageAccountName'"
    } catch {
        $i=0
        $DesiredStorageAccountName = $StorageAccountName
        while (!(Get-AzureRmStorageAccountNameAvailability $StorageAccountName).NameAvailable) {
            $i++
            $StorageAccountName = "$StorageAccountName$i"
        }
        if ($DesiredStorageAccountName -ne $StorageAccountName ) {
            Write-Output "Storage account '$DesiredStorageAccountName' is taken, using '$StorageAccountName' instead (available)"
        }
        try {
            $Splatt = @{
                ResourceGroupName = $ResourceGroup
                Name              = $StorageAccountName 
                SkuName           = 'Standard_LRS' 
                Kind              = 'Storage' 
                Location          = $Location 
                ErrorAction       = 'Stop'
            }
            $StorageAccount = New-AzureRmStorageAccount @Splatt
            Write-Output "Created storage account $StorageAccountName"
        } catch {
            throw "Failed to create storage account $StorageAccountName"
        }
    }
#endregion 

#region Create/validate Availability Set
    if ($AvailabilitySetName) {
        Write-Output "Creating/verifying Availability Set '$AvailabilitySetName'"
        try {
            $AvailabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroup -Name $AvailabilitySetName -ErrorAction Stop
            Write-Output "Availability Set '$AvailabilitySetName' already exists"
            Write-Output ($AvailabilitySet | Out-String)
        } catch {
            try {
                $AvailabilitySet = New-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroup -Name $AvailabilitySetName -Location $Location -ErrorAction Stop
                Write-Output "Created Availability Set '$AvailabilitySetName'"
            } catch {
                throw "Failed to create Availability Set '$AvailabilitySetName'"
            }
        }
        if ($AvailabilitySet.Location -ne $Location) {
            throw "Unable to proceed, Availability set must be in the same location '$($AvailabilitySet.Location)' as the desired VM location '$Location'"
        }
    }
#endregion

    try {
        $ExistingVM = Get-AzureRmVM -ResourceGroupName $ResourceGroup -Name $Name -ErrorAction Stop
        Write-Output "VM '$($ExistingVM.Name)' already exists"
        if ($AvailabilitySetName) {
            if ($ConfirmShutdown) {
                Write-Output "Shutting down VM '$Name' to add it to Availability set '$AvailabilitySetName'"
                Stop-AzureRmVM -Name $Name -Force -StayProvisioned -ResourceGroupName $ResourceGroup -Confirm:$false

                # Remove current VM 
                Remove-AzureRmVM -ResourceGroupName $ResourceGroup -Name $Name -Force -Confirm:$false

                # Prepare to recreate VM
                $VM = New-AzureRmVMConfig -VMName $ExistingVM.Name -VMSize $ExistingVM.HardwareProfile.VmSize -AvailabilitySetId $AvailabilitySet.Id
                Set-AzureRmVMOSDisk -VM $VM -VhdUri $ExistingVM.StorageProfile.OsDisk.Vhd.Uri -Name $ExistingVM.Name -CreateOption Attach -Windows

                #Add Data Disks
                foreach ($Disk in $ExistingVM.StorageProfile.DataDisks ) { 
                    Add-AzureRmVMDataDisk -VM $VM -Name $Disk.Name -VhdUri $Disk.Vhd.Uri -Caching $Disk.Caching -Lun $Disk.Lun -CreateOption Attach -DiskSizeInGB $Disk.DiskSizeGB
                }

                #Add NIC(s)
                foreach ($NIC in $ExistingVM.NetworkInterfaceIDs) {
                    Add-AzureRmVMNetworkInterface -VM $VM -Id $NIC
                }

                # Recreate the VM as part of the Availability Set
                New-AzureRmVM -ResourceGroupName $ResourceGroup -Location $ExistingVM.Location -VM $VM -DisableBginfoExtension
            } else {
                throw "To add existing VM(s) to availability set, the VM(s) must be shut down. Use the '-ConfirmShutdown:$('$')true' switch"
            }
        }
    } catch {
        Write-Output "Preparing to create new VM '$Name'"

        Write-Output "Requesting/updating public IP address assignment '$Name-PublicIP'" 
        $PublicIp = New-AzureRmPublicIpAddress -Name "$Name-PublicIP" -ResourceGroupName $ResourceGroup -Location $Location -AllocationMethod Dynamic -Force

        Write-Output "Provisining/updating vNIC '$Name-vNIC'"
        $vNIC = New-AzureRmNetworkInterface -Name "$Name-vNIC" -ResourceGroupName $ResourceGroup -Location $Location -SubnetId $vNet.Subnets[0].Id -PublicIpAddressId $PublicIp.Id -Force

        Write-Output "Provisioning VM configuration object for VM '$Name'"
        if ($AvailabilitySetName) {
            $VM = New-AzureRmVMConfig -VMName $Name -VMSize $VMSize -AvailabilitySetId $AvailabilitySet.Id
        } else {
            $VM = New-AzureRmVMConfig -VMName $Name -VMSize $VMSize 
        }

        Write-Output "Configuring VM OS (Windows), '$($Cred.UserName)' local admin "
        $VM = Set-AzureRmVMOperatingSystem -VM $VM -Windows -ComputerName $Name -Credential $Cred -ProvisionVMAgent -EnableAutoUpdate

        Write-Output 'Selecting VM image - Latest 2012-R2-Datacenter'
        $VM = Set-AzureRmVMSourceImage -VM $VM -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2012-R2-Datacenter" -Version "latest"

        Write-Output 'Adding vNIC'
        $VM = Add-AzureRmVMNetworkInterface -VM $VM -Id $vNIC.Id 

        Write-Output "Configuring OS Disk"
        $VhdUri = "$($StorageAccount.PrimaryEndpoints.Blob.ToString())vhds/$($Name)-OsDisk1.vhd"
        $VM = Set-AzureRmVMOSDisk -VM $VM -Name 'OSDisk' -VhdUri $VhdUri -CreateOption FromImage

        Write-Output 'Creating VM'
        New-AzureRmVM -ResourceGroupName $ResourceGroup -Location $Location -VM $VM 
        Get-AzureRmVM | where { $_.Name -eq $Name } | FT -a 
    }
}

if ($AvailabilitySetName) {
    $AvailabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroup -Name $AvailabilitySetName
    $VMDomains = @() 
    $AvailabilitySet.VirtualMachinesReferences | % { 
        $VM = Get-AzureRMVM -Name (Get-AzureRmResource -Id $_.id).Name -ResourceGroup $ResourceGroup -Status
        $VMDomains += [PSCustomObject]@{'Name'=$VM.Name; 'FaultDomain'=$VM.PlatformFaultDomain; 'UpdateDomain'=$VM.PlatformUpdateDomain}
    }
    $VMDomains | sort Name | FT -a 
} 