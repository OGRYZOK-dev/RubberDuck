function Get-WifiPasswords {
    $output = @()
    $wifiProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
    
    foreach ($profile in $wifiProfiles) {
        $profileInfo = netsh wlan show profile name="$profile" key=clear
        $password = ($profileInfo | Select-String "Key Content").ToString().Split(":")[1].Trim()
        
        $output += "SSID: $profile"
        $output += "Password: $password"
        $output += "---------------------"
    }
    
    return ($output -join "`n")
}
