-- WindEnergyUnleashed Client-Side Logic
-- Handles animations, UI (tooltips, context menus), timed actions, visual effects

local WindEnergy = require "WindEnergy/WindEnergy_Core" -- Get reference to core table
require "TimedActions/ISBaseTimedAction"
require "WindEnergy/WEU_TurbineStatusWindow" -- Added for the status UI

WindEnergy.Client = WindEnergy.Client or {} -- Define client-specific sub-table

local K = WindEnergy.ModDataKeys -- Alias for brevity

---===========================================================================
--- Event Registration (Deferred)
---===========================================================================
function WindEnergy.Client.RegisterEvents()
    WindEnergy.log("Registering client events...")
    Events.OnObjectAdded.Add(WindEnergy.Client.OnObjectAdded)
    Events.OnFillWorldObjectContextMenu.Add(WindEnergy.Client.BuildContextMenu)
    Events.OnObjectTooltip.Add(WindEnergy.Client.CreateToolTip)
    WindEnergy.log("Client events registered.")
end

---===========================================================================
--- Animation Handling
---===========================================================================

-- Updates the visual state (direction, animation) of a turbine based on its modData
-- This should be called when the object is updated or becomes visible.
function WindEnergy.Client.UpdateTurbineVisuals(obj)
    if not obj or not obj:getSquare() then return end
    local modData = obj:getModData()
    if not modData or not modData[K.IsWindTurbine] then return end
    local turbineData = modData[K.TurbineData]
    if not turbineData then return end

    local turbineDef = WindEnergy.TurbineTypes[turbineData[K.TypeName]]
    if not turbineDef then return end -- Should not happen if server logic is correct

    -- 1. Set Direction based on Wind
    local windDirection = turbineData[K.WindDirection] or 0
    local isoDir = WindEnergy.Utils.WindAngleToDirection(windDirection)
    if obj:getDir() ~= isoDir then
        obj:setDir(isoDir)
        -- Force redraw? May not be needed if animation state changes.
        -- obj:getSquare():clientModify() -- Might be too heavy
    end

    -- 2. Set Animation State based on Power Output
    local powerOutput = turbineData[K.PowerOutput] or 0
    local maxPower = turbineDef.maxPowerOutput
    local animState = "Idle" -- Default state

    if powerOutput > 0 then
        local powerRatio = 0
        if maxPower > 0 then -- Avoid division by zero
             powerRatio = powerOutput / maxPower
        end

        if powerRatio > 0.66 then
            animState = "SpinFast" -- Placeholder name
        elseif powerRatio > 0.1 then
            animState = "SpinSlow" -- Placeholder name
        else
            animState = "SpinIdle" -- Placeholder for very slow spin or just starting
        end
    end

    -- Check if the animation state needs changing
    -- Note: obj:getSprite():isPlaying() might not be reliable for checking the *current* state name.
    -- We might need to store the last set animation state in modData or a local client table if needed for optimization.
    -- For simplicity, we set it every time visual update is triggered.
    if obj:getSprite():hasActiveAnims() and obj:getSprite():isCurrentAnim(animState) then
         -- Already playing the correct animation
    else
        --WindEnergy.log("Setting anim state for turbine %d,%d,%d to %s (Power: %.1fW)", obj:getX(), obj:getY(), obj:getZ(), animState, powerOutput)
        obj:getSprite():PlayAnim(animState, true) -- Play the animation (ensure loop is set correctly in AnimSet)
        -- obj:transmitUpdatedSprite() -- May be needed in MP? Or handled by modData sync? Let's assume modData sync is enough for now.
    end

end

-- Hook into object updates to refresh visuals
-- OnObjectModDataUpdated is ideal as it triggers when server sends new data.
function WindEnergy.Client.OnObjectModDataUpdated(obj)
    if obj and obj:getModData()[K.IsWindTurbine] then
        --WindEnergy.log("ModData updated for turbine %d,%d,%d, updating visuals.", obj:getX(), obj:getY(), obj:getZ())
        WindEnergy.Client.UpdateTurbineVisuals(obj)
    end
end

-- Also update visuals when an object is added (e.g., loaded into view)
function WindEnergy.Client.OnObjectAdded(obj)
     if obj and obj:getModData()[K.IsWindTurbine] then
        --WindEnergy.log("Turbine %d,%d,%d added to client, updating visuals.", obj:getX(), obj:getY(), obj:getZ())
        WindEnergy.Client.UpdateTurbineVisuals(obj)
     end
end


---===========================================================================
--- Context Menu Building
---===========================================================================

