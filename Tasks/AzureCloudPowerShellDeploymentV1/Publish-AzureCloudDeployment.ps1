[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [String]$ServiceName,
    [Parameter(Mandatory = $true)]
    [String]$ServiceLocation,
    [Parameter(Mandatory = $true)]
    [String]$StorageAccount,
    [Parameter(Mandatory = $true)]
    [String]$CsPkg,
    [Parameter(Mandatory = $true)]
    [String]$CsCfg
)

try{
    $Slot = Production
    $DeploymentLabel = '$(Build.BuildNumber)'
    $AppendDateTimeToLabel = $false
    $AllowUpgrade = $true
    $SimultaneousUpgrade = $false
    $ForceUpgrade = $false
    $VerifyRoleInstanceStatus = $false
    $DiagnosticStorageAccountKeys = ""
    $NewServiceAdditionalArguments = ""
    $NewServiceAffinityGroup = ""
    $NewServiceCustomCertificates = ""

    $EnableAdvancedStorageOptions = $false
    $ARMConnectedServiceName = ""
    $ARMStorageAccount = ""

    # Initialize Azure.
    Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
    Initialize-Azure

    # Initialize Azure RM connection if required
    if ($EnableAdvancedStorageOptions)
    {
        $endpoint = Get-VstsEndpoint -Name $ARMConnectedServiceName -Require
        Initialize-AzureRMModule -Endpoint $endpoint
    }

    # Load all dependent files for execution
    . $PSScriptRoot/Utility.ps1

    $storageAccountKeysMap = Parse-StorageKeys -StorageAccountKeys $DiagnosticStorageAccountKeys

    Write-Host "Finding $CsCfg"
    $serviceConfigFile = Find-VstsFiles -LegacyPattern "$CsCfg"
    Write-Host "serviceConfigFile= $serviceConfigFile"
    $serviceConfigFile = Get-SingleFile $serviceConfigFile $CsCfg

    Write-Host "Find-VstsFiles -LegacyPattern $CsPkg"
    $servicePackageFile = Find-VstsFiles -LegacyPattern "$CsPkg"
    Write-Host "servicePackageFile= $servicePackageFile"
    $servicePackageFile = Get-SingleFile $servicePackageFile $CsPkg

    Write-Host "##[command]Get-AzureService -ServiceName $ServiceName -ErrorAction SilentlyContinue  -ErrorVariable azureServiceError"
    $azureService = Get-AzureService -ServiceName $ServiceName -ErrorAction SilentlyContinue  -ErrorVariable azureServiceError

    if($azureServiceError){
       $azureServiceError | ForEach-Object { Write-Verbose $_.Exception.ToString() }
    }   


    if (!$azureService)
    {    
        $azureService = "New-AzureService -ServiceName `"$ServiceName`""
        if($NewServiceAffinityGroup) {
            $azureService += " -AffinityGroup `"$NewServiceAffinityGroup`""
        }
        elseif($ServiceLocation) {
             $azureService += " -Location `"$ServiceLocation`""
        }
        else {
            throw "Either AffinityGroup or ServiceLocation must be specified"
        }
        $azureService += " $NewServiceAdditionalArguments"
        Write-Host "$azureService"
        $azureService = Invoke-Expression -Command $azureService

        #Add the custom certificates to the newly created Azure Cloud Service
        $customCertificatesMap = Parse-CustomCertificates -CustomCertificates $NewServiceCustomCertificates
        Add-CustomCertificates $serviceName $customCertificatesMap
    }

    if ($StorageAccount) 
    {
        $diagnosticExtensions = Get-DiagnosticsExtensions $StorageAccount $serviceConfigFile $storageAccountKeysMap
    }
    elseif ($ARMStorageAccount)
    {
        $diagnosticExtensions = Get-DiagnosticsExtensions $ARMStorageAccount $serviceConfigFile $storageAccountKeysMap -UseArmStorage
    }
    else 
    {
        Write-Error -Message "Could not determine storage account type from task input"
    }

    $label = $DeploymentLabel

    if ($label -and $AppendDateTimeToLabel)
    {
        $label += " "
        $label += [datetime]::now
    }

    Write-Host "##[command]Get-AzureDeployment -ServiceName $ServiceName -Slot $Slot -ErrorAction SilentlyContinue -ErrorVariable azureDeploymentError"
    $azureDeployment = Get-AzureDeployment -ServiceName $ServiceName -Slot $Slot -ErrorAction SilentlyContinue -ErrorVariable azureDeploymentError

    if($azureDeploymentError) {
       $azureDeploymentError | ForEach-Object { Write-Verbose $_.Exception.ToString() }
    }

    if (!$azureDeployment)
    {
        if ($label)
        {
            Write-Host "##[command]New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration <extensions>"
            $azureDeployment = New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration $diagnosticExtensions
        }
        else
        {
            Write-Host "##[command]New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration <extensions>"
            $azureDeployment = New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration $diagnosticExtensions
        }
    }
    elseif ($AllowUpgrade -eq $true -and $SimultaneousUpgrade -eq $true -and $ForceUpgrade -eq $true)
    {
        #Use -Upgrade -Mode Simultaneous -Force
        if ($label)
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -Label $label -ExtensionConfiguration <extensions> -Force"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -Label $label -ExtensionConfiguration $diagnosticExtensions -Force
        }
        else
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -ExtensionConfiguration <extensions> -Force"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -ExtensionConfiguration $diagnosticExtensions -Force
        }
    }
    elseif ($AllowUpgrade -eq $true -and $SimultaneousUpgrade -eq $true)
    {
        #Use -Upgrade -Mode Simultaneous
        if ($label)
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -Label $label -ExtensionConfiguration <extensions>"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -Label $label -ExtensionConfiguration $diagnosticExtensions
        }
        else
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -ExtensionConfiguration <extensions>"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Mode Simultaneous -ExtensionConfiguration $diagnosticExtensions
        }
    }
    elseif ($AllowUpgrade -eq $true -and $ForceUpgrade -eq $true)
    {
        #Use -Upgrade
        if ($label)
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration <extensions> -Force"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration $diagnosticExtensions -Force
        }
        else
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration <extensions> -Force"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration $diagnosticExtensions -Force
        }
    }
    elseif ($AllowUpgrade -eq $true) 
    {
        #Use -Upgrade
        if ($label)
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration <extensions>"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration $diagnosticExtensions
        }
        else
        {
            Write-Host "##[command]Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration <extensions>"
            $azureDeployment = Set-AzureDeployment -Upgrade -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration $diagnosticExtensions
        }
    }
    else
    {
        #Remove and then Re-create
        Write-Host "##[command]Remove-AzureDeployment -ServiceName $ServiceName -Slot $Slot -Force"
        $azureOperationContext = Remove-AzureDeployment -ServiceName $ServiceName -Slot $Slot -Force
        if ($label)
        {
            Write-Host "##[command]New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration <extensions>"
            $azureDeployment = New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -Label $label -ExtensionConfiguration $diagnosticExtensions
        }
        else
        {
            Write-Host "##[command]New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration <extensions>"
            $azureDeployment = New-AzureDeployment -ServiceName $ServiceName -Package $servicePackageFile -Configuration $serviceConfigFile -Slot $Slot -ExtensionConfiguration $diagnosticExtensions
        }
    }

    if ($VerifyRoleInstanceStatus -eq $true)
    {
        Validate-AzureCloudServiceStatus -CloudServiceName $ServiceName -Slot $Slot
    }
} finally {
	Trace-VstsLeavingInvocation $MyInvocation
}

