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
                        -- Check if "E" is pressed and if height adjustment is allowed
                        if IsControlJustPressed(0, 38) and canAdjustHeight then  -- Check if "E" is pressed (38 is the control ID for "E")
                            canAdjustHeight = false  -- Prevent further adjustments until re-enabled
                            TriggerServerEvent('adjustObjectHeight', objectId)  -- Send the object ID to the server to adjust its height

                            -- Re-enable height adjustment after 1 second delay
                            Citizen.Wait(1000)
                            canAdjustHeight = true
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

                    -- Check if debug has been printed for this object
                    if not debugPrinted[objectId] then
                        -- Animation Check: Determine which animation is playing and output debug info
                        if IsEntityPlayingAnim(playerPed, 'combat@damage@writhe', 'writhe_loop', 3) then
                            print("Player src: " .. playerSrc .. " is playing 'writhe_loop' animation near object ID: " .. objectId)
                        elseif IsEntityPlayingAnim(playerPed, 'dead', 'dead_a', 3) then
                            print("Player src: " .. playerSrc .. " is playing 'dead_a' animation near object ID: " .. objectId)
                        end
                        -- Mark that the debug has been printed for this object
                        debugPrinted[objectId] = true
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

-- Function to draw 3D text
function DrawText3D(msg, coords)
    AddTextEntry('floatingHelpNotification', msg)
    SetFloatingHelpTextWorldPosition(1, coords)
    SetFloatingHelpTextStyle(1, 1, 2, -1, 3, 0)
    BeginTextCommandDisplayHelp('floatingHelpNotification')
    EndTextCommandDisplayHelp(2, false, false, -1)
end


-- Carry and drop in trunk

local attachment = {
    InProgress = false,
    targetSrc = -1,
    type = "",
    playerAttaching = {
        animDict = "combat@drag_ped@",
        anim = "injured_drag_plyr",
        flag = 49,
    },
    playerAttached = {
        animDict = "combat@drag_ped@",
        anim = "injured_drag_ped",
        attachX = 0.0,
        attachY = 0.5,  -- Adjusted position
        attachZ = 0.0,
        flag = 33,
    }
}

-- Function to show a notification
local function showNotification(text)
    SetTextComponentFormat("STRING")
    AddTextComponentString(text)
    DisplayHelpTextFromStringLabel(0, 0, 1, -1)
end

-- Function to find the closest player
local function findClosestPlayer(radius)
    local players = GetActivePlayers()
    local closestDistance = -1
    local closestPlayer = -1
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    for _, playerId in ipairs(players) do
        local targetPed = GetPlayerPed(playerId)
        if targetPed ~= playerPed then
            local targetCoords = GetEntityCoords(targetPed)
            local distance = #(targetCoords - playerCoords)
            if closestDistance == -1 or closestDistance > distance then
                closestPlayer = playerId
                closestDistance = distance
            end
        end
    end
    if closestDistance ~= -1 and closestDistance <= radius then
        return closestPlayer
    else
        return nil
    end
end

-- Function to ensure an animation dictionary is loaded
local function ensureAnimDictLoaded(animDict)
    if not HasAnimDictLoaded(animDict) then
        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do
            Wait(0)
        end        
    end
    return animDict
end

-- Command to attach a player
RegisterCommand("attachPlayer", function()
    if not attachment.InProgress then
        local closestPlayer = findClosestPlayer(3)
        if closestPlayer then
            local targetSrc = GetPlayerServerId(closestPlayer)
            if targetSrc ~= -1 then
                local targetPed = GetPlayerPed(closestPlayer)

                -- Check if the target player is in one of the allowed animations
                local isPlayingAllowedAnim = IsEntityPlayingAnim(targetPed, 'dead', 'dead_a', 3) or 
                   IsEntityPlayingAnim(targetPed, 'combat@damage@writhe', 'writhe_loop', 3)

                if isPlayingAllowedAnim then
                    attachment.InProgress = true
                    attachment.targetSrc = targetSrc
                    TriggerServerEvent("customAttach:sync", targetSrc)
                    ensureAnimDictLoaded(attachment.playerAttaching.animDict)
                    ensureAnimDictLoaded(attachment.playerAttached.animDict)
                    attachment.type = "attaching"
                else
                    showNotification("~r~Player is not in a carryable state!")
                end
            else
                showNotification("~r~No one nearby to attach!")
            end
        else
            showNotification("~r~No one nearby to attach!")
        end
    else
        attachment.InProgress = false
        ClearPedSecondaryTask(PlayerPedId())
        DetachEntity(PlayerPedId(), true, false)
        TriggerServerEvent("customAttach:stop", attachment.targetSrc)
        attachment.targetSrc = -1
    end
end, false)


