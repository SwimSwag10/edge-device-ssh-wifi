# PowerShell script to generate an ed25519 keypair on Windows.
$KEY_PATH = "$HOME\.ssh\id_ed25519"

# To run: Open PowerShell, navigate to the admin folder, and execute ./generate_keys.ps1
# OR:
# ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "dental-admin@office"

if (Test-Path $KEY_PATH) {
    Write-Output "Key already exists at $KEY_PATH"
    Write-Output "Public key: $($KEY_PATH).pub"
    Get-Content "$($KEY_PATH).pub"
    exit 0
}

ssh-keygen -t ed25519 -f $KEY_PATH -C "dental-admin@office" -N ""
Write-Output "Generated keypair. Public key at $($KEY_PATH).pub"
Get-Content "$($KEY_PATH).pub"