function Get-BrowserData {
    $output = @()
    
    # Chrome history and passwords (if Chrome is installed)
    $chromePaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
    )
    
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            $output += "Chrome data found at: $path"
            # In a real script, you would read and parse these SQLite databases
            $output += "[Chrome data would be extracted here]"
        }
    }
    
    # Edge history and passwords (if Edge is installed)
    $edgePaths = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
    )
    
    foreach ($path in $edgePaths) {
        if (Test-Path $path) {
            $output += "Edge data found at: $path"
            # In a real script, you would read and parse these SQLite databases
            $output += "[Edge data would be extracted here]"
        }
    }
    
    return ($output -join "`n")
}