function WindEnergy.Client.BuildContextMenu(playerIndex, context, worldobjects)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    for i, obj in ipairs(worldobjects) do
        if obj and obj:getModData()[K.IsWindTurbine] then
            local turbineData = obj:getModData()[K.TurbineData]
            if not turbineData then WindEnergy.warn("Turbine %d,%d,%d has IsWindTurbine flag but no TurbineData!", obj:getX(), obj:getY(), obj:getZ()); return end

            local turbineDef = WindEnergy.TurbineTypes[turbineData[K.TypeName]]
            local bladeDef = WindEnergy.BladeTypes[turbineData[K.BladeType]]
            if not turbineDef or not bladeDef then WindEnergy.error("Missing def for turbine/blade on client: %s / %s", tostring(turbineData[K.TypeName]), tostring(turbineData[K.BladeType])); return end

            -- TODO: Use getText for turbineDef.name once translations are set up (Requires adding turbine names to translation files)
            local turbineOption = context:addOption(turbineDef.name, obj, nil) -- Main turbine entry
            local subMenu = context:getNew(context)
            context:addSubMenu(turbineOption, subMenu)

            -- 1. Inspect Option - Opens the UI Panel
            -- Pass player and obj to the OnOpenPanel function
            subMenu:addOption(getText("ContextMenu_WEU_Inspect"), obj, WEU_TurbineStatusWindow.OnOpenPanel, player, obj)

            -- 2. Connect/Disconnect Power Bank Option
            if ISA and ISAPowerBank then -- Check if ISA mod is loaded
                local connectedPB = turbineData[K.ConnectedPB]
                if connectedPB then
                    -- Option to disconnect
                    subMenu:addOption(getText("ContextMenu_WEU_DisconnectPB"), { turbine = obj, player = player }, WindEnergy.Client.OnDisconnectTurbineFromPB) -- Pass player
                else
                    -- Option to connect - find nearby banks
                    local nearbyPBs = {}
                    local searchRadius = 5 -- Tiles to search around the turbine
                    local tx, ty, tz = obj:getX(), obj:getY(), obj:getZ()
                    for dx = -searchRadius, searchRadius do
                        for dy = -searchRadius, searchRadius do
                            local square = getCell():getGridSquare(tx + dx, ty + dy, tz)
                            if square then
                                for objIdx = 0, square:getObjects():size() - 1 do
                                    local potentialPB = square:getObjects():get(objIdx)
                                    -- Check if it's an ISA Power Bank (using its known properties/modData)
                                    -- More reliable check: Use ISA's own system if available
                                    local isPB = false
                                    if ISA.PBSystem_Client and ISA.PBSystem_Client.getLuaObjectAt then
                                        isPB = ISA.PBSystem_Client:getLuaObjectAt(potentialPB:getX(), potentialPB:getY(), potentialPB:getZ()) ~= nil
                                    elseif potentialPB:getObjectName() == "ISAPowerBank" or (potentialPB:getModData() and potentialPB:getModData().isISAPowerBank) then
                                        -- Fallback check if system isn't ready or available
                                        isPB = true
                                    end

                                    if isPB then
                                        table.insert(nearbyPBs, potentialPB)
                                    end
                                end
                            end
                        end
                    end

                    if #nearbyPBs > 0 then
                        local connectOption = subMenu:addOption(getText("ContextMenu_WEU_ConnectPB"), obj, nil)
                        local connectSubMenu = context:getNew(context)
                        context:addSubMenu(connectOption, connectSubMenu)
                        for _, pbObj in ipairs(nearbyPBs) do
                            local pbName = "Power Bank at " .. pbObj:getX() .. "," .. pbObj:getY() -- Simple name
                            -- Format pbName for display
                            local pbDisplayName = string.format("%d,%d,%d", pbObj:getX(), pbObj:getY(), pbObj:getZ())
                            connectSubMenu:addOption(getText("ContextMenu_WEU_ConnectPB_Select", pbDisplayName), { turbine = obj, powerBank = pbObj, player = player }, WindEnergy.Client.OnConnectTurbineToPB) -- Pass player
                        end
                    else
                        subMenu:addOption(getText("ContextMenu_WEU_ConnectPB_NoneNearby"), false) -- Disabled option
                    end
                end
            end -- End ISA Check

            -- 3. Swap Blades Option
            local swapOption = subMenu:addOption(getText("ContextMenu_WEU_SwapBlades"), obj, nil)
            local swapSubMenu = context:getNew(context)
            context:addSubMenu(swapOption, swapSubMenu)
            local hasBlades = false
            for bladeKey, bladeDefCheck in pairs(WindEnergy.BladeTypes) do
                if player:getInventory():contains(bladeDefCheck.itemType) then
                    -- Add option only if blades are different from current ones
                    if turbineData[K.BladeType] ~= bladeKey then
                        -- TODO: Add blade names to translation files if needed, or keep them as is.
                        swapSubMenu:addOption(getText("ContextMenu_WEU_InstallBlade", bladeDefCheck.name), { turbine = obj, newBladeKey = bladeKey, player = player }, WindEnergy.Client.OnInitiateBladeSwap)
                        hasBlades = true
                    end
                end
            end
            if not hasBlades then
                swapSubMenu:addOption(getText("ContextMenu_WEU_NoBlades"), false) -- Disabled info text
            end

           -- 4. Repair Option
           local condition = turbineData[K.Condition] or turbineDef.conditionMax
           local maxCondition = turbineDef.conditionMax
           if condition < maxCondition and player:getPerkLevel(Perks.Mechanics) >= 2 then -- Check if damaged and player has min skill
               subMenu:addOption(getText("ContextMenu_WEU_RepairTurbine"), { turbine = obj, player = player }, WindEnergy.Client.OnInitiateRepair)
           elseif condition >= maxCondition then
                subMenu:addOption(getText("ContextMenu_WEU_RepairTurbine_NotDamaged"), false) -- Disabled info text
           else -- Not enough skill
                -- TODO: Get skill name dynamically if possible, otherwise hardcode "Mechanics"
                subMenu:addOption(getText("ContextMenu_WEU_RepairTurbine_SkillNeeded", Perks.Mechanics:getName(), 2), false) -- Disabled info text
           end


        end -- End IsWindTurbine check
    end
