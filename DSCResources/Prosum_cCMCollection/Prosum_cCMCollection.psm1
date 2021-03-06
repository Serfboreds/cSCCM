######################################################################################
# The Get-TargetResource cmdlet.
# This function will get the collection if it exists and return all information
######################################################################################
function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$CollectionName,
        
        [parameter(Mandatory = $true)]
        [PSCredential]
        $SCCMAdministratorCredential,

        [ValidateSet("1","2")]		
        [System.String]
		$CollectionType = "2"
	)
    
    #Login
    ($oldToken, $context, $newToken) = ImpersonateAs -cred $SCCMAdministratorCredential

	#Load Module if missing then set the location for execution
    if(!(Get-Module ConfigurationManager)) {
        Try {
            Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1')
            }
        Catch {
            Throw "Cannot load the SCCM Module, please ensure the SCCM Admin tools are installed and try again"
            }
        }
    $ComputerInfo = Get-WmiObject Win32_ComputerSystem
    $ComputerFQDN = $ComputerInfo.Name + '.' + $ComputerInfo.Domain
    $CM12ProviderLocation = Get-WmiObject -Query "Select * From SMS_ProviderLocation where ProviderForLocalSite = True" -Namespace "root\sms" -computername $ComputerFQDN
    $Site = $CM12ProviderLocation.SiteCode
    if(!((Get-PSDrive) -like $Site)) {
        throw "Problems discovering a valid Site.  Please Investigate."
        }
    $OriginalLocation = Get-Location
    Set-Location ${Site}:

    #Gather Collection and Parent Folder Information, and set the ObjectType for WMI Queries
    switch ($CollectionType) {
        1 {$CMCollection = Get-CMUserCollection -Name $CollectionName
            $FolderObjectType = "5001"}
        2 {$CMCollection = Get-CMDeviceCollection -Name $CollectionName
            $FolderObjectType = "5000"}
        }
    $CMCollectionID = $CMCollection.CollectionID
	$FolderObj = (Get-WmiObject -Class SMS_ObjectContainerItem -Namespace Root\SMS\Site_$Site -Filter "InstanceKey='$CMCollectionID' and ObjectType='$FolderObjectType'").ContainerNodeID
    $FolderName = (Get-WmiObject -Class SMS_ObjectContainerNode -Namespace Root\SMS\Site_$Site -Filter “ContainerNodeID='$FolderObj' and ObjectType='$FolderObjectType'”).Name

    $ReturnValue = @{
		CollectionName = $CMCollection.Name
		LimitingCollectionName = $CMCollection.LimitToCollectionName
		ParentFolder = if($FolderName){$FolderName}else{'Root'}
		Comment = $CMCollection.Comment
        Site = if($CMCollection){$CMCollection.CollectionID.Substring(0,3)}else{''}
		CollectionType = if($CMCollection.CollectionType -eq '1'){'User'}elseif($CMCollection.CollectionType -eq '2'){'Device'}else{''}
		RefreshDays = $CMCollection.RefreshSchedule.DaySpan
		RefreshType = if($CMCollection.RefreshType -eq '2'){'Periodic'}elseif($CMCollection.RefreshType -eq '4'){'Incremental'}elseif($CMCollection.RefreshType -eq '6'){'Both'}else{''}
		RefreshStart = $CMCollection.RefreshSchedule.StartTime
        Ensure = if($CMCollection){'Present'}else{'Absent'}
        }

    #Logout
    Set-Location $OriginalLocation
    if ($context) {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }

    $ReturnValue
}

######################################################################################
# The Set-TargetResource cmdlet.
# This function will pass the "apply" switch back to the validate function
######################################################################################
function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$CollectionName,
        
        [parameter(Mandatory = $true)]
        [PSCredential]
        $SCCMAdministratorCredential,

		[System.String]
		$LimitingCollectionName,

		[System.String]
		$ParentFolder,

		[System.String]
		$Comment,

		[System.String]
		$Site,

		[ValidateSet("1","2")]
		[System.String]
		$CollectionType,

		[System.String]
		$RefreshDays,

		[ValidateSet("2","4","6")]
		[System.String]
		$RefreshType,

		[System.DateTime]
		$RefreshStart,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure
	)

    ValidateProperties @PSBoundParameters -Apply

}

