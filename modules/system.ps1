function Get-SystemInfo {
    try {
        $output = @()
        
        $output += "Computer Name: $env:COMPUTERNAME"
        $output += "Username: $env:USERNAME"
        $output += "OS Version: $([System.Environment]::OSVersion.VersionString)"
        $output += "Date/Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $output += "Public IP: $(try { (Invoke-WebRequest -Uri 'https://api.ipify.org' -TimeoutSec 3).Content } catch { 'Unknown' })"
        
        return ($output -join "`n")
    }
    catch {
        return "Error in system module: $_"
    }
}