end


---===========================================================================
--- Context Menu Action Handlers (Client-Side)
---===========================================================================

-- Old OnInspectTurbine function removed. Functionality moved to WEU_TurbineStatusWindow.OnOpenPanel

-- Called when player selects a power bank to connect to
function WindEnergy.Client.OnConnectTurbineToPB(contextData)
    local turbine = contextData.turbine
    local powerBank = contextData.powerBank
    local player = contextData.player -- Get player from context
    WindEnergy.log("Client requesting connect Turbine %d,%d,%d to PB %d,%d,%d", turbine:getX(), turbine:getY(), turbine:getZ(), powerBank:getX(), powerBank:getY(), powerBank:getZ())
    sendClientCommand(player, "WindEnergy", "connectPB", {
        turbineX = turbine:getX(), turbineY = turbine:getY(), turbineZ = turbine:getZ(),
        pbX = powerBank:getX(), pbY = powerBank:getY(), pbZ = powerBank:getZ()
    })
end

-- Called when player selects "Disconnect"
function WindEnergy.Client.OnDisconnectTurbineFromPB(contextData)
    local turbine = contextData.turbine
    local player = contextData.player -- Get player from context
    WindEnergy.log("Client requesting disconnect Turbine %d,%d,%d", turbine:getX(), turbine:getY(), turbine:getZ())
    sendClientCommand(player, "WindEnergy", "disconnectPB", {
        turbineX = turbine:getX(), turbineY = turbine:getY(), turbineZ = turbine:getZ()
    })
end


-- Called when player selects a blade type to install
function WindEnergy.Client.OnInitiateBladeSwap(contextData)
    local turbine = contextData.turbine
    local newBladeKey = contextData.newBladeKey
    local player = contextData.player -- Player object passed directly

    -- Start the timed action
    local action = ISWindTurbineBladeSwapAction:new(player, turbine, newBladeKey, 150) -- 150 ticks = ~2.5 seconds
    ISTimedActionQueue.add(action)
    WindEnergy.log("Initiating blade swap action for turbine %d,%d,%d to %s", turbine:getX(), turbine:getY(), turbine:getZ(), newBladeKey)
end

-- Called when player selects "Repair Turbine"
function WindEnergy.Client.OnInitiateRepair(contextData)
   local turbine = contextData.turbine
   local player = contextData.player

   -- Start the timed action
   local action = ISWindTurbineRepairAction:new(player, turbine, 200) -- 200 ticks = ~3.3 seconds
   ISTimedActionQueue.add(action)
   WindEnergy.log("Initiating repair action for turbine %d,%d,%d", turbine:getX(), turbine:getY(), turbine:getZ())
end

---===========================================================================
--- Tooltip Creation
---===========================================================================

