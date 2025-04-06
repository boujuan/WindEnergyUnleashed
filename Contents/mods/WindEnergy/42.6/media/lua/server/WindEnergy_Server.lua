-- WindEnergyUnleashed Server-Side Logic
-- Handles turbine placement, power generation, state saving/loading, grid connections, interactions

require "shared/WindEnergy_Core" -- Ensure core is loaded

require "Map/SGlobalObjectSystem"
require "Map/SGlobalObject"
require "Map/MapObjects" -- Needed for IsoObject creation

WindEnergy.Server = WindEnergy.Server or {}

-- Forward declare
local WindTurbineObject_Server
local WindEnergyTurbineSystem

---=================================================================================================
--- Wind Turbine Object (Server)
--- Represents a single wind turbine instance. Managed by WindEnergyTurbineSystem.
---=================================================================================================
---@class WindTurbineObject_Server : SGlobalObject
---@field luaSystem WindEnergyTurbineSystem -- Reference to the managing system
---@field typeName string -- Key from WindEnergy.TurbineTypes (e.g., "SmallWooden")
---@field bladeType string -- Key from WindEnergy.BladeTypes (e.g., "MakeshiftWood")
---@field condition number -- Current condition (0 to turbineDef.conditionMax)
---@field powerOutput number -- Current power generation (Watts)
---@field windDirection number -- Current wind direction affecting the turbine (degrees)
---@field connectedPB table | nil -- {x=number, y=number, z=number} Coordinates of connected ISAPowerBank, if any
---@field currentWindSpeed number -- Wind speed (m/s) currently affecting the turbine for UI display
WindTurbineObject_Server = SGlobalObject:derive("WindTurbineObject_Server")

function WindTurbineObject_Server:new(luaSystem, globalObject)
    local o = SGlobalObject.new(self, luaSystem, globalObject)
    -- Initialize default values if not loaded from save
    o.typeName = o.typeName or nil
    o.bladeType = o.bladeType or nil
    o.condition = o.condition or nil
    o.powerOutput = o.powerOutput or 0
    o.windDirection = o.windDirection or 0
    o.connectedPB = o.connectedPB or nil
    o.currentWindSpeed = o.currentWindSpeed or 0 -- Initialize new field
    return o
end

-- Initialize properties for a newly placed turbine based on its type definition
function WindTurbineObject_Server:initNew(typeName)
    local turbineDef = WindEnergy.TurbineTypes[typeName]
    if not turbineDef then
        WindEnergy.error("Attempted to initialize turbine with invalid type: %s at %d,%d,%d", tostring(typeName), self.x, self.y, self.z)
        -- Fallback or handle error appropriately
        self.typeName = "SmallWooden" -- Fallback to a default?
        turbineDef = WindEnergy.TurbineTypes[self.typeName]
    end

    WindEnergy.log("Initializing new WindTurbineObject_Server (%s) at %d,%d,%d", typeName, self.x, self.y, self.z)
    self.typeName = typeName
    self.bladeType = turbineDef.defaultBladeType -- Use default blades from definition
    self.condition = turbineDef.conditionMax -- Start at full condition
    self.powerOutput = 0
    self.windDirection = 0
    self.connectedPB = nil
    self.currentWindSpeed = 0 -- Initialize new field
end

-- Load state from the IsoObject's modData when it's loaded into the world
function WindTurbineObject_Server:stateFromIsoObject(isoObject)
    WindEnergy.log("Loading stateFromIsoObject for turbine at %d,%d,%d", self.x, self.y, self.z)
    local modData = isoObject:getModData()
    local turbineData = modData[WindEnergy.ModDataKeys.TurbineData]

    if not modData[WindEnergy.ModDataKeys.IsWindTurbine] or not turbineData then
        WindEnergy.error("Turbine at %d,%d,%d loaded without valid WindEnergyData! Re-initializing.", self.x, self.y, self.z)
        -- Attempt recovery: Determine type from sprite? Or assume default?
        -- For now, let's assume it needs full re-init based on a potential sprite name match
        local spriteName = isoObject:getSprite():getName()
        local foundType = nil
        for typeKey, typeDef in pairs(WindEnergy.TurbineTypes) do
            if spriteName and string.starts(spriteName, typeDef.objectSprite) then
                 foundType = typeKey
                 break
            end
        end
        self:initNew(foundType or "SmallWooden") -- Re-initialize with found or default type
        self:stateToIsoObject(isoObject) -- Save the newly initialized state
    else
        self:fromModData(turbineData)
    end
end

