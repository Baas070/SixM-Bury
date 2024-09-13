local spawnedObjects = {}  -- Table to store references to the spawned objects along with their IDs

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

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for objectId, obj in pairs(spawnedObjects) do
            if DoesEntityExist(obj) then
                local objCoords = GetEntityCoords(obj)
                local distance = #(playerCoords - objCoords)
                
                if distance <= 3.0 then
                    -- Removed the 3D text, but keep the keybind check
                    if IsControlJustPressed(0, 38) then  -- Check if "E" is pressed (38 is the control ID for "E")
                        TriggerServerEvent('adjustObjectHeight', objectId)  -- Send the object ID to the server to adjust its height
                    end
                end
            end
        end
    end
end)

-- Handle height adjustment from the server
RegisterNetEvent('adjustObjectHeightOnClient')
AddEventHandler('adjustObjectHeightOnClient', function(objectId)
    local obj = spawnedObjects[objectId]
    if DoesEntityExist(obj) then
        Citizen.CreateThread(function()
            local objCoords = GetEntityCoords(obj)
            local targetZ = objCoords.z + 0.1  -- Adjust by 10 centimeters smoothly
            while objCoords.z < targetZ do
                objCoords = GetEntityCoords(obj)
                SetEntityCoordsNoOffset(obj, objCoords.x, objCoords.y, objCoords.z + 0.01, true, true, true)
                Citizen.Wait(20)  -- Adjust this for smoothness/speed
            end
        end)
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
    local groundHash = GetGroundHash(playerPed)
    local surfaceType, canDig = TranslateGroundHash(groundHash)

    if canDig then
        IsDigging = true
        DigText = Config.DiggingText
        ShovelHoldingAnimation()
        
        -- Start the digging animation and wait for it to play
        Citizen.Wait(3400)  -- Wait for the animation to start

        print("Digging started on surface: " .. surfaceType)
        
        -- Trigger the event to spawn the prop
        TriggerEvent('StartBuryingEvent')  -- This will spawn the prop as part of the digging process
    else
        print("You cannot dig on this surface: " .. surfaceType)
        IsDigging = false
    end
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


-- client.lua

local carrying = false
local carriedPlayer = nil

-- Function to find the closest vehicle and get its boot bone index
local function findClosestVehicleWithBoot(radius)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local vehicles = GetGamePool("CVehicle")
    local closestDistance = -1
    local closestVehicle = nil

    for _, vehicle in ipairs(vehicles) do
        local vehicleCoords = GetEntityCoords(vehicle)
        local distance = #(vehicleCoords - playerCoords)
        if closestDistance == -1 or distance < closestDistance then
            closestDistance = distance
            closestVehicle = vehicle
        end
    end

    if closestDistance ~= -1 and closestDistance <= radius then
        local bootBoneIndex = GetEntityBoneIndexByName(closestVehicle, "boot")
        return closestVehicle, bootBoneIndex
    else
        return nil, nil
    end
end

-- -- Function to draw 3D text
-- local function DrawText3D(x, y, z, text)
--     local onScreen, _x, _y = World3dToScreen2d(x, y, z)
--     local px, py, pz = table.unpack(GetGameplayCamCoords())

--     if onScreen then
--         SetTextScale(0.35, 0.35)
--         SetTextFont(4)
--         SetTextProportional(1)
--         SetTextColour(255, 255, 255, 215)
--         SetTextEntry("STRING")
--         SetTextCentre(1)
--         AddTextComponentString(text)
--         DrawText(_x, _y)
--         local factor = (string.len(text)) / 370
--         DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 41, 11, 41, 68)
--     end
-- end

-- Function to attach the player to the vehicle boot with the 'flee_backward_loop_shopkeeper' animation
RegisterNetEvent('carry:client:attachToBoot')
AddEventHandler('carry:client:attachToBoot', function(vehicleNetId)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if DoesEntityExist(vehicle) then
        local playerPed = PlayerPedId()
        local bootBoneIndex = GetEntityBoneIndexByName(vehicle, "boot")

        -- Adjust the position to properly align the player with the boot
        local xOffset, yOffset, zOffset = -0.12, 0.15, 0.3  -- Modify these offsets as needed
        
        -- Adjust the rotation of the player relative to the vehicle
        local xRot, yRot, zRot = 0.0, 0.0, 180.0  -- Adjust rotation as needed
        
        -- Adjust the heading (z-axis rotation) of the player relative to the vehicle
        local heading = 25.0  -- Set your desired heading here (0.0 - 360.0)

        -- Detach the player from any entity they are attached to
        DetachEntity(playerPed, true, true)
        
        -- Clear any existing animations
        ClearPedTasksImmediately(playerPed)

        -- Attach player to the vehicle boot with rotation and heading adjustments
        AttachEntityToEntity(playerPed, vehicle, bootBoneIndex, xOffset, yOffset, zOffset, xRot, yRot, heading, false, false, false, false, 2, true)
        
        -- Load the 'random@mugging4' animation dictionary
        RequestAnimDict("random@mugging4")
        while not HasAnimDictLoaded("random@mugging4") do
            Citizen.Wait(100)
        end

        -- Play the 'flee_backward_loop_shopkeeper' animation
        TaskPlayAnim(playerPed, "random@mugging4", "flee_backward_loop_shopkeeper", 8.0, -8.0, -1, 1, 0, false, false, false)

        -- Check if the trunk is broken and handle accordingly
        Citizen.CreateThread(function()
            while true do
                Citizen.Wait(100)

                -- Check if the trunk is broken (door index 5)
                if IsVehicleDoorDamaged(vehicle, 5) then
                    -- Trigger server event to sync detachment and ragdoll
                    TriggerServerEvent('carry:server:detachAndRagdoll', vehicleNetId, GetPlayerServerId(PlayerId()))

                    -- Break out of the loop as the trunk is already broken
                    break
                end
            end
        end)
    end
end)