######################################################################################
# The Test-TargetResource cmdlet.
# This function will only return a $true $false on compliance
######################################################################################
function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$CollectionName,
        
        [parameter(Mandatory = $true)]
        [PSCredential]
        $SCCMAdministratorCredential,

		[System.String]
		$LimitingCollectionName,

		[System.String]
		$ParentFolder,

		[System.String]
		$Comment,

		[System.String]
		$Site,

		[ValidateSet("1","2")]
		[System.String]
		$CollectionType,

		[System.String]
		$RefreshDays,

		[ValidateSet("2","4","6")]
		[System.String]
		$RefreshType,

		[System.DateTime]
		$RefreshStart,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure
	)

ValidateProperties @PSBoundParameters

}


######################################################################################
# The ValidateProperties cmdlet.
# This function accepts an -apply flag and "does the work"
######################################################################################
function ValidateProperties
{
param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$CollectionName,
        
        [parameter(Mandatory = $true)]
        [PSCredential]
        $SCCMAdministratorCredential,

		[System.String]
		$LimitingCollectionName,

		[System.String]
		$ParentFolder,

		[System.String]
		$Comment,

		[System.String]
		$Site,

		[ValidateSet("1","2")]
		[System.String]
		$CollectionType = "2",

		[System.String]
		$RefreshDays,

		[ValidateSet("2","4","6")]
		[System.String]
		$RefreshType,

		[System.DateTime]
		$RefreshStart,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [Switch]$Apply
	)
    
    #Set initial TestedOK value to true, whch will be called later to see if all variables are still valid
    [boolean]$TestedOK = $true
    
    #Login
    ($oldToken, $context, $newToken) = ImpersonateAs -cred $SCCMAdministratorCredential

    #Load Module if missing then set the location for execution
    if(!(Get-Module ConfigurationManager)) {
        Try {
            Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1')
            }
        Catch {
            Throw "Cannot load the SCCM Module, please ensure the SCCM Admin tools are installed and try again"
            }
        }
    $ComputerInfo = Get-WmiObject Win32_ComputerSystem
    $ComputerFQDN = $ComputerInfo.Name + '.' + $ComputerInfo.Domain
    $CM12ProviderLocation = Get-WmiObject -Query "Select * From SMS_ProviderLocation where ProviderForLocalSite = True" -Namespace "root\sms" -computername $ComputerFQDN
    if(!($Site)) {    
        $Site = $CM12ProviderLocation.SiteCode
        }
    if(!((Get-PSDrive) -like $Site)) {
        throw "Problems discovering a valid Site.  Please Investigate."
        }
    $OriginalLocation = Get-Location
    Set-Location ${Site}:

    #Gather the Collection and Parent Collection and set folder variables
    Switch($CollectionType)
    {
    1 {
        $CollExist = Get-CMUserCollection -Name $CollectionName
        If($LimitingCollectionName) {$ParentCollExist = Get-CMUserCollection -Name $LimitingCollectionName}
        $ConflictExist = Get-CMDeviceCollection -Name $CollectionName
        $CollectionFolder = $Site + ':\UserCollection\'
        $FolderType = "5001"
        }
    2 {
        $CollExist = Get-CMDeviceCollection -Name $CollectionName
        If($LimitingCollectionName) {$ParentCollExist = Get-CMDeviceCollection -Name $LimitingCollectionName}
        $ConflictExist = Get-CMUserCollection -Name $CollectionName
        $CollectionFolder = $Site + ':\DeviceCollection\'
        $FolderType = "5000"
        }
    }

    If($Ensure -eq 'Absent') {
        #Delete if Collection exists and Ensure is Absent
        If($CollExist) {
            If($Apply) {
                Switch($CollectionType) {
                    1 {Remove-CMUserCollection -Name $CollectionName -force}
                    2 {Remove-CMDeviceCollection -Name $CollectionName -force}
                    }
                }
            else {
                [boolean]$TestedOK = $false
                }
            }
        }

    Else {

        #Check for collection and it's parent, make corrections if needed.
        If(!($ParentCollExist) -and $LimitingCollectionName) {
            throw "The limiting collection $LimitingCollectionName cannot be found in Site $Site."
            }
        If($ConflictExist) {
            throw "A conflicting collection already exists with the name $CollectionName as another collection type."
            }
        
        #If the Collection Doesn't Exist, create it and recapture the $CollExist variable
        If(!($CollExist)) {
            Write-Verbose -Message "Collection $CollectionName cannot be found in Site $Site."
            If($apply){
                Write-Verbose -Message "Creating Collection..."
                If(!($LimitingCollectionName)) {$LimitingCollectionName = "All Systems"}
                Switch($CollectionType) {
                    1 {$CreateCollection = New-CMUserCollection -Name $CollectionName -LimitingCollectionName $LimitingCollectionName}
                    2 {$CreateCollection = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $LimitingCollectionName}
                    }
                $CollExist = $CreateCollection
                }
            else {
                [boolean]$TestedOK = $false
                }
            }

        #If the Collection STILL doesn't exist (recheck), it's becuase -apply wasn't set and these checks are unnessisary
        If($CollExist) {
            #Correct the Limiting Collection Name, if needed
            if(!($CollExist.LimitToCollectionName -eq $LimitingCollectionName) -and $LimitingCollectionName) {
                $cur = $CollExist.LimitToCollectionName
                Write-verbose -Message "Limiting Collection $cur does not match the desired name $LimitingCollectionName."
                if($Apply) {
                    Write-Verbose -Message "Updating Limiting Collection..."
                    Switch($CollectionType)
                    {
                        1 {Set-CMUserCollection -Name $CollectionName -LimitingCollectionName $LimitingCollectionName}
			            2 {Set-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $LimitingCollectionName} 
                        }
                    }
                else {
                    [boolean]$TestedOK = $false
                    }
               
                }  
    
            #Correct the Comment, if needed
            if(!($CollExist.Comment -eq $Comment) -and $Comment) {
                    Write-verbose -Message "The Comment does not match the desired value."
                    if($Apply) {
                        Write-Verbose -Message "Updating Comments..."
                        Switch($CollectionType)
                        {
                            1 {Set-CMUserCollection -Name $CollectionName -Comment $Comment}
			                2 {Set-CMDeviceCollection -Name $CollectionName -Comment $Comment} 
                            }
                        }
                    else {
                        [boolean]$TestedOK = $false
                        }
                    }
    
            #Correct the RefreshType, if needed
            if(!($CollExist.RefreshType -eq $RefreshType) -and $RefreshType) {
                    Write-verbose -Message "The Refresh Type is set incorrectly."
                    if($Apply) {
                        Write-Verbose -Message "Updating RefreshType..."
                        $CollExist.RefreshType = $RefreshType
                        $CollExist.put() | Out-Null
                        }
                    else {
                        [boolean]$TestedOK = $false
                        }
               
                    }

            #Correct the RefreshDays and generate a startdate, if needed.  These are processed together as both variables are related
            $IntervalClass = [WMIClass]"\\$($ComputerFQDN)\root\SMS\Site_$($Site):SMS_ST_RecurInterval"
            $Interval = $IntervalClass.CreateInstance()
            $CollExistID = $CollExist.CollectionID
            $CollExistWMI = [wmi]"\\$($ComputerFQDN)\root\SMS\Site_$($Site):SMS_Collection.CollectionID='$CollExistID'"
            if(!($CollExistWMI.RefreshSchedule.DaySpan -eq $RefreshDays) -and $RefreshDays) {
                    Write-verbose -Message "The Refresh Days is set incorrectly."
                    if($Apply) {
                        Write-Verbose -Message "Updating RefreshDays..."
                        $Interval.DaySpan = $RefreshDays
                        if(!($RefreshStart) -and !($CollExistWMI.RefreshSchedule.StartTime)) {
                            Write-Verbose -Message "No Refresh start time has been specified, generating a random date"
                            $DateMin = Get-date -year 2011 -month 1 -day 1
		                    $DateMax = Get-date
		                    $NewRefreshStart = New-object DateTime(Get-Random -min $DateMin.ticks -max $DateMax.ticks)
                            }
                        elseif(!($RefreshStart) -and $CollExistWMI.RefreshSchedule.StartTime) {
                            $NewRefreshStart = [System.Management.ManagementDateTimeconverter]::ToDateTime($CollExistWMI.RefreshSchedule.StartTime)
                            }
                        }
                    else {
                        [boolean]$TestedOK = $false
                        }
                    }
            #If the RefreshDays hasn't been set, set the Interval variable to live variable so it doesn't change during commit
            if(!($RefreshDays)) {$Interval.DaySpan = $CollExistWMI.RefreshSchedule.DaySpan}
            
            #Compare the stored Start Time with the desired start time
            if($CollExistWMI.RefreshSchedule.StartTime){$CollExistStartTime = [System.Management.ManagementDateTimeconverter]::ToDateTime($CollExistWMI.RefreshSchedule.StartTime)}
            if((!($CollExistStartTime -eq $RefreshStart) -and $RefreshStart) -or (!($CollExistStartTime -eq $NewRefreshStart) -and $NewRefreshStart)) {
                    if(!($RefreshStart)) {$RefreshStart = $NewRefreshStart}
 		            $Date = [System.Management.ManagementDateTimeconverter]::ToDMTFDateTime($RefreshStart.ToString())
                    if($Apply) {
                        Write-verbose -Message "Updating..."
		                $Interval.StartTime = $Date
                        }
                    else {
                        [boolean]$TestedOK = $false
                        }
                    }
            #If the RefreshStart hasn't been set, set the Interval variable to live variable so it doesn't change during commit
            if(!($RefreshDays) -and !($NewRefreshStart)) {$Interval.StartTime = $CollExistWMI.RefreshSchedule.StartTime}


            #If any interval changes were collected, it's time to apply them
            if($apply) {
                $CollExistWMI.RefreshSchedule = $Interval
                $CollExistWMI.put() | Out-Null
                }

            #Move a Collection to the appropriate Folder
            $CollExistID = $CollExist.CollectionID
	        $CurrFolderID = (Get-WmiObject -Class SMS_ObjectContainerItem -Namespace Root\SMS\Site_$Site -Filter "InstanceKey='$CollExistID' and ObjectType='$FolderType'").ContainerNodeID
            $CurrFolder = (Get-WmiObject -Class SMS_ObjectContainerNode -Namespace Root\SMS\Site_$Site -Filter “ContainerNodeID='$CurrFolderID'  and ObjectType='$FolderType'”).Name
            if(!($CurrFolderID)) {$CurrFolderID = 0}
            if(!($CurrFolder)) {$CurrFolder = "Root"}
            if(!($CurrFolder -eq $ParentFolder) -and $ParentFolder){
                Write-Verbose -Message "The collection was not found in $ParentFolder."
                if($apply) {
                    Write-Verbose -Message "Moving..."
                    $ParentFolderID = (Get-WmiObject -Class SMS_ObjectContainerNode -Namespace Root\SMS\Site_$Site | where-object {$_.Name -eq $ParentFolder -and $_.ObjectType -eq $FolderType}).ContainerNodeID
                    If(!($ParentFolderID)) {$ParentFolderID ="0"}
                    $ContainerItem = [WMIClass]"\\$ComputerFQDN\root\SMS\Site_${Site}:SMS_ObjectContainerItem"
		            $MoveItem = $ContainerItem.PSBase.GetMethodParameters("MoveMembers")
		            $MoveItem.ContainerNodeID = $CurrFolderID
		            $MoveItem.InstanceKeys = $CollExistID
		            $MoveItem.ObjectType = $FolderType
		            $MoveItem.TargetContainerNodeID = $ParentFolderID
		            $Result = $ContainerItem.PSBase.InvokeMethod("MoveMembers",$MoveItem,$null)
	                Write-Verbose -Message "Moved collection $CollExistID to folder $ParentFolder"
                    }
                else {
                    [boolean]$TestedOK = $false
                    }
                }
            }
        }

    #Logout
    Set-Location $OriginalLocation
    if ($context) {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    
    #If this is only a test, return the results
    if(!($apply)){
        return $TestedOK
        }
}

