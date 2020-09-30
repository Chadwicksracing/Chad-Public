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
     Edited:     2020.09.30
     Version:    1.1.0

     1.0.0 - First release, tested under system context.  Unknown how it will handle multiple users logged in, not sure if this a scenerio I need to worry about
     1.0.1 - Minor changes to output for CI handling.  CI did not like transcript output.  Got splatting working for New-ScheduledTaskSettingsSet
     making it easier for user of this script to make changes for their org
     1.1.0 - Major changes to handling. [string] $SchTActionProgram = "C:\Windows\System32\wscript.exe", # This will not work correctly. So I had to hard code it in the splatt

     Other Notes:  You can edit anything about the script to fit your org needs:
 #>
 [cmdletbinding()]
 Param (
    [Parameter()]
    [string] $SchTActionProgram = "C:\Windows\System32\wscript.exe", # Program to run
    [Parameter()]
    [string] $SchTActionArgs = 'Hidden.vbs RunToastHidden.cmd', # Arguments 
    [Parameter()]    
    [String] $SchTFolder = "FI-FeatureUpdate", # Folder Name
    [Parameter()]
    [string] $SchTName = "FeatureUpdate-Toast", # Task Name
    [Parameter()]
    [string] $SchTDes = "1909", # WaaS Update
    [Parameter()]
    [string] $SchTWrkPath = "C:\~FeatureUpdateTemp\Scripts\ToastNotificationScript", # Working path
    [Parameter()]
    [String] $UserDomain = "FIC", # Your domain alias
    [Parameter()]
    [Switch] $Remediate = $true, # Use to add task
    [Parameter()]
    [switch] $RemoveOnly, # want to remove it all?
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
    # Get current user logged in
    # Modified from here: https://community.spiceworks.com/scripts/show/4408-get-logged-in-users-remote-computers-or-local
    $GetCurrentUser = {
        $QueryUsers = quser /server:$($env:COMPUTERNAME) 2>$null
        [PSCustomObject]$PSObj = @()
          If (!$QueryUsers) {
            Write-Error "Unable to retrieve quser info for $($env:COMPUTERNAME)" -ea Stop
            Stop-Transcript | Out-Null
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
    # Building block for the Removal part
    $RemoveBit = {
        # Remove Task & Folder in Task Scheduler
        try {
            Unregister-ScheduledTask -TaskName $GetSchT.TaskName -Confirm:$false
            $GetSchTFolders.DeleteFolder($SchTFolder,$null)
            Write-Host "Task & Folder Removed"
        }
        catch [System.Exception] {
            $_
            Stop-Transcript | Out-Null
            Exit 1 
        }
    }
    # Building block for Creating the task
    # See https://docs.microsoft.com/en-us/powershell/module/scheduledtasks to help build out your task the way you need
    $CreateTaskBit = {
        Write-Host "Action: $SchTActionProgram"
        Write-Host "ActionArgs:  $SchTActionArgs"
        Write-Host "WorkDir: $SchTWrkPath"
        # Splat trigger param settings
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
        # Splatt actions
        # had to hard code Execute, the CI handler kept changing its value to "Compliant or Non-Comliant"
        $ActionSplatt = @{
            Execute = "C:\Windows\System32\wscript.exe"
            Argument = $SchTActionArgs
            WorkingDirectory = $SchTWrkPath
        }
        # Setup Toast Notification
        $Action = New-ScheduledTaskAction @ActionSplatt
        $Trigger = New-ScheduledTaskTrigger @TriggerSplatt
        $Principal = New-ScheduledTaskPrincipal "$($UserDomain)\$($GetUserName.UserName)"
        $SetSettings = New-ScheduledTaskSettingsSet @SetSettingsSplatt
        $InputObj = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger -Settings $SetSettings -Description $SchTDes
        # After building task bits, we need to register it
        Register-ScheduledTask -TaskName $SchTName -InputObject $InputObj -TaskPath $SchTFolder
        Write-Host "Task Created"  
    }
#EndRegion
#Region Main Discovery
    if (-NOT(($Remediate.IsPresent) -OR ($RemoveOnly.IsPresent))) {
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
                [String]$Compliance = "Error"
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
                [String]$Compliance = "Error"
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
                [String]$Compliance = "Error"
                Break
            }
            Break
        }
        # Write Compliance for CI Discovery
        if ($Compliance -eq "3") {
            # $Compliance # For Testing
            $ComplianceValue = "Compliant"
            Write-Information "Compliant" | Out-Null
            Return $ComplianceValue
        }
        else {
            # $Compliance # For Testing
            $ComplianceValue = "Non-Compliant"
            Write-Information "Non-Compliant" | Out-Null
            Write-Information "Compliance Issue: $($Error[0].Exception.Message)" | Out-Null
            Return $ComplianceValue
        }
    }
#EndRegion
#Region Main Remediate
    if ($Remediate.IsPresent) {
        # Get the current logged on user
        $GetUserName = & $GetCurrentUser
        # Create a New Folder in Task Scheduler
        if (!($ArrayFolders.path -eq "\$($SchTFolder)")) {
            # Create the folder
            try {
                $GetSchTFolders.CreateFolder($SchTFolder)
                Write-Host "Folder Created"
            }
            catch [System.Exception] {
                if($_.Exception.Message -like "*Cannot create a file when that file already exists*") {
                    Write-Host "Folder Already exists"
                }
                else { 
                $_
                Stop-Transcript | Out-Null
                Exit 1
                }
            }
        }
        else {
            Write-Host "Folder Already exists"
        }
        try {
            if ($null -eq $GetSchT) {
                & $CreateTaskBit
            }
            elseif ($GetSchT.Description -notmatch $SchTDes) {
                Write-Host "The task description did not match Parameters in script."
                Write-Warning "Removing Task and Folder.."
                & $RemoveBit
                $GetSchTFolders.CreateFolder($SchTFolder)
                Write-Host "Folder Created"
                & $CreateTaskBit
            }
            else {
                Write-Host "Task Already exists"
            }
        }
        catch [System.Exception] {
            $_
            Stop-Transcript | Out-Null
            Exit 1
        }
    }
#EndRegion
#Region Remove
if ($RemoveOnly.IsPresent) {
    & $RemoveBit
}
#EndRegion
Stop-Transcript | Out-Null