-- Client event to handle detaching and ragdoll
RegisterNetEvent('carry:client:detachAndRagdoll')
AddEventHandler('carry:client:detachAndRagdoll', function(vehicleNetId, playerServerId)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    local playerPed = GetPlayerPed(GetPlayerFromServerId(playerServerId))

    if DoesEntityExist(vehicle) and DoesEntityExist(playerPed) then
        -- Detach the player from the vehicle
        DetachEntity(playerPed, true, true)
        
        -- Put the player in ragdoll mode for 10 seconds
        SetPedToRagdoll(playerPed, 10000, 10000, 0, false, false, false)
    end
end)





Citizen.CreateThread(function()
    while true do
        local vehicle, bootBoneIndex = findClosestVehicleWithBoot(3.0)  -- 3-meter radius
        if vehicle and bootBoneIndex ~= -1 then
            local bootCoords = GetWorldPositionOfEntityBone(vehicle, bootBoneIndex)
            local lockStatus = GetVehicleDoorLockStatus(vehicle)
            if GetVehicleDoorAngleRatio(vehicle, 5) > 0 then -- Check if trunk (door index 5) is open
                -- DrawText3D(bootCoords.x, bootCoords.y, bootCoords.z + 0.5, "Press [E] to Place Body")
                
                if IsControlJustPressed(0, 38) and carrying then -- 'E' key is pressed (default key code 38)
                    print("E key pressed - attempting to place body in trunk")  -- Debug message

                    local playerPed = PlayerPedId()
                    local targetPed = GetPlayerPed(GetPlayerFromServerId(carriedPlayer))
                    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)

                    -- Detach the player from the carrying ped and trigger the server event
                    DetachEntity(targetPed, true, true)
                    TriggerServerEvent('carry:server:detachAndAttachToBoot', carriedPlayer, vehicleNetId)
                    
                    -- Clear carrying status
                    carrying = false
                    carriedPlayer = nil
                end
            else
                if lockStatus == 2 then
                    -- DrawText3D(bootCoords.x, bootCoords.y, bootCoords.z + 0.5, "Trunk Locked")
                else
                    -- DrawText3D(bootCoords.x, bootCoords.y, bootCoords.z + 0.5, "Trunk Closed")
                end
            end
        end
        Wait(0)  -- Continuously check
    end
end)


-- Function to carry a player
RegisterNetEvent('carry:client:startCarry')
AddEventHandler('carry:client:startCarry', function(targetPlayer)
    local playerPed = PlayerPedId()
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayer))

    if carrying then
        return -- Prevent multiple carry actions
    end

    -- Check if the player is currently in the boot and detach them
    if bootOccupied then
        DetachEntity(targetPed, true, true)
        -- Reset the bootOccupied status
        bootOccupied = false
        -- Notify the server that the boot is no longer occupied
        local vehicle = GetVehiclePedIsIn(targetPed, false)
        if DoesEntityExist(vehicle) then
            local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
            TriggerServerEvent('carry:server:updateBootStatus', vehicleNetId, false)
        end
    end

    carrying = true
    carriedPlayer = targetPlayer

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
    end
    
    DetachEntity(playerPed, true, true)
    ClearPedTasksImmediately(playerPed)

    carrying = false
    carriedPlayer = nil
end)

-- Triggered when being carried
RegisterNetEvent('carry:client:beingCarried')
AddEventHandler('carry:client:beingCarried', function(carrierPlayer)
    local playerPed = PlayerPedId()

    RequestAnimDict("nm")
    while not HasAnimDictLoaded("nm") do
        Citizen.Wait(100)
    end

    TaskPlayAnim(playerPed, "nm", "firemans_carry", 8.0, -8.0, -1, 33, 0, false, false, false)
    
    local carrierPed = GetPlayerPed(GetPlayerFromServerId(carrierPlayer))
    AttachEntityToEntity(playerPed, carrierPed, 0, 0.26, 0.15, 0.63, 0.5, 0.5, 0.0, false, false, false, false, 2, false)
end)

