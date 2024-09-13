local spawnedObjects = {}

RegisterServerEvent('broadcastObjectSpawn')
AddEventHandler('broadcastObjectSpawn', function(objectName, randomId, x, y, z)
    -- Store the object details on the server (optional, for tracking)
    table.insert(spawnedObjects, {objectName = objectName, id = randomId, x = x, y = y, z = z})

    -- Broadcast the event to all clients to spawn the object at the specified coordinates
    TriggerClientEvent('spawnObjectOnClient', -1, objectName, randomId, x, y, z)
end)

-- Optional: Command to list all spawned objects (for debugging or admin purposes)
RegisterCommand('listSpawnedObjects', function(source, args, rawCommand)
    print("List of spawned objects:")
    for i, object in ipairs(spawnedObjects) do
        print("Object ID: " .. object.id .. ", Object Name: " .. object.objectName)
    end
end, true)  -- true indicates this command is restricted to admins (or the server console)



RegisterServerEvent('adjustObjectHeight')
AddEventHandler('adjustObjectHeight', function(objectId)
    TriggerClientEvent('adjustObjectHeightOnClient', -1, objectId)
end)



local QBCore = exports['qb-core']:GetCoreObject()

-- Create usable shovel item
QBCore.Functions.CreateUseableItem(Config.ShovelItem, function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player.Functions.GetItemByName(item.name) then
        TriggerClientEvent("SxM-bury:UseShovel", source, item.name)
    end
end)

-- -- Server event to trigger the particle effect and attach dirt prop on all clients
-- RegisterNetEvent('SxM-bury:PlayParticleEffect')
-- AddEventHandler('SxM-bury:PlayParticleEffect', function(shovelNetId)
--     -- Broadcast the event to all clients to attach the dirt prop and play the particle effect
--     TriggerClientEvent('SxM-bury:PlayParticleOnShovel', -1, shovelNetId)
-- end)

-- -- Server event to handle dirt prop detachment on all clients
-- RegisterNetEvent('SxM-bury:DetachDirtProp')
-- AddEventHandler('SxM-bury:DetachDirtProp', function()
--     -- Broadcast the event to all clients to detach the dirt prop
--     TriggerClientEvent('SxM-bury:DetachDirtPropClient', -1)
-- end)

-- local DirtPiles = {}

-- RegisterNetEvent('SxM-bury:StoreDirtPileData')
-- AddEventHandler('SxM-bury:StoreDirtPileData', function(dirtPileData)
--     -- Check if a dirt pile already exists at this location
--     local found = false
--     for i, pile in ipairs(DirtPiles) do
--         if pile.x == dirtPileData.x and pile.y == dirtPileData.y and pile.z == dirtPileData.z then
--             -- Update the existing dirt pile data
--             DirtPiles[i] = dirtPileData
--             found = true
--             print("Updated existing dirt pile at coordinates: " .. dirtPileData.x .. ", " .. dirtPileData.y .. ", " .. dirtPileData.z)
--             break
--         end
--     end
    
--     -- If not found, add it as a new entry
--     if not found then
--         table.insert(DirtPiles, dirtPileData)
--         print("Stored new dirt pile data at coordinates: " .. dirtPileData.x .. ", " .. dirtPileData.y .. ", " .. dirtPileData.z)
--     end
-- end)

-- -- Command to retrieve all stored dirt pile data
-- RegisterCommand('getDirtPiles', function(source, args, rawCommand)
--     print("All stored dirt piles:")
--     for i, dirtPile in ipairs(DirtPiles) do
--         print("Dirt Pile #" .. i .. ": " .. dirtPile.x .. ", " .. dirtPile.y .. ", " .. dirtPile.z .. ", height: " .. dirtPile.height .. ", heading: " .. dirtPile.heading .. ", bury count: " .. dirtPile.buryCount)
--     end
-- end, true)

-- RegisterNetEvent('SxM-bury:RequestDirtPileData')
-- AddEventHandler('SxM-bury:RequestDirtPileData', function()
--     local _source = source
--     TriggerClientEvent('SxM-bury:ReceiveDirtPileData', _source, DirtPiles)
-- end)



