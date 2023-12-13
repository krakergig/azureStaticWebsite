param (
    [string]$subscription = 'index.html',
    [string]$resourceGroup = '404.html',
    [string]$appPath = 'aeu1pectld1sadata1',
    [string]$appName = 'aeu1pectld1sadata1',
    [string]$settingsPath = 'Enabled'
)

function publish{
    param(
        $projectName        
    )

    $projectPath="src/$($projectName)/$($projectName).csproj"
    $publishDestPath="publish/" + [guid]::NewGuid().ToString()

    log "publishing project '$($projectName)' in folder '$($publishDestPath)' ..." 
    dotnet publish $projectPath -c Release -o $publishDestPath

    $zipArchiveFullPath="$($publishDestPath).Zip"
    log "creating zip archive '$($zipArchiveFullPath)'"
    $compress = @{
        Path = $publishDestPath + "/*"
        CompressionLevel = "Fastest"
        DestinationPath = $zipArchiveFullPath
    }
    Compress-Archive @compress

    log "cleaning up ..."
    Remove-Item -path "$($publishDestPath)" -recurse

    return $zipArchiveFullPath
}

function log{
    param(
        $text
    )

    write-host $text -ForegroundColor Yellow -BackgroundColor DarkGreen
}

function deploy{
    param(
        $zipArchiveFullPath,
        $subscription,
        $resourceGroup,        
        $appName
    )    

    log "deploying '$($appName)' to Resource Group '$($resourceGroup)' in Subscription '$($subscription)' from zip '$($zipArchiveFullPath)' ..."
    az functionapp deployment source config-zip -g "$($resourceGroup)" -n "$($appName)" --src "$($zipArchiveFullPath)" --subscription "$($subscription)"   
}

function setConfig{
    param(
        $subscription,
        $resourceGroup,        
        $appName,
        $configPath
    )
    log "updating application config..."
    az functionapp config appsettings set --name "$($appName)" --resource-group "$($resourceGroup)" --subscription "$($subscription)" --settings @$configPath
}

function createArtifact {
    param(
        $appName
    )
    $zipPath = publish $appName
    if ($zipPath -is [array]) {
        $zipPath = $zipPath[$zipPath.Length - 1]
    }
    return $zipPath
}

function deployInstance {
    param(      
        $zipPath,  
        $subscription,
        $resourceGroup,        
        $appName,
        $configPath
    )

    deploy $zipPath $subscription $resourceGroup $appName

    if(![string]::IsNullOrEmpty($configPath)){
        setConfig $subscription $resourceGroup $appName $configPath
    }
}

$zipPath = createArtifact $appPath
deployInstance $zipPath $subscription $resourceGroup $appName $configPath