-- Event to sync attachment to target
RegisterNetEvent("customAttach:syncTarget")
AddEventHandler("customAttach:syncTarget", function(targetSrc)
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetSrc))
    attachment.InProgress = true
    ensureAnimDictLoaded(attachment.playerAttached.animDict)
    AttachEntityToEntity(PlayerPedId(), targetPed, 11816, attachment.playerAttached.attachX, attachment.playerAttached.attachY, attachment.playerAttached.attachZ, 0.5, 0.5, 180, false, false, false, false, 2, false)
    attachment.type = "beingAttached"
end)

-- Event to stop attachment
RegisterNetEvent("customAttach:stopTarget")
AddEventHandler("customAttach:stopTarget", function()
    attachment.InProgress = false
    ClearPedSecondaryTask(PlayerPedId())
    DetachEntity(PlayerPedId(), true, false)
end)

-- Main thread for managing attachment animations and movements
Citizen.CreateThread(function()
    while true do
        if attachment.InProgress then
            local playerPed = PlayerPedId()
            if attachment.type == "beingAttached" then
                if not IsEntityPlayingAnim(playerPed, attachment.playerAttached.animDict, attachment.playerAttached.anim, 3) then
                    TaskPlayAnim(playerPed, attachment.playerAttached.animDict, attachment.playerAttached.anim, 8.0, -8.0, -1, attachment.playerAttached.flag, 0, false, false, false)
                end
            elseif attachment.type == "attaching" then
                if not IsEntityPlayingAnim(playerPed, attachment.playerAttaching.animDict, attachment.playerAttaching.anim, 3) then
                    TaskPlayAnim(playerPed, attachment.playerAttaching.animDict, attachment.playerAttaching.anim, 8.0, -8.0, -1, attachment.playerAttaching.flag, 0, false, false, false)
                end
                
                -- Movement and heading adjustment logic
                if IsControlPressed(0, 32) or IsControlPressed(0, 33) then  -- 'W' or 'S' key
                    if not IsEntityPlayingAnim(playerPed, attachment.playerAttaching.animDict, attachment.playerAttaching.anim, 3) then
                        TaskPlayAnim(playerPed, attachment.playerAttaching.animDict, attachment.playerAttaching.anim, 8.0, -8.0, -1, attachment.playerAttaching.flag, 0, false, false, false)
                    end

                    -- Adjust player heading with 'A' and 'D' keys
                    if IsControlPressed(0, 34) then  -- 'A' key
                        TriggerServerEvent('updateHeading', 1.0)  -- Request server to adjust heading left by 1 degree
                    elseif IsControlPressed(0, 35) then  -- 'D' key
                        TriggerServerEvent('updateHeading', -1.0)  -- Request server to adjust heading right by 1 degree
                    end
                else
                    ClearPedTasks(playerPed)
                end
            end
        end
        Wait(0)
    end
end)

-- Event handler for updating the player's heading from the server
RegisterNetEvent('syncHeading')
AddEventHandler('syncHeading', function(source, heading)
    local playerPed = GetPlayerPed(GetPlayerFromServerId(source))
    if playerPed and playerPed ~= -1 then
        SetEntityHeading(playerPed, heading)
    end
end)

