<##
    .SYNOPSIS
        Compresses a directory or file into a ZIP archive and uploads it to
        BashUpload.com without requiring any account or API key.  Upon a
        successful upload, the script extracts and saves the public download
        link for the uploaded file.

    .DESCRIPTION
        BashUpload.com is a free service that accepts file uploads via simple
        HTTP requests.  You can upload a file anonymously and the service
        returns a unique URL through which the file can be downloaded for up to
        three days.  According to the service documentation, a file can be
        uploaded from the command line using a PUT request (`curl
        https://bashupload.com/ -T /path/to/file`)【587128402822914†L9-L27】.  This
        script uses PowerShell’s `Invoke-WebRequest` to perform the same
        operation.  After the upload completes, BashUpload returns a short
        instruction containing a `wget` command with the download URL; this
        script parses that output to retrieve the download link and writes it to
        a text file.

        The script is self‑contained and requires no third‑party modules.  It
        compresses the specified path into a ZIP archive (if it is a
        directory) and uploads the archive.  The resulting link is displayed
        on the console and saved in a file named `bashupload_link.txt` in the
        same folder as the ZIP.

    .PARAMETER SourcePath
        Path to the directory or single file you want to archive and upload.

    .PARAMETER ZipName
        Optional name for the ZIP archive.  If omitted, the script derives
        the name from the source path (appending `.zip`).

    .EXAMPLE
        PS> .\upload_bashupload.ps1 -SourcePath "C:\Temp\BuildOutput"

        Compresses `C:\Temp\BuildOutput` into `BuildOutput.zip`, uploads it
        anonymously to BashUpload.com, and outputs the download link.

    .EXAMPLE
        PS> .\upload_bashupload.ps1 -SourcePath "C:\Temp\report.pdf" -ZipName "report_archive.zip"

        Archives `report.pdf` into `report_archive.zip` and uploads it.  The
        resulting download URL is printed and saved locally.

    .NOTES
        Author: Arslan Baig
##>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$SourcePath,

    [Parameter(Mandatory=$false)]
    [string]$ZipName
)

set-strictmode -version latest

# Resolve and validate the source path
$resolvedSource = Resolve-Path -Path $SourcePath -ErrorAction Stop
if (-not (Test-Path -Path $resolvedSource)) {
    throw "Source path '$SourcePath' does not exist."
}

# Determine the ZIP file name and path
if ($ZipName -and $ZipName.Trim()) {
    $zipFileName = [System.IO.Path]::GetFileName($ZipName)
    if (-not $zipFileName.ToLower().EndsWith('.zip')) {
        $zipFileName += '.zip'
    }
} else {
    $sourceLeaf = [System.IO.Path]::GetFileNameWithoutExtension($resolvedSource)
    $zipFileName = "$sourceLeaf.zip"
}
$parentDir = [System.IO.Path]::GetDirectoryName($resolvedSource)
$zipPath   = Join-Path -Path $parentDir -ChildPath $zipFileName

# Remove existing ZIP if present and create new archive
Write-Host "Compressing '$resolvedSource' into '$zipPath'..." -ForegroundColor Cyan
if (Test-Path -Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}
Compress-Archive -Path $resolvedSource -DestinationPath $zipPath -Force

$zipInfo = Get-Item -Path $zipPath
Write-Host "Archive created. Size: $([math]::Round($zipInfo.Length / 1MB, 2)) MB." -ForegroundColor Green

# Build the upload URI.  Using the file name in the URI ensures the file is
# accessible via a human‑readable name on BashUpload.
$fileNameForUpload = [System.IO.Path]::GetFileName($zipPath)
$uploadUri = "https://bashupload.com/$fileNameForUpload"

Write-Host "Uploading ZIP to BashUpload.com..." -ForegroundColor Cyan

try {
    # Perform the HTTP PUT request.  Use Invoke-WebRequest to send the file as
    # the request body.  The response content contains a wget command with the
    # download URL.
    $response = Invoke-WebRequest -Uri $uploadUri -Method Put -InFile $zipPath -UseBasicParsing
} catch {
    throw "Upload failed: $($_.Exception.Message)"
}

# Extract the download URL from the response content.  The response typically
# includes a line like:
#   wget https://bashupload.com/4dcXO/file.zip
$downloadUrl = $null
$response.Content -split "`n" | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '(https://bashupload\.com/[^\s]+)') {
        $downloadUrl = $matches[1]
        return
    }
}

if (-not $downloadUrl) {
    throw "Unable to parse download URL from BashUpload response. Raw response: $($response.Content)"
}

Write-Host "Upload successful! Public download link:" -ForegroundColor Green
Write-Host $downloadUrl -ForegroundColor Yellow

# Write the link to a text file for convenience
$linkFile = Join-Path -Path $parentDir -ChildPath 'bashupload_link.txt'
$downloadUrl | Out-File -FilePath $linkFile -Force
Write-Host "Download link saved to $linkFile" -ForegroundColor Green