-- Apply state to the IsoObject's modData when the Lua object is created/synced
function WindTurbineObject_Server:stateToIsoObject(isoObject)
    --WindEnergy.log("Saving stateToIsoObject for turbine at %d,%d,%d", self.x, self.y, self.z)
    local modData = isoObject:getModData()
    -- Ensure the main data table exists
    if not modData[WindEnergy.ModDataKeys.TurbineData] then
        modData[WindEnergy.ModDataKeys.TurbineData] = {}
    end
    -- Mark as a wind turbine
    modData[WindEnergy.ModDataKeys.IsWindTurbine] = true
    -- Save specific data points
    self:toModData(modData[WindEnergy.ModDataKeys.TurbineData])
    -- No need to call transmitModData here, SGlobalObjectSystem handles it when necessary
end

-- Load state from a saved data table (usually from modData.WindEnergyData)
function WindTurbineObject_Server:fromModData(turbineData)
    local K = WindEnergy.ModDataKeys
    self.typeName = turbineData[K.TypeName] or self.typeName
    self.bladeType = turbineData[K.BladeType] or self.bladeType
    self.condition = turbineData[K.Condition] or self.condition
    self.powerOutput = turbineData[K.PowerOutput] or self.powerOutput or 0
    self.windDirection = turbineData[K.WindDirection] or self.windDirection or 0
    self.connectedPB = turbineData[K.ConnectedPB] or self.connectedPB or nil
    self.currentWindSpeed = turbineData["currentWindSpeed"] or self.currentWindSpeed or 0 -- Load new field (using string key for now)

    -- Validate loaded data against definitions
    if not WindEnergy.TurbineTypes[self.typeName] then
        WindEnergy.warn("Loaded invalid turbine type '%s' at %d,%d,%d. Resetting.", tostring(self.typeName), self.x, self.y, self.z)
        self.typeName = "SmallWooden" -- Reset to default
    end
    if not WindEnergy.BladeTypes[self.bladeType] then
         WindEnergy.warn("Loaded invalid blade type '%s' for turbine %s at %d,%d,%d. Resetting.",
                         tostring(self.bladeType), tostring(self.typeName), self.x, self.y, self.z)
         self.bladeType = WindEnergy.TurbineTypes[self.typeName].defaultBladeType -- Reset to default for the turbine type
    end
    local turbineDef = WindEnergy.TurbineTypes[self.typeName]
    if self.condition == nil or self.condition > turbineDef.conditionMax then
        self.condition = turbineDef.conditionMax -- Reset or cap condition
    end
end

-- Save state into a data table (usually for modData.WindEnergyData)
function WindTurbineObject_Server:toModData(turbineData)
    local K = WindEnergy.ModDataKeys
    turbineData[K.TypeName] = self.typeName
    turbineData[K.BladeType] = self.bladeType
    turbineData[K.Condition] = self.condition
    turbineData[K.PowerOutput] = self.powerOutput
    turbineData[K.WindDirection] = self.windDirection
    turbineData[K.ConnectedPB] = self.connectedPB
    turbineData["currentWindSpeed"] = self.currentWindSpeed -- Save new field (using string key for now)
end

-- Helper to save data directly to the IsoObject and trigger transmission if needed
-- Note: SGlobalObjectSystem usually handles saving and transmission automatically on changes.
-- This might be useful for forcing a save/transmit after specific actions.
function WindTurbineObject_Server:saveData(transmit)
    local isoObject = self:getIsoObject()
    if not isoObject then
        WindEnergy.warn("Attempted to save data for turbine at %d,%d,%d but IsoObject not found.", self.x, self.y, self.z)
        return
    end
    self:stateToIsoObject(isoObject) -- Apply Lua state to modData
    if transmit then
        isoObject:transmitModData() -- Force transmission if requested
    end
end

-- Calculate the power output based on current wind speed, turbine type, blades, and condition
function WindTurbineObject_Server:calculatePower(windSpeed)
    local turbineDef = WindEnergy.TurbineTypes[self.typeName]
    local bladeDef = WindEnergy.BladeTypes[self.bladeType]

    if not turbineDef or not bladeDef then
        WindEnergy.error("Missing definition for turbine '%s' or blades '%s' at %d,%d,%d",
                         tostring(self.typeName), tostring(self.bladeType), self.x, self.y, self.z)
        self.powerOutput = 0
        return
    end

    local cutIn = turbineDef.cutInSpeed
    local rated = turbineDef.ratedSpeed
    local cutOut = turbineDef.cutOutSpeed
    local maxPower = turbineDef.maxPowerOutput -- Use maxPowerOutput
    local exponent = turbineDef.powerCurveExponent

    local calculatedPower = 0

    -- Convert condition to a 0.0-1.0 multiplier
    local conditionModifier = math.max(0, self.condition / turbineDef.conditionMax)

    if windSpeed >= cutIn and windSpeed <= cutOut and conditionModifier > 0 then
        if windSpeed >= rated then
            -- At or above rated speed (but below cut-out), produce max power adjusted by modifiers
            calculatedPower = maxPower
        else
            -- Between cut-in and rated speed, use power curve
            -- Avoid division by zero if cutIn == rated
            if rated > cutIn then
                 local speedRatio = (windSpeed - cutIn) / (rated - cutIn)
                 calculatedPower = maxPower * math.pow(speedRatio, exponent)
            else
                 calculatedPower = maxPower -- If cutIn == rated, produce max power immediately at cutIn
            end
        end
    end
    -- else: Below cut-in, above cut-out, or broken (condition=0), power remains 0

    -- Apply modifiers
    calculatedPower = calculatedPower * bladeDef.efficiencyModifier -- Use efficiencyModifier
    calculatedPower = calculatedPower * conditionModifier
    calculatedPower = calculatedPower * WindEnergy.Options.PowerMultiplier

    -- Ensure power is not negative and round reasonably? (optional)
    self.powerOutput = math.max(0, calculatedPower)

    -- Optional: Log detailed calculation
    -- WindEnergy.log("Turbine %d,%d,%d (%s/%s): Wind=%.1f, Cond=%.1f, BladeEff=%.2f, Mult=%.1f -> Output=%.1fW",
    --                self.x, self.y, self.z, self.typeName, self.bladeType, windSpeed,
    --                conditionModifier * 100, bladeDef.efficiencyModifier, WindEnergy.Options.PowerMultiplier, self.powerOutput)

