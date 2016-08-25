# 
# Restore Nuget packages.
# Build the web application out to a zip package.

# Import useful functions from deployment library file
. "$(Split-Path $MyInvocation.MyCommand.Path)\DeploymentLib.ps1"

#-----------------------#
# Build web application #
#-----------------------#
 
Write-Host 'Building web app'

tool_nuget restore '..\src' -noninteractive

$log_path = (join-path $out_dir "msbuild.log")
tool_msbuild '..\src\ContosoOnlineBikeStore\ContosoOnlineBikeStore.csproj' /p:Platform="AnyCPU" /T:Package /P:PackageLocation="$out_dir" /P:_PackageTempDir="$temp_dir" /fileLoggerParameters:LogFile="$log_path"

# Scan for build error
if (-not (test-path $log_path)) {
    Write-Warning "Unable to find msbuild log file $log_path"
    return
}

$build_success = ((Select-String -Path $log_path -Pattern "Build FAILED." -SimpleMatch) -eq $null) -and $LASTEXITCODE -eq 0

if (-not $build_success) {
    Write-Warning "Error building project. See build log: $log_path"
    return
}
