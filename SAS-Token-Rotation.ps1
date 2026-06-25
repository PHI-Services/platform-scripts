param (
    [Parameter(Mandatory=$true)]
    [string]$subscriptionid = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",

    [Parameter(Mandatory=$true)]
    [string]$resourcegroupname = "resource-group-name",

    [Parameter(Mandatory=$true)]
    [string]$storageaccountname = "storage-account-name",

    [Parameter(Mandatory=$true)]
    [string]$containername = "container-name",

    [Parameter(Mandatory=$true)]
    [string]$keyvaultname = "key-vault-name",

    [Parameter(Mandatory=$true)]
    [string]$secretname = "secret-name",

    [Parameter(Mandatory=$false)]
    [int]$expiryindays = 180
)

try {
    Write-Output "===== SAS Token Rotation Runbook Started ====="

    # --------------------------------------------------
    # Authenticate using Managed Identity
    # --------------------------------------------------
    Write-Output "Authenticating using Managed Identity..."
    Connect-AzAccount -Identity | Out-Null

    Set-AzContext -SubscriptionId $subscriptionid | Out-Null
    Write-Output "Connected to subscription: $subscriptionid"

    # --------------------------------------------------
    # Get Storage Account Context
    # --------------------------------------------------
    Write-Output "Retrieving storage account context..."
    $storageAccount = Get-AzStorageAccount `
        -ResourceGroupName $resourcegroupname `
        -Name $storageaccountname

    if (-not $storageAccount) {
        throw "Storage account not found: $storageaccountname"
    }

    $ctx = $storageAccount.Context

    # --------------------------------------------------
    # Generate SAS Token
    # --------------------------------------------------
    Write-Output "Generating SAS token..."

    $expiryTime = (Get-Date).ToUniversalTime().AddDays($expiryindays)

    $sasToken = New-AzStorageContainerSASToken `
        -Name $containername `
        -Context $ctx `
        -Permission "racwdl" `
        -ExpiryTime $expiryTime

    if (-not $sasToken) {
        throw "Failed to generate SAS token"
    }

    Write-Output "SAS token generated successfully. Expiry: $expiryTime"

    # --------------------------------------------------
    # Construct SAS URL
    # --------------------------------------------------
    Write-Output "Constructing SAS URL..."

    $containerUrl = $storageAccount.PrimaryEndpoints.Blob + $containername
    $sasUrl = "$containerUrl$sasToken"

    Write-Output "SAS URL constructed successfully"

    # --------------------------------------------------
    # Store in Key Vault (new version)
    # --------------------------------------------------
    Write-Output "Updating Key Vault secret..."

    $secureValue = ConvertTo-SecureString $sasUrl -AsPlainText -Force

    $secret = Set-AzKeyVaultSecret `
        -VaultName $keyvaultname `
        -Name $secretname `
        -SecretValue $secureValue `
        -Expires $expiryTime `
        -ContentType "SAS URL - auto rotated"

    if (-not $secret) {
        throw "Failed to update Key Vault secret"
    }

    Write-Output "Key Vault secret updated successfully"
    Write-Output "New Secret Version: $($secret.Version)"

    # --------------------------------------------------
    # Summary
    # --------------------------------------------------
    Write-Output "===== Summary ====="
    Write-Output "Storage Account : $storageaccountname"
    Write-Output "Container       : $containername"
    Write-Output "Key Vault       : $keyvaultname"
    Write-Output "Secret Name     : $secretname"
    Write-Output "Expiry (UTC)    : $expiryTime"

    Write-Output "===== SAS Token Rotation Completed Successfully ====="
}
catch {
    Write-Error "Runbook failed: $_"
    throw
}
