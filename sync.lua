local spawnedObjects = {}  -- Table to store references to the spawned objects along with their IDs
local canAdjustHeight = true -- Flag to control when height adjustment is allowed

RegisterNetEvent('StartBuryingEvent')
AddEventHandler('StartBuryingEvent', function()
    local objectName = 'prop_pile_dirt_01'  -- Specific prop to spawn
    
    local randomId = math.random(10000, 99999)  -- Generate a random ID
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local forwardVector = GetEntityForwardVector(playerPed)
    
    local spawnCoords = playerCoords + forwardVector * 1.5  -- Calculate spawn coordinates in front of the player
    local modelHash = GetHashKey(objectName)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(1)
    end

    -- Initial spawn at the player's position
    local obj = CreateObjectNoOffset(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, true, false)
    SetEntityAsMissionEntity(obj, true, true)  -- Keep this to ensure the object isn't cleaned up

    spawnedObjects[randomId] = obj  -- Store the object reference with its ID

    -- Place the object properly on the ground
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    
    -- Adjust the object to your initial height
    local initialHeight = -1.50
    local objCoords = GetEntityCoords(obj)
    SetEntityCoordsNoOffset(obj, objCoords.x, objCoords.y, objCoords.z + initialHeight, true, true, true)

    SetModelAsNoLongerNeeded(modelHash)

    -- Send the object's spawn data to the server with its coordinates
    TriggerServerEvent('broadcastObjectSpawn', objectName, randomId, objCoords.x, objCoords.y, objCoords.z)
end)

RegisterNetEvent('spawnObjectOnClient')
AddEventHandler('spawnObjectOnClient', function(objectName, objectId, x, y, z)
    local modelHash = GetHashKey(objectName)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(1)
    end

    local obj = CreateObjectNoOffset(modelHash, x, y, z, false, true, false)
    SetEntityAsMissionEntity(obj, true, true)  -- Keep this to ensure the object isn't cleaned up

    spawnedObjects[objectId] = obj  -- Store the object reference with its ID

    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    
    -- Adjust the object to your initial height (keeping the logic intact)
    local initialHeight = -1.50
    SetEntityCoordsNoOffset(obj, x, y, z + initialHeight, true, true, true)

    SetModelAsNoLongerNeeded(modelHash)
end)

-- Create a flag to track whether debug has been printed for an object and player
local debugPrinted = {}

-- Table to store player and object references when animation is detected
local animationPlayers = {}

-- Function to store playerSrc and objectId only if not already stored, then send it to the server
function StorePlayerAndObject(playerSrc, objectId)
    if not animationPlayers[playerSrc] then
        animationPlayers[playerSrc] = objectId
        print("Stored player src: " .. playerSrc .. " with object ID: " .. objectId)

        -- Send the stored data to the server
        TriggerServerEvent('sendPlayerAndObjectData', playerSrc, objectId)
    end
end

