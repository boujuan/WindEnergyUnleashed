-- WindEnergyUnleashed Initialization

-- Get reference to the core table
local WindEnergy = require "WindEnergy/WindEnergy_Core"

-- Client and Server files are loaded automatically by the game.
-- We just need to ensure the Core is loaded before running init logic.

local function InitializeWEU()
    -- Check if already initialized (protection against multiple event triggers)
    if WindEnergy.Initialized then return end

    WindEnergy.log("Core Shared Loaded v" .. WindEnergy.VERSION)
    WindEnergy.log("Client Logic Loaded v" .. WindEnergy.VERSION)
    WindEnergy.log("Server Logic Loaded v" .. WindEnergy.VERSION)
    WindEnergy.log("Running WindEnergyUnleashed Initialization...")

    -- 1. Register Server System (Needs to happen early, SGlobalObjectSystem should be ready)
    if isServer() then
        WindEnergy.log("Registering WindEnergyTurbineSystem...")
        SGlobalObjectSystem.RegisterSystemClass(WindEnergyTurbineSystem)
        -- SGlobalObjectSystem framework will automatically create the instance
        -- and call its :initSystem() method, which hooks EveryTenMinutes.
        -- We rely on the framework calling initSystem after registration.
    end

    -- 2. Load Sandbox Options (Needs SandboxVars, available OnGameStart/OnLoad)
    -- Ensure the function exists before calling
    if WindEnergy.LoadSandboxOptions then
        WindEnergy.LoadSandboxOptions() -- This function logs its own success/details
    else
        WindEnergy.error("WindEnergy.LoadSandboxOptions function not found during initialization!")
    end

    -- 3. Register Client Events (Needs Events table and Client functions)
    if isClient() then
        if WindEnergy.Client and WindEnergy.Client.RegisterEvents then
            WindEnergy.log("Registering Client Events...")
            WindEnergy.Client.RegisterEvents() -- This function logs its own success
            -- Also hook the ModDataUpdated listener here, as it relies on Client functions
            Events.OnObjectModDataUpdated.Add(WindEnergy.Client.OnObjectModDataUpdated)
        else
             WindEnergy.error("WindEnergy.Client or WindEnergy.Client.RegisterEvents not found during initialization!")
        end
    end

    -- 4. Register Server Commands (Needs command system)
    if isServer() then
        if WindEnergy.Server and WindEnergy.Server.OnClientSwapBlades then -- Check if server functions exist
            WindEnergy.log("Registering Server Command Handlers...")
            addCommandHandler("WindEnergy", "swapBlades", WindEnergy.Server.OnClientSwapBlades)
            addCommandHandler("WindEnergy", "connectPB", WindEnergy.Server.OnClientConnectTurbineToPB)
            addCommandHandler("WindEnergy", "disconnectPB", WindEnergy.Server.OnClientDisconnectTurbineFromPB)
            addCommandHandler("WindEnergy", "WEU_RepairTurbine", WindEnergy.Server.OnClientRepairTurbine)
        else
            WindEnergy.error("WindEnergy.Server functions not found during command handler registration!")
        end
    end

    WindEnergy.Initialized = true -- Mark as initialized
    WindEnergy.log("WindEnergyUnleashed Initialization Complete.")
end

-- Hook into appropriate events
-- OnGameStart/OnLoad ensure SandboxVars are loaded before InitializeWEU is called.
Events.OnGameStart.Add(InitializeWEU)
Events.OnLoad.Add(InitializeWEU) -- For loading existing saves

WindEnergy.log("WindEnergy_Init.lua Loaded. Initialization deferred to OnGameStart/OnLoad.")