local attachedPlayers = {}
local attachedBy = {}

-- Sync attachment event
RegisterServerEvent("customAttach:sync")
AddEventHandler("customAttach:sync", function(targetSrc)
    local src = source
    local srcPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    
    if #(GetEntityCoords(srcPed) - GetEntityCoords(targetPed)) <= 3.0 then
        TriggerClientEvent("customAttach:syncTarget", targetSrc, src)
        attachedPlayers[src] = targetSrc
        attachedBy[targetSrc] = src
    else
        print("Players not within 3.0 units.")
    end
end)

-- Stop attachment event
RegisterServerEvent("customAttach:stop")
AddEventHandler("customAttach:stop", function(targetSrc)
    local src = source
    
    if attachedPlayers[src] then
        TriggerClientEvent("customAttach:stopTarget", targetSrc)
        attachedBy[attachedPlayers[src]] = nil
        attachedPlayers[src] = nil
    elseif attachedBy[src] then
        TriggerClientEvent("customAttach:stopTarget", attachedBy[src])
        attachedPlayers[attachedBy[src]] = nil
        attachedBy[src] = nil
    end

    -- Update the position of the detached player
    local targetPed = GetPlayerPed(targetSrc)
    local srcPed = GetPlayerPed(src)
    local srcCoords = GetEntityCoords(srcPed)
    SetEntityCoords(targetPed, srcCoords.x, srcCoords.y, srcCoords.z, false, false, false, true)
end)

-- Player dropped event
AddEventHandler('playerDropped', function(reason)
    local src = source
    
    if attachedPlayers[src] then
        TriggerClientEvent("customAttach:stopTarget", attachedPlayers[src])
        attachedBy[attachedPlayers[src]] = nil
        attachedPlayers[src] = nil
    end

    if attachedBy[src] then
        TriggerClientEvent("customAttach:stopTarget", attachedBy[src])
        attachedPlayers[attachedBy[src]] = nil
        attachedBy[src] = nil
    end
end)

-- Adjust heading on the server and broadcast it to all clients
RegisterServerEvent('updateHeading')
AddEventHandler('updateHeading', function(adjustment)
    local src = source
    local srcPed = GetPlayerPed(src)
    local currentHeading = GetEntityHeading(srcPed)
    local newHeading = currentHeading + adjustment

    -- Apply the new heading on the server side
    SetEntityHeading(srcPed, newHeading)

    -- Broadcast the new heading to all clients
    TriggerClientEvent('syncHeading', -1, src, newHeading)
end)



-- server.lua

RegisterServerEvent('carry:server:startCarry')
AddEventHandler('carry:server:startCarry', function(targetPlayer)
    local sourcePlayer = source

    -- Notify both players to start animations
    TriggerClientEvent('carry:client:startCarry', sourcePlayer, targetPlayer)
    TriggerClientEvent('carry:client:beingCarried', targetPlayer, sourcePlayer)
end)

RegisterServerEvent('carry:server:stopCarry')
AddEventHandler('carry:server:stopCarry', function(targetPlayer)
    local sourcePlayer = source

    -- Notify both players to stop the animations and detach entities
    TriggerClientEvent('carry:client:stopCarry', sourcePlayer)
    TriggerClientEvent('carry:client:stopCarry', targetPlayer)
end)

RegisterNetEvent('carry:server:detachAndAttachToBoot')
AddEventHandler('carry:server:detachAndAttachToBoot', function(targetPlayer, vehicleNetId)
    -- Trigger the client event to attach the player to the vehicle boot
    TriggerClientEvent('carry:client:attachToBoot', targetPlayer, vehicleNetId)
end)

RegisterNetEvent('carry:server:detachAndRagdoll')
AddEventHandler('carry:server:detachAndRagdoll', function(vehicleNetId, playerServerId)
    -- Trigger the client event for all players, passing the vehicle ID and the player to detach
    TriggerClientEvent('carry:client:detachAndRagdoll', -1, vehicleNetId, playerServerId)
end)