-- Function to check if the shovel is attached to the player
function IsShovelAttached()
    local playerPed = PlayerPedId()
    -- Check if the shovel object is attached to the player's hand
    return IsEntityAttachedToEntity(ShovelObject, playerPed)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local playerSrc = GetPlayerServerId(PlayerId())  -- Get the player's server-side ID (src)
        
        for objectId, obj in pairs(spawnedObjects) do
            if DoesEntityExist(obj) then
                local objCoords = GetEntityCoords(obj)
                local distance = #(playerCoords - objCoords)

                if distance <= 3.0 then
                    -- Check if the player is NOT in any restricted animation before allowing height adjustment
                    if not (IsEntityPlayingAnim(playerPed, 'combat@damage@writhe', 'writhe_loop', 3) or IsEntityPlayingAnim(playerPed, 'dead', 'dead_a', 3)) then
                        -- Check if the shovel is attached to the player's hand
                        if IsShovelAttached() then
                            -- Check if "E" is pressed and if height adjustment is allowed
                            if IsControlJustPressed(0, 38) and canAdjustHeight then  -- Check if "E" is pressed (38 is the control ID for "E")
                                canAdjustHeight = false  -- Prevent further adjustments until re-enabled
                                TriggerServerEvent('adjustObjectHeight', objectId)  -- Send the object ID to the server to adjust its height

                                -- Re-enable height adjustment after 1 second delay
                                Citizen.Wait(1000)
                                canAdjustHeight = true
                            end
                        else
                            print("Shovel is not attached, cannot adjust height.")
                        end
                    else
                        -- Check if the player and object combination has already been debugged
                        if not debugPrinted[playerSrc] or not debugPrinted[playerSrc][objectId] then
                            -- Debug: Player is in a restricted animation
                            print("Player is in a restricted animation and cannot press E.")
                            
                            -- Call the function to store playerSrc and objectId, and send to the server
                            StorePlayerAndObject(playerSrc, objectId)

                            -- Initialize table for the player if it doesn't exist
                            if not debugPrinted[playerSrc] then
                                debugPrinted[playerSrc] = {}
                            end

                            -- Mark that the debug has been printed for this player-object combination
                            debugPrinted[playerSrc][objectId] = true
                        end
                    end
                end
            end
        end
    end
end)



-- Handle receiving targeted data from the server
RegisterNetEvent('receiveTargetedData')
AddEventHandler('receiveTargetedData', function(targetedPlayerId, objectId)
    -- Debugging: Print the received data
    print("Received from server -> Targeted Player ID: " .. targetedPlayerId .. ", Object ID: " .. objectId)
end)



RegisterNetEvent('adjustObjectHeightOnClient')
AddEventHandler('adjustObjectHeightOnClient', function(objectId)
    local obj = spawnedObjects[objectId]
    
    if DoesEntityExist(obj) then
        -- Debug: Print the object ID when height adjustment starts
        print("Adjusting height for object ID:", objectId)

        Citizen.CreateThread(function()
            local objCoords = GetEntityCoords(obj)
            local targetZ = objCoords.z + 0.1  -- Adjust by 10 centimeters smoothly
            while objCoords.z < targetZ do
                objCoords = GetEntityCoords(obj)
                SetEntityCoordsNoOffset(obj, objCoords.x, objCoords.y, objCoords.z + 0.01, true, true, true)
                Citizen.Wait(20)  -- Adjust this for smoothness/speed
            end
        end)
    else
        -- Debug: Print an error if the object doesn't exist
        print("Object with ID", objectId, "does not exist.")
    end
end)

RegisterNetEvent('lowerObjectHeightOnClient')
AddEventHandler('lowerObjectHeightOnClient', function(objectId)
    local obj = spawnedObjects[objectId]
    
    if DoesEntityExist(obj) then
        -- Debug: Print the object ID when height lowering starts
        print("Lowering height for object ID:", objectId)

        Citizen.CreateThread(function()
            local objCoords = GetEntityCoords(obj)
            local targetZ = objCoords.z - 0.1  -- Lower by 10 centimeters smoothly
            while objCoords.z > targetZ do
                objCoords = GetEntityCoords(obj)
                SetEntityCoordsNoOffset(obj, objCoords.x, objCoords.y, objCoords.z - 0.01, true, true, true)
                Citizen.Wait(20)  -- Adjust this for smoothness/speed
            end
        end)
    else
        -- Debug: Print an error if the object doesn't exist
        print("Object with ID", objectId, "does not exist.")
    end
end)




local ShovelIsActive = false
local IsDigging = false 
local DigText = Config.StartDiggingText

-- Function to get the ground hash at the player's location
function GetGroundHash(entity)
    local coords = GetEntityCoords(entity)
    local num = StartShapeTestCapsule(coords.x, coords.y, coords.z + 4, coords.x, coords.y, coords.z - 2.0, 1, 1, entity, 7)
    local _, _, _, _, groundHash = GetShapeTestResultEx(num)
    return groundHash
end

