<powershell>

function run-once-on-login ($taskname, $action) {
    $trigger = New-ScheduledTaskTrigger -AtLogon -RandomDelay $(New-TimeSpan -seconds 30)
    $trigger.Delay = "PT30S"
    $selfDestruct = New-ScheduledTaskAction -Execute powershell.exe -Argument "-WindowStyle Hidden -Command `"Disable-ScheduledTask -TaskName $taskname`""
    Register-ScheduledTask -TaskName $taskname -Trigger $trigger -Action $action,$selfDestruct -RunLevel Highest
}

function install-chocolatey {
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    choco feature enable -n allowGlobalConfirmation
}

function install-parsec-cloud-preparation-tool {
    # https://github.com/jamesstringerparsec/Parsec-Cloud-Preparation-Tool
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $downloadPath = "C:\Parsec-Cloud-Preparation-Tool.zip"
    $extractPath = "C:\Parsec-Cloud-Preparation-Tool"
    $repoPath = Join-Path $extractPath "Parsec-Cloud-Preparation-Tool-master"
    $copyPath = Join-Path $desktopPath "ParsecTemp"
    $scriptEntrypoint = Join-Path $repoPath "PostInstall\PostInstall.ps1"

    if (!(Test-Path -Path $extractPath)) {
        [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
        (New-Object System.Net.WebClient).DownloadFile("https://github.com/jamesstringerparsec/Parsec-Cloud-Preparation-Tool/archive/master.zip", $downloadPath)
        New-Item -Path $extractPath -ItemType Directory
        Expand-Archive $downloadPath -DestinationPath $extractPath
        Remove-Item $downloadPath

        New-Item -Path $copyPath -ItemType Directory
        Copy-Item $repoPath/* $copyPath -Recurse -Container

        # Setup scheduled task to run Parsec-Cloud-Preparation-Tool once at logon
        $action = New-ScheduledTaskAction -Execute powershell.exe -WorkingDirectory $repoPath -Argument "-Command `"$scriptEntrypoint -DontPromptPasswordUpdateGPU`""
        run-once-on-login "Parsec-Cloud-Preparation-Tool" $action
    }
}

function install-admin-password {
    $password = (Get-SSMParameter -WithDecryption $true -Name '${password_ssm_parameter}').Value
    net user Administrator "$password"
}

function install-autologin {
    Install-Module -Name DSCR_AutoLogon -Force
    Import-Module -Name DSCR_AutoLogon
    $password = (Get-SSMParameter -WithDecryption $true -Name '${password_ssm_parameter}').Value
    $regPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    [microsoft.win32.registry]::SetValue($regPath, "AutoAdminLogon", "1")
    [microsoft.win32.registry]::SetValue($regPath, "DefaultUserName", "Administrator")
    Remove-ItemProperty -Path $regPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
    (New-Object PInvoke.LSAUtil.LSAutil -ArgumentList "DefaultPassword").SetSecret($password)
}

