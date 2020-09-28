 <#
 .SYNOPSIS
     Report Compliance for MEMCM Configuration Item.  Discovery, remediation and removal in 1 script. 
 .DESCRIPTION
     Report Compliance for MEMCM Configuration Item.  Discovery, remediation and removal in 1 script. Works with @mwbengtsson toast scripts. 
     https://www.imab.dk/
 .PARAMETER SchTActionScript
     Just like in a GUI, a program that runs
 .PARAMETER SchTActionArgs
     Arguments for the program
 .PARAMETER SchTFolder
     Specifies the object to be processed.  You can also pipe the objects to this command.
 .PARAMETER SchTFolder
     The folder you want this task to live under
 .PARAMETER SchTName
     The name of the task
 .PARAMETER SchTDes
     The description - The idea here is we resue this for each version of servicing.  Adding this to the currrent build of FU deploying will help with clean up
 .PARAMETER SchTWrkPath
     The working path where your files live
 .PARAMETER UserDomain
     The domain your user logs in with ex: CONTOSO
 .PARAMETER Remediate
     Fix it!
 .PARAMETER RemoveOnly
     Clean up!
 .PARAMETER TranscriptPath
     Log location
 .EXAMPLE
     C:\PS>
     .\Script.ps1 # will discover task and return compliant or non-compliant
 .EXAMPLE
     C:\PS>
     .\Script.ps1 -Remediate # will add the scheduled task
 .NOTES
     Author:     Chad Brower
     Contact:    @Brower_Chad
     Created:    2020.09.23
     Version:    1.0.1

     1.0.0 - First release, tested under system context.  Unknown how it will handle multiple users logged in, not sure if this a scenerio I need to worry about
     1.0.1 - Minor changes to output for CI handling.  CI did not like transcript output.  Got splatting working for New-ScheduledTaskSettingsSet
     making it easier for user of this script to make changes for their org. 

     Other Notes:  You can edit anything about the script to fit your org needs:
 #>
 [cmdletbinding()]
 Param (
    [Parameter()]
    [string] $SchTActionScript = "wscript.exe", # Program to run
    [Parameter()]
    [string] $SchTActionArgs = 'Hidden.vbs RunToastHidden.cmd', # Arguments 
    [Parameter()]    
    [String] $SchTFolder = "FI-FeatureUpdate", # Folder Name
    [Parameter()]
    [string] $SchTName = "FeatureUpdate-Toast", # Task Name
    [Parameter()]
    [string] $SchTDes = "1909", # WaaS Update
    [Parameter()]
    [string] $SchTWrkPath = "C:\~FeatureUpdateTemp\ToastNotificationScript", # Working path
    [Parameter()]
    [String] $UserDomain = "CONTOSO", # Your domain alias
    [Parameter()]
    [switch] $Remediate,
    [Parameter()]
    [switch] $RemoveOnly,
    [Parameter()]
    [string] $TranscriptPath = "$env:windir\CCM\Logs\FeatureUpdate-ToastNotifcation.log"
)
Start-Transcript -Path $TranscriptPath -Append -Force -ErrorAction SilentlyContinue | Out-Null
#Region Begin Build Variables
    $ScheduleObject = New-Object -ComObject Schedule.Service
    $ScheduleObject.Connect()
    $GetSchTFolders = $ScheduleObject.GetFolder($null) # Create the folders method
    $SchTFolders = $GetSchTFolders.GetFolders(0) # Build a list of folders on this system
    $GetSchT = Get-ScheduledTask -TaskName $SchTName -ea SilentlyContinue
    # Build an array we can use for later
    [Array]$ArrayFolders = @(
        if($SchTFolders) {
            foreach ($Fold in $SchTFolders) {
                $Fold
            }
        }
    )
    # Modified from here: https://community.spiceworks.com/scripts/show/4408-get-logged-in-users-remote-computers-or-local
    $GetCurrentUser = {
        $QueryUsers = quser /server:$($env:COMPUTERNAME) 2>$null
        [PSCustomObject]$PSObj = @()
          If (!$QueryUsers) {
            Write-Error "Unable to retrieve quser info for $($env:COMPUTERNAME)" -ea Stop
            Exit 1
          }
        ForEach ($Line in $QueryUsers) {
            If ($Line -match "logon time") {
                Continue
            }
             $PSObj = @{
              ComputerName    = $env:COMPUTERNAME
              Username        = $line.SubString(1, 20).Trim()
              SessionName     = $line.SubString(23, 17).Trim()
              ID             = $line.SubString(42, 2).Trim()
              State           = $line.SubString(46, 6).Trim()
              LogonTime      = [datetime]$line.SubString(65)
              }
              $Results += New-Object psobject -Property $PSObj
        }
        Return $Results
    }
    if($Remediate) {
        # Splatting trigger param settings
        $TriggerSplatt = @{
            Daily = $true
            At = (Get-Date 09:00AM)
        }
        # Splatting for the New-ScheduledTaskSettingsSet commandlet
        $SetSettingsSplatt = @{
             WakeToRun = $true
             AllowStartIfOnBatteries = $true
             DontStopIfGoingOnBatteries = $true
             ExecutionTimeLimit = (New-TimeSpan -Hours 1)
             StartWhenAvailable = $true
        }
    }