-- Load the animation dictionary when the resource starts
Citizen.CreateThread(function()
    RequestAnimDict("combat@drag_ped@")
    while not HasAnimDictLoaded("combat@drag_ped@") do
        Citizen.Wait(100)
    end
end)


-- Ensure the animation plays when 'W' or 'S' key is pressed
Citizen.CreateThread(function()
    local isPlayingAnim = false

    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()

        if attachment.InProgress then
            if IsControlPressed(0, 32) or IsControlPressed(0, 33) or IsControlPressed(0, 34) or IsControlPressed(0, 35) then  -- 'W', 'A', 'S' or 'D' key
                if not isPlayingAnim then
                    TaskPlayAnim(playerPed, "combat@drag_ped@", "injured_drag_plyr", 8.0, -8.0, -1, 1, 0, false, false, false)
                    isPlayingAnim = true
                end

                -- Adjust player heading with 'A' and 'D' keys
                if IsControlPressed(0, 34) then  -- 'A' key
                    local heading = GetEntityHeading(playerPed)
                    SetEntityHeading(playerPed, heading + 1.0)  -- Turn left
                elseif IsControlPressed(0, 35) then  -- 'D' key
                    local heading = GetEntityHeading(playerPed)
                    SetEntityHeading(playerPed, heading - 1.0)  -- Turn right
                end
            else
                if isPlayingAnim then
                    ClearPedTasks(playerPed)
                    isPlayingAnim = false

                    -- Ensure the attached player is positioned correctly before detachment
                    local targetPed = GetPlayerPed(GetPlayerFromServerId(attachment.targetSrc))
                    local playerCoords = GetEntityCoords(playerPed)
                    SetEntityCoords(targetPed, playerCoords.x, playerCoords.y, playerCoords.z, false, false, false, true)

                    -- Trigger detachment when no key is pressed
                    attachment.InProgress = false
                    DetachEntity(playerPed, true, false)
                    TriggerServerEvent("customAttach:stop", attachment.targetSrc)
                    attachment.targetSrc = -1
                end
            end

            if isPlayingAnim then
                if not IsEntityPlayingAnim(playerPed, "combat@drag_ped@", "injured_drag_plyr", 3) then
                    TaskPlayAnim(playerPed, "combat@drag_ped@", "injured_drag_plyr", 8.0, -8.0, -1, 1, 0, false, false, false)
                end
            end
        end
    end
end)



-- Client-Side Script

-- Variables to store the text and position received from the server
local displayText = ""
local textPosition = nil
local isNearTrunk = false  -- Variable to check proximity to the trunk

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0) -- Prevents crashing, runs every frame

        local playerPed = PlayerPedId()
        local vehicle = GetClosestVehicle(GetEntityCoords(playerPed), 5.0, 0, 70)

        if vehicle ~= 0 then
            -- Get the trunk bone index and position
            local trunkBoneIndex = GetEntityBoneIndexByName(vehicle, "boot")
            local trunkPos = GetWorldPositionOfEntityBone(vehicle, trunkBoneIndex)
            local playerPos = GetEntityCoords(playerPed)

            -- Calculate the distance between the player and the trunk
            local distance = #(playerPos - trunkPos)

            if distance <= 3.0 then
                isNearTrunk = true  -- Player is near the trunk
                -- Check if the player is in one of the specified animations
                local inWritheAnimation = IsEntityPlayingAnim(playerPed, 'combat@damage@writhe', 'writhe_loop', 3)
                local inDeadAnimation = IsEntityPlayingAnim(playerPed, 'dead', 'dead_a', 3)

                if inWritheAnimation or inDeadAnimation then
                    local animName = inWritheAnimation and "writhe_loop" or "dead_a"
                    
                    -- Send the animation data to the server
                    TriggerServerEvent('notifyPlayerInAnimation', GetPlayerServerId(PlayerId()), animName, trunkBoneIndex, distance, trunkPos)
                end

            else
                isNearTrunk = false -- Player is not near the trunk
            end
        else
            isNearTrunk = false -- No vehicle nearby
        end
    end
end)