function WindEnergy.Client.CreateToolTip(tooltip, obj)
     if obj and obj:getModData()[K.IsWindTurbine] then
         local turbineData = obj:getModData()[K.TurbineData]
         if not turbineData then return end -- Data not loaded yet?

         local turbineDef = WindEnergy.TurbineTypes[turbineData[K.TypeName]]
         local bladeDef = WindEnergy.BladeTypes[turbineData[K.BladeType]]
         if not turbineDef or not bladeDef then return end -- Definitions missing?

         local conditionPercent = 0
         if turbineDef.conditionMax > 0 then -- Avoid division by zero
             conditionPercent = (turbineData[K.Condition] / turbineDef.conditionMax) * 100
         end

         -- Build tooltip text using Rich Text and placeholders for translation
         local conditionColor = "<RGB:0,1,0>" -- Green (High)
         if conditionPercent < 30 then
             conditionColor = "<RGB:1,0,0>" -- Red (Low)
         elseif conditionPercent < 70 then
             conditionColor = "<RGB:1,1,0>" -- Yellow (Medium)
         end

         -- TODO: Add translation keys for Tooltip labels if desired. For now, keeping labels hardcoded.
         local text = "<CENTRE>" .. turbineDef.name .. "<LINE>" .. -- Use formatting tags
                      "<LEFT>" .. -- Align subsequent lines left
                      "Blades: " .. bladeDef.name .. "<LINE>" .. -- Use <LINE> for newlines
                      "Condition: " .. conditionColor .. string.format("%.1f%%", conditionPercent) .. "<RESET><LINE>" .. -- Add color and reset
                      "Power Output: " .. string.format("%.1f W", turbineData[K.PowerOutput] or 0) .. "<LINE>"

         if turbineData[K.ConnectedPB] then
             text = text .. "Connected to: Power Bank (" .. turbineData[K.ConnectedPB].x .. "," .. turbineData[K.ConnectedPB].y .. ")"
         else
             text = text .. "Connection: None"
         end

         tooltip:setName(turbineDef.name) -- Set the main title
         tooltip:setDescription(text) -- Set the detailed description
         tooltip:setTexture(turbineDef.objectSprite) -- Optional: Show turbine icon? Needs texture path.
     end
end


---===========================================================================
--- Timed Action: Blade Swap
---===========================================================================

ISWindTurbineBladeSwapAction = ISBaseTimedAction:derive("ISWindTurbineBladeSwapAction")

function ISWindTurbineBladeSwapAction:new(character, turbine, newBladeKey, time)
    local o = ISBaseTimedAction.new(self, character)
    o.turbine = turbine
    o.newBladeKey = newBladeKey
    o.newBladeDef = WindEnergy.BladeTypes[newBladeKey]
    o.time = time
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = time -- Store original time if needed
    return o
end

function ISWindTurbineBladeSwapAction:isValid()
    -- Check if turbine still exists and player still has the required blades
    if not self.turbine or self.turbine:getObjectIndex() == -1 then return false end
    if not self.newBladeDef then return false end -- Should not happen
    -- Check distance
    if not self:checkDistSq(self.turbine:getX(), self.turbine:getY(), self.turbine:getZ(), true) then return false end
    -- Check inventory
    return self.character:getInventory():contains(self.newBladeDef.itemType)
end

function ISWindTurbineBladeSwapAction:waitToStart()
    self.character:faceThisObject(self.turbine)
    return self.character:shouldBeTurning()
end

function ISWindTurbineBladeSwapAction:update()
    -- Update progress bar, etc.
    self.character:faceThisObject(self.turbine)
    self.character:setMetabolicTarget(Metabolics.UsingTools) -- Set metabolic rate
end

function ISWindTurbineBladeSwapAction:start()
    -- Play sound? Start animation?
    self:setActionAnim(CharacterActionAnims.Craft) -- Use a generic crafting animation
    -- self:setAnimVariable("LootPosition", "Low") -- Example variable if needed by anim
    self:setOverrideHandModels(self.character:getPrimaryHandItem(), self.character:getSecondaryHandItem()) -- Show equipped items
    self.character:playSound("PZ_InstallGenerator") -- Placeholder sound
    WindEnergy.log("Starting blade swap action: %s -> %s", self.turbine:getModData()[K.TurbineData][K.BladeType], self.newBladeKey)
    self.action:setText(getText("TimedActions_SwappingBlades")) -- Set progress bar text
end

function ISWindTurbineBladeSwapAction:stop()
    ISBaseTimedAction.stop(self)
    -- Stop sound/animation if started
    self.character:stopOrTriggerSound("PZ_InstallGenerator")
