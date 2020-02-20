 <#
.SYNOPSIS
    Triggers an evaluation of a configuration baseline
.DESCRIPTION
    Triggers an evaluation of a configuration baseline. Use this to launch the eval of the SetupConfig.ini Baseline from your app install.
.PARAMETER ComputerName
    $Env:Computername is used by default, specify other name for remote use
.PARAMETER BaseLineName
    The name of the configuration baseline to run.
.PARAMETER NameSpace
    WMI Namespace for the WMI class where the DCM is
.PARAMETER ClassName
    The WMI class for the DCM Baseline
.PARAMETER MethodName
    The name of the method to call on the WMI Object
.PARAMETER Credidential
    Supports PS Credential Objects
.NOTES
  Version:          1.0
  Author:           Adam Gross - @AdamGrossTX
  GitHub:           https://www.github.com/AdamGrossTX
  WebSite:          https://www.asquaredozen.com
  Creation Date:    08/08/2019
  Purpose/Change:   Initial script development
  
 #>
Function Invoke-FISCCMDCMEvaluation {
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true,HelpMessage="Enter Computer Names")]
        [String[]]
        $ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory=$True,HelpMessage="Enter the Name of the Baseline that will be on clients")]
        [String]
        $BaseLineName,

        [Parameter(Mandatory=$false,HelpMessage="HardSet for root\ccm\dcm, but can change")]
        [String]
        $NameSpace = "root\ccm\dcm",

        [Parameter(Mandatory=$false,HelpMessage="HardSet for SMS_DesiredConfiguration, but can be changed")]
        [String]
        $ClassName = "SMS_DesiredConfiguration",

        [Parameter(Mandatory=$false,HelpMessage="HardSet for TriggerEvaluation a method in SMS_DesiredConfiguration")]
        [String]
        $MethodName = "TriggerEvaluation",

        [Parameter(Mandatory=$false,HelpMessage="Enter Elevated Creds for remote computers")]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty  

    )
        $Status = @{
            0 = "NonCompliant"
            1 = "Compliant"
            2 = "NotApplicable"
            3 = "Unknown"
            4 = "Error"
            5 = "NotEvaluated"
        }
    if([Bool](Test-Connection -ComputerName $ComputerName -Count "1" -Quiet)) {
        Write-Verbose "$($ComputerName) is Powered on!" -Verbose
        Try {
            # Elevate $Credential var if remote
            if ($PSBoundParameters.ContainsKey('Credential')) {
                Write-Verbose "Passing -Credential into WMIInstance" -Verbose
                $Baselines = Get-WmiObject -Namespace $NameSpace -QUERY "SELECT * FROM $($ClassName) WHERE DisplayName LIKE ""$BaselineName""" -ComputerName $ComputerName -Credential $Credential
            }
            else { 
                $Baselines = Get-WmiObject -Namespace $NameSpace -QUERY "SELECT * FROM $($ClassName) WHERE DisplayName LIKE ""$BaselineName""" -ComputerName $ComputerName
            }

            If ($Baselines) {
                $Results = @()
                ForEach ($Baseline in $Baselines) {
                    Write-Verbose "Running Evaluation on: $($Baseline.DisplayName)" -Verbose
                    # Method MUST Be in this Order: IsEnforced = $True | IsMachineTarget = $True | $Method.Name = $Baseline.Name | $Method.PolicyType = 0 | $Method.Version = $Baseline.Version
                    [array]$WMIMethod = ($True,$True,$Baseline.Name,$Null,$Baseline.Version)
                    Write-Verbose "Triggering DCM Baseline" -Verbose
                    # Elevate $Credential var if remote
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        Write-Verbose "Passing -Credential into WMIMethod" -Verbose
                        Invoke-WmiMethod -Namespace $NameSpace -Class $ClassName -Name $MethodName -ArgumentList $WMIMethod -ComputerName $ComputerName -Credential $Credential
                    }
                    else { 
                        Invoke-WmiMethod -Namespace $NameSpace -Class $ClassName -Name $MethodName -ArgumentList $WMIMethod -ComputerName $ComputerName | Out-Null
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        [int]$ComplianceStatus = (Get-WmiObject -Namespace $NameSpace -QUERY "SELECT * FROM $($ClassName) WHERE DisplayName LIKE ""$($BaseLine.DisplayName)""" -ComputerName $ComputerName -Credential $Credential).LastComplianceStatus
                    }
                    else {
                        [int]$ComplianceStatus = (Get-WmiObject -Namespace $NameSpace -QUERY "SELECT * FROM $($ClassName) WHERE DisplayName LIKE ""$($BaseLine.DisplayName)""" -ComputerName $ComputerName).LastComplianceStatus
                    }
                    $Results += "{0} : {1}" -f $BaseLine.DisplayName, $Status[$ComplianceStatus]
                }
                Write-Verbose -Message "$($Results)" -Verbose
            }
            Else {
                Write-Warning "No Baseline Found" -Verbose
            }
        }
        Catch {
            Write-Error $_ -Verbose
            Return $Error[0]
        }
    }
    else { Write-Host -ForegroundColor "Red" "$($ComputerName) is Powered OFF!" -Verbose }
}