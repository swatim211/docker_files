#Parameters
param ([string]$mode, [string]$mount, [string]$db_import, 
	[string]$sec_import, [string]$ui_import, [string]$gw_import, 
	[string]$config, [string]$cfg_import, [string]$host_ip)

#enable scripting
Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force

#set asset guard version variable
$env:ASSETGUARD_VERSION = "2.0"

function CreateImage([string]$image) {
	Invoke-Expression "docker load -i $image"
}

function DeleteService([string]$service) {
	Invoke-Expression ("docker-compose rm -s -f " + $service)		
}

function ResetService([string]$service) {
	DeleteService $service
	
	Invoke-Expression ("docker-compose up -d " + $service)
}

function DeleteImageByName([string] $name) {
	$search = (docker images | Select-String -Pattern "asset_guard/$name") -split("\s+")
	Invoke-Expression ("docker image rm " + $search[2])
}

function CheckMountDirectory([string] $mountDir) {	
	if($mountDir -eq "" -or $mountDir -eq $null) {
		$msg = "Invalid source path has been specified"
		Write-Output $msg
		exit		
	}

	if(![System.IO.Directory]::Exists($mountDir)) {
		$msg = "The source path $mountDir doesn't exist"
		Write-Output $msg
		exit
	}
}

function DisplayStatus() {
	Write-Output "" 
	Write-Output "-----------------" 
	Write-Output "Container Status:" 
	Write-Output "-----------------" 
	Invoke-Expression ("docker ps -a --format 'table {{.Names}}\t{{.Status}}'")
}

if([string]::IsNullOrEmpty($mode)) {
    Write-Output "Available modes: "
    Write-Output "install                     | Installs all docker images (First Installation)"
    Write-Output "full-update                 | Re-creates all images without overwritting the existing DB"
    Write-Output "gw-db-update                | Re-initializes the asset guard gateway database. All existing tables will be overwritten"	
    Write-Output "ui-update                   | Re-initializes the UI docker image"
    Write-Output "securityserver-update       | Re-initializes the UI docker image"
    Write-Output "gateway-update              | Re-initializes the gateway docker image"    
    Write-Output "uninstall                   | Uninstalls all docker containers"
	Write-Output "factory-reset               | Resets system database to factory, delete all logfiles"
	Write-Output "sw-restart                  | Restarts all running containers"
    exit
}

if([string]::IsNullOrEmpty($db_import)) {
	$db_import = "AssetGuard_NG_DB.tar"
} 
if([string]::IsNullOrEmpty($cfg_import)) {
	$cfg_import = "AssetGuard_NG_CFG.tar"
} 
if([string]::IsNullOrEmpty($gw_import)) {
	$gw_import = "AssetGuard_NG_GW.tar" 
} 
if([string]::IsNullOrEmpty($sec_import)) {
	$sec_import = "AssetGuard_NG_SecSrv.tar" 
} 
if([string]::IsNullOrEmpty($ui_import)) {
	$ui_import = "AssetGuardUI.tar" 
}

$env:CONFIG_FILE=$config
$env:SETTINGS_DIR=$mount
$env:HOST_IP=$host_ip