-- Function to translate the ground hash to a readable surface type and dig permission
function TranslateGroundHash(hash)
    local groundData = Config.groundHashes[hash]
    if groundData then
        return groundData.name, groundData.canDig
    else
        return "Unknown Surface", false
    end
end

function StartDigging()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local groundHash = GetGroundHash(playerPed)
    local surfaceType, canDig = TranslateGroundHash(groundHash)

    -- Check if any spawned objects are within a 5-meter radius
    local isNearbyObject = false
    for objectId, obj in pairs(spawnedObjects) do
        if DoesEntityExist(obj) then
            local objCoords = GetEntityCoords(obj)
            local distance = #(playerCoords - objCoords)
            if distance <= 5.0 then
                print("Debug: Found a prop within 5 meters. Object ID: " .. objectId)
                isNearbyObject = true
                break  -- Exit the loop once an object is found within the radius
            end
        end
    end

    if canDig then
        IsDigging = true
        DigText = Config.DiggingText

        -- Play the digging animation (looping)
        ShovelHoldingAnimation()

        -- Disable height adjustment until animation completes
        canAdjustHeight = false

        print("Digging started on surface: " .. surfaceType)
        
        -- Trigger the event to spawn the prop if no nearby object is found
        if not isNearbyObject then
            TriggerEvent('StartBuryingEvent')
        else
            print("Debug: Skipping object spawn due to nearby prop.")
        end

        -- Re-enable height adjustment after a delay
        Citizen.Wait(1000)
        canAdjustHeight = true

    else
        print("You cannot dig on this surface: " .. surfaceType)
        IsDigging = false
    end
end

function ShovelHoldingAnimation()
    local HoldingAnimDict = Config.ShovelAnimDict
    RequestAnimDict(HoldingAnimDict)
    while not HasAnimDictLoaded(HoldingAnimDict) do
        Citizen.Wait(150)
    end

    DetachEntity(ShovelObject, false, false)
    local ShovelDiggingBone = GetPedBoneIndex(PlayerPedId(), Config.ShovelDiggingBone)
    AttachEntityToEntity(ShovelObject, PlayerPedId(), ShovelDiggingBone, Config.ShovelDiggingPlacement.XCoords, Config.ShovelDiggingPlacement.YCoords, Config.ShovelDiggingPlacement.ZCoords, Config.ShovelDiggingPlacement.XRotation, Config.ShovelDiggingPlacement.YRotation, Config.ShovelDiggingPlacement.ZRotation, true, true, true, true, 1, true)

    -- Play the animation in a loop (-1 as duration, and flag 1 to loop it)
    TaskPlayAnim(PlayerPedId(), HoldingAnimDict, Config.ShovelAnim, 1.0, 1.5, -1, 1, 0, false, false, false)
end



Citizen.CreateThread(function()
    while true do 
        local sleep = 500 -- Default wait time
        local playerPed = PlayerPedId()

        -- Handle scenarios where shovel should be removed
        if IsPedRagdoll(playerPed) or IsPedInAnyVehicle(playerPed, false) then 
            RemoveShovel()
            ShovelIsActive = false
            IsDigging = false
            DigText = Config.StartDiggingText
        end

        if ShovelIsActive then 
            sleep = 10 -- Reduced wait time for responsiveness

            -- Show the prompt to start digging
            DrawText3D(DigText, GetEntityCoords(playerPed))
            if IsControlJustPressed(0, Config.DigButton) then 
                Citizen.Wait(500)  -- Wait half a second for `E`
                StartDigging()  -- Start digging action
            end
        end

        Citizen.Wait(sleep)
    end
end)