-- Handle the broadcast from the server and update the existing text display for all clients
RegisterNetEvent('receivePlayerAnimationInfo')
AddEventHandler('receivePlayerAnimationInfo', function(playerId, animName, trunkBoneIndex, distance, trunkPos)
    -- Update the display text and position with the data received from the server
    displayText = string.format("Player %d in Animation: %s\nDistance: %.2f\nTrunk Bone ID: %d", playerId, animName, distance, trunkBoneIndex)
    textPosition = trunkPos
end)

-- Thread to draw the text only when there is data to display
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0) -- This loop will run every frame to check if there's something to display

        if displayText ~= "" and textPosition ~= nil then
            -- If there's something to display, draw the text
            -- DrawText3D(textPosition.x, textPosition.y, textPosition.z, displayText)
        end
    end
end)

-- Variables to store the text and position received from the server
local displayText = ""
local textPosition = nil
local isNearTrunk = false  -- Variable to check proximity to the trunk
local wasNearTrunk = true  -- Track if the player was near the trunk in the previous frame

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100) -- Check every 100ms

        local playerPed = PlayerPedId()
        local vehicle = GetClosestVehicle(GetEntityCoords(playerPed), 5.0, 0, 70)

        if vehicle ~= 0 then
            -- Get the trunk bone index and position
            local trunkBoneIndex = GetEntityBoneIndexByName(vehicle, "boot")
            local trunkPos = GetWorldPositionOfEntityBone(vehicle, trunkBoneIndex)
            local playerPos = GetEntityCoords(playerPed)

            -- Calculate the distance between the player and the trunk
            local distance = #(playerPos - trunkPos)

            if distance <= 3.0 then
                isNearTrunk = true  -- Player is near the trunk

            else
                isNearTrunk = false -- Player is not near the trunk
            end
        else
            isNearTrunk = false -- No vehicle nearby
        end

        -- Check if the player was near the trunk and now is not, trigger the drop
        if carrying and not isNearTrunk and wasNearTrunk then
            TriggerServerEvent('carry:server:stopCarry', carriedPlayer) -- Drop the target player
            carrying = false -- Ensure carrying is reset so we don't trigger again
        end

        -- Update the tracking variable
        wasNearTrunk = isNearTrunk
    end
end)



-- Carry animation

local carrying = false
local carriedPlayer = nil
local carrierPlayer = nil -- Store the ID of the player carrying you
local isNearTrunk = false -- Variable to check proximity to the trunk
local wasNearTrunk = true -- Track if the player was near the trunk in the previous frame

-- Function to carry a player
RegisterNetEvent('carry:client:startCarry')
AddEventHandler('carry:client:startCarry', function(targetPlayer)
    if not isNearTrunk then
        print("You must be near a trunk to carry someone.")
        return -- Block the action if not near the trunk
    end

    local playerPed = PlayerPedId()
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayer))

    if carrying then
        return -- Prevent multiple carry actions
    end

    carrying = true
    carriedPlayer = targetPlayer

    print("You (ID:", GetPlayerServerId(PlayerId()), ") are carrying player ID:", targetPlayer) -- Debug message

    RequestAnimDict("missfinale_c2mcs_1")
    while not HasAnimDictLoaded("missfinale_c2mcs_1") do
        Citizen.Wait(100)
    end

    TaskPlayAnim(playerPed, "missfinale_c2mcs_1", "fin_c2_mcs_1_camman", 8.0, -8.0, -1, 49, 0, false, false, false)
    
    AttachEntityToEntity(targetPed, playerPed, 0, 0.26, 0.15, 0.63, 0.5, 0.5, 0.0, false, false, false, false, 2, false)
end)

-- Function to stop carrying a player
RegisterNetEvent('carry:client:stopCarry')
AddEventHandler('carry:client:stopCarry', function()
    local playerPed = PlayerPedId()
    
    if carriedPlayer then
        local targetPed = GetPlayerPed(GetPlayerFromServerId(carriedPlayer))
        DetachEntity(targetPed, true, true)
        ClearPedTasksImmediately(targetPed)

        print("You (ID:", GetPlayerServerId(PlayerId()), ") have stopped carrying player ID:", carriedPlayer) -- Debug message
    end
    
    DetachEntity(playerPed, true, true)
    ClearPedTasksImmediately(playerPed)

    carrying = false
    carriedPlayer = nil
end)