end

-- Update the turbine's condition (e.g., due to wear and tear)
function WindTurbineObject_Server:updateCondition(damageAmount)
    local turbineDef = WindEnergy.TurbineTypes[self.typeName]
    if not turbineDef then return end -- Should not happen

    self.condition = math.max(0, self.condition - damageAmount)
    WindEnergy.log("Turbine %d,%d,%d condition updated: %.2f / %.2f", self.x, self.y, self.z, self.condition, turbineDef.conditionMax)
    -- SGlobalObjectSystem should detect the change and save/transmit automatically
    self:saveData(true) -- Force transmit to update client UI immediately
end

-- Set the blade type
function WindTurbineObject_Server:setBladeType(newBladeTypeKey)
    if WindEnergy.BladeTypes[newBladeTypeKey] then
        WindEnergy.log("Turbine %d,%d,%d blades changed from %s to %s", self.x, self.y, self.z, self.bladeType, newBladeTypeKey)
        self.bladeType = newBladeTypeKey
        -- Optionally reset condition or apply other effects? For now, just swap.
        -- SGlobalObjectSystem should detect the change and save/transmit automatically
        self:saveData(true) -- Force transmit to update client UI immediately
    else
        WindEnergy.error("Attempted to set invalid blade type '%s' for turbine %d,%d,%d", tostring(newBladeTypeKey), self.x, self.y, self.z)
    end
end

-- Connect to a power bank
function WindTurbineObject_Server:connectToPowerBank(pbCoords)
    if pbCoords and pbCoords.x and pbCoords.y and pbCoords.z then
        WindEnergy.log("Turbine %d,%d,%d connecting to Power Bank at %d,%d,%d", self.x, self.y, self.z, pbCoords.x, pbCoords.y, pbCoords.z)
        self.connectedPB = { x = pbCoords.x, y = pbCoords.y, z = pbCoords.z }
    else
        WindEnergy.error("Invalid power bank coordinates provided for turbine %d,%d,%d", self.x, self.y, self.z)
        self.connectedPB = nil
    end
    -- SGlobalObjectSystem should detect the change and save/transmit automatically
    self:saveData(true) -- Force transmit to update client UI immediately
end

-- Disconnect from power bank
function WindTurbineObject_Server:disconnectFromPowerBank()
    if self.connectedPB then
        WindEnergy.log("Turbine %d,%d,%d disconnecting from Power Bank at %d,%d,%d", self.x, self.y, self.z, self.connectedPB.x, self.connectedPB.y, self.connectedPB.z)
        self.connectedPB = nil
        -- SGlobalObjectSystem should detect the change and save/transmit automatically
        self:saveData(true) -- Force transmit to update client UI immediately
    end
end

-- Repair the turbine, consuming materials and granting XP
-- Returns true if repair was successful, false otherwise
function WindTurbineObject_Server:repair(player, repairAmount)
   local turbineDef = WindEnergy.TurbineTypes[self.typeName]
   if not turbineDef then return false end

   local oldCondition = self.condition
   local maxCondition = turbineDef.conditionMax

   if self.condition >= maxCondition then
       -- Already fully repaired
       return false
   end

   self.condition = math.min(maxCondition, self.condition + repairAmount)
   local repairedBy = self.condition - oldCondition

   WindEnergy.log("Turbine %d,%d,%d repaired by %.2f (%.1f -> %.1f / %.1f)",
                  self.x, self.y, self.z, repairedBy, oldCondition, self.condition, maxCondition)

   -- SGlobalObjectSystem should detect the change and save/transmit automatically
   self:saveData(true) -- Force transmit to update client UI immediately
   return true
end


