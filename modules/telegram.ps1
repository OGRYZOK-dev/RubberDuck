function Send-TelegramMessage {
    param (
        [string]$Token,
        [string]$ChatID,
        [string]$Message
    )
    
    $url = "https://api.telegram.org/bot$Token/sendMessage"
    $body = @{
        chat_id = $ChatID
        text = $Message
    }
    
    try {
        $jsonBody = $body | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -TimeoutSec 5
        return $true
    }
    catch {
        Write-Output "Telegram API Error: $_"
        return $false
    }
}
