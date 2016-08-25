Write-Host 'Executing database bootstrap scripts (this may take some time)'

$sql_scripts = @(
    "$script_dir\sql\store_inserts.sql"
)

$sqlServer         = $OUTPUTS['sqlServerName']
$sqlServerUsername = $OUTPUTS['sqlServerUsername']
$sqlServerPassword = $OUTPUTS['sqlServerPassword']
$sqlServerDatabase = $OUTPUTS['sqlServerDbName']

$sqlTimeoutSeconds = [int] [TimeSpan]::FromMinutes(8).TotalSeconds 
$sqlConnectionTimeoutSeconds = [int] [TimeSpan]::FromMinutes(2).TotalSeconds

Push-Location
try {
    foreach ($script_path in $sql_scripts) {
        Write-Host "Executing $script_path"
        Invoke-Sqlcmd -ServerInstance $sqlServer -Username $sqlServerUsername -Password $sqlServerPassword -Database $sqlServerDatabase -InputFile $script_path -QueryTimeout $sqlTimeoutSeconds -ConnectionTimeout $sqlConnectionTimeoutSeconds
    }
} catch {
    Write-Warning "Error executing $sql_script (consider executing manually)`n$($_.Exception)"
}
finally {
    # Work around Invoke-Sqlcmd randomly changing the working directory
    Pop-Location
}

Write-Host "Bye"