-- Function to handle the shovel holding animation
function ShovelHoldingAnimation()
    local HoldingAnimDict = Config.ShovelAnimDict
    RequestAnimDict(HoldingAnimDict)
    while not HasAnimDictLoaded(HoldingAnimDict) do
        Citizen.Wait(150)
    end

    DetachEntity(ShovelObject, false, false)
    local ShovelDiggingBone = GetPedBoneIndex(PlayerPedId(), Config.ShovelDiggingBone)
    AttachEntityToEntity(ShovelObject, PlayerPedId(), ShovelDiggingBone, Config.ShovelDiggingPlacement.XCoords, Config.ShovelDiggingPlacement.YCoords, Config.ShovelDiggingPlacement.ZCoords, Config.ShovelDiggingPlacement.XRotation, Config.ShovelDiggingPlacement.YRotation, Config.ShovelDiggingPlacement.ZRotation, true, true, true, true, 1, true)
    TaskPlayAnim(PlayerPedId(), HoldingAnimDict, Config.ShovelAnim, 1.0, 1.5, -1, 2, 0.79, nil, nil, nil)
end

-- Function to exit digging mode
function ExitDigging()
    StopAnimTask(PlayerPedId(), Config.ShovelAnimDict, Config.ShovelAnim, 1.5)
    DetachEntity(ShovelObject, false, false)
    local ShovelIdleBone = GetPedBoneIndex(PlayerPedId(), Config.ShovelIdleBone)
    AttachEntityToEntity(ShovelObject, PlayerPedId(), ShovelIdleBone, Config.ShovelIdlePlacement.XCoords, Config.ShovelIdlePlacement.YCoords, Config.ShovelIdlePlacement.ZCoords, Config.ShovelIdlePlacement.XRotation, Config.ShovelIdlePlacement.YRotation, Config.ShovelIdlePlacement.ZRotation, true, true, true, true, 1, true)
end

-- Function to remove the shovel
function RemoveShovel()
    StopAnimTask(PlayerPedId(), Config.ShovelAnimDict, Config.ShovelAnim, 1.5)
    DetachEntity(ShovelObject, false, false)
    if DoesEntityExist(ShovelObject) then 
        DeleteObject(ShovelObject)
    end
    ShovelIsActive = false
end

-- Event to handle shovel usage
RegisterNetEvent("SxM-bury:UseShovel", function()
    if ShovelIsActive == false then 
        GrabShovel()
        ShovelIsActive = true 
    elseif ShovelIsActive == true then 
        RemoveShovel()
    end
end)

-- Function to grab the shovel
function GrabShovel()
    if DoesEntityExist(ShovelObject) then 
        DeleteObject(ShovelObject)
    end
    local ShovelModel = Config.ShovelObject
    RequestModel(ShovelModel)
    while not HasModelLoaded(ShovelModel) do
        Citizen.Wait(150)
    end
    ShovelObject = CreateObjectNoOffset(ShovelModel, GetEntityCoords(PlayerPedId()), true, true, false)
    SetEntityCollision(ShovelObject, false, false)
    local ShovelIdleBone = GetPedBoneIndex(PlayerPedId(), Config.ShovelIdleBone)
    AttachEntityToEntity(ShovelObject, PlayerPedId(), ShovelIdleBone, Config.ShovelIdlePlacement.XCoords, Config.ShovelIdlePlacement.YCoords, Config.ShovelIdlePlacement.ZCoords, Config.ShovelIdlePlacement.XRotation, Config.ShovelIdlePlacement.YRotation, Config.ShovelIdlePlacement.ZRotation, true, true, true, true, 1, true)
end

-- Event to clean up the shovel on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DeleteObject(ShovelObject)
    end
end)

-- Function to draw 3D text at specified coordinates
function DrawText3D(msg, coords)
    AddTextEntry('floatingHelpNotification', msg)
    SetFloatingHelpTextWorldPosition(1, coords)
    SetFloatingHelpTextStyle(1, 1, 2, -1, 3, 0)
    BeginTextCommandDisplayHelp('floatingHelpNotification')
    EndTextCommandDisplayHelp(2, false, false, -1)
end