######################################################################################
# The below functions are used for user impersonation
# There are 3 functions in total
######################################################################################
function Get-ImpersonatetLib
{
    if ($script:ImpersonateLib)
    {
        return $script:ImpersonateLib
    }

    $sig = @'
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);

[DllImport("kernel32.dll")]
public static extern Boolean CloseHandle(IntPtr hObject);
'@ 
   $script:ImpersonateLib = Add-Type -PassThru -Namespace 'Lib.Impersonation' -Name ImpersonationLib -MemberDefinition $sig 

   return $script:ImpersonateLib
    
}

function ImpersonateAs([PSCredential] $cred)
{
    [IntPtr] $userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token
    $userToken
    $ImpersonateLib = Get-ImpersonatetLib

    $bLogin = $ImpersonateLib::LogonUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, $cred.GetNetworkCredential().Password, 
    9, 0, [ref]$userToken)
    
    if ($bLogin)
    {
        $Identity = New-Object Security.Principal.WindowsIdentity $userToken
        $context = $Identity.Impersonate()
    }
    else
    {
        throw "Can't Logon as User $cred.GetNetworkCredential().UserName."
    }
    $context, $userToken
}

function CloseUserToken([IntPtr] $token)
{
    $ImpersonateLib = Get-ImpersonatetLib

    $bLogin = $ImpersonateLib::CloseHandle($token)
    if (!$bLogin)
    {
        throw "Can't close token"
    }
}

#  FUNCTIONS TO BE EXPORTED 
Export-ModuleMember -Function *-TargetResource
