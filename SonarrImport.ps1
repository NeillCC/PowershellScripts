<#Begin User defined variables #>
#Protocol used to access Sonarr. [http|https]
$WebProtocol = 'http'
#Sonarr API key for authentication. Found under Settings-> General-> API.
$ApiKey = '00dfd2f8a4564a77bf0e4e6c280526df'
#Sonarr IP or hostname. This is used to access the Sonarr API
$SonarrHost = 'butler'
#Sonarr port. Default is 8989
$Port = '8989'
#Would you like to receive notifications in the webUI when a file is imported? [$true|$false]
$ClientNotifications = $true
#Action Sonarr takes when it is notified about the files. [move|copy|auto]
$SonarrAction = 'move'
#Maximum items to be actioned each time the script is run.
[int]$MaxitemCount = 50
#Types of media to import. Seperate with '|'
$ExtensionRegex = '.mp4|.mkv|.wmv|.avi|.srt'
#Would you like to delete empty directories? [$true|$false]
$PurgeEmptyDirectories = $true
#Would you like to delete empty directories? [$true|$false]
$PurgeExtraFiles = $true
#Would you like to delete any files that is not marked as monitored? [$true|$false]
$PurgeUnmonitoredFiles = $true
#Path to media for import on the machine running the script. Use full path; i.e. '/mnt/...'
$MediaDirectoryRelativeToScript = '/mnt/butler/media/tmp/'
#Path to media from Sonarr's perspective. if running in a docker, this may be '/downloads'. If this is running on the same machine as sonarr they can be the same path
$MediaDirectoryRelativeToSonarr = '/downloads/'
##PLEASE NOTE $MediaDirectoryRelativeToSonarr and $MediaDirectoryRelativeToScript must have the same file structure.
#if $MediaDirectoryRelativeToScript/1.txt exists then $MediaDirectoryRelativeToSonarr/1.txt must exist.
<#End of User Defined Variables#>

#Get all files in directory
$AllFiles = Get-ChildItem -Recurse -File -Path $MediaDirectoryRelativeToScript
#select only files with extensions defined in variable and up to the file count limit
$AllMedia = $AllFiles | Where-Object {$_.extension -match $ExtensionRegex}|Select-Object -First $MaxitemCount
#Add path relative to sonarr variable
$Media = $AllMedia | Select-Object *,@{Name='SonarrPath';Expression={$_.fullname -replace($MediaDirectoryRelativeToScript,$MediaDirectoryRelativeToSonarr)}}
#Forming the connection string to access Sonarr
$URL = $WebProtocol + '://' + $SonarrHost + ':' + $Port + '/api/command?apikey=' + $ApiKey
$ParseURL = $WebProtocol + '://' + $SonarrHost + ':' + $Port + '/api/parse?apikey=' + $ApiKey


#Remove superfluous files if elected
if($PurgeExtraFiles -eq $true){
    $NonMediaItems = $AllFiles | Where-Object {$_.extension -notmatch $ExtensionRegex}
    $NonMediaItems|Remove-Item -Verbose
}
#Remove empty directories if elected
if($PurgeEmptyDirectories -eq $true){
    $EmptyDirectories = Get-ChildItem $MediaDirectoryRelativeToScript -Recurse -Directory | Where-Object -FilterScript {$_.PSIsContainer -eq $True} | Where-Object -FilterScript {$_.GetFiles().Count -eq 0 -and $_.GetDirectories().Count -eq 0}
    $EmptyDirectories | Remove-Item -Verbose
}


#Sending Sonarr the commands
foreach($i in $Media){

    #Parse episode to determine if already present and if recognized by Sonarr as a TV show
    $ParseJSON = @{
        'path'=$i.SonarrPath
    }
    $FileNeeded = Invoke-RestMethod -Uri $ParseURL -Method Get -Body $ParseJSON

    #Perform Logic.
    if($FileNeeded.episodes.monitored -eq $true -and $null -ne $FileNeeded.episodes){
        #Sonarr recognizes this as a TV show and is missing this episode
        #Form the JSON for the api. This is a hashtable that is converted to JSON using the 'ConvertTo-Json' function
        $JSON = @{
            #Send notifications to the webUI on file import
            'sendUpdatesToClient'=$ClientNotifications;
            'sendUpdates'=$ClientNotifications;
            #This is the part of the api being called
            'name'='DownloadedEpisodesScan';
            #Path to media relative to sonarr
            'path'=$i.SonarrPath;
            #What to do with the files. [move|copy|auto]
            'importmode'=$SonarrAction
        }|ConvertTo-Json

        Invoke-RestMethod -Uri $URL -Method Post -Body $JSON

    }elseif($FileNeeded.episodes.monitored -ne $true -and $null -ne $FileNeeded.episodes){
        #This file is not marked as monitored in Sonarr
        Write-Warning -Message "File not marked as monitored found. $($i.fullname)"
        if($PurgeUnmonitoredFiles -eq $true){
            $i|Remove-Item -Verbose
        }
    }elseif($FileNeeded.episodes.monitored -ne $true -and $null -eq $FileNeeded.episodes){
        #Sonarr doesn't know what to do with this file
        Write-Warning -Message "no match found for $($i.fullname). Is this a TV Show?"
    }else{
        #If this happens, you're on your own.
        Write-Error -Message "Unhandled Logic."
    }
}
