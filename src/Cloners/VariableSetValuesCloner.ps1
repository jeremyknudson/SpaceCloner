function Copy-OctopusVariableSetValues
{
    param
    (
        $SourceVariableSetVariables,
        $DestinationVariableSetVariables,        
        $SourceData,
        $DestinationData,
        $SourceProjectData,
        $DestinationProjectData,
        $CloneScriptOptions
    )
    
    $variableTracker = @{}  
    
    foreach ($octopusVariable in $sourceVariableSetVariables.Variables)
    {                             
        $variableName = $octopusVariable.Name        
        
        if (Get-Member -InputObject $octopusVariable.Scope -Name "Environment" -MemberType Properties)
        {
            Write-OctopusVerbose "$variableName has environment scoping, converting to destination values"
            $NewEnvironmentIds = @(Convert-SourceIdListToDestinationIdList -SourceList $sourcedata.EnvironmentList -DestinationList $DestinationData.EnvironmentList -IdList $octopusVariable.Scope.Environment)
            $octopusVariable.Scope.Environment = @($NewEnvironmentIds)            
        }

        if (Get-Member -InputObject $octopusVariable.Scope -Name "Channel" -MemberType Properties)
        {
            Write-OctopusVerbose "$variableName has channel scoping, converting to destination values"
            $NewChannelIds = @(Convert-SourceIdListToDestinationIdList -SourceList $sourceProjectData.ChannelList -DestinationList $DestinationProjectData.ChannelList -IdList $octopusVariable.Scope.Channel)
            $octopusVariable.Scope.Channel = @($NewChannelIds)            
        }

        if (Get-Member -InputObject $octopusVariable.Scope -Name "ProcessOwner" -MemberType Properties)
        {
            if ($destinationData.HasRunbooks)
            {
                Write-OctopusVerbose "$variableName has process owner scoping, converting to destination values"
                $NewOwnerIds = @()
                foreach($value in $octopusVariable.Scope.ProcessOwner)
                {
                    Write-OctopusVerbose "Attempting to convert $value to a destination value"

                    if ($value -like "Projects-*")
                    {
                        Write-OctopusVerbose "The process owner is the project, converting to the new project id"
                        $NewOwnerIds += $DestinationProjectData.Project.Id
                    }
                    elseif($value -like "Runbooks-*")
                    {
                        Write-OctopusVerbose "The process owner is a runbook, converting to the new runbook id"
                        $NewOwnerIds += Convert-SourceIdToDestinationId -SourceList $SourceProjectData.RunbookList -DestinationList $DestinationProjectData.RunbookList -IdValue $value
                    }
                }

                Write-OctopusVerbose "The new process owner ids are $NewOwnerIds"
                
                $octopusVariable.Scope.ProcessOwner = @($NewOwnerIds)            
            }
            else 
            {
                $octopusVariable.Scope.PSObject.Properties.Remove('ProcessOwner')    
            }
        }

        if ($octopusVariable.Type -match ".*Account")
        {
            Write-OctopusVerbose "$variableName is an account value, converting to destination account"
            $octopusVariable.Value = Convert-SourceIdToDestinationId -SourceList $sourceData.InfrastructureAccounts -DestinationList $destinationData.InfrastructureAccounts -IdValue $octopusVariable.Value
        }

        if ($octopusVariable.IsSensitive -eq $true)
        {
            $octopusVariable.Value = "Dummy Value"
        }

        $trackingName = $variableName -replace "\.", ""        
        
        Write-OctopusVerbose "Cloning $variableName"
        if ($null -eq $variableTracker[$trackingName])
        {
            Write-OctopusVerbose "This is the first time we've seen $variableName"
            $variableTracker[$trackingName] = 1
        }
        else
        {
            $variableTracker.$trackingName += 1
            Write-OctopusVerbose "We've now seen $variableName $($variableTracker[$trackingName]) times"
        }

        $foundCounter = 0
        $foundIndex = -1
        $variableExistsOnDestination = $false        
        for($i = 0; $i -lt $DestinationVariableSetVariables.Variables.Length; $i++)
        {            
            if ($DestinationVariableSetVariables.Variables[$i].Name -eq $variableName)
            {
                $variableExistsOnDestination = $true
                $foundCounter += 1
                if ($foundCounter -eq $variableTracker[$trackingName])
                {
                    $foundIndex = $i
                }
            }
        }        
        
        if ($foundCounter -gt 1 -and $variableExistsOnDestination -eq $true -and $CloneScriptOptions.AddAdditionalVariableValuesOnExistingVariableSets -eq $false)
        {
            Write-OctopusVerbose "The variable $variableName already exists on destination. You selected to skip duplicate instances, skipping."
        }       
        elseif ($foundIndex -eq -1)
        {
            Write-OctopusVerbose "New variable $variableName value found.  This variable has appeared so far $($variableTracker[$trackingName]) time(s) in the source variable set.  Adding to list."
            $DestinationVariableSetVariables.Variables += $octopusVariable
        }
        elseif ($CloneScriptOptions.OverwriteExistingVariables -eq $false)
        {
            Write-OctopusVerbose "The variable $variableName already exists on the host and you elected to only copy over new items, skipping this one."
        }                                         
        elseif ($foundIndex -gt -1 -and $DestinationVariableSetVariables.Variables[$foundIndex].IsSensitive -eq $true)
        {
            Write-OctopusVerbose "The variable $variableName at value index $($variableTracker[$trackingName]) is sensitive, leaving as is on the destination."
        }
        elseif ($foundIndex -gt -1)
        {
            $DestinationVariableSetVariables.Variables[$foundIndex].Value = $octopusVariable.Value
            $DestinationVariableSetVariables.Variables[$foundIndex].Scope = $octopusVariable.Scope
            if ($octopusVariable.Value -eq "Dummy Value")         
            {                
                Write-OctopusPostCloneCleanUp "The variable $variableName is a sensitive variable, value set to 'Dummy Value'"
            }
        }        
    }

    Save-OctopusVariableSetVariables -libraryVariableSetVariables $DestinationVariableSetVariables -destinationData $DestinationData    
}