-- Function to clone the nearby player
function ClonePlayerPed(nearbyPed)
    local cloneCoords = GetEntityCoords(nearbyPed)
    local cloneHeading = GetEntityHeading(nearbyPed)
    local clonePed = ClonePed(nearbyPed, cloneHeading, true, true) -- Clone the ped
    return clonePed
end

-- Function to apply position, rotation, and animation from the original to the clone
function ApplyMatrixAndAnimationToClone(originalPed, clonePed)
    -- Retrieve the entity matrix of the original ped
    local forwardX, forwardY, forwardZ, rightX, rightY, rightZ, upX, upY, upZ, posX, posY, posZ = GetEntityMatrix(originalPed)

    -- Set the clone's coordinates and rotation matrix to match the original ped's
    SetEntityCoords(clonePed, posX, posY, posZ, false, false, false, true)
    SetEntityRotation(clonePed, GetEntityRotation(originalPed, 2), 2, true)

    -- Get animation details and apply to clone
    local animDict, animName = GetCurrentPedAnimation(originalPed) -- Get animation details

    if animDict and animName then
        RequestAnimDict(animDict) -- Request animation dictionary
        while not HasAnimDictLoaded(animDict) do
            Citizen.Wait(0) -- Wait for the dictionary to load
        end

        -- Play the animation on the clone ped
        TaskPlayAnim(clonePed, animDict, animName, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end
end

-- Function to get the animation the ped is playing
function GetCurrentPedAnimation(ped)
    if IsEntityPlayingAnim(ped, 'combat@damage@writhe', 'writhe_loop', 3) then
        return 'combat@damage@writhe', 'writhe_loop'
    elseif IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3) then
        return 'dead', 'dead_a'
    else
        return nil, nil -- No matching animation found
    end
end