#EndRegion
#Region Main Discovery
    if ((!$PSBoundParameters.ContainsKey('Remediate')) -AND (!$PSBoundParameters.ContainsKey('RemoveOnly'))) {
        $Compliance = $null
        while ($null -eq $Compliance -or !($Compliance -eq "Error") -or !($Compliance -eq "3")) {
            # Does the Folder Exist    
            try {
                if ($ArrayFolders.path -eq "\$($SchTFolder)") {
                    [Int]$Compliance += "1"
                }
                else {
                    THROW "FOLDER NOT PRESENT"
                }
            }
            catch [System.Exception] {
                $Compliance = "Error"
                #Write-Error "$_" -ea Continue
                Break
            }
            # Does the Task Exist
            try {
                if (!($null -eq $GetSchT)) {
                    $Compliance += "1"
                }
                else {
                    THROW "TASK NOT PRESENT"
                }
            }
            catch [System.Exception] {
                $Compliance = "Error"
                #Write-Error "$_" -ea Continue
                Break
            }
            # Does the Task Make the Description? 1909.ect
            try {
                if (!($null -eq $GetSchT)) {
                    if ($GetSchT.Description -eq $SchTDes) {
                        $Compliance += "1"
                    }
                    else {
                        THROW "THE DESCRIPTION DOES NOT MATCH"                  
                    }
                }
                else {
                    THROW "TASK NOT PRESENT, THEREFORE NO DESCRIPTION WILL BE THERE"
                }
            }
            catch [System.Exception] {
                $Compliance = "Error"
                Break
            }
            Break
        }
        # Write Compliance for CI Discovery
        if ($Compliance -eq "3") {
            # $Compliance # For Testing
            Write-Host "Compliant"
        }
        else {
            # $Compliance # For Testing
            Write-Information "Compliance Issue: $($Error[0].Exception.Message)" | Out-Null
            Write-Host "Non-Compliant"
        }
    }
#EndRegion
#Region Main Remediate
    elseif ($Remediate) {
        # Get the current logged on user
        $GetUserName = &$GetCurrentUser
        # Create a New Folder in Task Scheduler
        if (!($ArrayFolders.path -eq "\$($SchTFolder)")) {
            # Create the folder
            try {
                $GetSchTFolders.CreateFolder($SchTFolder)
            }
            catch [System.Exception] {
                if($_.Exception.Message -like "*Cannot create a file when that file already exists*") {
                    Write-Host "Folder Already exists"
                }
                else { 
                $_
                Exit 1
                }
            }
        }
        else {
            Write-Host "Folder Already exists"
        }
        try {
            if ($null -eq $GetSchT) {
                # Setup Toast Notification
                $Action = New-ScheduledTaskAction -Execute $SchTActionScript -Argument $SchTActionArgs -WorkingDirectory $SchTWrkPath
                ########################## EDIT ME IF NEEDED ######################
                $Trigger = New-ScheduledTaskTrigger @TriggerSplatt # Edit this if needed - https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger?view=win10-ps
                $Principal = New-ScheduledTaskPrincipal "$($UserDomain)\$($GetUserName.UserName)" # Edit this to match your needs - https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal?view=win10-ps
                $SetSettings = New-ScheduledTaskSettingsSet @SetSettingsSplatt # Add anything here you need - https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=win10-ps
                ###################################################################
                $InputObj = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger -Settings $SetSettings -Description $SchTDes # Edit if you need - https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtask?view=win10-ps
                # After building task bits, we need to register it
                Register-ScheduledTask -TaskName $SchTName -InputObject $InputObj -TaskPath $SchTFolder
            }
            else {
                Write-Host "Task Already exists"
            }
        }
        catch [System.Exception] {
            $_
            Exit 1
        }
    }
#EndRegion
#Region Remove
    elseif ($RemoveOnly) {
            # Remove Task & Folder in Task Scheduler
            try {
                Unregister-ScheduledTask -TaskName $GetSchT.TaskName -Confirm:$false
                $GetSchTFolders.DeleteFolder($SchTFolder,$null)
            }
            catch [System.Exception] {
                $_
                Exit 1 
            }
        }
#EndRegion
Stop-Transcript | Out-Null