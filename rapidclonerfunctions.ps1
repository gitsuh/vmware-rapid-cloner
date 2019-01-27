function getlinkedclonesnapshot {
	param
		(
			$vm
		)
	$snapshotname = "linkedclone-" + $([int64](([datetime]::UtcNow)-(get-date "1/1/1970")).TotalMilliseconds)
	$snapshots = $vm | get-snapshot
	$linkedclonesnapshots = @()
	foreach($snapshot in $snapshots){
		if($snapshot.name -like "*linkedclone*"){
			write-host "Found linked clone named $($snapshot.name), adding to collection."
			$linkedclonesnapshots += $snapshot
		}
	}
	if($linkedclonesnapshots.length -gt 0){
		write-host "Snapshots exist."
		$lastsnap = $linkedclonesnapshots[$linkedclonesnapshots.length - 1]
		$lastchildsnapname = $lastsnap.extensiondata.childsnapshotlist.name
		write-host "Last snapshot named" $lastsnap.name
		write-host "Last snapshot child snapshot named" $lastchildsnapname
		if( $lastchildsnapname -notlike "*linkedclone*" -and $lastchildsnapname){
			write-host "Creating snapshot named $($snapshotname) because there are non linkedclone child snapshots."
			$targetsnapshot = $vm | new-snapshot -name $snapshotname
			return $targetsnapshot
		}else{
			write-host "Last snapshot name contains linkedclone and childsnapshot is nothing."
			return $lastsnap
		}
	}else{
		write-host "Creating snapshot named $($snapshotname) because there were no snapshots."
		$targetsnapshot = $vm | new-snapshot -name $snapshotname
		return $targetsnapshot
	}
}
#look for the vm
#if can't find vm then look for template
#if can't find template or vm throw error

function makesureitsavm {
	param
		(
			$name
		)
	$target = $null
	$targetvm = $null
	$targettemplate = $null
	$targetfolder = $null
	try{
		$targetfolder = get-folder "templates" -ErrorAction SilentlyContinue
		$targetvm = $targetfolder | get-vm -name $name -ErrorAction SilentlyContinue
		$targettemplate = $targetfolder | get-template -name $name -ErrorAction SilentlyContinue
	}catch{
		write-host "Could not find."
	}
	if($targetvm){
		return $targetvm
	}
	if($targettemplate){
		$targetvm = $targettemplate | set-template -tovm
		return $targetvm
	}
	if(!$targettemplate -and !$targetvm){
		if(!$targetfolder){
			#return $null
			throw "Failed to locate the templates folder."
		}else{
			#return $null
			throw "Failed to locate vm or template named $($template.name)"
		}
	}
}

function servernamemaker {
	param
		(
			$clonecount,
			$basename,
			$domain
		)
	$clonenames = @()
	for($i = 0; $i -lt $clonecount; $i++){
		$clonename = $basename + $($i + 1).ToString("0#") + "." + $domain
		$clonenames += $clonename
	}
	return $clonenames
}

function new-rapidclone {
		param
			(
					$basevm,
					$computeresourcename,
					$portgroupname,
					$datastorename,
					$foldername,
					#$credentials,
					$basename,
					$domain,
					#$ipstart,
					#$ipend,
					$clonecount

			)
		$clonebasis = $null
		$linkedclonesnapshot = $null
		$targetcomputeresourcerp = $null
		$targetcomputeresourcecluster = $null
		$targetcomputeresourcehostsystem = $null
		$targetportgroup = $null
		$clonebasis = makesureitsavm -name $basevm
		$linkedclonesnapshot = getlinkedclonesnapshot -vm $clonebasis -ErrorAction SilentlyContinue
		$targetcomputeresourcerp = get-resourcepool -name $computeresourcename -ErrorAction SilentlyContinue
		$targetcomputeresourcecluster = get-cluster -name $computeresourcename -ErrorAction SilentlyContinue
		$targetcomputeresourcehostsystem = get-vmhost -name $computeresourcename -ErrorAction SilentlyContinue
		$targetportgroup = get-virtualportgroup | where-object {$_.name -eq $portgroupname} -ErrorAction SilentlyContinue
		$targetdatastore = get-datastore | where-object {$_.name -eq $datastorename} -ErrorAction SilentlyContinue
		$targetfolder = get-folder | where-object {$_.name -eq $foldername} -ErrorAction SilentlyContinue

		if(!$linkedclonesnapshot){
			throw "Unable to find or create the linked clone snapshot."
		}
		if(!$targetcomputeresourcerp -and !$targetcomputeresourcecluster -and !$targetcomputeresourcehostsystem){
			throw "Unable to find compute resource."
		}elseif($targetcomputeresourcerp){
			$targetcomputeresource = $targetcomputeresourcerp
		}elseif($targetcomputeresourcecluster){
			$targetcomputeresource = targetcomputeresourcecluster
		}elseif($targetcomputeresourcehostsystem){
			$targetcomputeresource = targetcomputeresourcehostsystem
		}
		if(!$targetportgroup){
			throw "Unable to find portgroup."
		}
		if(!$targetdatastore){
			throw "Unable to find datastore."
		}
		if(!$targetfolder){
			throw "Unable to find folder."
		}
	#$targetdatastore = get-datastore -name $(get-view -id $targettemplate.extensiondata.datastore).name
	
	$vmnames = servernamemaker -clonecount $clonecount -basename $basename -domain $domain


	$newvms = @()
	foreach ($item in $vmnames){
		#add decision point based on $targetcomputersource to handle RP, host, and cluster
		
		write-host "Createing linked clone named $item"
		$newvm = new-vm -name $item -vm $clonebasis -resourcepool $targetcomputeresource -datastore $targetdatastore -location $targetfolder -linkedclone:$true -referencesnapshot $linkedclonesnapshot
		$newvms += $newvm
		#write-host "Changing clone $item to 128 MB memory"
		#set-vm -VM $newvm -memorymb 128 -numcpu 1 -confirm:$false
		#write-host "Powering on clone $item"
		#start-vm -vm $newvm -confirm:$false -runasync
		#read-host "Continue?"
	}
	write-host "Built" $newvms.length "clones from $clonebasis.name"
}


function testfunction-master {

	$basevm = "turnkey-core-15.0-stretch-amd64"
	$computeresourcename = "rapid-clones"
	$portgroupname = "vlan-0-192.168.0.1-24"
	$datastorename = "freenas-datastore"
	$foldername = "rapid-clones"
	#$credentials = get-credential
	$basename = "labvmb"
	$domain = "lab.lan"
	#$ipstart = "192.168.1.200"
	#$ipend = "192.168.1.220"
	$clonecount = 1
	#new-rapidclone  -basevm $basevm -computeresourcename $computeresourcename -portgroupname $portgroupname -datastorename $datastorename -foldername $foldername -credentials $credentials -basename $basename -domain $domain -ipstart $ipstart -ipend $ipend -clonecount $clonecount
	
	new-rapidclone  -basevm $basevm -computeresourcename $computeresourcename -portgroupname $portgroupname -datastorename $datastorename -foldername $foldername -basename $basename -domain $domain -clonecount $clonecount
	

}