-- Triggered when being carried
RegisterNetEvent('carry:client:beingCarried')
AddEventHandler('carry:client:beingCarried', function(carrierPlayerId)
    local playerPed = PlayerPedId()
    carrierPlayer = carrierPlayerId

    print("You (ID:", GetPlayerServerId(PlayerId()), ") are being carried by player ID:", carrierPlayerId) -- Debug message

    RequestAnimDict("nm")
    while not HasAnimDictLoaded("nm") do
        Citizen.Wait(100)
    end

    TaskPlayAnim(playerPed, "nm", "firemans_carry", 8.0, -8.0, -1, 33, 0, false, false, false)
    
    local carrierPed = GetPlayerPed(GetPlayerFromServerId(carrierPlayerId))
    AttachEntityToEntity(playerPed, carrierPed, 0, 0.26, 0.15, 0.63, 0.5, 0.5, 0.0, false, false, false, false, 2, false)
end)

-- Command to start carrying a player
RegisterCommand('carry', function()
    local closestPlayer = GetClosestPlayer()
    local playerPed = PlayerPedId()
    local vehicle = GetClosestVehicle(GetEntityCoords(playerPed), 5.0, 0, 70)

    if vehicle ~= 0 then
        -- Check if the trunk is open or destroyed
        local trunkDoorIndex = 5 -- The trunk door index
        if GetVehicleDoorAngleRatio(vehicle, trunkDoorIndex) > 0 or IsVehicleDoorDamaged(vehicle, trunkDoorIndex) then
            if closestPlayer then
                TriggerServerEvent('carry:server:startCarry', GetPlayerServerId(closestPlayer))
            else
                print("No player nearby to carry")
            end
        else
            print("The trunk is closed. You cannot carry anyone.")
        end
    else
        print("No vehicle nearby.")
    end
end)

-- Command to stop carrying
RegisterCommand('stopcarry', function()
    if carrying then
        TriggerServerEvent('carry:server:stopCarry', carriedPlayer)
    else
        print("You are not carrying anyone")
    end
end)

-- Utility function to get the closest player
function GetClosestPlayer()
    local players = GetActivePlayers()
    local closestDistance = -1
    local closestPlayer = -1
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)

    for _, player in ipairs(players) do
        local targetPed = GetPlayerPed(player)
        if targetPed ~= playerPed then
            local targetPos = GetEntityCoords(targetPed)
            local distance = #(playerPos - targetPos)
            if closestDistance == -1 or closestDistance > distance then
                closestPlayer = player
                closestDistance = distance
            end
        end
    end

    if closestDistance ~= -1 and closestDistance <= 3.0 then
        return closestPlayer
    else
        return nil
    end
end

-- Thread to monitor proximity to the trunk and stop carrying if out of range
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100) -- Check every 100ms

        local playerPed = PlayerPedId()
        local vehicle = GetClosestVehicle(GetEntityCoords(playerPed), 5.0, 0, 70)

        if vehicle ~= 0 then
            -- Get the trunk bone index and position
            local trunkBoneIndex = GetEntityBoneIndexByName(vehicle, "boot")
            local trunkPos = GetWorldPositionOfEntityBone(vehicle, trunkBoneIndex)
            local playerPos = GetEntityCoords(playerPed)

            -- Calculate the distance between the player and the trunk
            local distance = #(playerPos - trunkPos)

            if distance <= 3.0 then
                isNearTrunk = true  -- Player is near the trunk
            else
                isNearTrunk = false -- Player is not near the trunk
            end
        else
            isNearTrunk = false -- No vehicle nearby
        end

        -- Check if the player was near the trunk and now is not, trigger the drop and debug
        if carrying and not isNearTrunk and wasNearTrunk then
            print("Player ID:", GetPlayerServerId(PlayerId()), "moved out of radius while carrying player ID:", carriedPlayer)
            TriggerServerEvent('carry:server:stopCarry', carriedPlayer) -- Drop the target player
        end

        -- Update the tracking variable
        wasNearTrunk = isNearTrunk
    end