end

function ISWindTurbineBladeSwapAction:perform()
    ISBaseTimedAction.perform(self)
    -- Action completed - Send command to server

    -- Stop sound
    self.character:stopOrTriggerSound("PZ_InstallGenerator")

    WindEnergy.log("Blade swap action finished. Sending command to server.")
    sendClientCommand(self.character, "WindEnergy", "swapBlades", {
        turbineX = self.turbine:getX(), turbineY = self.turbine:getY(), turbineZ = self.turbine:getZ(),
        newBladeTypeKey = self.newBladeKey
    })

    -- Server will handle item removal and turbine state update.
    -- Client visuals will update automatically when modData is received.
end

---===========================================================================
--- Timed Action: Repair Turbine
---===========================================================================

ISWindTurbineRepairAction = ISBaseTimedAction:derive("ISWindTurbineRepairAction")

function ISWindTurbineRepairAction:new(character, turbine, time)
   local o = ISBaseTimedAction.new(self, character)
   o.turbine = turbine
   o.turbineDef = WindEnergy.TurbineTypes[turbine:getModData()[K.TurbineData][K.TypeName]] -- Store def for condition max
   o.time = time
   o.stopOnWalk = true
   o.stopOnRun = true
   o.stopOnAim = true
   o.maxTime = time
   return o
end

function ISWindTurbineRepairAction:isValid()
   -- Check if turbine still exists and is damaged
   if not self.turbine or self.turbine:getObjectIndex() == -1 then return false end
   if not self.turbineDef then return false end -- Should not happen

   local turbineData = self.turbine:getModData()[K.TurbineData]
   if not turbineData then return false end
   local isDamaged = (turbineData[K.Condition] or self.turbineDef.conditionMax) < self.turbineDef.conditionMax

   -- Check distance
   if not self:checkDistSq(self.turbine:getX(), self.turbine:getY(), self.turbine:getZ(), true) then return false end

   -- Check skill
   local hasSkill = self.character:getPerkLevel(Perks.Mechanics) >= 2

   -- Check for *any* potential repair materials (server does the real check)
   local playerInv = self.character:getInventory()
   local hasMats = playerInv:contains("Base.ScrapMetal") or
                   playerInv:contains("Base.ElectronicsScrap") or
                   playerInv:contains("Base.MetalPipe") or
                   playerInv:contains("Base.ElectricWire")

   return isDamaged and hasSkill and hasMats
end

function ISWindTurbineRepairAction:waitToStart()
   self.character:faceThisObject(self.turbine)
   return self.character:shouldBeTurning()
end

function ISWindTurbineRepairAction:update()
   self.character:faceThisObject(self.turbine)
   self.character:setMetabolicTarget(Metabolics.UsingTools)
end

function ISWindTurbineRepairAction:start()
   -- TODO: Use a more specific sound? Maybe based on materials?
   self:setActionAnim(CharacterActionAnims.Craft) -- Use generic crafting animation
   self:setOverrideHandModels(self.character:getPrimaryHandItem(), self.character:getSecondaryHandItem())
   self.character:playSound("PZ_Hammer") -- Placeholder sound
   self.action:setText(getText("TimedActions_RepairingTurbine")) -- Set progress bar text
end

function ISWindTurbineRepairAction:stop()
   ISBaseTimedAction.stop(self)
   self.character:stopOrTriggerSound("PZ_Hammer")
end

function ISWindTurbineRepairAction:perform()
   ISBaseTimedAction.perform(self)
   self.character:stopOrTriggerSound("PZ_Hammer")

   WindEnergy.log("Repair action finished. Sending command to server.")
   sendClientCommand(self.character, "WindEnergy", "WEU_RepairTurbine", {
       turbineX = self.turbine:getX(), turbineY = self.turbine:getY(), turbineZ = self.turbine:getZ()
   })
   -- Server handles material consumption, condition update, XP gain.
end


-- WindEnergy.log("Client Logic Loaded v" .. WindEnergy.VERSION) -- Moved to Init file

---===========================================================================
--- Initialization Hook
---===========================================================================
local function InitWEUClientEvents()
    -- Ensure core table exists before registering
    if not WindEnergy or not WindEnergy.Client then
        WindEnergy.error("WindEnergy or WindEnergy.Client not ready for event registration!")
        return
    end
    WindEnergy.Client.RegisterEvents()
end

-- Events.OnGameStart.Add(InitWEUClientEvents) -- Moved to Init file
-- Events.OnLoad.Add(InitWEUClientEvents) -- Moved to Init file