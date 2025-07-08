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
        Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" | Out-Null
    }
    catch {
        Write-Error "Failed to send Telegram message: $_"
    }
}