end)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0) -- Check every frame

        if isNearTrunk and carrying then
            -- Check if the player presses the "E" key
            if IsControlJustReleased(0, 38) then -- 38 is the default control ID for the "E" key
                local playerPed = PlayerPedId()
                local vehicle = GetClosestVehicle(GetEntityCoords(playerPed), 5.0, 0, 70)
                
                if vehicle ~= 0 then
                    -- Check if the trunk is open
                    if GetVehicleDoorAngleRatio(vehicle, 5) > 0 then
                        -- Get the trunk bone index
                        local trunkBoneIndex = GetEntityBoneIndexByName(vehicle, "bodyshell")

                        -- Get the network ID of the vehicle to pass to the server
                        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)

                        -- Trigger the server event to handle the attachment
                        TriggerServerEvent('carry:server:attachToTrunk', GetPlayerServerId(PlayerId()), carriedPlayer, vehicleNetId, trunkBoneIndex)

                        -- Reset carrying state on the client
                        carrying = false
                    else
                        -- Optionally, notify the player that the trunk is closed
                        print("Trunk is closed. Open it before placing the body.")
                    end
                end
            end
        end
    end
end)



-- Listen for the server's response with the carry status
RegisterNetEvent('carry:client:sendCarryStatus')
AddEventHandler('carry:client:sendCarryStatus', function(isCarrying, carriedPlayerId)
    if isCarrying then
        local message = "You are carrying player ID: " .. tostring(carriedPlayerId)
        TriggerEvent('chat:addMessage', { args = {"DEBUG", message} })
    else
        local message = "You are not carrying anyone."
        TriggerEvent('chat:addMessage', { args = {"DEBUG", message} })
    end
end)

RegisterNetEvent('carry:client:attachToTrunk')
AddEventHandler('carry:client:attachToTrunk', function(carrierPlayerId, targetPlayerId, vehicleNetId, trunkBoneIndex)
    local carrierPed = GetPlayerPed(GetPlayerFromServerId(carrierPlayerId))
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)

    -- Detach the carried player from the carrier
    DetachEntity(targetPed, true, true)
    ClearPedTasksImmediately(targetPed)

    -- Attach the carried player to the trunk's bone
    AttachEntityToEntity(targetPed, vehicle, trunkBoneIndex,  0.15, -1.75, 0.96, 0.0, 0.0, 104.0, false, false, false, false, 2, false)

    -- Stop the carrying animation for the carrying player
    ClearPedTasksImmediately(carrierPed)

    print("Carried player has been detached from carrier and attached to the trunk.")
end)



Citizen.CreateThread(function()
    local trunkDestroyed = false  -- Flag to track if the trunk has been destroyed

    while true do
        Citizen.Wait(100)  -- Check every 100 milliseconds; adjust this value as needed

        -- Get the vehicle the player is currently driving
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)

        -- Check if the player is in a vehicle
        if vehicle ~= 0 then
            local trunkDoorIndex = 5  -- Trunk/boot door index

            -- Check if the trunk is destroyed
            if IsVehicleDoorDamaged(vehicle, trunkDoorIndex) then
                if not trunkDestroyed then
                    -- Trunk is destroyed and this is the first time detecting it
                    print("The trunk/boot of the vehicle you are driving is destroyed.")
                    trunkDestroyed = true  -- Set the flag to true
                    -- Additional logic can be added here (e.g., notify server, detach entities)
                end
            else
                -- Reset the flag if the trunk is repaired or the player changes vehicles
                trunkDestroyed = false
            end
        else
            -- Reset the flag if the player is not in a vehicle
            trunkDestroyed = false
        end
    end
end)