---=================================================================================================
--- Wind Turbine System (Server)
--- Manages all WindTurbineObject_Server instances using SGlobalObjectSystem.
---=================================================================================================
---@class WindEnergyTurbineSystem : SGlobalObjectSystem
---@field instance WindEnergyTurbineSystem -- Singleton instance
WindEnergyTurbineSystem = SGlobalObjectSystem:derive("WindEnergyTurbineSystem")

-- Define which keys in the Lua object should be saved in the IsoObject's modData[WindEnergy.ModDataKeys.TurbineData] table
WindEnergyTurbineSystem.savedObjectModData = {
    WindEnergy.ModDataKeys.TypeName,
    WindEnergy.ModDataKeys.BladeType,
    WindEnergy.ModDataKeys.Condition,
    WindEnergy.ModDataKeys.PowerOutput,
    WindEnergy.ModDataKeys.WindDirection,
    WindEnergy.ModDataKeys.ConnectedPB,
    "currentWindSpeed" -- Add new field to be saved/synced (using string key for now)
}

-- Called when the system instance is created by SGlobalObjectSystem
function WindEnergyTurbineSystem:new()
    WindEnergy.log("Creating WindEnergyTurbineSystem instance")
    local o = SGlobalObjectSystem.new(self, "wind_turbine") -- Unique key for this system
    WindEnergy.Server.TurbineSystem = o -- Store instance for easy access
    return o
end

-- Called after the system instance is created and registered
function WindEnergyTurbineSystem:initSystem()
    WindEnergy.log("Initializing WindEnergyTurbineSystem")
    -- Tell the system which Lua object fields correspond to modData keys within the TurbineData table
    self.system:setObjectModDataKeys(self.savedObjectModData, WindEnergy.ModDataKeys.TurbineData)

    -- Hook into game events
    Events.EveryTenMinutes.Add(WindEnergyTurbineSystem.updateTurbines) -- Periodic update
    -- Events.OnObjectAdded.Add(WindEnergyTurbineSystem.onObjectAdded) -- Removed: Placement now handled by OnCreate callback
    -- TODO: Add OnObjectRemoved handler if cleanup is needed? SGlobalObjectSystem might handle this.
end

-- Create the Lua object wrapper for a global object instance
function WindEnergyTurbineSystem:newLuaObject(globalObject)
    return WindTurbineObject_Server:new(self, globalObject)
end

-- Check if an IsoObject is a valid wind turbine managed by this system
-- This is called by SGlobalObjectSystem when scanning objects.
function WindEnergyTurbineSystem:isValidIsoObject(isoObject)
    -- Check the modData flag set during placement or loading
    return isoObject and isoObject:getModData()[WindEnergy.ModDataKeys.IsWindTurbine] == true
end

-- Removed WindEnergyTurbineSystem.onObjectAdded function (lines 303-363)
-- Placement is now handled by the global WindEnergy_OnPlaceTurbine callback.

