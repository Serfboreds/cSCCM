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
		$RuleName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ParentCollection,
        
		[parameter(Mandatory = $true)]
		[PSCredential]
		$SCCMAdministratorCredential,

		[ValidateSet("1","2")]
		[System.String]
		$ParentCollectionType = "2",

		[ValidateSet("Direct","Exclude","Include","Query")]
		[System.String]
		$QueryType = "Query"
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
   
   #Grab the ParentCollection if it exists
    switch ($ParentCollectionType) {
        1 {$CMCollection = Get-CMUserCollection -Name $ParentCollection}
        2 {$CMCollection = Get-CMDeviceCollection -Name $ParentCollection}
        }

    #Search the Collection for any rule matching the RuleName
    If($ParentCollectionType -eq "1" -and $CMCollection) {
        switch ($QueryType) {
            Direct {$QueryExpressionReturn = (Get-CMUserCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceName $RuleName).RuleName}
            Exclude{$QueryExpressionReturn = (Get-CMUserCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName).ExcludeCollectionID}
            Include{$QueryExpressionReturn = (Get-CMUserCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName).IncludeCollectionID}
            Query  {$QueryExpressionReturn = (Get-CMUserCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName).QueryExpression}
            }
        }
    Elseif($ParentCollectionType -eq "2" -and $CMCollection) {
        switch ($QueryType) {
            Direct {$QueryExpressionReturn = (Get-CMDeviceCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceName $RuleName).RuleName}
            Exclude{$QueryExpressionReturn = (Get-CMDeviceCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName).ExcludeCollectionID}
            Include{$QueryExpressionReturn = (Get-CMDeviceCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName).IncludeCollectionID}
            Query  {$QueryExpressionReturn = (Get-CMDeviceCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName).QueryExpression}
            }
        }

	$returnValue = @{
		RuleName = $RuleName
		ParentCollection = if($CMCollection){$ParentCollection}else{''}
		ParentCollectionType = if($ParentCollectionType -eq "1"){'User'}else{'Device'}
		QueryExpression = $QueryExpressionReturn
        QueryType = $QueryType
		Ensure = if($QueryExpressionReturn){'Present'}else{'Absent'}
	}
    
    #Logout
    Set-Location $OriginalLocation
    if ($context) {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }

	$returnValue
	
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
		$RuleName,
        
        [parameter(Mandatory = $true)]
		[System.String]
		$ParentCollection,
        
        [parameter(Mandatory = $true)]
        [PSCredential]
        $SCCMAdministratorCredential,

		[ValidateSet("1","2")]
		[System.String]
		$ParentCollectionType,
        
        [ValidateSet("Direct","Exclude","Include","Query")]
		[System.String]
		$QueryType,

		[System.String]
		$QueryExpression,

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
		$RuleName,

		[parameter(Mandatory = $true)]
        [System.String]
		$ParentCollection,
        
        [parameter(Mandatory = $true)]
        [PSCredential]
        $SCCMAdministratorCredential,

		[ValidateSet("1","2")]
		[System.String]
		$ParentCollectionType,

        [ValidateSet("Direct","Exclude","Include","Query")]
		[System.String]
		$QueryType,		

        [System.String]
		$QueryExpression,

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
		$RuleName,
        
        [parameter(Mandatory = $true)]
		[System.String]
		$ParentCollection,
        
        [parameter(Mandatory = $true)]
        [PSCredential]
        $SCCMAdministratorCredential,

		[ValidateSet("1","2")]
		[System.String]
		$ParentCollectionType = "2",
        
        [ValidateSet("Direct","Exclude","Include","Query")]
		[System.String]
		$QueryType = "Query",

		[System.String]
		$QueryExpression,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

        [switch]
        $Apply
	)
    
    #Preset The Return varibale for a test
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
    $Site = $CM12ProviderLocation.SiteCode
    if(!((Get-PSDrive) -like $Site)) {
        throw "Problems discovering a valid Site.  Please Investigate."
        }
    $OriginalLocation = Get-Location
    Set-Location ${Site}:
   
   #Grab the ParentCollection if it exists
    switch ($ParentCollectionType) {
        1 {$CMCollection = Get-CMUserCollection -Name $ParentCollection}
        2 {$CMCollection = Get-CMDeviceCollection -Name $ParentCollection}
        }
    if(!($CMCollection)) {
        Throw "The mandatory parent collection $ParentCollection cannot be found.  Please Correct Entry."
        }

    #Search the Collection for any rule matching the RuleName
    If($ParentCollectionType -eq "1") {
        switch ($QueryType) {
            Direct {$CMQuery = Get-CMUserCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceName $RuleName}
            Exclude{$CMQuery = Get-CMUserCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName}
            Include{$CMQuery = Get-CMUserCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName}
            Query  {$CMQuery = Get-CMUserCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName}
            }
        }
    Elseif($ParentCollectionType -eq "2") {
        switch ($QueryType) {
            Direct {$CMQuery = Get-CMDeviceCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceName $RuleName}
            Exclude{$CMQuery = Get-CMDeviceCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName}
            Include{$CMQuery = Get-CMDeviceCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName}
            Query  {$CMQuery = Get-CMDeviceCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName}
            }
        }

    #If $Ensure is set to 'Absent', take action to report or delete the query then quit
    if($Ensure -eq 'Absent') {
        if ($CMQuery -and !($Apply)){
            [boolean]$TestedOK = $false
            }
        elseif($CMQuery -and $Apply -and ($ParentCollectionType -eq "1")){
            switch ($QueryType) {
                Direct {Remove-CMUserCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceName $RuleName -force}
                Exclude{Remove-CMUserCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName -force}
                Include{Remove-CMUserCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName -force}
                Query  {Remove-CMUserCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName -force}
                }
            }
        elseif($CMQuery -and $Apply -and ($ParentCollectionType -eq "2")){
            switch ($QueryType) {
                Direct {Remove-CMDeviceCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceName $RuleName -force}
                Exclude{Remove-CMDeviceCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName -force}
                Include{Remove-CMDeviceCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName -force}
                Query  {Remove-CMDeviceCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName -force}
                }
            }
        }

    else{
        #Translate $QueryType Specfic Variables needed to create Collections
        if($QueryType -eq "Direct") {
            switch ($ParentCollectionType) {
                1 {$QueryResourceID = (Get-CMUser -Name $RuleName).ResourceID}
                2 {$QueryResourceID = (Get-CMDevice -Name $RuleName).ResourceID}
                }
            }

        #Create the new rule if it is missing
        if(!($CMQuery)) {
            if (!($Apply)) {
                [boolean]$TestedOK = $false
                }
            elseif($Apply -and ($ParentCollectionType -eq "1")) {
                switch ($QueryType) {
                    Direct {Add-CMUserCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceID $QueryResourceID}
                    Exclude{Add-CMUserCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName}
                    Include{Add-CMUserCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName}
                    Query  {Add-CMUserCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName -QueryExpression $QueryExpression}
                    }
                }
            elseif($Apply -and ($ParentCollectionType -eq "2")) {
                switch ($QueryType) {
                    Direct {Add-CMDeviceCollectionDirectMembershipRule -CollectionName $CMCollection.Name -ResourceID $QueryResourceID}
                    Exclude{Add-CMDeviceCollectionExcludeMembershipRule -CollectionName $CMCollection.Name -ExcludeCollectionName $RuleName}
                    Include{Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $CMCollection.Name -IncludeCollectionName $RuleName}
                    Query  {Add-CMDeviceCollectionQueryMembershipRule -CollectionName $CMCollection.Name -RuleName $RuleName -QueryExpression $QueryExpression}
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

    #Return The Test results if $apply is not set
    if(!($Apply)) {
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

Export-ModuleMember -Function *-TargetResource