function install-graphic-driver {
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/install-nvidia-driver.html#nvidia-gaming-driver

    if (!(Test-Path -Path "C:\Program Files\NVIDIA Corporation\NVSMI")) {
        $ExtractionPath = "C:\nvidia-driver\driver"
        $Bucket = ""
        $KeyPrefix = ""
        $InstallerFilter = "*win10*"

        %{ if regex("^g[0-9]+", var.instance_type) == "g3" }

        # GRID driver for g3
        $Bucket = "ec2-windows-nvidia-drivers"
        $KeyPrefix = "latest"

        # download driver
        $Objects = Get-S3Object -BucketName $Bucket -KeyPrefix $KeyPrefix -Region us-east-1
        foreach ($Object in $Objects) {
            $LocalFileName = $Object.Key
            if ($LocalFileName -ne '' -and $Object.Size -ne 0) {
                $LocalFilePath = Join-Path $ExtractionPath $LocalFileName
                Copy-S3Object -BucketName $Bucket -Key $Object.Key -LocalFile $LocalFilePath -Region us-east-1
            }
        }

        # disable licencing page in control panel
        New-ItemProperty -Path "HKLM:\SOFTWARE\NVIDIA Corporation\Global\GridLicensing" -Name "NvCplDisableManageLicensePage" -PropertyType "DWord" -Value "1"

        %{ else }
        %{ if regex("^g[0-9]+", var.instance_type) == "g4" }

        # vGaming driver for g4
        $Bucket = "nvidia-gaming"
        $KeyPrefix = "windows/latest"

        # download and extract driver
        $Objects = Get-S3Object -BucketName $Bucket -KeyPrefix $KeyPrefix -Region us-east-1
        foreach ($Object in $Objects) {
            if ($Object.Size -ne 0) {
                $LocalFileName = "C:\nvidia-driver\driver.zip"
                Copy-S3Object -BucketName $Bucket -Key $Object.Key -LocalFile $LocalFileName -Region us-east-1
                Expand-Archive $LocalFileName -DestinationPath $ExtractionPath
                break
            }
        }

        # install licence
        Copy-S3Object -BucketName $Bucket -Key "GridSwCert-Archive/GridSwCert-Windows_2020_04.cert" -LocalFile "C:\Users\Public\Documents\GridSwCert.txt" -Region us-east-1
        [microsoft.win32.registry]::SetValue("HKEY_LOCAL_MACHINE\SOFTWARE\NVIDIA Corporation\Global", "vGamingMarketplace", 0x02)

        %{ endif }
        %{ endif }

        if (Test-Path -Path $ExtractionPath) {
            # install driver
            $InstallerFile = Get-ChildItem -path $ExtractionPath -Include $InstallerFilter -Recurse | ForEach-Object { $_.FullName }
            Start-Process -FilePath $InstallerFile -ArgumentList "/s /n" -Wait

            # install task to disable second monitor on login
            $trigger = New-ScheduledTaskTrigger -AtLogon
            $action = New-ScheduledTaskAction -Execute displayswitch.exe -Argument "/internal"
            Register-ScheduledTask -TaskName "disable-second-monitor" -Trigger $trigger -Action $action -RunLevel Highest

            # cleanup
            Remove-Item -Path "C:\nvidia-driver" -Recurse
        }
        else {
            $action = New-ScheduledTaskAction -Execute powershell.exe -Argument "-WindowStyle Hidden -Command `"(New-Object -ComObject Wscript.Shell).Popup('Automatic GPU driver installation is unsupported for this instance type: ${var.instance_type}. Please install them manually.')`""
            run-once-on-login "gpu-driver-warning" $action
        }
    }
}

function install-logmein {
    # install logmein
    $downloadPath = "C:\Logmein.msi"
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
    (New-Object System.Net.WebClient).DownloadFile("https://secure.logmein.com/Logmein.msi", $downloadPath)
    msiexec.exe /q /l* c:\logfile.txt /i $downloadPath REBOOTYESNO=No
}

function install-vrdesktop {
    # virtual desktop
    $downloadPath = "C:\VirtualDesktop.Streamer.Setup.exe"
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
    (New-Object System.Net.WebClient).DownloadFile("https://download.vrdesktop.net/files/VirtualDesktop.Streamer.Setup.exe", $downloadPath)
    iex "$downloadPath /q /l* c:\logfile2.txt REBOOTYESNO=No" 
}

function install-games {
    # install logmein and virtual desktop
    $steam_user = "${var.steam_user}"
    $steam_password = "${var.steam_password}"
    $steam_folder = "C:\Program Files (x86)\Steam"
    $steam_shortcut = "C:\Users\Public\Desktop\Steam.lnk"
    #make steam shortcut
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($steam_shortcut)
    $Shortcut.TargetPath =  "$steam_folder\steam.exe"
    $Shortcut.Arguments =  "-login $steam_user $steam_password"
    $Shortcut.WorkingDirectory =  "$steam_folder"
    $Shortcut.Save()
    #schedule steam to start on boot logged in
    Start-Process -FilePath $steam_shortcut
    $action = New-ScheduledTaskAction -Execute $steam_shortcut
    $trigger = New-JobTrigger -AtStartup -RandomDelay 00:00:30
    Register-ScheduledJob -Trigger $trigger -Action $action -Name StartSteam
    #install games
    $games = ${var.steam_games}
    foreach ($g in $games) {
        steamcmd +login $steam_user $steam_password +force_install_dir "$steam_folder\" +app_update $g +quit
    }
}

install-chocolatey
Install-PackageProvider -Name NuGet -Force
choco install awstools.powershell

%{ if var.install_parsec }
install-parsec-cloud-preparation-tool
%{ endif }

install-admin-password

%{ if var.install_auto_login }
install-autologin
%{ endif }

%{ if var.install_graphic_card_driver }
install-graphic-driver
%{ endif }

%{ if var.install_gog_galaxy }
choco install goggalaxy
%{ endif }

%{ if var.install_uplay }
choco install uplay
%{ endif }

%{ if var.install_origin }
choco install origin
%{ endif }

%{ if var.install_epic_games_launcher }
choco install epicgameslauncher
%{ endif }

%{ if var.install_vrdesktop }
install-vrdesktop
%{ endif }

install-logmein

%{ if var.install_steam }
choco install steam
choco install steamcmd
install-games
%{ endif }

Restart-Computer
</powershell>