-- Periodic update function called by the timer event
function WindEnergyTurbineSystem.updateTurbines()
    if not WindEnergy.Server.TurbineSystem then return end -- System not ready
    local self = WindEnergy.Server.TurbineSystem
    --WindEnergy.log("Running periodic turbine update...")

    -- 1. Get Current Wind Conditions
    local climateManager = getClimateManager()
    local windSpeed = climateManager:getWindspeedKph() -- Use confirmed method
    local windAngle = climateManager:getWindAngleDegrees() -- Use confirmed method
    -- Store globally? Not really needed if we pass it.
    -- WindEnergy.WindSystem.currentSpeed = windSpeed
    -- WindEnergy.WindSystem.currentDirection = windAngle
    -- WindEnergy.log("Current Wind: %.2f kph @ %.1f degrees", windSpeed, windAngle)

    -- 2. Update each active turbine
    local objects = self.system:getObjects() -- Get list of managed global objects
    for i = 1, #objects do
        local globalObj = objects[i]
        ---@type WindTurbineObject_Server
        local turbine = globalObj:getModData() -- Get the Lua object wrapper
        local isoTurbine = turbine:getIsoObject()

        if isoTurbine and turbine then
            -- Store current wind direction affecting the turbine
            turbine.windDirection = windAngle -- Store the raw angle

            -- Calculate power based on wind, type, blades, condition
            turbine:calculatePower(windSpeed)

            -- Store the current wind speed (converted to m/s for UI consistency)
            -- Assuming windSpeed is kph from ClimateManager
            turbine.currentWindSpeed = windSpeed / 3.6 -- Convert kph to m/s

            -- TODO: Apply damage/wear based on wind speed, condition, blade durabilityFactor
            -- local bladeDef = WindEnergy.BladeTypes[turbine.bladeType]
            -- local damage = calculateWear(windSpeed, turbine.condition, bladeDef.durabilityFactor)
            -- turbine:updateCondition(damage)

            -- Push power to connected power bank (if any)
            if turbine.connectedPB and turbine.powerOutput > 0 then
                -- Check if ISA system is loaded and accessible
                if ISA and ISA.PBSystem_Server then
                    local pbSystem = ISA.PBSystem_Server -- Get the ISA Power Bank system instance
                    ---@type PowerbankObject_Server
                    local pb = pbSystem:getLuaObjectAt(turbine.connectedPB.x, turbine.connectedPB.y, turbine.connectedPB.z)

                    if pb then
                        -- Calculate energy generated in the last 10 minutes (Watt-Hours)
                        -- PowerOutput is in Watts (Joules/sec). Interval is 10 mins = 600 secs.
                        -- Energy (Joules) = Power (W) * Time (s) = turbine.powerOutput * 600
                        -- Convert Joules to Watt-Hours: Wh = Joules / 3600
                        -- Energy (Wh) = (turbine.powerOutput * 600) / 3600 = turbine.powerOutput / 6
                        local energyToAdd_Wh = turbine.powerOutput / 6

                        -- Assuming ISA's pb.charge expects Watt-hours or a compatible unit
                        local oldCharge = pb.charge
                        pb:charge(energyToAdd_Wh) -- Use ISA's charge method directly
                        local newCharge = pb.charge

                        -- Check if charge actually changed before saving/logging
                        if newCharge ~= oldCharge then
                             -- pb:charge likely handles capping at maxcapacity and saving internally.
                             -- If not, we'd need: pb.charge = math.min(pb.maxcapacity, pb.charge + energyToAdd_Wh)
                             -- And potentially: pb:updateGenerator() and pb:saveData(true)
                             -- Let's assume pb:charge handles this based on ISA's typical design.

                             -- Optional: Log the power transfer
                             -- WindEnergy.log("Transferred %.2f Wh from turbine %d,%d,%d to PowerBank %d,%d,%d (Old: %.1f, New: %.1f)",
                             --                energyToAdd_Wh, turbine.x, turbine.y, turbine.z,
                             --                pb.x, pb.y, pb.z, oldCharge, newCharge)
                        end
                    else
                        -- Power bank at coordinates not found (maybe destroyed?)
                        WindEnergy.warn("Turbine %d,%d,%d connected to non-existent PowerBank at %d,%d,%d. Disconnecting.",
                                        turbine.x, turbine.y, turbine.z, turbine.connectedPB.x, turbine.connectedPB.y, turbine.connectedPB.z)
                        turbine:disconnectFromPowerBank() -- Disconnect automatically
                    end
                else
                     -- ISA mod/system not detected, disconnect if previously connected
                     if turbine.connectedPB then
                         WindEnergy.warn("Turbine %d,%d,%d connected to PB %d,%d,%d but ISA system not found. Disconnecting.",
                                         turbine.x, turbine.y, turbine.z, turbine.connectedPB.x, turbine.connectedPB.y, turbine.connectedPB.z)
                         turbine:disconnectFromPowerBank()
                     end
                end
            end

            -- SGlobalObjectSystem handles saving changed data automatically.
            -- We don't need turbine:saveData(true) here unless we want to force immediate transmit.
        else
            WindEnergy.warn("Turbine Lua object exists at %d,%d,%d but IsoObject is missing during update.", turbine.x, turbine.y, turbine.z)
            -- Consider cleanup logic here if needed (e.g., self.system:removeObject(globalObj))
        end
    end
end

---===========================================================================
--- Server Command Handlers (Triggered by Client Actions)
---===========================================================================

-- Handle request from client to swap blades
function WindEnergy.Server.OnClientSwapBlades(playerIndex, turbineX, turbineY, turbineZ, newBladeTypeKey)
    local player = getSpecificPlayer(playerIndex)
    if not player then WindEnergy.error("SwapBlades: Invalid player index %d", playerIndex); return end

    local turbine = WindEnergy.Server.TurbineSystem:getLuaObjectAt(turbineX, turbineY, turbineZ)
    if not turbine then WindEnergy.error("SwapBlades: Turbine not found at %d,%d,%d", turbineX, turbineY, turbineZ); return end

    local newBladeDef = WindEnergy.BladeTypes[newBladeTypeKey]
    if not newBladeDef then
        WindEnergy.error("SwapBlades: Invalid new blade type key '%s'", tostring(newBladeTypeKey))
        player:Say(getText("Feedback_WEU_InvalidBladeType"))
        return
    end

    -- Check if player has the required blade item
    local bladeItemType = newBladeDef.itemType
    if not player:getInventory():contains(bladeItemType) then
        WindEnergy.log("SwapBlades: Player %s does not have item %s", player:getUsername(), bladeItemType)
        player:Say(getText("Feedback_WEU_MissingItem", newBladeDef.name))
        return
    end

    -- Skill/Tool Checks (Example: Mechanics 1 and a Wrench)
    local requiredSkill = Perks.Mechanics
    local requiredLevel = 1
    local requiredTool = "Base.Wrench" -- Example tool

    if player:getPerkLevel(requiredSkill) < requiredLevel then
        WindEnergy.log("SwapBlades: Player %s lacks skill %s %d", player:getUsername(), requiredSkill:getName(), requiredLevel)
        player:Say(getText("Feedback_WEU_SkillRequired", requiredSkill:getName(), requiredLevel))
        return
    end

    if not player:getInventory():contains(requiredTool) and not player:getPrimaryHandItem():getType() == requiredTool and not player:getSecondaryHandItem():getType() == requiredTool then
        WindEnergy.log("SwapBlades: Player %s lacks tool %s", player:getUsername(), requiredTool)
        player:Say(getText("Feedback_WEU_ToolRequired", getItemNameFromFullType(requiredTool)))
        return
    end

    -- Consume the item
    player:getInventory():RemoveOneOf(bladeItemType);
    WindEnergy.log("SwapBlades: Player %s used %s", player:getUsername(), bladeItemType)

    -- Update the turbine's blade type
    turbine:setBladeType(newBladeTypeKey)
    -- The change should be automatically saved and transmitted by SGlobalObjectSystem

    -- Grant XP
    player:getXp():AddXP(requiredSkill, 3) -- Example XP amount
    WindEnergy.log("SwapBlades: Granted %s XP to %s", requiredSkill:getName(), player:getUsername())

    -- Send confirmation feedback
    player:Say(getText("Feedback_WEU_BladesSwapped", newBladeDef.name))
