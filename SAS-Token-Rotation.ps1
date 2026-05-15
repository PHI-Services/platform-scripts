param (
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName = "resource-group-name",

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName = "storage-account-name",

    [Parameter(Mandatory=$true)]
    [string]$ContainerName = "container-name",

    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName = "key-vault-name",

    [Parameter(Mandatory=$true)]
    [string]$SecretName = "secret-name",

    [Parameter(Mandatory=$false)]
    [int]$ExpiryInDays = 180
)

try {
    Write-Output "===== SAS Token Rotation Runbook Started ====="

    # --------------------------------------------------
    # Authenticate using Managed Identity
    # --------------------------------------------------
    Write-Output "Authenticating using Managed Identity..."
    Connect-AzAccount -Identity | Out-Null

    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    Write-Output "Connected to subscription: $SubscriptionId"

    # --------------------------------------------------
    # Get Storage Account Context
    # --------------------------------------------------
    Write-Output "Retrieving storage account context..."
    $storageAccount = Get-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName `
        -Name $StorageAccountName

    if (-not $storageAccount) {
        throw "Storage account not found: $StorageAccountName"
    }

    $ctx = $storageAccount.Context

    # --------------------------------------------------
    # Generate SAS Token
    # --------------------------------------------------
    Write-Output "Generating SAS token..."

    $expiryTime = (Get-Date).ToUniversalTime().AddDays($ExpiryInDays)

    $sasToken = New-AzStorageContainerSASToken `
        -Name $ContainerName `
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

    $containerUrl = $storageAccount.PrimaryEndpoints.Blob + $ContainerName
    $sasUrl = "$containerUrl$sasToken"

    Write-Output "SAS URL constructed successfully"

    # --------------------------------------------------
    # Store in Key Vault (new version)
    # --------------------------------------------------
    Write-Output "Updating Key Vault secret..."

    $secureValue = ConvertTo-SecureString $sasUrl -AsPlainText -Force

    $secret = Set-AzKeyVaultSecret `
        -VaultName $KeyVaultName `
        -Name $SecretName `
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
    Write-Output "Storage Account : $StorageAccountName"
    Write-Output "Container       : $ContainerName"
    Write-Output "Key Vault       : $KeyVaultName"
    Write-Output "Secret Name     : $SecretName"
    Write-Output "Expiry (UTC)    : $expiryTime"

    Write-Output "===== SAS Token Rotation Completed Successfully ====="
}
catch {
    Write-Error "Runbook failed: $_"
    throw
}
