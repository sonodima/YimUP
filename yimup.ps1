$scriptVersion = "1.0.0"
$repoUrl = "https://github.com/YimMenu/YimMenu"
$dataDir = "$env:APPDATA\YimMenu"
$libName = "YimMenu.dll"


Write-Output @"


    ██╗   ██╗██╗███╗   ███╗██╗   ██╗██████╗ ██╗
    ╚██╗ ██╔╝██║████╗ ████║██║   ██║██╔══██╗██║
     ╚████╔╝ ██║██╔████╔██║██║   ██║██████╔╝██║
      ╚██╔╝  ██║██║╚██╔╝██║██║   ██║██╔═══╝ ╚═╝
       ██║   ██║██║ ╚═╝ ██║╚██████╔╝██║     ██╗
       ╚═╝   ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝     ╚═╝
       version: $( $scriptVersion )

"@

# =================================================================================================


Add-Type -Namespace PInvoke -Name Kernel32 -MemberDefinition @'
    [DllImport("Kernel32")]
    public static extern uint GetLastError();

    [DllImport("Kernel32", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr handle);

    [DllImport("Kernel32", SetLastError=true)]
    public static extern UInt32 WaitForSingleObject(IntPtr handle, UInt32 milliseconds);

    [DllImport("Kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr GetModuleHandle([MarshalAs(UnmanagedType.LPWStr)] string moduleName);

    [DllImport("Kernel32", CharSet=CharSet.Ansi, SetLastError=true)]
    public static extern IntPtr GetProcAddress(IntPtr module, string procName);

    [DllImport("Kernel32", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint processAccess, bool inheritHandle, uint processId);

    [DllImport("Kernel32", SetLastError=true)]
    public static extern IntPtr VirtualAllocEx(IntPtr process, IntPtr address, uint size,
                                               uint allocationType, uint protect);
    
    [DllImport("Kernel32", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool VirtualFreeEx(IntPtr process, IntPtr address, int size, uint freeType);

    [DllImport("Kernel32", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WriteProcessMemory(IntPtr process, IntPtr address, byte[] buffer,
                                                 Int32 size, out IntPtr bytesWritten);

    [DllImport("Kernel32", SetLastError=true)]
    public static extern IntPtr CreateRemoteThread(IntPtr process, IntPtr attributes, uint stackSize,
                                                   IntPtr startAddress, IntPtr parameter,
                                                   uint creationFlags, out IntPtr threadId);
'@


# =================================================================================================


# Create menu data directory if not found, then download the latest build from GitHub.
New-Item -ItemType dir -Path $dataDir -ErrorAction Ignore
$libPath = $dataDir + "/" + $libName

try {
    Write-Output "[>] downloading the latest release..."
    # Microsoft thought that updating the progress bar every byte downloaded would be a good idea.
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest "$( $repoUrl )/releases/download/nightly/YimMenu.dll" -OutFile $libPath
} catch {
    Write-Output "[-] failed to download the file; check your network and ensure that the menu has not already been loaded."
    return
}

try {
    # This will throw an exception if Windows Defender is enabled!
    $libHash = Get-FileHash -Path $libPath -Algorithm SHA256 -ErrorAction SilentlyContinue
    Write-Output "[+] file downloaded successfully. sha256=$( $libHash.Hash.ToLower() )"
} catch {
    Write-Output @"
[-] the menu may have been falsely-flagged by your anti-virus!
    game modifications are often (erroneously) flagged as malware by anti-viruses due to the way
    they interact with games.
    
    to fix this, temporarely disable your anti-virus or add the following directory to its
    exclusions list: $( $dataDir )

"@

    $confirmation = Read-Host "    do you need help with this? [y/N]"
    if ( $confirmation.ToLower() -eq "y" ) {
        Start-Process "https://support.microsoft.com/en-us/windows/add-an-exclusion-to-windows-security-811816c0-4dfd-af4a-47e4-c301afe13b26"
    }

    return
}



# Obtain the id of the GTA5.exe process, or wait for it if it isn't found.
$game = Get-Process -Name "GTA5" -ErrorAction Ignore
if ( -not $game ) {
    Write-Output "[>] game is not running, please launch it now."

    do {
        Start-Sleep -Milliseconds 1000
        $game = Get-Process -Name "GTA5" -ErrorAction Ignore
    } while ( -not $game )

    # Game was just launched... Wait a few seconds for the game to initialize before injecting.
    Write-Output "[+] target process found, waiting 10 seconds. pid=$($game.Id)"
    Start-Sleep -Seconds 10
} else {
    Write-Output "[+] target process found. pid=$($game.Id)"
}



$handle = [PInvoke.Kernel32]::OpenProcess(0x43A, $false, $game.Id)
if ( $handle -eq 0x0 ) {
    $result = [PInvoke.Kernel32]::GetLastError()
    Write-Output "[-] failed to open process. error=$( $result )"
    return
}



$libPathBytes = [System.Text.Encoding]::Unicode.GetBytes($libPath) + @(0x00, 0x00)
$libPathAlloc = [PInvoke.Kernel32]::VirtualAllocEx($handle, 0x0, $libPathBytes.Count, 0x1000, 0x4)
if ( $libPathAlloc -eq 0x0 ) {
    $result = [PInvoke.Kernel32]::GetLastError()
    Write-Output "[-] failed to allocate string buffer. error=$( $result )"

    [PInvoke.Kernel32]::CloseHandle($handle) | Out-Null
    return
}

$result = [PInvoke.Kernel32]::WriteProcessMemory($handle, $libPathAlloc, $libPathBytes,
                                                 $libPathBytes.Count, [ref] 0x0)
if ( -not $result ) {
    $result = [PInvoke.Kernel32]::GetLastError()
    Write-Output "[-] failed to write library path. error=$( $result )"

    [PInvoke.Kernel32]::VirtualFreeEx($handle, $libPathAlloc, 0, 0x8000) | Out-Null
    [PInvoke.Kernel32]::CloseHandle($handle) | Out-Null
    return
}



$hKernel32 = [PInvoke.Kernel32]::GetModuleHandle("Kernel32")
if ( $hKernel32 -eq 0x0 ) {
    $result = [PInvoke.Kernel32]::GetLastError()
    Write-Output "[-] failed to get handle to Kernel32. error=$( $result )"

    [PInvoke.Kernel32]::VirtualFreeEx($handle, $libPathAlloc, 0, 0x8000) | Out-Null
    [PInvoke.Kernel32]::CloseHandle($handle) | Out-Null
    return
}

$loadLibrary = [PInvoke.Kernel32]::GetProcAddress($hKernel32, "LoadLibraryW")
if ( $loadLibrary -eq 0x0 ) {
    $result = [PInvoke.Kernel32]::GetLastError()
    Write-Output "[-] failed to get address of LoadLibraryW. error=$( $result )"

    [PInvoke.Kernel32]::VirtualFreeEx($handle, $libPathAlloc, 0, 0x8000) | Out-Null
    [PInvoke.Kernel32]::CloseHandle($handle) | Out-Null
    return
}



$thread = [PInvoke.Kernel32]::CreateRemoteThread($handle, 0x0, 0, $loadLibrary, $libPathAlloc,
                                                 0, [ref] 0x0)
if ( $thread -eq 0x0 ) {
    $result = [PInvoke.Kernel32]::GetLastError()
    Write-Output "[-] failed to create thread in process. error=$( $result )"

    [PInvoke.Kernel32]::VirtualFreeEx($handle, $libPathAlloc, 0, 0x8000) | Out-Null
    [PInvoke.Kernel32]::CloseHandle($handle) | Out-Null
    return
}

[PInvoke.Kernel32]::WaitForSingleObject($thread, [UInt32]::MaxValue) | Out-Null
Write-Output "[+] injection succeeded! have fun."

[PInvoke.Kernel32]::CloseHandle($thread) | Out-Null
[PInvoke.Kernel32]::VirtualFreeEx($handle, $libPathAlloc, 0, 0x8000) | Out-Null
[PInvoke.Kernel32]::CloseHandle($handle) | Out-Null