end

-- Handle request from client to connect turbine to a power bank
function WindEnergy.Server.OnClientConnectTurbineToPB(playerIndex, turbineX, turbineY, turbineZ, pbX, pbY, pbZ)
    local player = getSpecificPlayer(playerIndex)
    if not player then WindEnergy.error("ConnectTurbine: Invalid player index %d", playerIndex); return end

    local turbine = WindEnergy.Server.TurbineSystem:getLuaObjectAt(turbineX, turbineY, turbineZ)
    if not turbine then WindEnergy.error("ConnectTurbine: Turbine not found at %d,%d,%d", turbineX, turbineY, turbineZ); return end

    -- Validate PB coordinates
    if not pbX or not pbY or not pbZ then WindEnergy.error("ConnectTurbine: Invalid Power Bank coordinates received."); return end

    -- Check if the target Power Bank actually exists (using ISA's system)
    if ISA and ISA.PBSystem_Server then
        local pbSystem = ISA.PBSystem_Server
        local pb = pbSystem:getLuaObjectAt(pbX, pbY, pbZ)
        if not pb then
            WindEnergy.log("ConnectTurbine: Power Bank not found at target coordinates %d,%d,%d", pbX, pbY, pbZ)
            player:Say(getText("Feedback_WEU_PBNotFound"))
            return
        end

        -- Connect the turbine
        turbine:connectToPowerBank({ x = pbX, y = pbY, z = pbZ })
        -- The change should be automatically saved and transmitted by SGlobalObjectSystem

        WindEnergy.log("ConnectTurbine: Player %s connected turbine %d,%d,%d to PB %d,%d,%d", player:getUsername(), turbineX, turbineY, turbineZ, pbX, pbY, pbZ)
        player:Say(getText("Feedback_WEU_ConnectedPB"))
    else
        WindEnergy.error("ConnectTurbine: ISA Power Bank system not found on server.")
        player:Say(getText("Feedback_WEU_ISANotFound"))
    end
end

-- Handle request from client to disconnect turbine from power bank
function WindEnergy.Server.OnClientDisconnectTurbineFromPB(playerIndex, turbineX, turbineY, turbineZ)
     local player = getSpecificPlayer(playerIndex)
     if not player then WindEnergy.error("DisconnectTurbine: Invalid player index %d", playerIndex); return end

     local turbine = WindEnergy.Server.TurbineSystem:getLuaObjectAt(turbineX, turbineY, turbineZ)
     if not turbine then WindEnergy.error("DisconnectTurbine: Turbine not found at %d,%d,%d", turbineX, turbineY, turbineZ); return end

     turbine:disconnectFromPowerBank()
     WindEnergy.log("DisconnectTurbine: Player %s disconnected turbine %d,%d,%d", player:getUsername(), turbineX, turbineY, turbineZ)
     player:Say(getText("Feedback_WEU_DisconnectedPB"))
end

-- Handle request from client to repair a turbine
function WindEnergy.Server.OnClientRepairTurbine(playerIndex, turbineX, turbineY, turbineZ)
    local player = getSpecificPlayer(playerIndex)
    if not player then WindEnergy.error("RepairTurbine: Invalid player index %d", playerIndex); return end

    local turbine = WindEnergy.Server.TurbineSystem:getLuaObjectAt(turbineX, turbineY, turbineZ)
    if not turbine then WindEnergy.error("RepairTurbine: Turbine not found at %d,%d,%d", turbineX, turbineY, turbineZ); return end

    local turbineDef = WindEnergy.TurbineTypes[turbine.typeName]
    if not turbineDef then WindEnergy.error("RepairTurbine: Invalid turbine type '%s'", turbine.typeName); return end

    local currentCondition = turbine.condition
    local maxCondition = turbineDef.conditionMax

    if currentCondition >= maxCondition then
        WindEnergy.log("RepairTurbine: Turbine %d,%d,%d already at max condition.", turbineX, turbineY, turbineZ)
        player:Say(getText("Feedback_WEU_AlreadyRepaired"))
        return
    end

    -- Skill Check (Example: Mechanics 2)
    local requiredSkill = Perks.Mechanics
    local requiredLevel = 2
    if player:getPerkLevel(requiredSkill) < requiredLevel then
        WindEnergy.log("RepairTurbine: Player %s lacks skill %s %d", player:getUsername(), requiredSkill:getName(), requiredLevel)
        player:Say(getText("Feedback_WEU_SkillRequired", requiredSkill:getName(), requiredLevel))
        return
    end

    -- Determine Materials Needed (Example Logic)
    local materialsNeeded = {}
    local damagePercent = 1 - (currentCondition / maxCondition) -- Damage from 0.0 to 1.0

    -- Base materials (adjust quantities based on turbine type/damage)
    materialsNeeded["Base.ScrapMetal"] = math.ceil(damagePercent * 2) + 1 -- Need more scrap for more damage
    materialsNeeded["Base.ElectronicsScrap"] = math.ceil(damagePercent * 1)
    if turbine.typeName == "LargeMetal" then -- Large turbines need more/different parts
        materialsNeeded["Base.MetalPipe"] = math.ceil(damagePercent * 1)
        materialsNeeded["Base.ElectricWire"] = math.ceil(damagePercent * 2)
        materialsNeeded["Base.ElectronicsScrap"] = materialsNeeded["Base.ElectronicsScrap"] + 1 -- Extra electronics
    end

    -- Check if player has materials
    local playerInv = player:getInventory()
    local hasAllMaterials = true
    local missingMaterials = {}
    for itemType, count in pairs(materialsNeeded) do
        if playerInv:getItemCount(itemType, true) < count then
            hasAllMaterials = false
            table.insert(missingMaterials, getItemNameFromFullType(itemType) .. " x" .. count)
            WindEnergy.log("RepairTurbine: Player %s missing %s x%d", player:getUsername(), itemType, count)
        end
    end

    if not hasAllMaterials then
        player:Say(getText("Feedback_WEU_MissingMaterials", table.concat(missingMaterials, ", ")))
        return
    end

    -- Consume Materials
    for itemType, count in pairs(materialsNeeded) do
        for i = 1, count do
            playerInv:RemoveOneOf(itemType)
        end
        WindEnergy.log("RepairTurbine: Player %s used %s x%d", player:getUsername(), itemType, count)
    end

    -- Calculate Repair Amount (Based on skill, maybe random element)
    local skillLevel = player:getPerkLevel(requiredSkill)
    local baseRepair = maxCondition * 0.1 -- Base 10% repair
    local skillBonus = (skillLevel - requiredLevel) * (maxCondition * 0.05) -- Extra 5% per level above required
    local randomFactor = ZombRand(80, 121) / 100 -- +/- 20% randomness
    local repairAmount = (baseRepair + skillBonus) * randomFactor
    repairAmount = math.max(1, repairAmount) -- Ensure at least 1 point repaired

    -- Perform Repair
    if turbine:repair(player, repairAmount) then
        -- Grant XP
        local xpAmount = ZombRand(2, 5) + math.floor(skillBonus / (maxCondition * 0.05)) -- More XP for higher skill bonus used
        player:getXp():AddXP(requiredSkill, xpAmount)
        WindEnergy.log("RepairTurbine: Granted %d %s XP to %s", xpAmount, requiredSkill:getName(), player:getUsername())

        -- Send Feedback
        player:Say(getText("Feedback_WEU_RepairSuccess", string.format("%.1f", turbine.condition / maxCondition * 100)))
    else
        -- Repair failed (e.g., already repaired - though checked earlier)
        player:Say(getText("Feedback_WEU_RepairFailed"))
        -- Refund materials? Probably not, action was performed.
    end
end


-- Register command handlers
--[[ -- Moved to Init file
if isServer() then
    WindEnergy.log("Registering Server Command Handlers...")
    addCommandHandler("WindEnergy", "swapBlades", WindEnergy.Server.OnClientSwapBlades)
    addCommandHandler("WindEnergy", "connectPB", WindEnergy.Server.OnClientConnectTurbineToPB)
    addCommandHandler("WindEnergy", "disconnectPB", WindEnergy.Server.OnClientDisconnectTurbineFromPB)
    addCommandHandler("WindEnergy", "WEU_RepairTurbine", WindEnergy.Server.OnClientRepairTurbine) -- Register new handler
end
--]]

---===========================================================================
--- Construction Callback
--- Called after a player successfully constructs a turbine via recipe.
---===========================================================================
---@param player IsoPlayer | nil The player who performed the construction.
---@param square IsoGridSquare The square where the object was placed.
---@param recipe Recipe The recipe used for construction.
function WindEnergy_OnPlaceTurbine(player, square, recipe)
    if not isServer() then return end
    if not square or not recipe then
        WindEnergy.error("WindEnergy_OnPlaceTurbine called with invalid square or recipe.")
        return
    end

    local playerDesc = player and player:getUsername() or "Unknown Player"
    WindEnergy.log("WindEnergy_OnPlaceTurbine called by %s for recipe %s at %d,%d,%d", playerDesc, recipe:getName(), square:getX(), square:getY(), square:getZ())

    -- Find the newly placed object on the square.
    -- The construction system places the object matching the recipe result tiledef *before* calling OnCreate.
    local isoObject = nil
    local tileName = recipe:getResult() -- This should be the tiledef name (e.g., "WindEnergy_SmallTurbine_0")

    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        -- Check if the object's sprite name matches the tile name (recipe result)
        -- Note: This assumes the tiledef name directly matches the sprite name. Adjust if needed.
        if obj and obj:getSprite() and obj:getSprite():getName() == tileName then
            isoObject = obj
            WindEnergy.log("Found matching object %s on square.", tileName)
            break
        end
    end

    if not isoObject then
        WindEnergy.error("WindEnergy_OnPlaceTurbine: Could not find the newly placed object '%s' on square %d,%d,%d!", tileName, square:getX(), square:getY(), square:getZ())
        -- Also check if the object has the custom property from the tiledef, as sprite might not be set yet?
        for i = 0, square:getObjects():size() - 1 do
             local obj = square:getObjects():get(i)
             if obj and obj:getProperties() and obj:getProperties():Val("WindEnergyType") then
                 -- Check if WindEnergyType matches expected type based on tileName
                 local expectedType = nil
                 if tileName == "WindEnergy_SmallTurbine_0" then expectedType = "SmallWooden"
                 elseif tileName == "WindEnergy_LargeTurbine_0" then expectedType = "LargeMetal" end

                 if expectedType and obj:getProperties():Val("WindEnergyType") == expectedType then
                     isoObject = obj
                     WindEnergy.log("Found matching object via WindEnergyType property: %s", expectedType)
                     break
                 end
             end
        end
        if not isoObject then return end -- Still not found, exit.
    end

    -- Determine the turbine type based on the recipe result (tile name) or tile property
    local turbineTypeKey = isoObject:getProperties() and isoObject:getProperties():Val("WindEnergyType") or nil
    if not turbineTypeKey then
        if tileName == "WindEnergy_SmallTurbine_0" then
            turbineTypeKey = "SmallWooden"
        elseif tileName == "WindEnergy_LargeTurbine_0" then
            turbineTypeKey = "LargeMetal"
        else
            WindEnergy.error("WindEnergy_OnPlaceTurbine: Unknown tile name '%s' and no WindEnergyType property. Cannot determine turbine type.", tileName)
            return
        end
    end

    WindEnergy.log("Determined turbine type: %s", turbineTypeKey)

    -- Ensure the system is ready
    if not WindEnergy.Server.TurbineSystem or not WindEnergy.Server.TurbineSystem.system then
         WindEnergy.error("WindEnergy_OnPlaceTurbine: TurbineSystem not ready!")
         return
    end

    -- Mark it as a turbine immediately so isValidIsoObject works if called concurrently
    isoObject:getModData()[WindEnergy.ModDataKeys.IsWindTurbine] = true

    -- Register with the SGlobalObjectSystem
    local globalObj = WindEnergy.Server.TurbineSystem.system:addObject(isoObject)

    if globalObj then
        -- Get the Lua wrapper object
        ---@type WindTurbineObject_Server
        local turbineLuaObj = globalObj:getModData() -- SGlobalObjectSystem stores the Lua object here

        -- Initialize its state
        turbineLuaObj:initNew(turbineTypeKey)

        -- Save the initial state to the IsoObject's modData
        turbineLuaObj:stateToIsoObject(isoObject)

        -- Transmit the initial state to clients
        isoObject:transmitModData()

        WindEnergy.log("Turbine %s successfully registered and initialized via OnCreate.", turbineTypeKey)
    else
        WindEnergy.error("Failed to register turbine %s with SGlobalObjectSystem via OnCreate.", turbineTypeKey)
        -- Revert the flag if registration failed?
        isoObject:getModData()[WindEnergy.ModDataKeys.IsWindTurbine] = nil
    end
end


-- Register the system with Project Zomboid
-- SGlobalObjectSystem.RegisterSystemClass(WindEnergyTurbineSystem) -- Moved to Init file

-- WindEnergy.log("Server Logic Loaded v" .. WindEnergy.VERSION) -- Moved to Init file