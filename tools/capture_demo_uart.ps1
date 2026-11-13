# Windows built-in SerialPort: no pyserial installation is needed.
param(
    [Parameter(Mandatory=$true)][string]$Port,
    [string]$Output = "build/board_demo/mnist/fpga_uart.txt",
    [int]$Samples = 20
)
$ErrorActionPreference = "Stop"
$serial = [System.IO.Ports.SerialPort]::new($Port,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.ReadTimeout = 1000
$serial.NewLine = "`n"
$fullOutput = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $fullOutput) { throw "Use a new output filename; capture already exists: $fullOutput" }
$parent = Split-Path -Parent $fullOutput
[System.IO.Directory]::CreateDirectory($parent) | Out-Null
$writer = [System.IO.StreamWriter]::new($fullOutput,$false,[System.Text.Encoding]::ASCII)
$headers = 0
$ends = 0
try {
    $serial.Open()
    Write-Host "Listening on $Port at 115200 8N1. Press BTN0, then BTN1 for each image. Ctrl+C stops."
    while ($headers -lt $Samples -or $ends -lt $Samples*16) {
        try { $line = $serial.ReadLine().TrimEnd("`r") }
        catch [System.TimeoutException] { continue }
        $writer.WriteLine($line)
        $writer.Flush()
        if ($line.StartsWith("C,")) { $headers++; Write-Host $line }
        if ($line -match '^[IO],[0-9A-F]{2},[0-7],100$') { $ends++ }
    }
    Write-Host "Saved $headers class records and $ends tick-end records to $fullOutput. Run the Python verifier."
}
finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    $writer.Dispose()
}
