param (
    [Parameter(Mandatory=$true)]
    [string]$subscriptionId = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",

    [Parameter(Mandatory=$true)]
    [string]$resourceGroupName = "resource-group-name",

    [Parameter(Mandatory=$true)]
    [string]$storageAccountName = "storage-account-name",

    [Parameter(Mandatory=$true)]
    [string]$containerName = "container-name",

    [Parameter(Mandatory=$true)]
    [string]$keyVaultName = "key-vault-name",

    [Parameter(Mandatory=$true)]
    [string]$secretName = "secret-name",

    [Parameter(Mandatory=$false)]
    [int]$expiryindays = 180
)

try {
    Write-Output "===== SAS Token Rotation Runbook Started ====="
    
    # Ensure Az modules are loaded
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.Resources -ErrorAction Stop
    Import-Module Az.Storage -ErrorAction Stop

    # --------------------------------------------------
    # Authenticate using Managed Identity
    # --------------------------------------------------
    Write-Output "Authenticating using Managed Identity..."
    Connect-AzAccount -Identity | Out-Null

    Set-AzContext -SubscriptionId $subscriptionId | Out-Null
    Write-Output "Connected to subscription: $subscriptionId"

    # --------------------------------------------------
    # Get Storage Account Context
    # --------------------------------------------------
    Write-Output "Retrieving storage account context..."
    $storageAccount = Get-AzStorageAccount `
        -ResourceGroupName $resourceGroupName `
        -Name $storageAccountName

    if (-not $storageAccount) {
        throw "Storage account not found: $storageAccountName"
    }

    $ctx = $storageAccount.Context

    # --------------------------------------------------
    # Generate SAS Token
    # --------------------------------------------------
    Write-Output "Generating SAS token..."

    $expiryTime = (Get-Date).ToUniversalTime().AddDays($expiryindays)

    $sasToken = New-AzStorageContainerSASToken `
        -Name $containerName `
        -Context $ctx `
        -Permission "racwdl" `
        -ExpiryTime $expiryTime `
        -FullUri

    if (-not $sasToken) {
        throw "Failed to generate SAS token"
    }

    Write-Output "SAS token generated successfully. Expiry: $expiryTime"

    # --------------------------------------------------
    # Store in Key Vault (new version)
    # --------------------------------------------------
    Write-Output "Adding Keyvault Firewall Rule..."
    
    $agentIp = (Invoke-RestMethod -Uri "http://ipinfo.io/json").ip

    Write-Output "Adding Keyvault Firewall Rule for IP $agentIp"
    Add-AzKeyVaultNetworkRule -VaultName $keyVaultName -IpAddress $agentIp -ErrorAction SilentlyContinue

    try {
        Write-Output "Updating Key Vault secret..."

        $secureValue = ConvertTo-SecureString $sasToken -AsPlainText -Force

        $secret = Set-AzKeyVaultSecret `
            -VaultName $keyVaultName `
            -Name $secretName `
            -SecretValue $secureValue `
            -Expires $expiryTime `
            -ContentType "SAS URL - auto rotated"

        if (-not $secret) {
            throw "Failed to update Key Vault secret"
        }

        Write-Output "Key Vault secret updated successfully"
        Write-Output "New Secret Version: $($secret.Version)"
    }
    catch {
        Write-Error "Failed to add Keyvault Firewall Rule or update secret: $_"
        throw
    }
    finally { 
        Write-Output "Cleaning up firewall rule for IP $agentIp"
        Remove-AzKeyVaultNetworkRule -VaultName $keyVaultName -IpAddress $agentIp -ErrorAction SilentlyContinue
    }

    # --------------------------------------------------
    # Summary
    # --------------------------------------------------
    Write-Output "===== Summary ====="
    Write-Output "Storage Account : $storageAccountName"
    Write-Output "Container       : $containerName"
    Write-Output "Key Vault       : $keyVaultName"
    Write-Output "Secret Name     : $secretName"
    Write-Output "Expiry (UTC)    : $expiryTime"

    Write-Output "===== SAS Token Rotation Completed Successfully ====="
}
catch {
    Write-Error "Runbook failed: $_"
    throw
}
