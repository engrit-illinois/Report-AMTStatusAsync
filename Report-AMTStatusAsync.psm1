# Documentation home: https://github.com/engrit-illinois/Report-AMTStatus
# By mseng3

function Report-AMTStatusAsync {

	param (
		[Parameter(Position=0,Mandatory=$true,ParameterSetName="Array")]
		[string[]]$Computers,
		
		[string]$OUDN = "OU=Desktops,OU=Engineering,OU=Urbana,DC=ad,DC=uillinois,DC=edu",
		
		[Parameter(Position=0,Mandatory=$true,ParameterSetName="Collection")]
		[string]$Collection,
		
		[string[]]$Username,
		
		[string[]]$Password,
		
		[int]$CredDelaySec = 0,
		
		[int]$ThrottleLimit = 20,
		
		[switch]$SkipPing,
		
		[switch]$SkipModel,
		
		[int]$Pings=1, # Number of times to ping before giving up
		
		[switch]$NoCSV,
		
		[switch]$ForceBootIfOff,
		
		[switch]$ForceBootIfHibernated,
		
		[switch]$WakeIfStandby,
		
		[switch]$SkipFWVer,
		
		[switch]$NoLog,
		
		[string]$LogPath="c:\engrit\logs\Report-AMTStatusAsync_$(Get-Date -Format `"yyyy-MM-dd_HH-mm-ss-ffff`").log",
		
		[int]$Verbosity=0,
		
		[string]$SiteCode="MP0",
		
		[string]$Provider="sccmcas.ad.uillinois.edu",
		
		[string]$CMPSModulePath="$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
	)
	
	function logAsync {
		param (
			[string]$msg,
			[int]$l=0, # level (of indentation)
			[int]$v=0, # verbosity level
			[switch]$nots, # omit timestamp
			[switch]$nnl # No newline after output
		)
		
		if(-not $nots) { $nots = $false }
		if(-not $nnl) { $nnl = $false }
		
		logNotAsync -msg $msg -l $l -v $v -nots:$nots -nnl:$nnl -async
	}
	
	function log {
		param (
			[string]$msg,
			[int]$l=0, # level (of indentation)
			[int]$v=0, # verbosity level
			[switch]$nots, # omit timestamp
			[switch]$nnl, # No newline after output
			[switch]$async
		)
		
		if(!(Test-Path -PathType leaf -Path $LogPath)) {
			$shutup = New-Item -ItemType File -Force -Path $LogPath
		}
		
		for($i = 0; $i -lt $l; $i += 1) {
			$msg = "    $msg"
		}
		if(!$nots) {
			$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
			$msg = "[$ts] $msg"
		}
		
		if($v -le $Verbosity) {
			if($nnl) {
				Write-Host $msg -NoNewline
			}
			else {
				Write-Host $msg
			}
			
			if((-not $NoLog) -and (-not $async)) {
				if($nnl) {
					$msg | Out-File $LogPath -Append -NoNewline
				}
				else {
					$msg | Out-File $LogPath -Append
				}
			}
		}
	}

	function Prep-SCCM {
		log "Preparing connection to SCCM..."
		$initParams = @{}
		if((Get-Module ConfigurationManager) -eq $null) {
			Import-Module $CMPSModulePath @initParams 
		}
		if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
			New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Provider @initParams
		}
		Set-Location "$($SiteCode):\" @initParams
		log "Done prepping connection to SCCM." -v 2
	}
	
	function Log-Error($e, $l) {
		log "$($e.Exception.Message)" -l $l
		log "$($e.InvocationInfo.PositionMessage.Split("`n")[0])" -l ($l + 1)
	}
	
	function count($array) {
		$count = 0
		if($array) {
			# If we didn't check $array in the above if statement, this would return 1 if $array was $null
			# i.e. @().count = 0, @($null).count = 1
			$count = @($array).count
			# We can't simply do $array.count, because if it's null, that would throw an error due to trying to access a method on a null object
		}
		$count
	}
	
	function Get-CompNameString($compNames) {
		$list = ""
		foreach($name in @($compNames)) {
			$list = "$list, $name"
		}
		$list = $list.Substring(2,$list.length - 2) # Remove leading ", "
		$list
	}
	
	function Get-CompNames {
		log "Getting list of computer names..."
		if($Computers) {
			log "List was given as an array." -l 1 -v 1
			$compNames = @()
			foreach($query in @($Computers)) {
				$thisQueryComps = (Get-ADComputer -Filter "name -like '$query'" -SearchBase $OUDN | Select Name).Name
				$compNames += @($thisQueryComps)
			}
			$compNamesCount = count $compNames
			log "Found $compNamesCount computers in given array." -l 1
			if($compNamesCount -gt 0) {
				$list = Get-CompNameString $compNames
				log "Computers: $list." -l 2
			}
		}
		elseif($Collection) {
			log "List was given as a collection. Getting members of collection: `"$Collection`"..." -l 1 -v 1
		
			$myPWD = $pwd.path
			Prep-SCCM
				
			$colObj = Get-CMCollection -Name $Collection
			if(!$colObj) {
				log "The given collection was not found!" -l 1
			}
			else {
				# Get comps
				$comps = Get-CMCollectionMember -CollectionName $Collection | Select Name,ClientActiveStatus
				if(!$comps) {
					log "The given collection is empty!" -l 1
				}
				else {
					# Sort by active status, with active clients first, just in case inactive clients might come online later
					# Then sort by name, just for funsies
					$comps = $comps | Sort -Property @{Expression = {$_.ClientActiveStatus}; Descending = $true}, @{Expression = {$_.Name}; Descending = $false}
					$compNames = $comps.Name
					
					$compNamesCount = count $compNames
					log "Found $compNamesCount computers in `"$Collection`" collection." -l 1
					if($compNamesCount -gt 0) {
						$list = Get-CompNameString $compNames
						log "Computers: $list." -l 2
					}
				}
			}
			
			Set-Location $myPWD
		}
		else {
			log "Somehow neither the -Computers, nor -Collection parameter was specified!" -l 1
		}
		
		log "Done getting list of computer names." -v 2
		
		$compNames
	}
	
	function Get-Creds {
		log "Getting credentials..."
		
		if($Username -and $Password) {
			log "-Username and -Password were both specified." -l 1 -v 2
			
			$creds = @()
			
			if(@($Username).count -ne @($Password).count) {
				log "-Username and -Password contain a different number of values!" -l 1
				log "To specify multiple sets of credentials, format these parameters like so:" -l 2 
				log "-Username `"user1name`",`"user2name`" -Password `"user1pass`",`"user2pass`"" -l 2
			}
			else {
				log "Building credentials..." -l 1
				if(@($Username).count -gt 1) {
					log "Multiple sets of credentials were specified." -l 2
				}
				
				for($i = 0; $i -lt @($Username).count; $i += 1) {
					$user = @($Username)[$i]
					$pass = @($Password)[$i]
					$securePass = ConvertTo-SecureString $pass -AsPlainText -Force
					$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user,$securePass
					$creds += @($cred)
				}
			}
		}
		else {
			log "-Username and/or -Password was not specified. Prompting for credentials." -l 1 -v 2
			if($Username) {
				$creds = Get-Credential $Username
			}
			else {
				$creds = Get-Credential
			}
		}
		log "Done getting credentials." -v 2
		$creds
	}
	
	function Get-State($comp, $creds, $credNum=0) {
		$cred = @($creds)[$credNum]
		$credNumFriendly = $credNum + 1
		log "Calling Get-AMTPowerState with credential set #$($credNumFriendly)/$(@($creds).count) (user: `"$($cred.UserName)`")..." -l 2
		
		try {
			$state = Get-AMTPowerState -ComputerName $comp -Credential $cred
		}
		catch {
			log "Get-AMTPowerState call failed!" -l 3
			Log-Error $_ 4
		}
		
		$workingCred = -1
		$forceBooted = "No"
		
		# If there was any result
		if($state) {
			log "Get-AMTPowerState call returned a result." -l 3 -v 1
			$desc = $state."Power State Description"
			$reason = $state.Reason
			$id = $state."Power State ID"
			
			$forceBooted = "No"
			
			# If the result has the data we want
			if($desc) {
				log "Get-AMTPowerState call received response: `"$desc`"." -l 3
				# If it didn't respond
				if($desc -eq "Cannot connect") {
					log "AMT didn't respond." -l 4
				}
				# If it responded, but didn't auth
				elseif($desc -eq "Unauthorized") {
					log "Credentials not authorized." -l 4
					$newCredNum = $credNum + 1
					if($newCredNum -ge @($creds).count) {
						log "No more credentials to try." -l 5
						$desc = "No working credentials"
					}
					else {
						log "Trying next set of credentials..." -l 5
						
						if($CredDelaySec -gt 0) {
							log "Waiting $CredDelaySec seconds to avoid flooding with attempts..." -l 6
							Start-Sleep -Seconds $CredDelaySec
						}
						
						$newState = Get-State $comp $creds $newCredNum
						$id = $newState.id
						$desc = $newState.desc
						$reason = $newState.reason
						$workingCred = $newState.workingCred
						$forceBooted = $newState.forceBooted
						$bootResult = $newState.bootResult
					}
				}
				# If it responds and is powered on
				elseif($desc -eq "On (S0)") {
					log "Computer is already powered on." -l 4
					$workingCred = $credNum
				}
				# If it responds and is powered off
				elseif($desc -eq "Off (S5)") {
					log "Computer is powered off." -l 4
					$workingCred = $credNum
					if($ForceBootIfOff) {
						log "-ForceBootIfOff was specified. Booting computer with Invoke-AMTForceBoot..." -l 4
						$bootResult = Invoke-AMTForceBoot -ComputerName $comp -Operation PowerOn -Device HardDrive -Credential $cred
						log "Result: `"$($bootResult.Status)`"." -l 5
						$forceBooted = "Yes"
					}
					else {
						log "-ForceBootIfOff was not specified." -l 4 -v 1
					}
				}
				# If it responds and is hibernated
				elseif($desc -eq "Hibernate (S4)") {
					log "Computer is hibernated." -l 4
					$workingCred = $credNum
					if($ForceBootIfHibernated) {
						log "-ForceBootIfHibernated was specified. Booting computer with Invoke-AMTForceBoot..." -l 4
						$bootResult = Invoke-AMTForceBoot -ComputerName $comp -Operation PowerOn -Device HardDrive -Credential $cred
						log "Result: `"$($bootResult.Status)`"." -l 5
						$forceBooted = "Yes"
					}
					else {
						log "-ForceBootIfHibernated was not specified." -l 4 -v 1
					}
				}
				elseif($desc -eq "Standby (S3)") {
					log "Computer is in standby." -l 4
					$workingCred = $credNum
					if($WakeIfStandby) {
						log "-WakeIfStandby was specified. Waking computer with Invoke-AMTPowerManagement..." -l 4
						$bootResult = Invoke-AMTPowerManagement -ComputerName $comp -Operation PowerOn -Credential $cred
						log "Result: `"$($bootResult.Status)`"." -l 5
						$forceBooted = "Yes"
					}
					else {
						log "-WakeIfStandby was not specified." -l 4 -v 1
					}
				}
				elseif($desc -eq "Exception Thrown") {
					log "Exception thrown by Get-AMTPowerState!" -l 4
					log "Reason: `"$reason`"." -l 5
					
					if($reason -like "*Password can contain between 8 to 32 characters*") {
						log "Credentials invalid." -l 4
						$newCredNum = $credNum + 1
						if($newCredNum -ge @($creds).count) {
							log "No more credentials to try." -l 5
							$desc = "No working credentials"
						}
						else {
							log "Trying next set of credentials..." -l 5
							
							if($CredDelaySec -gt 0) {
								log "Waiting $CredDelaySec seconds to avoid flooding with attempts..." -l 6
								Start-Sleep -Seconds $CredDelaySec
							}
							
							$newState = Get-State $comp $creds $newCredNum
							$id = $newState.id
							$desc = $newState.desc
							$reason = $newState.reason
							$workingCred = $newState.workingCred
							$forceBooted = $newState.forceBooted
							$bootResult = $newState.bootResult
						}
					}
				}
				else {
					log "Unrecognized result: `"$($desc): $($reason)`"" -l 4
					# Could potentially return valid states I don't know about
					# In which case $workingCred would incorrectly be -1
					# So newly discovered valid states should be given their own elseif block
					# However in a sample of 400+ computers, I never saw anything not accounted for above
				}
			}
			else {
				log "Get-AMTPowerState call returned an unexpected result!" -l 3
				$desc = "Unexpected result: `"$($desc): $($reason)`""
			}
		}
		else {
			log "Get-AMTPowerState returned no result." -l 3
			$desc = "Call failed"
		}
		log "Done calling Get-AMTPowerState for credential set #$credNumFriendly." -l 2 -v 2
		
		$result = [PSCustomObject]@{
			id = $id
			desc = $desc
			reason = $reason
			workingCred = $workingCred
			forceBooted = $forceBooted
			bootResult = $bootResult
		}
		$result
	}
	
	function Get-FW($comp, $cred) {
		#log "Calling Get-AMTFirmwareVersion with credential set #$($credNum + 1)/$(@($creds).count) (user: `"$($cred.UserName)`")..." -l 2
		log "Calling Get-AMTFirmwareVersion with known good credentials..." -l 2
		try {
			$fw = Get-AMTFirmwareVersion -ComputerName $comp -Credential $cred
		}
		catch {
			log "Get-AMTFirmwareVersion call failed!" -l 3
			Log-Error $_ 4
		}
		
		# If there was any result
		if($fw) {
			log "Get-AMTFirmwareVersion call returned a result." -l 3 -v 1
			$value = $fw."Value"
			
			# If the result has the data we want
			if($value) {
				log "Get-AMTFirmwareVersion call received response: `"$value`"." -l 3
				# If it didn't respond
				if($value -eq "Cannot connect") {
					log "AMT didn't respond." -l 4
				}
				# If it responded, but didn't auth
				elseif($value -eq "Unauthorized") {
					log "Credentials not authorized." -l 4
					
					# Now I'm only running this function with known good creds
					# So this should never happen
					<#
					$newCredNum = $credNum + 1
					if($newCredNum -ge @($creds).count) {
						log "No more credentials to try." -l 5
					}
					else {
						log "Trying next set of credentials..." -l 5
						$value = Get-FW $comp $creds $newCredNum
					}
					#>
				}
				# If it responds with an unrecognized value
				else {
					# It's probably a version number
					if($value -match '^\d*\.\d*\.\d*\.\d*$') {
						log "Result looks like a version number." -l 4
					}
					else {
						log "Result not recognized as a version number!" -l 4
					}
				}
			}
			else {
				log "Get-AMTFirmwareVersion call returned an unexpected result!" -l 3
				$value = "Unexpected result"
			}
		}
		else {
			log "Get-AMTFirmwareVersion returned no result." -l 3
			$value = "Call failed"
		}
		log "Done calling Get-AMTFirmwareVersion." -l 2 -v 2
		$value
	}
	
	function Get-HW($comp, $cred) {
		#log "Calling Get-AMTHardwareAsset with credential set #$($credNum + 1)/$(@($creds).count) (user: `"$($cred.UserName)`")..." -l 2
		log "Calling Get-AMTHardwareAsset with known good credentials..." -l 2
		
		# Recursion in the Traverse() function of the Get-AMTHardwareAsset cmdlet in the Intelvpro Powershell module of the AMT SDK v16.0.5.1 isn't implemented with adequate error checking, and can return both an error AND legitimate data, which breaks this try/catch.
		# Instead of trying to work around it here, I just added a workaround in Get-AMTHardwareAsset.ps1.
		try {
			$hw = Get-AMTHardwareAsset -ComputerName $comp -Credential $cred -ErrorAction "Stop"
		}
		catch {
			log "Get-AMTHardwareAsset call failed!" -l 3
			Log-Error $_ 4
			
			log ($hw.GetType() | Out-String)
		}
		
		# If there was any result
		if($hw) {
			log "Get-AMTHardwareAsset call returned a result." -l 3 -v 1

			# If it didn't respond
			if($hw -eq "Could not connect to host $comp : Check Name or IP address") {
				log "AMT didn't respond." -l 3
				$error = "AMT didn't respond"
			}
			# If it responded, but didn't auth
			elseif($hw -eq "Unauthorized to connect to $comp : Incorrect username or password") {
				log "Credentials not authorized." -l 3
				$error = "Credentials not authorized"
				
				# Now I'm only running this function with known good creds
				# So this should never happen
				<#
				$newCredNum = $credNum + 1
				if($newCredNum -ge @($creds).count) {
					log "No more credentials to try." -l 5
				}
				else {
					log "Trying next set of credentials..." -l 5
					$value = Get-HW $comp $creds $newCredNum
				}
				#>
			}
			# If it responds with an unrecognized value
			else {
				# It's probably the object we wanted
				
				# If the result has the data we want
				$csMake = $hw | Where { $_.PSParentPath -like "*ComputerSystem*" -and $_.Name -eq "Manufacturer" } | Select -ExpandProperty "Value"
				$csModel = $hw | Where { $_.PSParentPath -like "*ComputerSystem*" -and $_.Name -eq "Model" } | Select -ExpandProperty "Value"
				$csSerial = $hw | Where { $_.PSParentPath -like "*ComputerSystem*" -and $_.Name -eq "SerialNumber" } | Select -ExpandProperty "Value"
				
				$biosVer = $hw | Where { $_.PSParentPath -like "*BIOS\Primary BIOS*" -and $_.Name -eq "Version" } | Select -ExpandProperty "Value"
				$biosDate = $hw | Where { $_.PSParentPath -like "*BIOS\Primary BIOS*" -and $_.Name -eq "ReleaseDate" } | Select -ExpandProperty "Value"
				
				$memAccess = $hw | Where { $_.PSParentPath -like "*Memory\Memory 0*" -and $_.Name -eq "Access" } | Select -ExpandProperty "Value"
				
				$moboModel = $hw | Where { $_.PSParentPath -like "*Baseboard\Managed System Base Board*" -and $_.Name -eq "Model" } | Select -ExpandProperty "Value"
				$moboVer = $hw | Where { $_.PSParentPath -like "*Baseboard\Managed System Base Board*" -and $_.Name -eq "Version" } | Select -ExpandProperty "Value"
				$moboSerial = $hw | Where { $_.PSParentPath -like "*Baseboard\Managed System Base Board*" -and $_.Name -eq "SerialNumber" } | Select -ExpandProperty "Value"
				
				log "Make: `"$csMake`", Model: `"$csModel`", Serial: `"$csSerial`", BiosVer: `"$biosVer`", BiosDate: `"$biosDate`", MemAccess: `"$memAccess`", MoboModel: `"$moboModel`", MoboVer: `"$moboVer`", MoboSerial: `"$moboSerial`"" -l 3
			}
		}
		else {
			log "Get-AMTHardwareAsset returned no result." -l 3
			$value = "Call failed"
		}
		log "Done calling Get-AMTHardwareAsset." -l 2 -v 2
		
		$result = [PSCustomObject]@{
			"Make" = $csMake
			"Model" = $csModel
			"Serial" = $csSerial
			"BiosVer" = $biosVer
			"BiosDate" = $biosDate
			"MemAccess" = $memAccess
			"MoboModel" = $moboModel
			"MoboVer" = $moboVer
			"MoboSerial" = $moboSerial
			"Error" = $error
		}
		$result
	}
	
	function Get-CompData($comp, $creds, $progress) {
		
		$started = Get-Date
		
		if($progress) {
			log "Processing computer $progress`: `"$comp`"..." -l 1
		}
		else {
			log "Processing computer `"$comp`"..." -l 1
		}
	
		# Determine whether machine is online
		# Ping machine. AMT can be configured to respond to pings, but ours are not it seems, which is useful here
		$ponged = "Unknown"
		if($SkipPing) {
			log "-SkipPing was specified. Skipping ping." -l 2 -v 1
			$ponged = "Skipped"
		}
		else {
			log "Pinging computer... " -l 2 -nnl
			$ponged = "False"
			if(Test-Connection -ComputerName $comp -Count $Pings -Quiet) {
				log "Responded to ping." -nots
				$ponged = "True"
			}
			# If machine is offline
			else {
				log "Did not respond to ping." -nots
			}
		}
		
		$state = Get-State $comp $creds
		log "state: `"$state`"" -v 3
		
		$error = ""
		$stateID = $state.id
		$stateDesc = $state.desc
		$stateReason = $state.reason
		$workingCred = $state.workingCred
		$forceBooted = $state.forceBooted
		$bootResult = $state.bootResult.Status
		log "id: `"$stateID`", desc: `"$stateDesc`", reason: `"$stateReason`", workingCred: `"$workingCred`", forceBooted: `"$forceBooted`", bootResult: `"$bootResult`"" -v 3
		# Don't bother with more calls if we know they're not going to succeed
		if($state.workingCred -lt 0) {
			log "AMT on computer did not respond, or denied authentication for Get-AMTPowerState call. Skipping further AMT calls." -l 2
			$error = $stateDesc
			$stateID = ""
			$stateDesc = ""
			$stateReason = $stateReason
			$fwv = ""
			$csMake = ""
			$csModel = ""
			$csSerial = ""
			$biosVer = ""
			$biosDate = ""
			$memAccess = ""
			$moboModel = ""
			$moboVer = ""
			$moboSerial = ""
		}
		else {
			log "Get-AMTPowerState succeeded." -l 2
			if($SkipFWVer) {
				log "-SkipFWVer was specified. Skipping Get-AMTFirmwareVersion call." -l 2 -v 1
				$fwv = "Skipped"
			}
			else {
				log "Continuing with Get-AMTFirmwareVersion call." -l 2
				$fwv = Get-FW $comp $creds[$state.workingCred]
			}
			
			if($SkipModel) {
				log "-SkipModel was specified. Skipping Get-AMTHardwareAsset call." -l 2 -v 1
				$csMake = "Skipped"
				$csModel = "Skipped"
				$csSerial = "Skipped"
				$biosVer = "Skipped"
				$biosDate = "Skipped"
				$memAccess = "Skipped"
				$moboModel = "Skipped"
				$moboVer = "Skipped"
				$moboSerial = "Skipped"
			}
			else {
				log "Continuing with Get-AMTHardwareAsset call." -l 2
				$hw = Get-HW $comp $creds[$state.workingCred]
				if($hw.Error) {
					$csMake = "Error"
					$csModel = "Error"
					$csSerial = "Error"
					$biosVer = "Error"
					$biosDate = "Error"
					$memAccess = "Error"
					$moboModel = "Error"
					$moboVer = "Error"
					$moboSerial = "Error"
				}
				else {
					$csMake = $hw.Make
					$csModel = $hw.Model
					$csSerial = $hw.Serial
					$biosVer = $hw.BiosVer
					$biosDate = $hw.BiosDate
					$memAccess = $hw.MemAccess
					$moboModel = $hw.MoboModel
					$moboVer = $hw.MoboVer
					$moboSerial = $hw.MoboSerial
				}
			}
		}
		
		$ended = Get-Date
		$runtime = $ended - $started
		
		$compData = [PSCustomObject]@{
			"ComputerName" = $comp
			"Ponged" = $ponged
			"KnownError" = $error
			"ErrorReason" = $stateReason
			"Make" = $csMake
			"Model" = $csModel
			"Serial" = $csSerial
			"BiosVer" = $biosVer
			"BiosDate" = $biosDate
			"MemAccess" = $memAccess
			"MoboModel" = $moboModel
			"MoboVer" = $moboVer
			"MoboSerial" = $moboSerial
			"PowerStateID" = $stateID
			"PowerStateDesc" = $stateDesc
			"ForceBooted" = $forceBooted
			"BootResult" = $bootResult
			"Firmware" = $fwv
			"WorkingCred" = ($state.workingCred + 1) # Translating from index to human speech
			"Runtime" = $runtime
		}
		
		log "Done processing computer: `"$comp`"." -l 1 -v 2
		$compData
	}
	
	function Get-CompsData($comps, $creds) {
		$compsData = @()
		if(@($comps).count -gt 0) {
			log "Looping through computers..."
			$i = 1
			$count = @($comps).count
			
			<# Old sequential loop
			foreach($comp in $comps) {
				$percent = [math]::Round(($i - 1)/$count,2)*100
				$progress = "$i/$count ($percent%)"
				$compData = Get-CompData $comp $creds $progress
				$compsData += @($compData)
				$i += 1
			}
			#>
			
			# New parallel loop hack
			# Sacrifices logging, sane console output, and progress reporting
			
			$f_GetCompData = ${function:Get-CompData}.ToString()
			$f_GetState = ${function:Get-State}.ToString()
			$f_GetFW = ${function:Get-FW}.ToString()
			$f_GetHW = ${function:Get-HW}.ToString()
			$f_count = ${function:count}.ToString()
			$f_log = ${function:log}.ToString()
			$f_logAsync = ${function:logAsync}.ToString()
			$f_LogError = ${function:Log-Error}.ToString()
			
			$compsData = $comps | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
				$comp = $_
				
				${function:Get-CompData} = $using:f_GetCompData
				${function:Get-State} = $using:f_GetState
				${function:Get-FW} = $using:f_GetFW
				${function:Get-HW} = $using:f_GetHW
				${function:count} = $using:f_count
				${function:log} = $using:f_logAsync
				${function:logNotAsync} = $using:f_log
				${function:Log-Error} = $using:f_LogError
				
				$SkipPing = $using:SkipPing
				$Pings = $using:Pings
				$SkipFWVer = $using:SkipFWVer
				$SkipModel = $using:SkipModel
				$CredDelaySec = $using:CredDelaySec
				$ForceBootIfOff = $using:ForceBootIfOff
				$ForceBootIfHibernated = $using:ForceBootIfHibernated
				$WakeIfStandby = $using:WakeIfStandby
				$NoLog = $using:NoLog
				$LogPath = $using:LogPath
				$Verbosity = $using:Verbosity
				
				Get-CompData $comp $using:creds
			}
			
			log "Done looping through computers." -v 2
		}
		$compsData
	}
	
	function Select-CompsData($compsData) {
		$compsData | Select ComputerName,Ponged,KnownError,ErrorReason,WorkingCred,Firmware,PowerStateID,PowerStateDesc,ForceBooted,BootResult,Make,Model,Serial,BiosVer,BiosDate,MemAccess,MoboModel,MoboVer,MoboSerial,Runtime | Sort ComputerName
	}
	
	function Export-CompsData($compsData) {
		if($NoCSV) {
			log "-NoCSV was specified. Skipping export of gathered data." -v 1
		}
		else {
			if($compsData) {
				$csvPath = $LogPath.Replace('.log','.csv')
				log "Exporting data to: `"$csvPath`"..."
				$compsData | Export-Csv -Encoding ascii -NoTypeInformation -Path $csvPath
				log "Done exporting data." -v 2
			}
			else {
				log "There was no data to export to CSV."
			}
		}
	}
	
	function Print-CompsData($compsData) {
		$compsData | Format-Table *
	}
	
	function Do-Stuff {
		$started = Get-Date
		$creds = Get-Creds
		if(@($creds).count -gt 0) {
			$comps = Get-CompNames
			$compsData = Get-CompsData $comps $creds
			$compsData = Select-CompsData $compsData
			Export-CompsData $compsData
			Print-CompsData $compsData
		}
		$ended = Get-Date
		$runtime = $ended - $started
		log "Runtime: $runtime"
	}
	
	Do-Stuff
	
	log "EOF"
}