RegisterCommand("cloneplayer", function(source, args, rawCommand)
    local playerPed = PlayerPedId() -- Get the local player ped
    local playerCoords = GetEntityCoords(playerPed) -- Get local player position
    local checkRadius = 20.0 -- Define the radius to check for nearby players
    local clonePed = nil -- Variable to store the cloned player entity
    local cloneCoords = nil -- Store the clone's coordinates
    local moveEnabled = false -- Toggle for enabling movement
    local nearbyPed = nil -- Store the original nearby ped reference
    local nearbyPlayerId = nil -- Store the server ID of the nearby player
    local objectMatch = false -- Flag to track if both players are near the same object
    local matchedObjectId = nil -- To store the matched object ID
    local matchedObjectCoords = nil -- To store the matched object’s coordinates

    Citizen.CreateThread(function()
        -- Loop through all players to find one in range
        for _, playerId in ipairs(GetActivePlayers()) do
            if playerId ~= PlayerId() then -- Skip the local player
                local targetPed = GetPlayerPed(playerId) -- Get other player ped
                local targetCoords = GetEntityCoords(targetPed) -- Get target player position

                -- Calculate the distance between the local player and the other player
                local distance = GetDistanceBetweenCoords(playerCoords, targetCoords, true)

                if distance <= checkRadius then
                    -- Check if both players are near the same object within 3 meters
                    for objectId, obj in pairs(spawnedObjects) do
                        if DoesEntityExist(obj) then
                            local objCoords = GetEntityCoords(obj)
                            local playerDistance = #(playerCoords - objCoords)
                            local targetDistance = #(targetCoords - objCoords)

                            -- If both players are within 3 meters of the same object
                            if playerDistance <= 3.0 and targetDistance <= 3.0 then
                                objectMatch = true
                                matchedObjectId = objectId
                                matchedObjectCoords = objCoords -- Store the object's coordinates
                                break
                            end
                        end
                    end

                    -- If a match is found, proceed with the cloning logic
                    if objectMatch then
                        nearbyPlayerId = GetPlayerServerId(playerId) -- Get the server ID of the nearby player
                        nearbyPed = targetPed -- Set the nearby player's ped
                        clonePed = ClonePlayerPed(nearbyPed) -- Clone the nearby player
                        cloneCoords = GetEntityCoords(clonePed) -- Store the clone's initial position
                        DrawText3D("Press ENTER to move the clone! Use PageUp/PageDown to adjust height.", cloneCoords) -- Show message

                        -- Apply the matrix (position, rotation) and animation to the clone
                        ApplyMatrixAndAnimationToClone(nearbyPed, clonePed)
                        break -- Exit the loop if the condition is met
                    end
                end
            end
        end

        if clonePed and objectMatch then
            -- Check if "Enter" key (38) is pressed to enable movement mode
            while true do
                Citizen.Wait(0)

                if IsControlJustPressed(0, 38) then
                    moveEnabled = not moveEnabled -- Toggle movement mode

                    if moveEnabled then
                        print("Movement mode enabled. Use arrow keys to move the clone, PageUp/PageDown for height.")
                    else
                        print("Movement mode disabled. Moving original player.")
                        -- Send the position of the clone to the server
                        TriggerServerEvent("dropPlayerAtCoords", nearbyPlayerId, cloneCoords) 
                        DeleteEntity(clonePed) -- Delete the clone after moving the original player
                        break -- Exit the loop when movement mode is disabled
                    end
                end

                -- Move the clone based on arrow key input when movement is enabled
                if moveEnabled then
                    local moveAmount = 0.1 -- Adjust this for the movement speed
                    local maxDistance = 3.0 -- Maximum distance allowed from the object

                    -- Move the clone along X/Y axis using arrow keys
                    if IsControlPressed(0, 172) then -- Up Arrow
                        cloneCoords = vector3(cloneCoords.x + moveAmount, cloneCoords.y, cloneCoords.z)
                    elseif IsControlPressed(0, 173) then -- Down Arrow
                        cloneCoords = vector3(cloneCoords.x - moveAmount, cloneCoords.y, cloneCoords.z)
                    elseif IsControlPressed(0, 174) then -- Left Arrow
                        cloneCoords = vector3(cloneCoords.x, cloneCoords.y + moveAmount, cloneCoords.z)
                    elseif IsControlPressed(0, 175) then -- Right Arrow
                        cloneCoords = vector3(cloneCoords.x, cloneCoords.y - moveAmount, cloneCoords.z)
                    end

                    -- Adjust height using Page Up (10) and Page Down (11)
                    if IsControlPressed(0, 10) then -- Page Up
                        cloneCoords = vector3(cloneCoords.x, cloneCoords.y, cloneCoords.z + 0.05)
                    elseif IsControlPressed(0, 11) then -- Page Down
                        cloneCoords = vector3(cloneCoords.x, cloneCoords.y, cloneCoords.z - 0.05)
                    end

                    -- Calculate the new distance from the object after movement
                    local newDistance = #(vector3(cloneCoords.x, cloneCoords.y, cloneCoords.z) - matchedObjectCoords)

                    -- If the new position is within the 3-meter radius, move the clone
                    if newDistance <= maxDistance then
                        -- Apply the new position to the clone
                        SetEntityCoords(clonePed, cloneCoords.x, cloneCoords.y, cloneCoords.z, false, false, false, true)
                    else
                        -- Restrict the movement to within the radius by keeping it on the boundary
                        local direction = (cloneCoords - matchedObjectCoords) / newDistance -- Get the direction vector
                        cloneCoords = matchedObjectCoords + direction * maxDistance -- Clamp to the boundary
                        SetEntityCoords(clonePed, cloneCoords.x, cloneCoords.y, cloneCoords.z, false, false, false, true)
                        print("Movement restricted within 3 meters of the object.")
                    end
                end
            end
        elseif not objectMatch then
            print("No nearby objects found that both players are near.")
        else
            print("No nearby players found.")
        end
    end)
end, false)

-- Event to drop the player at specific coordinates
RegisterNetEvent("dropPlayerAtCoords")
AddEventHandler("dropPlayerAtCoords", function(coords)
    local playerPed = PlayerPedId()
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z, false, false, false, true)
end)