-- Command to start carrying a player
RegisterCommand('carry', function()
    local closestPlayer = GetClosestPlayer()
    local vehicle, bootBoneIndex = findClosestVehicleWithBoot(3.0)  -- Ensure player is near a vehicle boot

    if closestPlayer and vehicle and bootBoneIndex ~= -1 then
        if GetVehicleDoorAngleRatio(vehicle, 5) > 0 then  -- Ensure trunk is open
            TriggerServerEvent('carry:server:startCarry', GetPlayerServerId(closestPlayer))
        else
            print("The trunk must be open to carry a player.")
        end
    else
        print("No player nearby to carry or not near a vehicle boot")
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

-- -- Control variable to determine if checks should be performed
-- local shouldCheck = false

-- -- Predefined mapping of hash values to readable surface types
-- local groundHashes = {
--     [-1885547121] = "Dirt",
--     [282940568] = "Road",
--     [510490462] = "Sand",
--     [951832588] = "Sand 2",
--     [2128369009] = "Grass and Dirt Combined",
--     [-840216541] = "Rock Surface",
--     [-1286696947] = "Grass and Dirt Combined 2",
--     [1333033863] = "Grass",
--     [1187676648] = "Concrete",
--     [1144315879] = "Grass 2",
--     [-1942898710] = "Gravel, Dirt, and Cobblestone",
--     [560985072] = "Sand Grass",
--     [-1775485061] = "Cement",
--     [581794674] = "Grass 3",
--     [1993976879] = "Cement 2",
--     [-1084640111] = "Cement 3",
--     [-700658213] = "Dirt with Grass",
--     [0] = "Air",
--     [-124769592] = "Dirt with Grass 4",
--     [-461750719] = "Dirt with Grass 5",
--     [-1595148316] = "Concrete 4", 
--     [1288448767] = "Water",
--     [765206029] = "Marble Tiles",
--     [-1186320715] = "Pool Water",
--     [1639053622] = "Concrete 3",  
-- }

-- function GetGroundHash(entity)
--     local coords = GetEntityCoords(entity)
--     local num = StartShapeTestCapsule(coords.x, coords.y, coords.z + 4, coords.x, coords.y, coords.z - 2.0, 1, 1, entity, 7)
--     local _, _, _, _, groundHash = GetShapeTestResultEx(num)
--     return groundHash
-- end

-- function TranslateGroundHash(hash)
--     return groundHashes[hash] or "Unknown Surface"
-- end

-- -- Conditionally run the loop only if shouldCheck is true
-- if shouldCheck then
--     Citizen.CreateThread(function()
--         while true do
--             local entity = PlayerPedId() -- Use PlayerPedId as the default entity, which represents the player character
--             local groundHash = GetGroundHash(entity)
--             local surfaceType = TranslateGroundHash(groundHash)
--             print("Ground Surface Type: " .. surfaceType .. " (Hash: " .. groundHash .. ")")
--             Citizen.Wait(5000) -- Wait for 5 seconds
--         end
--     end)
-- end




-- Citizen.CreateThread(function()
--     while true do
--         local playerPed = PlayerPedId() -- Get the player's ped
--         local playerCoords = GetEntityCoords(playerPed) -- Get the player's coordinates

--         local players = GetActivePlayers() -- Get all active players

--         for _, targetPlayerId in ipairs(players) do
--             if targetPlayerId ~= PlayerId() then -- Exclude the current player
--                 local targetPed = GetPlayerPed(targetPlayerId) -- Get the target player's ped
--                 local targetCoords = GetEntityCoords(targetPed) -- Get the target player's coordinates

--                 local distance = #(targetCoords - playerCoords) -- Calculate distance between players

--                 if distance <= 3.0 then -- Check if within 3 meters
--                     -- List of animations to check for
--                     local animationsToCheck = {
--                         {animDict = 'mp_suicide', animName = 'pill'},
--                         {animDict = 'anim@amb@business@weed@weed_inspecting_high_dry@', animName = 'weed_inspecting_high_base_inspector'},
--                         {animDict = 'dead', animName = 'dead_a'},
--                         {animDict = 'veh@low@front_ps@idle_duck', animName = 'sit'},
--                         {animDict = 'combat@damage@writhe', animName = 'writhe_loop'}, -- Last Stand animation
--                         {animDict = 'veh@low@front_ps@idle_duck', animName = 'sit'}, -- Sitting animation in vehicle
--                         -- Add more animations if needed
--                     }

--                     for _, anim in ipairs(animationsToCheck) do
--                         if IsEntityPlayingAnim(targetPed, anim.animDict, anim.animName, 3) then
--                             print("Player " .. GetPlayerName(targetPlayerId) .. " is playing the animation " .. anim.animName .. " from " .. anim.animDict)
--                         else
--                             print("Player " .. GetPlayerName(targetPlayerId) .. " is not playing any specified animations.")
--                         end
--                     end
--                 end
--             end
--         end

--         Citizen.Wait(5000) -- Wait for 5 seconds before the next check
--     end
-- end)