switch($mode){
    
    install {
        if([string]::IsNullOrEmpty($mount) -or [string]::IsNullOrEmpty($config) -or 
			[string]::IsNullOrEmpty($host_ip))
        {
            Write-Output "Please use following options to initialize the asset guard system:"
            Write-Output "-mount        | Shared directory on the docker host machine."
            Write-Output "-config       | Customer specific asset configuration (xml file)."             
            Write-Output "-host_ip      | The IP address of the host machine" 
            exit
        }
        else {
			CheckMountDirectory($mount)

			Write-Output "This operation could take up to 5 minutes..."
			
			CreateImage $db_import
			Invoke-Expression ("docker-compose up -d database")
			#Invoke-Expression ("docker wait asset_guard_db")
			CreateImage $cfg_import
			Invoke-Expression ("docker-compose up -d config")
			Invoke-Expression ("docker wait asset_guard_cfg")
			CreateImage $gw_import
			Invoke-Expression ("docker-compose up -d gateway")
			CreateImage $sec_import
			Invoke-Expression ("docker-compose up -d auth-server")
			CreateImage $ui_import
			Invoke-Expression ("docker-compose up -d ui")
			
			#setup scheduler tasks
			$path = split-path -parent $MyInvocation.MyCommand.Definition
			Write-Output "Creating Windows scheduler tasks"
						
			Invoke-Expression "schtasks /create /tn `"docker_vm_start`" /sc onstart /delay 0002:30 /rl highest /tr `"powershell.exe -windowstyle hidden -file $path\ContainerStart.ps1 -hip $host_ip`""
			#Invoke-Expression("schtasks /create /tn `"lock_user`" /sc onlogon /rl highest /tr `"rundll32.exe user32.dll,LockWorkStation`"")

			DisplayStatus
        }    
    }
    gw-db-update {
        if([string]::IsNullOrEmpty($config) -or [string]::IsNullOrEmpty($mount)) 
        {
            Write-Output "Please use following options to initialize the database:"
            Write-Output "-mount        | Shared directory on the docker host machine."
            Write-Output "-config       | Customer specific asset configuration (xml file)"            
            exit
        }
        else {
			
			CheckMountDirectory($mount)

			Invoke-Expression ("docker-compose stop ui")
			Invoke-Expression ("docker-compose stop auth-server")
			Invoke-Expression ("docker-compose stop gateway")

			DeleteService "config"
			DeleteImageByName("configtool")
			CreateImage $cfg_import
			Invoke-Expression ("docker-compose up -d config")
			Invoke-Expression ("docker wait asset_guard_cfg")

			Invoke-Expression ("docker-compose start gateway")			
			Invoke-Expression ("docker-compose start auth-server")			
			Invoke-Expression ("docker-compose start ui")

			DisplayStatus
        }
    }	
    ui-update {
        if([string]::IsNullOrEmpty($mount) -or [string]::IsNullOrEmpty($host_ip)) 
        {
            Write-Output "Please use following options to initialize asset guard ui:"
            Write-Output "-mount       	| Shared directory on the docker host machine."            
            Write-Output "-host_ip		| The IP address of the host machine" 
            exit
        }
        else {
			CheckMountDirectory($mount)

			DeleteService "ui"
			Invoke-Expression ("docker-compose up -d ui")
			
			DisplayStatus
        }
    }
    gateway-update {
        if([string]::IsNullOrEmpty($mount)) 
        {
            Write-Output "Please use following options to initialize asset guard gateway:"
            Write-Output "-mount        | Shared directory on the docker host machine."             
            exit
        }
        else {
			CheckMountDirectory($mount)
            ResetService "gateway"			
			DisplayStatus
        }
    }
    securityserver-update {
        if([string]::IsNullOrEmpty($config) -or [string]::IsNullOrEmpty($mount)) 
        {
            Write-Output "Please use following options to initialize the database:"
            Write-Output "-mount        | Shared directory on the docker host machine."
            Write-Output "-config       | Customer specific asset configuration (xml file)"              
            exit
        }
        else {
			CheckMountDirectory($mount)
            ResetService "auth-server"			
			DisplayStatus
        }
    }
    full-update {
        Write-Output "This operation will remove all containers and images! (except database)"

		if([string]::IsNullOrEmpty($mount) -or [string]::IsNullOrEmpty($config) -or 
			[string]::IsNullOrEmpty($host_ip)) 
		{
			Write-Output "Please use following options to initialize the asset guard system:"
            Write-Output "-mount        | Shared directory on the docker host machine."
            Write-Output "-config       | Customer specific asset configuration (xml file)."            
            Write-Output "-host_ip		| The IP address of the host machine" 
            exit
		}
		else {
			CheckMountDirectory($mount)
			
			DeleteService "gateway"
			DeleteService "auth-server"
			DeleteService "ui"
			
			#delete images
			DeleteImageByName("gateway")
			DeleteImageByName("ui")
			DeleteImageByName("security_server")

			#re-init
			CreateImage $gw_import			
			CreateImage $sec_import			
			CreateImage $ui_import
			
			#start services
			Invoke-Expression ("docker-compose up -d gateway")
			Invoke-Expression ("docker-compose up -d auth-server")
			Invoke-Expression ("docker-compose up -d ui")
			
			DisplayStatus
		}
    }
    uninstall {

		Write-Output "Removal of scheduler tasks"
		#removal of scheduler tasks
		Invoke-Expression "schtasks /delete /F /tn `"docker_vm_start`""
		#Invoke-Expression "schtasks /delete /F /tn `"lock_user`""		

		Invoke-Expression ("docker-compose down")
		Invoke-Expression ("docker volume prune -f")

		#Cleanup images
		DeleteImageByName("gateway")
		DeleteImageByName("ui")
		DeleteImageByName("db")
		DeleteImageByName("configtool")
		DeleteImageByName("security_server")
    }
	factory-reset {		
		
		#Reinitialize the database
		if(![string]::IsNullOrEmpty($mount) -and ![string]::IsNullOrEmpty($config) -and 
			![string]::IsNullOrEmpty($host_ip)) 
		{
			CheckMountDirectory($mount)

			Invoke-Expression ("docker-compose stop ui")
			Invoke-Expression ("docker-compose stop auth-server")
			Invoke-Expression ("docker-compose stop gateway")
			
			#Delete logs
			$logs=Get-ChildItem -Path $mount -Filter '*_log*.txt'
			foreach($item in $logs) {
				$item.Delete()
			}
			
			DeleteService "config"
			
			Invoke-Expression ("docker-compose up -d config")
			Invoke-Expression ("docker wait asset_guard_cfg")
			Write-Output "Waiting for database initialization"

			Invoke-Expression ("docker-compose up -d gateway")			
			Invoke-Expression ("docker-compose up -d auth-server")
			Invoke-Expression ("docker-compose start ui")
			
			DisplayStatus
		}
		else {
			Write-Output "Unable to process factory reset due to missing script parameters"
			
			Write-Output "Please use following options to initialize the factory reset:"
            Write-Output "-mount        | Shared directory on the docker host machine "
            Write-Output "-config       | Customer specific asset configuration (xml file)"             
            Write-Output "-host_ip		| The IP address of the host machine" 
		}
	}
	sw-restart {
		Write-Output "Asset Guard will be restarted"
		Write-Output "Stopping running containers"
		
		Invoke-Expression ("docker-compose restart db")
		Invoke-Expression ("docker-compose restart gateway")	
		Invoke-Expression ("docker-compose restart auth-server")				
		Invoke-Expression ("docker-compose restart ui")

		DisplayStatus
	}
}