-- ============================================================
-- STEP 1: GLOBALS + BASE TABLE + RPC DECLS
-- ============================================================
_G.g_Botmater = _G.g_Botmater or "Botmater"

local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}

BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }

-- ============================================================
-- STEP 2: IMPORTS
-- ============================================================
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ESpecialMovementType = import("ESpecialMovementType")
local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local EStateType = import("EStateType")
local ESTEPoseState = import("ESTEPoseState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")

-- ============================================================
-- STEP 3: BANNER WIDGET
-- ============================================================
local BTN_BP = "/Game/UMG/UI_BP/Common/BaseComponent/CommonBaseComponent_TextButton_UIBP.CommonBaseComponent_TextButton_UIBP"

_G._BANNER_CREATED = _G._BANNER_CREATED or false
_G.DsBannerWidget  = _G.DsBannerWidget or nil

function _G.CreateDsDemonBanner()
    if _G._BANNER_CREATED == true then
        return _G.DsBannerWidget
    end

    pcall(function()
        local btn = slua.loadUI(BTN_BP)
        if not btn or not slua.isValid(btn) then return end
        require("game_frontend_hud").AddToContainer(UIContainers.Top, btn, 999)

        if btn.RichText_Content then
            btn.RichText_Content:SetText(" B O T M A S T E R ")
            local fontInfo = btn.RichText_Content.Font
            if fontInfo then
                fontInfo.Size = 14
                btn.RichText_Content:SetFont(fontInfo)
            end
            btn.RichText_Content:SetColorAndOpacity(FSlateColor(FLinearColor(1, 0, 0, 1)))
        end

        local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
        local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(btn)
        if slot then
            slot:SetAnchors(FAnchors(0, 1, 0, 1))
            slot:SetAlignment(FVector2D(0, 1))
            slot:SetPosition(FVector2D(10, -10))
            slot:SetSize(FVector2D(180, 30))
        end

        btn:SetBackgroundColor(FLinearColor(0, 0, 0, 0.7))
        btn:SetRenderOpacity(0.9)
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)

        _G.DsBannerWidget = btn
        _G._BANNER_CREATED = true
        print("[Banner] Botmaster banner created (permanent)")
    end)

    return _G.DsBannerWidget
end

-- ============================================================
-- STEP 4: WALLHACK ENGINE (gated by _G.PBCEnabled)
-- ============================================================
local LinearColor = import("LinearColor")

local _PBC = {
    CONSOLE_READY   = false,
    PROCESSED_PAWNS = {},
    TICK_COUNT      = 0,
    WH_TIMER        = nil,
    TIMER_OWNER     = nil,
    colors          = nil,
    BotDetectCache  = {}
}

local PBC_TICK_INTERVAL       = 0.3
local PBC_MAX_PAWNS_PER_TICK  = 20
local PBC_RESET_EVERY         = 6
local PBC_AVATAR_SLOTS        = {0,1,2,3,4,5,6,7}

pcall(function()
    _PBC.colors = {
        vis  = LinearColor(0, 100, 100, 100),
        occ  = LinearColor(0, 100, 0, 100),
        bVis = LinearColor(100, 0, 100, 100),
        bOcc = LinearColor(100, 100, 5, 100)
    }
end)

local function PBC_SetupConsole()
    if _PBC.CONSOLE_READY then return end
    pcall(function()
        local KismetSystemLibrary = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KismetSystemLibrary or not world then return end
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        _PBC.CONSOLE_READY = true
        print("[PBC] Console ready")
    end)
end

local function PBC_DisableConsole()
    pcall(function()
        local KismetSystemLibrary = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KismetSystemLibrary or not world then return end
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 0")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 0")
        KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 0")
        print("[PBC] Console disabled")
    end)
    _PBC.CONSOLE_READY = false
end

local function PBC_ApplyToMesh(mesh, visColor, occColor)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        mesh:SetDrawDyeing(true)
        mesh:SetDrawDyeingMode(1)
        mesh:SetVisibleDyeingColor(visColor)
        mesh:SetOccludedDyeingColor(occColor)
        mesh:SetDyeingColorFadeDistance(99999.0)
        mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
        mesh:SetDrawHighlight(true)
        mesh:OverrideHighlightColor(visColor)
        mesh:SetHighlightCanBeOccluded(false)
        mesh:SetDrawIdeaOutline(true)
        mesh:SetIdeaOutlineNew(true)
        mesh:SetIdeaOutlineOcclusionHighlight(true)
        mesh:OverrideIdeaOutlineColor(visColor)
        mesh:SetIdeaOutlineOcclusionColor(occColor)
        mesh:OverrideIdeaOutlineThickness(20.0)
        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
        mesh:SetRenderCustomDepth(true)
        mesh:SetCustomDepthStencilValue(255)
    end)
end

local function PBC_ClearMeshVisuals(mesh)
    if not mesh or not slua.isValid(mesh) then return end
    pcall(function()
        mesh:SetDrawDyeing(false)
        mesh:SetDrawDyeingMode(0)
        mesh:SetDyeingColorFadeDistance(0.0)
        mesh:SetDyeingColorMinMaxDistance(0.0, 0.0)
        mesh:SetDrawHighlight(false)
        mesh:SetHighlightCanBeOccluded(true)
        mesh:SetDrawIdeaOutline(false)
        mesh:SetIdeaOutlineNew(false)
        mesh:SetIdeaOutlineOcclusionHighlight(false)
        mesh:SetIdeaOverrideOutlineAndOcclusion(false)
        mesh:OverrideIdeaOutlineThickness(0.0)
        mesh:SetRenderCustomDepth(false)
        mesh:SetCustomDepthStencilValue(0)
    end)
end

local function PBC_ClearAllVisuals()
    pcall(function()
        local SkeletalMeshComponent = import("SkeletalMeshComponent")
        local StaticMeshComponent   = import("StaticMeshComponent")

        local allPawns = Game:GetAllPlayerPawns() or {}
        for _, pawn in pairs(allPawns) do
            if slua.isValid(pawn) then
                pcall(function()
                    if slua.isValid(pawn.Mesh) then
                        PBC_ClearMeshVisuals(pawn.Mesh)
                    end

                    local avatarComp = pawn.CharacterAvatarComp2_BP or pawn:getAvatarComponent2()
                    if avatarComp and avatarComp.GetMeshCompBySlot then
                        for _, slot in ipairs(PBC_AVATAR_SLOTS) do
                            local m = avatarComp:GetMeshCompBySlot(slot)
                            if slua.isValid(m) then PBC_ClearMeshVisuals(m) end
                        end
                    end

                    if SkeletalMeshComponent then
                        local skComps = pawn:GetComponentsByClass(SkeletalMeshComponent)
                        if skComps then
                            for i = 0, skComps:Num() - 1 do
                                local comp = skComps:Get(i)
                                if slua.isValid(comp) and comp ~= pawn.Mesh then
                                    PBC_ClearMeshVisuals(comp)
                                end
                            end
                        end
                    end

                    if StaticMeshComponent then
                        local stComps = pawn:GetComponentsByClass(StaticMeshComponent)
                        if stComps then
                            for i = 0, stComps:Num() - 1 do
                                PBC_ClearMeshVisuals(stComps:Get(i))
                            end
                        end
                    end

                    local weapon = pawn:GetCurrentWeapon()
                    if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                        PBC_ClearMeshVisuals(weapon.Mesh)
                    end
                end)
            end
        end
    end)
    print("[PBC] All visuals cleared (glass emptied)")
end

local function PBC_IsPawnAlive(pawn)
    if not slua.isValid(pawn) then return false end
    if pawn.Health and pawn.Health > 0 then return true end
    return false
end

local function PBC_DetectIsBot(pawn)
    if not slua.isValid(pawn) then return false end
    local pk = pawn.PlayerKey
    if pk and _PBC.BotDetectCache[pk] ~= nil then
        return _PBC.BotDetectCache[pk]
    end
    local result = false

    pcall(function()
        if Game and Game.IsAI then
            local r = Game:IsAI(pawn)
            if r == true or r == 1 then result = true end
        end
    end)

    if not result then
        if pawn.bIsAI == true or pawn.IsAI == true then result = true end
        if pawn.bIsABot == true or pawn.bBot == true then result = true end
    end

    if not result then
        local ps = pawn.PlayerState
        if slua.isValid(ps) then
            if ps.bIsABot == true or ps.bIsBot == true or ps.bIsAI == true then
                result = true
            end
        end
    end

    if not result then
        pcall(function()
            local ctrl = nil
            if type(pawn.GetControllerSafety) == "function" then
                ctrl = pawn:GetControllerSafety()
            end
            if slua.isValid(ctrl) and ctrl.bIsAI == true then result = true end
        end)
    end

    if pk then _PBC.BotDetectCache[pk] = result end
    return result
end

local function PBC_tick()
    if _G.PBCEnabled ~= true then return end

    pcall(function()
        local localPawn = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPawn) then return end

        PBC_SetupConsole()
        if not _PBC.colors then return end

        _PBC.TICK_COUNT = _PBC.TICK_COUNT + 1
        if _PBC.TICK_COUNT % PBC_RESET_EVERY == 0 then
            _PBC.PROCESSED_PAWNS = {}
        end
        if _PBC.TICK_COUNT % (PBC_RESET_EVERY * 20) == 0 then
            _PBC.BotDetectCache = {}
        end

        local myTeamId = localPawn.TeamID or 0
        local allPawns = Game:GetAllPlayerPawns() or {}
        local processedCount = 0

        local SkeletalMeshComponent = import("SkeletalMeshComponent")
        local StaticMeshComponent   = import("StaticMeshComponent")

        for _, pawn in pairs(allPawns) do
            if processedCount >= PBC_MAX_PAWNS_PER_TICK then break end

            local skip = false
            if not slua.isValid(pawn) or pawn == localPawn then
                skip = true
            elseif pawn.PlayerKey and _PBC.PROCESSED_PAWNS[pawn.PlayerKey] then
                skip = true
            end

            if not skip then
                if PBC_IsPawnAlive(pawn) and pawn.TeamID and pawn.TeamID ~= myTeamId then
                    local isAI = PBC_DetectIsBot(pawn)
                    local vis = isAI and _PBC.colors.bVis or _PBC.colors.vis
                    local occ = isAI and _PBC.colors.bOcc or _PBC.colors.occ

                    pcall(function()
                        if slua.isValid(pawn.Mesh) then
                            PBC_ApplyToMesh(pawn.Mesh, vis, occ)
                        end

                        local avatarComp = pawn.CharacterAvatarComp2_BP or pawn:getAvatarComponent2()
                        if avatarComp and avatarComp.GetMeshCompBySlot then
                            for _, slot in ipairs(PBC_AVATAR_SLOTS) do
                                local mesh = avatarComp:GetMeshCompBySlot(slot)
                                if slua.isValid(mesh) then
                                    PBC_ApplyToMesh(mesh, vis, occ)
                                end
                            end
                        end

                        if SkeletalMeshComponent then
                            local skComps = pawn:GetComponentsByClass(SkeletalMeshComponent)
                            if skComps then
                                for i = 0, skComps:Num() - 1 do
                                    local comp = skComps:Get(i)
                                    if slua.isValid(comp) and comp ~= pawn.Mesh then
                                        PBC_ApplyToMesh(comp, vis, occ)
                                    end
                                end
                            end
                        end

                        if StaticMeshComponent then
                            local stComps = pawn:GetComponentsByClass(StaticMeshComponent)
                            if stComps then
                                for i = 0, stComps:Num() - 1 do
                                    local comp = stComps:Get(i)
                                    if slua.isValid(comp) then
                                        PBC_ApplyToMesh(comp, vis, occ)
                                    end
                                end
                            end
                        end

                        local weapon = pawn:GetCurrentWeapon()
                        if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                            PBC_ApplyToMesh(weapon.Mesh, vis, occ)
                        end
                    end)

                    if pawn.PlayerKey then _PBC.PROCESSED_PAWNS[pawn.PlayerKey] = true end
                    processedCount = processedCount + 1
                end
            end
        end
    end)
end

local function PBC_Start()
    if _G.PBCEnabled ~= true then return false end

    PBC_SetupConsole()
    if not _PBC.colors then
        print("[PBC] Colors not initialized")
        return false
    end

    if _PBC.WH_TIMER and _PBC.TIMER_OWNER then
        pcall(function()
            if _PBC.TIMER_OWNER.RemoveGameTimer then
                _PBC.TIMER_OWNER:RemoveGameTimer(_PBC.WH_TIMER)
            end
        end)
    end
    _PBC.WH_TIMER = nil
    _PBC.TIMER_OWNER = nil

    if _G.Game and _G.Game.AddGameTimer then
        _PBC.TIMER_OWNER = _G.Game
        _PBC.WH_TIMER = _G.Game:AddGameTimer(PBC_TICK_INTERVAL, true, PBC_tick)
        print("[PBC] Wallhack ON (Game timer)")
        return true
    end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        _PBC.TIMER_OWNER = pc
        _PBC.WH_TIMER = pc:AddGameTimer(PBC_TICK_INTERVAL, true, PBC_tick)
        print("[PBC] Wallhack ON (PC timer)")
        return true
    end

    print("[PBC] Timer unavailable — switch off/on karo")
    return false
end

local function PBC_Cleanup()
    if _PBC.WH_TIMER and _PBC.TIMER_OWNER then
        pcall(function()
            if _PBC.TIMER_OWNER.RemoveGameTimer then
                _PBC.TIMER_OWNER:RemoveGameTimer(_PBC.WH_TIMER)
            end
        end)
    end
    _PBC.WH_TIMER    = nil
    _PBC.TIMER_OWNER = nil

    PBC_ClearAllVisuals()
    PBC_DisableConsole()

    _PBC.PROCESSED_PAWNS = {}
    _PBC.BotDetectCache  = {}
    _PBC.CONSOLE_READY   = false
    _PBC.TICK_COUNT      = 0
    print("[PBC] Cleanup done")
end

-- ============================================================
-- STEP 5: PBC PUBLIC CONTROL (ON / OFF / TOGGLE)
-- ============================================================
_G.PBCEnabled = _G.PBCEnabled or false

function _G.PBCOn()
    if _G.PBCEnabled == true and _PBC.WH_TIMER then
        return
    end
    _G.PBCEnabled = true
    pcall(PBC_Start)
    print("[PBC] ESP ON")
end

function _G.PBCOff()
    _G.PBCEnabled = false
    pcall(PBC_Cleanup)
    print("[PBC] ESP OFF")
end

function _G.PBCToggle()
    if _G.PBCEnabled then _G.PBCOff() else _G.PBCOn() end
    return _G.PBCEnabled
end

-- ============================================================
-- STEP 5.5: AIMBOT ENGINE (gated by _G.AimbotEnabled)
-- ============================================================
_G.XthrlenConfig = _G.XthrlenConfig or {}
_G.XthrlenState  = _G.XthrlenState or {}
_G.XthrlenState.CustomTextData = _G.XthrlenState.CustomTextData or {}

_G.XthrlenConfig.AimTouchEnable        = true
_G.XthrlenConfig.AimTouchHipfire       = true
_G.XthrlenConfig.AimTouchScopeAll      = true
_G.XthrlenConfig.AimTouchHipVisCheck   = true
_G.XthrlenConfig.AimTouchScopeVisCheck = true
_G.XthrlenConfig.AimTouchHipIgKnock    = true
_G.XthrlenConfig.AimTouchScopeIgKnock  = true

_G.XthrlenConfig.AimTouchHipIgBot      = false
_G.XthrlenConfig.AimTouchScopeIgBot    = false
_G.XthrlenConfig.AimTouchSG            = false
_G.XthrlenConfig.AimTouchSGAutoFire    = false
_G.XthrlenConfig.AimTouchScopeSniper   = false
_G.XthrlenConfig.AimTouchMortar        = false
_G.XthrlenConfig.EspFovCircle          = false

_G.XthrlenState.CustomTextData.AimTouchHipPrio    = 1
_G.XthrlenState.CustomTextData.AimTouchHipBone    = 1
_G.XthrlenState.CustomTextData.AimTouchHipCond    = 1
_G.XthrlenState.CustomTextData.AimTouchHipSpeed   = 120
_G.XthrlenState.CustomTextData.AimTouchHipDist    = 120
_G.XthrlenState.CustomTextData.AimTouchHipFOV     = 30

_G.XthrlenState.CustomTextData.AimTouchScopePrio   = 1
_G.XthrlenState.CustomTextData.AimTouchScopeBone   = 1
_G.XthrlenState.CustomTextData.AimTouchScopeCond   = 1
_G.XthrlenState.CustomTextData.AimTouchScopeSpeed  = 120
_G.XthrlenState.CustomTextData.AimTouchScopeDist   = 120
_G.XthrlenState.CustomTextData.AimTouchScopeFOV    = 30
_G.XthrlenState.CustomTextData.AimTouchScopePred   = 0

_G.XthrlenState.offPitch = _G.XthrlenState.offPitch or 0
_G.XthrlenState.offYaw   = _G.XthrlenState.offYaw   or 0

local _AIM = {
    TIMER       = nil,
    TIMER_OWNER = nil,
    VisCache    = {},
    TickCount   = 0,
}

local AIM_TICK_INTERVAL   = 0.016
local AIM_VIS_RESET_EVERY = 300

local function AIM_ClampAngles(angles)
    if angles.Pitch > 180 then angles.Pitch = angles.Pitch - 360 end
    if angles.Pitch < -180 then angles.Pitch = angles.Pitch + 360 end

    if angles.Pitch < -75 then
        angles.Pitch = -75
    elseif angles.Pitch > 75 then
        angles.Pitch = 75
    end

    while angles.Yaw < -180 do angles.Yaw = angles.Yaw + 360 end
    while angles.Yaw > 180  do angles.Yaw = angles.Yaw - 360 end

    return angles
end

_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()
    if not (slua and slua.isValid and slua.isValid(player)) then return result end

    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end

    local myTeam = player:GetTeamID()
    for _, actor in pairs(allCharacters) do
        if slua.isValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

local function AIM_Tick()
    if _G.AimbotEnabled ~= true then return end
    if not _G.XthrlenConfig.AimTouchEnable then return end

    _AIM.TickCount = _AIM.TickCount + 1
    if _AIM.TickCount % AIM_VIS_RESET_EVERY == 0 then
        _AIM.VisCache = {}
    end

    pcall(function()
        local player = GameplayData.GetPlayerCharacter()
        if not (slua and slua.isValid and slua.isValid(player)) then return end

        local pc = player:GetPlayerControllerSafety()
        if not (slua and slua.isValid and slua.isValid(pc)) then return end

        local isFiring = player.bIsWeaponFiring
        local isADS = player.bIsGunADS

        local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end

        local isShotgun = false
        local isSniper = false
        local isMortar = false
        local currentAmmo = 1

        if slua.isValid(weapon) then
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""

            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then
                isShotgun = true
            end
            if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                isSniper = true
            end
            if wName:lower():find("mortar") or wName:lower():find("cối") then
                isMortar = true
            end

            if type(weapon.GetCurrentAmmo) == "function" then
                currentAmmo = weapon:GetCurrentAmmo()
            elseif weapon.ShootWeaponComponent and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then
                currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo()
            elseif weapon.CurrentAmmo ~= nil then
                currentAmmo = weapon.CurrentAmmo
            end
        end

        if _G.XthrlenState.IsAutoFiring then
            pcall(function()
                player.bIsWeaponFiring = false
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end
                if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end
                local wepMgr = player.WeaponManagerComponent
                if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = false end
            end)
            _G.XthrlenState.IsAutoFiring = false
        end

        if isShotgun and currentAmmo <= 0 then return end

        local cond = 2
        local prioMode = 1
        local boneIdx = 1
        local speedVal = 100
        local fovVal = 30
        local maxDistMeters = 100
        local useVisCheck = false
        local igKnock = false
        local igBot = false
        local predVal = 0

        if isMortar and _G.XthrlenConfig.AimTouchMortar then
            local isPlaced = false
            pcall(function()
                if weapon and weapon.MortarState == 2 then isPlaced = true end
            end)
            if not isPlaced then return end

            cond = 2
            prioMode = 1
            boneIdx = 4
            speedVal = 100
            fovVal = _G.XthrlenState.CustomTextData.AimTouchMortarFOV or 360
            maxDistMeters = 2000
            useVisCheck = false
            igKnock = false
            igBot = false
            predVal = _G.XthrlenState.CustomTextData.AimTouchMortarPred or 0

        elseif isShotgun and _G.XthrlenConfig.AimTouchSG then
            cond = _G.XthrlenState.CustomTextData.AimTouchSGCond or 1
            if _G.XthrlenConfig.AimTouchSGAutoFire then cond = 2 end
            if cond == 1 and not isFiring then return end
            prioMode = _G.XthrlenState.CustomTextData.AimTouchSGPrio or 1
            boneIdx = _G.XthrlenState.CustomTextData.AimTouchSGBone or 2
            speedVal = _G.XthrlenState.CustomTextData.AimTouchSGSpeed or 80
            fovVal = _G.XthrlenState.CustomTextData.AimTouchSGFOV or 40
            maxDistMeters = _G.XthrlenState.CustomTextData.AimTouchSGDist or 30
            useVisCheck = _G.XthrlenConfig.AimTouchSGVisCheck
            igKnock = _G.XthrlenConfig.AimTouchSGIgKnock
            igBot = _G.XthrlenConfig.AimTouchSGIgBot

        elseif isADS then
            if isSniper and _G.XthrlenConfig.AimTouchScopeSniper then
                cond = _G.XthrlenState.CustomTextData.AimTouchSniperCond or 2
                if cond == 1 and not isFiring then return end
                prioMode = _G.XthrlenState.CustomTextData.AimTouchSniperPrio or 1
                boneIdx = _G.XthrlenState.CustomTextData.AimTouchSniperBone or 1
                speedVal = _G.XthrlenState.CustomTextData.AimTouchSniperSpeed or 30
                fovVal = _G.XthrlenState.CustomTextData.AimTouchSniperFOV or 20
                maxDistMeters = _G.XthrlenState.CustomTextData.AimTouchSniperDist or 400
                useVisCheck = _G.XthrlenConfig.AimTouchSniperVisCheck
                igKnock = _G.XthrlenConfig.AimTouchSniperIgKnock
                igBot = _G.XthrlenConfig.AimTouchSniperIgBot
                predVal = _G.XthrlenState.CustomTextData.AimTouchSniperPred or 0
            elseif _G.XthrlenConfig.AimTouchScopeAll then
                cond = _G.XthrlenState.CustomTextData.AimTouchScopeCond or 1
                if cond == 1 and not isFiring then return end
                prioMode = _G.XthrlenState.CustomTextData.AimTouchScopePrio or 1
                boneIdx = 1
                speedVal = _G.XthrlenState.CustomTextData.AimTouchScopeSpeed or 100
                fovVal = _G.XthrlenState.CustomTextData.AimTouchScopeFOV or 30
                maxDistMeters = _G.XthrlenState.CustomTextData.AimTouchScopeDist or 100
                useVisCheck = _G.XthrlenConfig.AimTouchScopeVisCheck
                igKnock = _G.XthrlenConfig.AimTouchScopeIgKnock
                igBot = _G.XthrlenConfig.AimTouchScopeIgBot
                predVal = _G.XthrlenState.CustomTextData.AimTouchScopePred or 0
            else
                return
            end
        else
            if not _G.XthrlenConfig.AimTouchHipfire then return end
            cond = _G.XthrlenState.CustomTextData.AimTouchHipCond or 1
            if cond == 1 and not isFiring then return end
            prioMode = _G.XthrlenState.CustomTextData.AimTouchHipPrio or 1
            boneIdx = 1
            speedVal = _G.XthrlenState.CustomTextData.AimTouchHipSpeed or 100
            fovVal = _G.XthrlenState.CustomTextData.AimTouchHipFOV or 30
            maxDistMeters = _G.XthrlenState.CustomTextData.AimTouchHipDist or 100
            useVisCheck = _G.XthrlenConfig.AimTouchHipVisCheck
            igKnock = _G.XthrlenConfig.AimTouchHipIgKnock
            igBot = _G.XthrlenConfig.AimTouchHipIgBot
        end

        local currentMaxDist = maxDistMeters * 100
        local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
        if not enemies or #enemies == 0 then return end

        local FVector2D = import("Vector2D")
        local UGameplayStatics = import("GameplayStatics")
        local KismetMathLibrary = import("KismetMathLibrary")

        local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
        if not slua.isValid(camManager) then return end

        local camLoc = camManager:GetCameraLocation()
        if not camLoc then return end

        local ui_util = require("client.common.ui_util")
        if not ui_util then return end

        local viewportSize = ui_util.GetViewportSize()
        if not viewportSize then return end

        local centerX = viewportSize.X * 0.5
        local centerY = viewportSize.Y * 0.5
        local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)

        local bestTarget = nil
        local bestScore = 99999999

        local selBoneName = "head"
        if boneIdx == 1 then selBoneName = "head"
        elseif boneIdx == 2 then selBoneName = "spine_03"
        elseif boneIdx == 3 then selBoneName = "spine_01"
        elseif boneIdx == 4 then selBoneName = "pelvis" end

        local function tryTarget(target)
            if not slua.isValid(target) then return end

            pcall(function()
                if slua.isValid(target.Mesh) then
                    target.Mesh.MeshComponentUpdateFlag = 0
                end
            end)

            if igKnock and target.HealthStatus == 1 then return end

            if igBot then
                local tIsBot = false
                if target.bIsAI == true or target.IsAI == true then tIsBot = true end
                local pState = target.PlayerState
                if slua.isValid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end
                if tIsBot then return end
            end

            if useVisCheck then
                local curTime = os.clock()
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                if not _AIM.VisCache[tId] or (curTime - _AIM.VisCache[tId].time) > 0.2 then
                    local isHidden = true
                    pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                    _AIM.VisCache[tId] = { hidden = isHidden, time = curTime }
                end
                if _AIM.VisCache[tId].hidden then return end
            end

            local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.GetSocketLocation) == "function" then
                    tPos = target:GetSocketLocation(selBoneName)
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.K2_GetActorLocation) == "function" then
                    tPos = target:K2_GetActorLocation()
                    if tPos then
                        if boneIdx == 1 then tPos.Z = tPos.Z + 70
                        elseif boneIdx == 2 then tPos.Z = tPos.Z + 40
                        elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end
                    end
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then return end

            local screen = FVector2D()
            local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
            if not success or screen.X <= 0 or screen.Y <= 0 then return end

            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local distScreen = math.sqrt(dx*dx + dy*dy)

            if distScreen > FOV_RADIUS then return end

            local currentScore = distScreen
            if prioMode == 2 then currentScore = player:GetDistanceTo(target)
            elseif prioMode == 3 then currentScore = target.Health or 100
            elseif prioMode == 4 then
                local hp = target.Health or 100
                local maxhp = target.HealthMax or 100
                if maxhp <= 0 then maxhp = 100 end
                currentScore = hp / maxhp
            end

            if currentScore < bestScore then
                bestScore = currentScore
                bestTarget = target
            end
        end

        for i, target in ipairs(enemies) do
            tryTarget(target)
        end

        if not slua.isValid(bestTarget) then return end

        local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.GetSocketLocation) == "function" then
                finalBonePos = bestTarget:GetSocketLocation(selBoneName)
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.K2_GetActorLocation) == "function" then
                finalBonePos = bestTarget:K2_GetActorLocation()
                if finalBonePos then
                    if boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70
                    elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40
                    elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end
                end
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end

        local tVelocity = nil
        pcall(function()
            if type(bestTarget.GetVelocity) == "function" then
                tVelocity = bestTarget:GetVelocity()
            end
        end)

        if not isMortar and predVal > 0 then
            pcall(function()
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0
                    local ToF = (distToEnemy / 800.0) * (predVal / 50.0)
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF)
                end
            end)
        end

        if isADS and isFiring then
            local dist = player:GetDistanceTo(bestTarget) / 100.0
            finalBonePos.Z = finalBonePos.Z - (dist * 1.0)
        end

        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
        if not rot then return end

        local currentRot = pc:GetControlRotation()
        if not currentRot then return end

        if not isADS then
            _G.XthrlenState.offPitch = 0
            _G.XthrlenState.offYaw   = 0
        end

        local dPitch = rot.Pitch - currentRot.Pitch
        local dYaw   = rot.Yaw   - currentRot.Yaw

        if isADS then
            local camRot = nil
            if type(camManager.GetCameraRotation) == "function" then
                camRot = camManager:GetCameraRotation()
            end
            if camRot then
                dYaw   = dYaw   - (camRot.Yaw   - currentRot.Yaw)
                dPitch = dPitch - (camRot.Pitch - currentRot.Pitch)
            end
        end

        while dPitch > 180  do dPitch = dPitch - 360 end
        while dPitch < -180 do dPitch = dPitch + 360 end
        while dYaw > 180    do dYaw   = dYaw   - 360 end
        while dYaw < -180   do dYaw   = dYaw   + 360 end

        if isADS then
            _G.XthrlenState.offPitch = _G.XthrlenState.offPitch + (dPitch * 0.12)
            _G.XthrlenState.offYaw   = _G.XthrlenState.offYaw   + (dYaw   * 0.12)

            if _G.XthrlenState.offPitch > 30  then _G.XthrlenState.offPitch = 30  end
            if _G.XthrlenState.offPitch < -30 then _G.XthrlenState.offPitch = -30 end
            if _G.XthrlenState.offYaw   > 30  then _G.XthrlenState.offYaw   = 30  end
            if _G.XthrlenState.offYaw   < -30 then _G.XthrlenState.offYaw   = -30 end
        end

        local apply = {
            Pitch = rot.Pitch + _G.XthrlenState.offPitch,
            Yaw   = rot.Yaw   + _G.XthrlenState.offYaw,
            Roll  = 0
        }

        local s = 1.0
        if speedVal < 100 then
            s = math.max(1.0, 100.0 / math.max(speedVal, 1))
        end

        local out = {
            Pitch = currentRot.Pitch + (apply.Pitch - currentRot.Pitch) / s,
            Yaw   = currentRot.Yaw   + (apply.Yaw   - currentRot.Yaw)   / s,
            Roll  = 0
        }

        out = AIM_ClampAngles(out)
        pc:SetControlRotation(out, "AimTouch")
    end)
end

_G.AimTouch = AIM_Tick

-- ============================================================
-- AIM START / CLEANUP (no retry — direct switch)
-- ============================================================
local function AIM_Start()
    if _G.AimbotEnabled ~= true then return false end

    -- Kill old timer if exists
    if _AIM.TIMER and _AIM.TIMER_OWNER then
        pcall(function()
            if _AIM.TIMER_OWNER.RemoveGameTimer then
                _AIM.TIMER_OWNER:RemoveGameTimer(_AIM.TIMER)
            end
        end)
    end
    _AIM.TIMER       = nil
    _AIM.TIMER_OWNER = nil

    -- Fresh state reset
    _AIM.VisCache   = {}
    _AIM.TickCount  = 0
    _G.XthrlenState.offPitch = 0
    _G.XthrlenState.offYaw   = 0

    if _G.Game and _G.Game.AddGameTimer then
        _AIM.TIMER_OWNER = _G.Game
        _AIM.TIMER = _G.Game:AddGameTimer(AIM_TICK_INTERVAL, true, AIM_Tick)
        print("[AIM] Active (Game timer)")
        return true
    end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        _AIM.TIMER_OWNER = pc
        _AIM.TIMER = pc:AddGameTimer(AIM_TICK_INTERVAL, true, AIM_Tick)
        print("[AIM] Active (PC timer)")
        return true
    end

    print("[AIM] Could not start timer")
    return false
end

local function AIM_Cleanup()
    if _AIM.TIMER and _AIM.TIMER_OWNER then
        pcall(function()
            if _AIM.TIMER_OWNER.RemoveGameTimer then
                _AIM.TIMER_OWNER:RemoveGameTimer(_AIM.TIMER)
            end
        end)
    end
    _AIM.TIMER       = nil
    _AIM.TIMER_OWNER = nil

    _AIM.VisCache   = {}
    _AIM.TickCount  = 0

    _G.XthrlenState.offPitch = 0
    _G.XthrlenState.offYaw   = 0

    print("[AIM] Cleanup done — fully reset")
end

-- ============================================================
-- AIMBOT PUBLIC CONTROL (ON / OFF / TOGGLE)
-- ============================================================
_G.AimbotEnabled = _G.AimbotEnabled or false

function _G.AimbotOn()
    if _G.AimbotEnabled == true and _AIM.TIMER then return end
    _G.AimbotEnabled = true
    pcall(AIM_Start)
    print("[AIM] Aimbot ON — fresh install")
end

function _G.AimbotOff()
    _G.AimbotEnabled = false
    pcall(AIM_Cleanup)
    print("[AIM] Aimbot OFF — fully reset")
end

function _G.AimbotToggle()
    if _G.AimbotEnabled then _G.AimbotOff() else _G.AimbotOn() end
    return _G.AimbotEnabled
end


-- ============================================================
-- STEP 5.6: ESP ENGINE (Line / Name+Health / Distance)
-- Counter independent (auto-start after 0.5s, always on).
-- ============================================================
_G.ESPLineEnabled        = _G.ESPLineEnabled        or false
_G.ESPNameHealthEnabled  = _G.ESPNameHealthEnabled  or false
_G.ESPDistanceEnabled    = _G.ESPDistanceEnabled    or false

_G.g_Botmater_MasterShotESP = _G.g_Botmater_MasterShotESP or {
    Enabled = true,
    MaxRangeMeters = 300.0,
    ScanInterval = 0.05,
    UpdateInterval = 0.008,
    TransformInterval = 0.033,
    MaxRendered = 10,
    TracerThickness = 1.0,
    NameFontSize = 9,
    DistanceFontSize = 10,
}
_G.MasterShotESP = _G.g_Botmater_MasterShotESP

local g_Botmater_ShotESP = {
    Canvas = nil,
    Enemies = {},
    Lines = {},
    Names = {},
    LastScanClock = -999.0,
    LastTransformClock = -999.0,
    LastWorld = nil,
    CanvasScaleX = 1.0,
    CanvasScaleY = 1.0,
    CanvasOffsetX = 0.0,
    CanvasOffsetY = 0.0,
    RealCount = 0,
    BotCount = 0,
    Running = false,
    TickRegistered = false,
}

local ESP_V2 = _G.FVector2D
if not ESP_V2 then pcall(function() ESP_V2 = import("Vector2D") end) end
local LinearColorESP = _G.FLinearColor
if not LinearColorESP then pcall(function() LinearColorESP = import("LinearColor") end) end
local SlateBlueprintLibrary = nil
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
local WidgetLayoutLibrary = nil
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)
local SlateColor = nil
pcall(function() SlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
local GameplayStaticsESP = nil
pcall(function() GameplayStaticsESP = import("GameplayStatics") end)

local slua_isValid = (slua and slua.isValid) or nil

local g_Botmater_RobotoFont = nil
local g_Botmater_RobotoTried = false

local function g_Botmater_LoadRobotoFont()
    if g_Botmater_RobotoFont and slua_isValid and slua_isValid(g_Botmater_RobotoFont) then
        return g_Botmater_RobotoFont
    end
    if g_Botmater_RobotoTried then return g_Botmater_RobotoFont end
    g_Botmater_RobotoTried = true
    local font = nil
    pcall(function()
        if slua and slua.loadObject then
            font = slua.loadObject("Font Roboto.Roboto")
        end
    end)
    if not (font and slua_isValid and slua_isValid(font)) then
        pcall(function()
            if UE4 and UE4.FindObject then font = UE4.FindObject("Font Roboto.Roboto") end
        end)
    end
    if not (font and slua_isValid and slua_isValid(font)) then
        pcall(function()
            if UObject and UObject.StaticFindObject then font = UObject.StaticFindObject("Font Roboto.Roboto") end
        end)
    end
    if font and slua_isValid and slua_isValid(font) then
        g_Botmater_RobotoFont = font
    end
    return g_Botmater_RobotoFont
end

local ZERO_VEC3 = { X = 0, Y = 0, Z = 0 }
local g_Botmater_ActiveSet = {}
local g_Botmater_DistLabelCache = {}

local function g_Botmater_FormatDistLabel(meters)
    local di = math.floor((meters or 0) + 0.5)
    if di < 0 then di = 0 end
    local cached = g_Botmater_DistLabelCache[di]
    if cached then return cached end
    cached = di .. "m"
    g_Botmater_DistLabelCache[di] = cached
    return cached
end

local function g_Botmater_ESPV2(x, y)
    if ESP_V2 then return ESP_V2(x, y) end
    return {X = x, Y = y}
end

local function g_Botmater_ESPColor(r, g, b, a)
    if LinearColorESP then return LinearColorESP(r, g, b, a or 1.0) end
    return {R=r, G=g, B=b, A=a or 1.0}
end

local COLOR_TEXT_WHITE            = g_Botmater_ESPColor(1.00, 1.00, 1.00, 1.00)
local COLOR_TEXT_BLACK            = g_Botmater_ESPColor(0.00, 0.00, 0.00, 1.00)
local CACHE_DIST_YELLOW           = g_Botmater_ESPColor(1.0, 1.0, 0.0, 1.00)
local CACHE_COUNTER_BG_GREEN      = g_Botmater_ESPColor(0.00, 1.00, 0.00, 1.00)
local CACHE_COUNTER_BG_YELLOW     = g_Botmater_ESPColor(1.00, 1.00, 0.00, 1.00)
local CACHE_COUNTER_TEXT_MAGENTA  = g_Botmater_ESPColor(1.00, 0.00, 1.00, 1.00)
local CACHE_COUNTER_TEXT_BLACK    = g_Botmater_ESPColor(0.00, 0.00, 0.00, 1.00)
local HEALTH_FULL_GREEN  = g_Botmater_ESPColor(0.0, 1.0, 0.0, 1.0)
local HEALTH_MID_CYAN    = g_Botmater_ESPColor(0.1, 1.0, 1.0, 1.0)
local HEALTH_LOW_RED     = g_Botmater_ESPColor(1.0, 0.0, 0.0, 1.0)
local HEALTH_BG_DARK     = g_Botmater_ESPColor(0.0, 0.0, 0.0, 0.75)

local COLOR_BOT       = g_Botmater_ESPColor(1.0, 1.0, 1.0, 1.0)   -- bot (white)
local COLOR_PLAYER    = g_Botmater_ESPColor(1.0, 0.0, 0.0, 1.0)   -- player (red)

local function g_Botmater_ESPGetColors(isBot)
    if isBot then
        return COLOR_BOT, COLOR_TEXT_BLACK
    else
        return COLOR_PLAYER, COLOR_TEXT_WHITE
    end
end

local function g_Botmater_ESPValid(obj)
    if not obj then return false end
    if slua_isValid then
        local ok, valid = pcall(slua_isValid, obj)
        return ok and valid == true
    end
    return false
end

local _cachedWorld = nil
local function g_Botmater_ESPWorld()
    if slua and slua.getWorld then
        local ok, w = pcall(slua.getWorld)
        if ok then return w end
    end
    return _cachedWorld
end

local function g_Botmater_ESPNow()
    local w = g_Botmater_ESPWorld()
    _cachedWorld = w
    if GameplayStaticsESP and w then
        local ok, t = pcall(GameplayStaticsESP.GetRealTimeSeconds, w)
        if ok and tonumber(t) then return tonumber(t) end
    end
    if os and os.clock then
        local ok, v = pcall(os.clock)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return 0.0
end

local function g_Botmater_ESPGetController()
    local pc = nil
    pcall(function()
        local GDP = require("GameLua.GameCore.Data.GameplayData")
        if GDP and GDP.GetPlayerController then pc = GDP.GetPlayerController() end
    end)
    if not g_Botmater_ESPValid(pc) then
        pcall(function()
            if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
        end)
    end
    return g_Botmater_ESPValid(pc) and pc or nil
end

local function g_Botmater_ESPGetLocalCharacter()
    local c = nil
    pcall(function()
        local GDP = require("GameLua.GameCore.Data.GameplayData")
        if GDP then
            if GDP.GetPlayerCharacter then c = GDP.GetPlayerCharacter() end
            if not g_Botmater_ESPValid(c) and GDP.GetLocalCharacter then c = GDP:GetLocalCharacter() end
        end
    end)
    if not g_Botmater_ESPValid(c) then
        local pc = g_Botmater_ESPGetController()
        pcall(function() if pc and pc.GetPawn then c = pc:GetPawn() end end)
    end
    return g_Botmater_ESPValid(c) and c or nil
end

local function g_Botmater_ESPGetPlayerState(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local ps = nil
    pcall(function()
        if character.GetPlayerStateSafety then ps = character:GetPlayerStateSafety() end
    end)
    if not g_Botmater_ESPValid(ps) then
        pcall(function() if character.GetPlayerState then ps = character:GetPlayerState() end end)
    end
    if not g_Botmater_ESPValid(ps) then
        pcall(function() ps = character.PlayerState end)
    end
    return g_Botmater_ESPValid(ps) and ps or nil
end

local function g_Botmater_ESPNormalizeName(value)
    if value == nil or value == false then return nil end
    local ok, text = pcall(tostring, value)
    if not ok or not text then return nil end
    text = text:match("^%s*(.-)%s*$")
    if text == "" or text == "nil" or text == "None" or text == "NULL" then return nil end
    return text
end

local function g_Botmater_ESPResolvePlayerName(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local name = nil
    local function take(value)
        if not name then name = g_Botmater_ESPNormalizeName(value) end
    end
    pcall(function() if character.GetPlayerNameSafety then take(character:GetPlayerNameSafety()) end end)
    pcall(function() if not name and character.GetPlayerName then take(character:GetPlayerName()) end end)
    pcall(function() if not name then take(character.PlayerName) end end)
    pcall(function() if not name then take(character.NickName) end end)
    if not name then
        local ps = g_Botmater_ESPGetPlayerState(character)
        if ps then
            pcall(function() if ps.GetPlayerName then take(ps:GetPlayerName()) end end)
            pcall(function() if not name then take(ps.PlayerName) end end)
            pcall(function() if not name then take(ps.PlayerNamePrivate) end end)
            pcall(function() if not name then take(ps.NickName) end end)
        end
    end
    return name
end

local function g_Botmater_ESPGetPlayerKey(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local key = nil
    pcall(function() if character.GetPlayerKey then key = character:GetPlayerKey() end end)
    if key == nil then pcall(function() key = character.PlayerKey end) end
    if key == nil then
        local ps = g_Botmater_ESPGetPlayerState(character)
        if ps then
            pcall(function() key = ps.PlayerKey end)
            if key == nil then pcall(function() if ps.GetPlayerID then key = ps:GetPlayerID() end end) end
        end
    end
    if key == nil then
        pcall(function() key = character:GetName() end)
    end
    if key == nil then
        pcall(function() key = tostring(character) end)
    end
    return tostring(key)
end

local function g_Botmater_ESPGetTeamID(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local id = nil
    pcall(function() if character.GetTeamID then id = character:GetTeamID() end end)
    if id == nil then pcall(function() id = character.TeamID end) end
    if id == nil then
        local ps = g_Botmater_ESPGetPlayerState(character)
        if ps then
            pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
            if id == nil then pcall(function() id = ps.TeamID end) end
        end
    end
    return id
end

local function g_Botmater_ESPIsAlive(character)
    if not g_Botmater_ESPValid(character) then return false end
    local alive = nil
    pcall(function() if character.IsAlive then alive = character:IsAlive() end end)
    if type(alive) == "boolean" then return alive end
    local hp = nil
    pcall(function() hp = character.Health end)
    if type(hp) ~= "number" then pcall(function() hp = character.HP end) end
    if type(hp) == "number" then return hp > 0 end
    return true
end

local function g_Botmater_ESPGetHealthPct(character)
    if not g_Botmater_ESPValid(character) then return 1.0 end
    local hp, maxHp = nil, nil
    pcall(function() hp = character.Health end)
    if type(hp) ~= "number" then pcall(function() hp = character.HP end) end
    pcall(function() maxHp = character.MaxHealth end)
    if type(maxHp) ~= "number" then pcall(function() maxHp = character.MaxHP end) end
    if type(hp) ~= "number" then return 1.0 end
    if type(maxHp) ~= "number" or maxHp <= 0 then maxHp = 100 end
    local pct = hp / maxHp
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    return pct
end

local function g_Botmater_ESPGetHealthColor(pct)
    pct = tonumber(pct) or 1.0
    if pct > 0.5 then return HEALTH_FULL_GREEN
    elseif pct > 0.2 then return HEALTH_MID_CYAN
    else return HEALTH_LOW_RED end
end

local function g_Botmater_ESPIsBot(character)
    if not g_Botmater_ESPValid(character) then return false end
    local key = g_Botmater_ESPGetPlayerKey(character)
    local cache = g_Botmater_ShotESP._BotCache
    if not cache then cache = {} g_Botmater_ShotESP._BotCache = cache end
    local cached = cache[key]
    if cached ~= nil then return cached end
    local result = nil
    local function take(v)
        if result == nil and (v == true or v == false or v == 1 or v == 0) then result = (v == true or v == 1) end
    end
    pcall(function() if Game and Game.IsAI then take(Game:IsAI(character)) end end)
    if result == nil then pcall(function() take(character.bIsAI) end) end
    if result == nil then pcall(function() take(character.IsAI) end) end
    if result == nil then pcall(function() if character.IsBot then take(character:IsBot()) end end) end
    if result == nil then
        local ps = g_Botmater_ESPGetPlayerState(character)
        if ps then
            pcall(function() take(ps.bIsABot) end)
            if result == nil then pcall(function() take(ps.bIsBot) end) end
            if result == nil then pcall(function() take(ps.bIsAI) end) end
            if result == nil then pcall(function() if ps.IsBot then take(ps:IsBot()) end end) end
        end
    end
    if result == nil then result = false end
    cache[key] = result
    return result
end

local function g_Botmater_ESPActorLocation(character)
    local loc = nil
    if not g_Botmater_ESPValid(character) then return nil end
    pcall(function()
        if character.K2_GetActorLocation then loc = character:K2_GetActorLocation()
        elseif Game and Game.GetActorLocation then loc = Game:GetActorLocation(character) end
    end)
    return loc
end

local function g_Botmater_ESPDistanceMeters(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
end

local function g_Botmater_ESPGetCharacterVerticalBounds(character)
    if not g_Botmater_ESPValid(character) then return nil, nil end
    local center, halfHeight = nil, nil
    local capsule = nil
    pcall(function()
        if character.GetCapsuleComponent then capsule = character:GetCapsuleComponent()
        elseif character.CapsuleComponent then capsule = character.CapsuleComponent end
    end)
    if capsule and g_Botmater_ESPValid(capsule) then
        pcall(function()
            if capsule.K2_GetComponentLocation then center = capsule:K2_GetComponentLocation()
            elseif capsule.GetComponentLocation then center = capsule:GetComponentLocation() end
            if capsule.GetScaledCapsuleHalfHeight then halfHeight = capsule:GetScaledCapsuleHalfHeight()
            elseif capsule.GetUnscaledCapsuleHalfHeight then halfHeight = capsule:GetUnscaledCapsuleHalfHeight()
            elseif capsule.CapsuleHalfHeight then halfHeight = capsule.CapsuleHalfHeight end
        end)
    end
    if not center then
        pcall(function() if character.K2_GetActorLocation then center = character:K2_GetActorLocation() end end)
    end
    if not center then
        pcall(function() if Game and Game.GetActorLocation then center = Game:GetActorLocation(character) end end)
    end
    if not center then return nil, nil end
    if not halfHeight or halfHeight < 10 or halfHeight > 200 then halfHeight = 85 end
    return center, halfHeight
end

local function g_Botmater_ESPHeadLocation(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local bonePos = nil
    pcall(function()
        if character.GetBonePos then bonePos = character:GetBonePos("Head", ZERO_VEC3) end
    end)
    if not bonePos or (bonePos.X == 0 and bonePos.Y == 0 and bonePos.Z == 0) then
        pcall(function()
            if character.GetBonePos then bonePos = character:GetBonePos("head", ZERO_VEC3) end
        end)
    end
    if not bonePos or (bonePos.X == 0 and bonePos.Y == 0 and bonePos.Z == 0) then
        pcall(function()
            if character.GetSocketLocation then bonePos = character:GetSocketLocation("head") end
        end)
    end
    if bonePos and (bonePos.X ~= 0 or bonePos.Y ~= 0 or bonePos.Z ~= 0) then
        return { X = bonePos.X, Y = bonePos.Y, Z = bonePos.Z }
    end
    local center, halfHeight = g_Botmater_ESPGetCharacterVerticalBounds(character)
    if not center or not halfHeight then return nil end
    return { X = center.X, Y = center.Y, Z = center.Z + halfHeight }
end

local function g_Botmater_ESPFootLocation(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local bonePos = nil
    pcall(function()
        if character.GetBonePos then bonePos = character:GetBonePos("Root", ZERO_VEC3) end
    end)
    if not bonePos or (bonePos.X == 0 and bonePos.Y == 0 and bonePos.Z == 0) then
        pcall(function()
            if character.GetBonePos then bonePos = character:GetBonePos("root", ZERO_VEC3) end
        end)
    end
    if bonePos and (bonePos.X ~= 0 or bonePos.Y ~= 0 or bonePos.Z ~= 0) then
        return { X = bonePos.X, Y = bonePos.Y, Z = bonePos.Z }
    end
    local center, halfHeight = g_Botmater_ESPGetCharacterVerticalBounds(character)
    if not center or not halfHeight then return nil end
    return { X = center.X, Y = center.Y, Z = center.Z - halfHeight }
end

local function g_Botmater_ESPDestroyWidgetData(data)
    if not data then return end
    local widget = data.Widget or data.Container
    if g_Botmater_ESPValid(widget) then
        pcall(function() widget:RemoveFromParent() end)
        pcall(function() widget:ConditionalBeginDestroy() end)
    end
end

local function g_Botmater_ESPResetWidgets()
    for _, data in pairs(g_Botmater_ShotESP.Lines) do g_Botmater_ESPDestroyWidgetData(data) end
    for _, data in pairs(g_Botmater_ShotESP.Names) do g_Botmater_ESPDestroyWidgetData(data) end
    g_Botmater_ShotESP.Lines = {}
    g_Botmater_ShotESP.Names = {}
    g_Botmater_ShotESP.Canvas = nil
    g_Botmater_ShotESP.Enemies = {}
    g_Botmater_ShotESP._BotCache = nil
end

local function g_Botmater_ESPDestroyAllLines()
    for key, data in pairs(g_Botmater_ShotESP.Lines) do
        g_Botmater_ESPDestroyWidgetData(data)
        g_Botmater_ShotESP.Lines[key] = nil
    end
    g_Botmater_ShotESP.Lines = {}
end

local function g_Botmater_ESPDestroyAllNames()
    for key, data in pairs(g_Botmater_ShotESP.Names) do
        g_Botmater_ESPDestroyWidgetData(data)
        g_Botmater_ShotESP.Names[key] = nil
    end
    g_Botmater_ShotESP.Names = {}
end

local function g_Botmater_ESPGetCanvas()
    if g_Botmater_ESPValid(g_Botmater_ShotESP.Canvas) then return g_Botmater_ShotESP.Canvas end
    local root = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        if InGameUITools and InGameUITools.GetMainControlBaseUI then root = InGameUITools.GetMainControlBaseUI() end
    end)
    if not g_Botmater_ESPValid(root) then return nil end
    local canvas = nil
    pcall(function()
        if g_Botmater_ESPValid(root.CanvasPanel_0) then canvas = root.CanvasPanel_0
        elseif g_Botmater_ESPValid(root.CanvasPanel_42) then canvas = root.CanvasPanel_42 end
    end)
    if g_Botmater_ESPValid(canvas) then g_Botmater_ShotESP.Canvas = canvas return canvas end
    return nil
end

local function g_Botmater_ESPViewport(pc)
    local w, h = 1920.0, 1080.0
    pcall(function()
        if pc and pc.GetViewportSize then
            local v = g_Botmater_ESPV2(0,0)
            pc:GetViewportSize(v)
            if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
        end
    end)
    return w, h
end

local function g_Botmater_ESPGetCanvasLocalSize()
    local canvas = g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return nil, nil end
    local cw, ch = nil, nil
    pcall(function()
        local geo = canvas:GetCachedGeometry()
        if not geo then return end
        local size = nil
        if geo.GetLocalSize then size = geo:GetLocalSize()
        elseif SlateBlueprintLibrary and SlateBlueprintLibrary.GetLocalSize then size = SlateBlueprintLibrary.GetLocalSize(geo) end
        if size and tonumber(size.X) and tonumber(size.Y) and size.X > 1 and size.Y > 1 then
            cw, ch = tonumber(size.X), tonumber(size.Y)
        end
    end)
    return cw, ch
end

local function g_Botmater_ESPUpdateCanvasTransform(pc)
    local canvas = g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return false end
    local geo = nil
    pcall(function() geo = canvas:GetCachedGeometry() end)
    local calibrated = false
    pcall(function()
        if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal and geo then
            local p0 = SlateBlueprintLibrary.AbsoluteToLocal(geo, g_Botmater_ESPV2(0, 0))
            local p1 = SlateBlueprintLibrary.AbsoluteToLocal(geo, g_Botmater_ESPV2(100, 100))
            if p0 and p1
                and tonumber(p0.X) and tonumber(p0.Y)
                and tonumber(p1.X) and tonumber(p1.Y)
                and p1.X ~= p0.X and p1.Y ~= p0.Y then
                g_Botmater_ShotESP.CanvasScaleX = (p1.X - p0.X) / 100.0
                g_Botmater_ShotESP.CanvasScaleY = (p1.Y - p0.Y) / 100.0
                g_Botmater_ShotESP.CanvasOffsetX = p0.X
                g_Botmater_ShotESP.CanvasOffsetY = p0.Y
                calibrated = true
            end
        end
    end)
    if not calibrated then
        local scale = 1.0
        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
                local s = WidgetLayoutLibrary:GetViewportScale(pc)
                if tonumber(s) and s > 0 then scale = s end
            end
        end)
        g_Botmater_ShotESP.CanvasScaleX = 1.0 / scale
        g_Botmater_ShotESP.CanvasScaleY = 1.0 / scale
        g_Botmater_ShotESP.CanvasOffsetX = 0.0
        g_Botmater_ShotESP.CanvasOffsetY = 0.0
    end
    return true
end

local function g_Botmater_ESPProject(pc, worldLoc)
    if not pc or not worldLoc then return nil end
    local pix = g_Botmater_ESPV2(0, 0)
    local ok = false
    pcall(function()
        local res = pc:ProjectWorldLocationToScreen(worldLoc, pix, true)
        ok = (res == true or res == 1 or (pix and (pix.X ~= 0 or pix.Y ~= 0)))
    end)
    if not ok then return nil end
    local sx = g_Botmater_ShotESP.CanvasScaleX or 1.0
    local sy = g_Botmater_ShotESP.CanvasScaleY or 1.0
    local ox = g_Botmater_ShotESP.CanvasOffsetX or 0.0
    local oy = g_Botmater_ShotESP.CanvasOffsetY or 0.0
    return g_Botmater_ESPV2(pix.X * sx + ox, pix.Y * sy + oy)
end

local function g_Botmater_ESPSetFont(textWidget, size)
    if not g_Botmater_ESPValid(textWidget) then return end
    pcall(function()
        local fontAsset = g_Botmater_LoadRobotoFont()
        local f = nil
        if fontAsset and slua_isValid and slua_isValid(fontAsset) then
            f = fontAsset
        else
            f = textWidget.Font
        end
        if f then
            f.Size = size
            if f.OutlineSettings then
                pcall(function() f.OutlineSettings.OutlineSize = 0 end)
                pcall(function()
                    f.OutlineSettings.OutlineColor =
                        _G.FLinearColor and _G.FLinearColor(0, 0, 0, 1)
                end)
            end
            textWidget:SetFont(f)
        end
        pcall(function()
            if textWidget.SetShadowOffset then
                textWidget:SetShadowOffset(g_Botmater_ESPV2(0.0, 0.0))
            end
        end)
        pcall(function()
            if textWidget.SetShadowColorAndOpacity then
                textWidget:SetShadowColorAndOpacity(g_Botmater_ESPColor(0.0, 0.0, 0.0, 0.0))
            end
        end)
    end)
end

local function g_Botmater_ESPSetTextColor(textWidget, color)
    if not g_Botmater_ESPValid(textWidget) then return end
    pcall(function()
        if SlateColor then textWidget:SetColorAndOpacity(SlateColor(color))
        else textWidget:SetColorAndOpacity(color) end
    end)
end

local function g_Botmater_ESPCreateLine(color)
    local canvas = g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return nil end
    local border = nil
    pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", canvas) end)
    if not g_Botmater_ESPValid(border) then return nil end
    pcall(function()
        border:SetBrushColor(color)
        border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        border:SetRenderTransformPivot(g_Botmater_ESPV2(0.0, 0.5))
    end)
    local slot = nil
    pcall(function() slot = canvas:AddChildToCanvas(border) end)
    if not slot then g_Botmater_ESPDestroyWidgetData({Widget=border}) return nil end
    pcall(function() slot:SetAutoSize(false) slot:SetZOrder(30) end)
    return {Widget=border, Slot=slot, Visible=true}
end

local function g_Botmater_ESPDrawLine(data, x1, y1, x2, y2, thickness)
    if not data or not g_Botmater_ESPValid(data.Widget) or not data.Slot then return false end
    local dx, dy = x2-x1, y2-y1
    local lenSq = dx*dx + dy*dy
    if lenSq < 4 then
        if data.Visible ~= false then
            pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            data.Visible = false
        end
        return false
    end
    local len = math.sqrt(lenSq)
    local angle
    if math.atan2 then
        angle = math.atan2(dy, dx) * 57.29577951308232
    else
        angle = math.atan(dy, dx) * 57.29577951308232
    end
    pcall(function()
        data.Slot:SetPosition(g_Botmater_ESPV2(x1, y1 - thickness*0.5))
        data.Slot:SetSize(g_Botmater_ESPV2(len, thickness))
        data.Widget:SetRenderAngle(angle)
        if data.Visible ~= true then
            data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            data.Visible = true
        end
    end)
    return true
end

local function g_Botmater_ESPHide(data)
    if data and g_Botmater_ESPValid(data.Widget) then
        if data.Visible ~= false then
            pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            data.Visible = false
        end
    end
end

local function g_Botmater_ESPCreateNameTag(isBot)
    local canvas = g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return nil end

    local container = nil
    pcall(function() container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
    if not g_Botmater_ESPValid(container) then return nil end

    local nameText = nil
    pcall(function() nameText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
    local distanceText = nil
    pcall(function() distanceText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
    local healthBarBg = nil
    pcall(function() healthBarBg = CGame:NewObjectFromPath("/Script/UMG.Border", container) end)
    local healthBarFill = nil
    pcall(function() healthBarFill = CGame:NewObjectFromPath("/Script/UMG.Border", container) end)

    if not g_Botmater_ESPValid(nameText)
        or not g_Botmater_ESPValid(distanceText)
        or not g_Botmater_ESPValid(healthBarBg)
        or not g_Botmater_ESPValid(healthBarFill) then
        g_Botmater_ESPDestroyWidgetData({Widget=container})
        return nil
    end

    local BAR_W = 35.0
    local BAR_H = 3.0

    pcall(function()
        nameText:SetText("")
        distanceText:SetText("")
        nameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        distanceText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        if nameText.SetJustification then nameText:SetJustification(1) end
        if distanceText.SetJustification then distanceText:SetJustification(1) end
        healthBarBg:SetBrushColor(HEALTH_BG_DARK)
        healthBarBg:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        healthBarFill:SetBrushColor(HEALTH_FULL_GREEN)
        healthBarFill:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    g_Botmater_ESPSetTextColor(nameText, COLOR_TEXT_WHITE)
    g_Botmater_ESPSetTextColor(distanceText, CACHE_DIST_YELLOW)
    g_Botmater_ESPSetFont(nameText, tonumber(_G.g_Botmater_MasterShotESP.NameFontSize) or 9)
    g_Botmater_ESPSetFont(distanceText, tonumber(_G.g_Botmater_MasterShotESP.DistanceFontSize) or 10)

    local nameSlot, distSlot, bgSlot, fillSlot, mainSlot = nil, nil, nil, nil, nil
    pcall(function() bgSlot = container:AddChildToCanvas(healthBarBg) end)
    pcall(function() fillSlot = container:AddChildToCanvas(healthBarFill) end)
    pcall(function() nameSlot = container:AddChildToCanvas(nameText) end)
    pcall(function() distSlot = container:AddChildToCanvas(distanceText) end)
    pcall(function() mainSlot = canvas:AddChildToCanvas(container) end)

    if not nameSlot or not distSlot or not bgSlot or not fillSlot or not mainSlot then
        g_Botmater_ESPDestroyWidgetData({Widget=container})
        return nil
    end

    pcall(function()
        bgSlot:SetAutoSize(false)
        bgSlot:SetAlignment(g_Botmater_ESPV2(0.0, 0.0))
        bgSlot:SetSize(g_Botmater_ESPV2(BAR_W + 2.0, BAR_H + 2.0))
        bgSlot:SetZOrder(1)

        fillSlot:SetAutoSize(false)
        fillSlot:SetAlignment(g_Botmater_ESPV2(0.0, 0.0))
        fillSlot:SetSize(g_Botmater_ESPV2(BAR_W, BAR_H))
        fillSlot:SetZOrder(2)

        nameSlot:SetAutoSize(true)
        nameSlot:SetAlignment(g_Botmater_ESPV2(0.5, 0.5))
        nameSlot:SetZOrder(3)

        distSlot:SetAutoSize(true)
        distSlot:SetAlignment(g_Botmater_ESPV2(0.5, 0.5))
        distSlot:SetZOrder(3)

        mainSlot:SetAutoSize(false)
        mainSlot:SetZOrder(35)
    end)

    return {
        Widget         = container,
        HealthBg       = healthBarBg,
        HealthFill     = healthBarFill,
        Text           = nameText,
        DistanceText   = distanceText,
        NameSlot       = nameSlot,
        DistSlot       = distSlot,
        HealthBgSlot   = bgSlot,
        HealthFillSlot = fillSlot,
        Slot           = mainSlot,
        IsBot          = isBot,
        Visible        = true,
        LastHealthPct  = -1,
    }
end

local function g_Botmater_ESPUpdateNameTag(key, character, nameScreen, healthScreen, distScreen, isBot, distance, healthPct)
    local showName     = _G.ESPNameHealthEnabled == true
    local showDistance = _G.ESPDistanceEnabled == true

    local data = g_Botmater_ShotESP.Names[key]

    if not nameScreen then
        if data and g_Botmater_ESPValid(data.Widget) then
            if data.Visible ~= false then
                pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                data.Visible = false
            end
        end
        return
    end

    local name = nil
    if isBot then
        name = "BOT"
    else
        name = data and data.CachedName or nil
        if not name then
            name = g_Botmater_ESPResolvePlayerName(character)
            if data and name then data.CachedName = name end
        end
        if not name then name = "UNKNOWN" end
    end

    if not data or not g_Botmater_ESPValid(data.Widget) then
        g_Botmater_ESPDestroyWidgetData(data)
        data = g_Botmater_ESPCreateNameTag(isBot)
        g_Botmater_ShotESP.Names[key] = data
        if data then data.CachedName = name end
    end
    if not data then return end

    local BAR_W = 35.0
    local BAR_H = 3.0

    local hp = tonumber(healthPct) or 1.0
    if hp < 0 then hp = 0 end
    if hp > 1 then hp = 1 end

    local nameX = nameScreen.X
    local nameY = nameScreen.Y - 12.0

    local healthX = nameX - BAR_W * 0.5
    local healthY = nameY - BAR_H * 1.5
    if healthScreen then
        healthX = healthScreen.X - BAR_W * 0.5
        healthY = healthScreen.Y - BAR_H * 1.5
    end

    local distX = nameX
    local distY = nameY + 12.0
    if distScreen then
        distX = distScreen.X
        distY = distScreen.Y + 7.0
    end

    local shownName = showName and name or ""
    local distLabel = showDistance and g_Botmater_FormatDistLabel(distance) or ""

    pcall(function()
        if data.LastName ~= shownName then
            data.Text:SetText(shownName)
            data.LastName = shownName
        end
        if data.LastDist ~= distLabel then
            data.DistanceText:SetText(distLabel)
            data.LastDist = distLabel
        end
    end)

    if data.LastHealthPct ~= hp then
        data.LastHealthPct = hp
        local hpColor = g_Botmater_ESPGetHealthColor(hp)
        pcall(function()
            if data.HealthFill and g_Botmater_ESPValid(data.HealthFill) then
                data.HealthFill:SetBrushColor(hpColor)
            end
        end)
    end

    pcall(function()
        data.NameSlot:SetPosition(g_Botmater_ESPV2(nameX, nameY))
        data.HealthBgSlot:SetPosition(g_Botmater_ESPV2(healthX - 1.0, healthY - 1.0))
        data.HealthBgSlot:SetSize(g_Botmater_ESPV2(BAR_W + 2.0, BAR_H + 2.0))
        data.HealthFillSlot:SetPosition(g_Botmater_ESPV2(healthX, healthY))
        data.HealthFillSlot:SetSize(g_Botmater_ESPV2(BAR_W * hp, BAR_H))
        data.DistSlot:SetPosition(g_Botmater_ESPV2(distX, distY))
    end)

    pcall(function()
        data.Text:SetWidgetVisibility(showName and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed)
        data.DistanceText:SetWidgetVisibility(showDistance and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed)
    end)

    if data.Visible ~= true then
        pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        data.Visible = true
    end

    data.LineEndX = healthX + BAR_W * 0.5
    data.LineEndY = healthY
end

local function g_Botmater_ESPScanEnemies()
    local pc = g_Botmater_ESPGetController()
    local me = g_Botmater_ESPGetLocalCharacter()
    if not pc or not me then
        g_Botmater_ShotESP.Enemies = {}
        g_Botmater_ShotESP.RealCount = 0
        g_Botmater_ShotESP.BotCount = 0
        return nil
    end
    local myLoc = g_Botmater_ESPActorLocation(me)
    if not myLoc then
        g_Botmater_ShotESP.Enemies = {}
        g_Botmater_ShotESP.RealCount = 0
        g_Botmater_ShotESP.BotCount = 0
        return pc
    end
    local myTeam = g_Botmater_ESPGetTeamID(me)
    local myTeamStr = (myTeam ~= nil) and tostring(myTeam) or nil

    local list = {}
    local realCount = 0
    local botCount = 0
    local pawns = nil
    pcall(function() if Game and Game.GetAllPlayerPawns then pawns = Game:GetAllPlayerPawns() end end)
    if pawns then
        for _, character in pairs(pawns) do
            if g_Botmater_ESPValid(character) and character ~= me and g_Botmater_ESPIsAlive(character) then
                local team = g_Botmater_ESPGetTeamID(character)
                local sameTeam = false
                if myTeam ~= nil and team ~= nil then
                    if team == myTeam then
                        sameTeam = true
                    else
                        sameTeam = (tostring(team) == myTeamStr)
                    end
                end
                if not sameTeam then
                    local loc = g_Botmater_ESPActorLocation(character)
                    local dist = g_Botmater_ESPDistanceMeters(myLoc, loc)
                    if dist <= (tonumber(_G.g_Botmater_MasterShotESP.MaxRangeMeters) or 300.0) then
                        local isBot = g_Botmater_ESPIsBot(character)
                        local k = g_Botmater_ESPGetPlayerKey(character)
                        if k then
                            list[#list+1] = {Character=character, Key=k, IsBot=isBot, Distance=dist}
                            if isBot then botCount = botCount + 1 else realCount = realCount + 1 end
                        end
                    end
                end
            end
        end
    end
    local maxRendered = math.max(1, math.floor(tonumber(_G.g_Botmater_MasterShotESP.MaxRendered) or 10))
    if #list > maxRendered then
        table.sort(list, function(a,b) return (a.Distance or 99999) < (b.Distance or 99999) end)
    end
    g_Botmater_ShotESP.Enemies = list
    g_Botmater_ShotESP.RealCount = realCount
    g_Botmater_ShotESP.BotCount = botCount
    return pc
end

local function g_Botmater_ESPPrune(active)
    for key, data in pairs(g_Botmater_ShotESP.Lines) do
        if not active[key] then g_Botmater_ESPDestroyWidgetData(data) g_Botmater_ShotESP.Lines[key] = nil end
    end
    for key, data in pairs(g_Botmater_ShotESP.Names) do
        if not active[key] then g_Botmater_ESPDestroyWidgetData(data) g_Botmater_ShotESP.Names[key] = nil end
    end
    if g_Botmater_ShotESP._BotCache then
        local activeKeys = {}
        for _, item in ipairs(g_Botmater_ShotESP.Enemies or {}) do
            if item.Key then activeKeys[item.Key] = true end
        end
        for k in pairs(g_Botmater_ShotESP._BotCache) do
            if not activeKeys[k] then
                g_Botmater_ShotESP._BotCache[k] = nil
            end
        end
    end
end

-- Enemy Counter (independent)
local g_Botmater_EnemyCounter = {
    Container = nil, Slot = nil, BG = nil, BGSlot = nil, Text = nil, TextSlot = nil,
    FontSize = 12, ScreenY = 50.0, BG_Height = 30.0, Padding = 20.0, CharWidth = 12.0,
    _LastText = nil, _LastWidth = nil, _LastX = nil, _LastY = nil, _LastHasEnemies = nil,
    CanvasCenterX = 0.0, CanvasCenterY = 0.0,
    TickRegistered = false,
}

local function g_Botmater_CounterCreate()
    if g_Botmater_EnemyCounter.Container and g_Botmater_ESPValid(g_Botmater_EnemyCounter.Container) then
        return true
    end
    local canvas = g_Botmater_ESPGetCanvas()
    if not canvas or not g_Botmater_ESPValid(canvas) then return false end

    local Container, BG, Text = nil, nil, nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
    if not g_Botmater_ESPValid(Container) then return false end
    pcall(function() BG = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    pcall(function() Text = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)

    if not g_Botmater_ESPValid(BG) or not g_Botmater_ESPValid(Text) then
        pcall(function() Container:ConditionalBeginDestroy() end)
        return false
    end

    pcall(function()
        BG:SetBrushColor(CACHE_COUNTER_BG_YELLOW)
        BG:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    local bgSlot = nil
    pcall(function() bgSlot = Container:AddChildToCanvas(BG) end)
    if not bgSlot then
        pcall(function() Container:ConditionalBeginDestroy() end)
        return false
    end
    pcall(function()
        bgSlot:SetAutoSize(false)
        bgSlot:SetAlignment(g_Botmater_ESPV2(0.0, 0.0))
        bgSlot:SetPosition(g_Botmater_ESPV2(0, 0))
        bgSlot:SetSize(g_Botmater_ESPV2(100, g_Botmater_EnemyCounter.BG_Height))
        bgSlot:SetZOrder(0)
    end)

    pcall(function()
        Text:SetText("CLEAR")
        local fontAsset = g_Botmater_LoadRobotoFont()
        if fontAsset and slua_isValid and slua_isValid(fontAsset) then
            fontAsset.Size = g_Botmater_EnemyCounter.FontSize
            Text:SetFont(fontAsset)
        elseif Text.Font then
            local f = Text.Font
            f.Size = g_Botmater_EnemyCounter.FontSize
            Text:SetFont(f)
        end
        if Text.SetJustification then Text:SetJustification(1) end
        Text:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    if SlateColor then
        pcall(function() Text:SetColorAndOpacity(SlateColor(CACHE_COUNTER_TEXT_BLACK)) end)
    else
        pcall(function() Text:SetColorAndOpacity(CACHE_COUNTER_TEXT_BLACK) end)
    end

    local textSlot = nil
    pcall(function() textSlot = Container:AddChildToCanvas(Text) end)
    if textSlot then
        pcall(function()
            textSlot:SetAutoSize(true)
            textSlot:SetAlignment(g_Botmater_ESPV2(0.5, 0.5))
            textSlot:SetPosition(g_Botmater_ESPV2(50, g_Botmater_EnemyCounter.BG_Height * 0.5))
            textSlot:SetZOrder(2)
        end)
    end

    local mainSlot = nil
    pcall(function() mainSlot = canvas:AddChildToCanvas(Container) end)
    if not mainSlot then
        pcall(function() Container:ConditionalBeginDestroy() end)
        return false
    end
    pcall(function()
        mainSlot:SetAutoSize(false)
        mainSlot:SetSize(g_Botmater_ESPV2(100, g_Botmater_EnemyCounter.BG_Height))
        mainSlot:SetZOrder(50)
    end)

    g_Botmater_EnemyCounter.Container = Container
    g_Botmater_EnemyCounter.Slot = mainSlot
    g_Botmater_EnemyCounter.BG = BG
    g_Botmater_EnemyCounter.BGSlot = bgSlot
    g_Botmater_EnemyCounter.Text = Text
    g_Botmater_EnemyCounter.TextSlot = textSlot
    g_Botmater_EnemyCounter._LastText = nil
    g_Botmater_EnemyCounter._LastWidth = nil
    g_Botmater_EnemyCounter._LastX = nil
    g_Botmater_EnemyCounter._LastY = nil
    g_Botmater_EnemyCounter._LastHasEnemies = nil

    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    return true
end

local function g_Botmater_CounterUpdatePosition(pc)
    local slot = g_Botmater_EnemyCounter.Slot
    if not slot or not g_Botmater_ESPValid(slot) then return end

    local canvasW, canvasH = g_Botmater_ESPGetCanvasLocalSize()
    if not canvasW or not canvasH then
        local vw, vh = g_Botmater_ESPViewport(pc)
        if not vw or vw <= 200 then return end
        local sx = g_Botmater_ShotESP.CanvasScaleX or 1.0
        local sy = g_Botmater_ShotESP.CanvasScaleY or 1.0
        local ox = g_Botmater_ShotESP.CanvasOffsetX or 0.0
        local oy = g_Botmater_ShotESP.CanvasOffsetY or 0.0
        canvasW = (vw * sx) - ox
        canvasH = (vh * sy) - oy
    end
    if not canvasW or not canvasH then return end

    local screenY = g_Botmater_EnemyCounter.ScreenY
    local sy = g_Botmater_ShotESP.CanvasScaleY or 1.0
    local oy = g_Botmater_ShotESP.CanvasOffsetY or 0.0
    local canvasY = screenY * sy + oy

    local bgH = g_Botmater_EnemyCounter.BG_Height
    local bgW = g_Botmater_EnemyCounter._LastWidth or 100.0

    local canvasCenterX = canvasW * 0.5
    local x = canvasCenterX - bgW * 0.5
    local y = canvasY - bgH * 0.5

    g_Botmater_EnemyCounter.CanvasCenterX = canvasCenterX
    g_Botmater_EnemyCounter.CanvasCenterY = canvasY + bgH * 0.5

    local lx, ly = g_Botmater_EnemyCounter._LastX, g_Botmater_EnemyCounter._LastY
    if lx ~= nil and ly ~= nil and math.abs(lx - x) < 0.1 and math.abs(ly - y) < 0.1 then return end
    g_Botmater_EnemyCounter._LastX = x
    g_Botmater_EnemyCounter._LastY = y
    pcall(function() slot:SetPosition(g_Botmater_ESPV2(x, y)) end)
end

local function g_Botmater_GetLineOrigin(pc)
    if not g_Botmater_EnemyCounter.Container or not g_Botmater_ESPValid(g_Botmater_EnemyCounter.Container) then
        g_Botmater_CounterCreate()
    end
    g_Botmater_CounterUpdatePosition(pc)
    local sy = g_Botmater_ShotESP.CanvasScaleY or 1.0
    local oy = g_Botmater_ShotESP.CanvasOffsetY or 0.0
    local originScreenY = 60.0
    local originCanvasY = originScreenY * sy + oy
    return g_Botmater_ESPV2(g_Botmater_EnemyCounter.CanvasCenterX, originCanvasY)
end

local function g_Botmater_CounterSetCounts(realCount, botCount)
    realCount = tonumber(realCount) or 0
    botCount = tonumber(botCount) or 0

    local hasEnemies = (realCount > 0) or (botCount > 0)
    local text = hasEnemies and string.format("%d  |  %d", realCount, botCount) or "CLEAR"

    local data = g_Botmater_EnemyCounter
    if not data.Container or not g_Botmater_ESPValid(data.Container) then return end

    local bgColor = hasEnemies and CACHE_COUNTER_BG_GREEN or CACHE_COUNTER_BG_YELLOW
    local textColor = hasEnemies and CACHE_COUNTER_TEXT_MAGENTA or CACHE_COUNTER_TEXT_BLACK
    local bgW = (#text) * data.CharWidth + data.Padding * 2
    local bgH = data.BG_Height

    if data._LastHasEnemies ~= hasEnemies then
        data._LastHasEnemies = hasEnemies
        pcall(function()
            if data.BG and g_Botmater_ESPValid(data.BG) then
                data.BG:SetBrushColor(bgColor)
            end
        end)
        pcall(function()
            if data.Text and g_Botmater_ESPValid(data.Text) then
                if SlateColor then
                    data.Text:SetColorAndOpacity(SlateColor(textColor))
                else
                    data.Text:SetColorAndOpacity(textColor)
                end
            end
        end)
    end

    if data._LastText ~= text then
        data._LastText = text
        pcall(function()
            if data.Text and g_Botmater_ESPValid(data.Text) then
                data.Text:SetText(text)
            end
        end)
    end

    if data._LastWidth ~= bgW then
        data._LastWidth = bgW
        pcall(function()
            if data.BGSlot then data.BGSlot:SetSize(g_Botmater_ESPV2(bgW, bgH)) end
            if data.Slot then data.Slot:SetSize(g_Botmater_ESPV2(bgW, bgH)) end
            if data.TextSlot then data.TextSlot:SetPosition(g_Botmater_ESPV2(bgW * 0.5, bgH * 0.5)) end
        end)
    end
end

local function g_Botmater_CounterStart(pc)
    if not g_Botmater_CounterCreate() then return end
    pcall(function()
        g_Botmater_EnemyCounter.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    g_Botmater_CounterUpdatePosition(pc)
end

local function g_Botmater_CounterStop()
    local data = g_Botmater_EnemyCounter
    local container = data.Container
    data.Container = nil
    data.Slot = nil
    data.BG = nil
    data.BGSlot = nil
    data.Text = nil
    data.TextSlot = nil
    data._LastText = nil
    data._LastWidth = nil
    data._LastX = nil
    data._LastY = nil
    data._LastHasEnemies = nil
    data.CanvasCenterX = 0.0
    data.CanvasCenterY = 0.0
    if g_Botmater_ESPValid(container) then
        pcall(function() container:RemoveFromParent() end)
        pcall(function() container:ConditionalBeginDestroy() end)
    end
end

local function g_Botmater_CounterTick()
    if not g_Botmater_EnemyCounter.TickRegistered then return end

    pcall(function()
        local canvas = g_Botmater_ESPGetCanvas()
        if not canvas then return end
        local now = g_Botmater_ESPNow()
        local pc = g_Botmater_ESPGetController()
        if not pc then return end

        if (now - g_Botmater_ShotESP.LastScanClock) >= (tonumber(_G.g_Botmater_MasterShotESP.ScanInterval) or 0.05) then
            g_Botmater_ESPScanEnemies()
            g_Botmater_ShotESP.LastScanClock = now
        end

        if (now - (g_Botmater_ShotESP.LastTransformClock or -999.0))
            >= (tonumber(_G.g_Botmater_MasterShotESP.TransformInterval) or 0.033) then
            g_Botmater_ESPUpdateCanvasTransform(pc)
            g_Botmater_ShotESP.LastTransformClock = now
        end

        pcall(g_Botmater_CounterStart, pc)
        pcall(g_Botmater_CounterSetCounts, g_Botmater_ShotESP.RealCount or 0, g_Botmater_ShotESP.BotCount or 0)
        pcall(g_Botmater_CounterUpdatePosition, pc)
    end)

    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce and g_Botmater_EnemyCounter.TickRegistered then
        ticker.AddTimerOnce(
            tonumber(_G.g_Botmater_MasterShotESP.UpdateInterval) or 0.016,
            g_Botmater_CounterTick
        )
    else
        g_Botmater_EnemyCounter.TickRegistered = false
    end
end

local function g_Botmater_CounterAutoStart()
    if g_Botmater_EnemyCounter.TickRegistered then return end
    g_Botmater_EnemyCounter.TickRegistered = true
    g_Botmater_CounterTick()
    print("[COUNTER] Auto-start")
end

local function g_Botmater_ESPUpdate()
    local anyFeature = _G.ESPLineEnabled or _G.ESPNameHealthEnabled or _G.ESPDistanceEnabled
    if not anyFeature then return end
    if not _G.g_Botmater_MasterShotESP.Enabled then return end

    local world = g_Botmater_ESPWorld()
    if world ~= g_Botmater_ShotESP.LastWorld then
        g_Botmater_ESPResetWidgets()
        g_Botmater_ShotESP.LastWorld = world
        g_Botmater_ShotESP.LastScanClock = -999.0
        g_Botmater_ShotESP.LastTransformClock = -999.0
    end

    local canvas = g_Botmater_ESPGetCanvas()
    if not canvas then return end

    local now = g_Botmater_ESPNow()
    local pc = g_Botmater_ESPGetController()
    if (now - g_Botmater_ShotESP.LastScanClock) >= (tonumber(_G.g_Botmater_MasterShotESP.ScanInterval) or 0.05) then
        pc = g_Botmater_ESPScanEnemies()
        g_Botmater_ShotESP.LastScanClock = now
    end
    pc = pc or g_Botmater_ESPGetController()
    if not pc then return end

    if (now - (g_Botmater_ShotESP.LastTransformClock or -999.0))
        >= (tonumber(_G.g_Botmater_MasterShotESP.TransformInterval) or 0.033) then
        g_Botmater_ESPUpdateCanvasTransform(pc)
        g_Botmater_ShotESP.LastTransformClock = now
    end

    local originCenter = g_Botmater_GetLineOrigin(pc)
    local active = g_Botmater_ActiveSet
    for k in pairs(active) do active[k] = nil end

    local masterCfg = _G.g_Botmater_MasterShotESP
    local maxRendered = math.max(1, math.floor(tonumber(masterCfg.MaxRendered) or 10))
    local tracerThickness = tonumber(masterCfg.TracerThickness) or 1.0
    local enemies = g_Botmater_ShotESP.Enemies

    for i = 1, #enemies do
        if i > maxRendered then break end
        local item = enemies[i]
        local c = item.Character
        local key = item.Key
        local isBot = item.IsBot
        if key and g_Botmater_ESPValid(c) and g_Botmater_ESPIsAlive(c) then
            local headBone = g_Botmater_ESPHeadLocation(c)
            local rootBone = g_Botmater_ESPFootLocation(c)

            local nameScreen, healthScreen, distScreen = nil, nil, nil
            if headBone then
                nameScreen   = g_Botmater_ESPProject(pc, { X = headBone.X, Y = headBone.Y, Z = headBone.Z + 40.0 })
                healthScreen = g_Botmater_ESPProject(pc, { X = headBone.X, Y = headBone.Y, Z = headBone.Z + 25.0 })
            end
            if rootBone then
                distScreen   = g_Botmater_ESPProject(pc, { X = rootBone.X, Y = rootBone.Y, Z = rootBone.Z - 20.0 })
            end

            if nameScreen then
                active[key] = true
                local mainColor = g_Botmater_ESPGetColors(isBot)
                local healthPct = g_Botmater_ESPGetHealthPct(c)

                if _G.ESPNameHealthEnabled or _G.ESPDistanceEnabled then
                    g_Botmater_ESPUpdateNameTag(key, c, nameScreen, healthScreen, distScreen, isBot, item.Distance, healthPct)
                end

                local line = g_Botmater_ShotESP.Lines[key]
                if _G.ESPLineEnabled and (not line or not g_Botmater_ESPValid(line.Widget)) then
                    g_Botmater_ESPDestroyWidgetData(line)
                    line = g_Botmater_ESPCreateLine(mainColor)
                    g_Botmater_ShotESP.Lines[key] = line
                end
                if _G.ESPLineEnabled and line then
                    local targetX = nameScreen.X
                    local targetY = nameScreen.Y - 12.0
                    if healthScreen then
                        targetX = healthScreen.X
                        targetY = healthScreen.Y - 4.5
                    end
                    g_Botmater_ESPDrawLine(line, originCenter.X, originCenter.Y, targetX, targetY, tracerThickness)
                elseif line then g_Botmater_ESPHide(line) end
            end
        end
    end
    g_Botmater_ESPPrune(active)
end

local function g_Botmater_ESPTick()
    local anyFeature = _G.ESPLineEnabled or _G.ESPNameHealthEnabled or _G.ESPDistanceEnabled
    if not anyFeature then
        g_Botmater_ShotESP.Running = false
        g_Botmater_ShotESP.TickRegistered = false
        return
    end

    pcall(g_Botmater_ESPUpdate)

    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce and g_Botmater_ShotESP.TickRegistered then
        ticker.AddTimerOnce(
            tonumber(_G.g_Botmater_MasterShotESP.UpdateInterval) or 0.016,
            g_Botmater_ESPTick
        )
    else
        g_Botmater_ShotESP.Running = false
        g_Botmater_ShotESP.TickRegistered = false
    end
end

local function g_Botmater_ESPStartTick()
    if g_Botmater_ShotESP.TickRegistered then return end
    g_Botmater_ShotESP.Running = true
    g_Botmater_ShotESP.TickRegistered = true
    g_Botmater_ESPTick()
end

-- Per-feature public control
function _G.ESPLineOn()
    if _G.ESPLineEnabled == true and g_Botmater_ShotESP.TickRegistered then return end
    _G.ESPLineEnabled = true
    g_Botmater_ShotESP.LastWorld = nil
    g_Botmater_ESPStartTick()
    print("[ESP] Line ON")
end
function _G.ESPLineOff()
    _G.ESPLineEnabled = false
    pcall(g_Botmater_ESPDestroyAllLines)
    if not (_G.ESPNameHealthEnabled or _G.ESPDistanceEnabled) then
        g_Botmater_ShotESP.Enemies = {}
        g_Botmater_ShotESP.RealCount = 0
        g_Botmater_ShotESP.BotCount = 0
        g_Botmater_ShotESP._BotCache = nil
        g_Botmater_ShotESP.LastWorld = nil
        g_Botmater_ShotESP.LastScanClock = -999.0
        g_Botmater_ShotESP.LastTransformClock = -999.0
        g_Botmater_ShotESP.Canvas = nil
        g_Botmater_ShotESP.CanvasScaleX = 1.0
        g_Botmater_ShotESP.CanvasScaleY = 1.0
        g_Botmater_ShotESP.CanvasOffsetX = 0.0
        g_Botmater_ShotESP.CanvasOffsetY = 0.0
        g_Botmater_ShotESP.Running = false
        g_Botmater_ShotESP.TickRegistered = false
        g_Botmater_DistLabelCache = {}
        for k in pairs(g_Botmater_ActiveSet) do g_Botmater_ActiveSet[k] = nil end
    end
    print("[ESP] Line OFF")
end
function _G.ESPLineToggle()
    if _G.ESPLineEnabled then _G.ESPLineOff() else _G.ESPLineOn() end
    return _G.ESPLineEnabled
end

function _G.ESPNameHealthOn()
    if _G.ESPNameHealthEnabled == true and g_Botmater_ShotESP.TickRegistered then return end
    _G.ESPNameHealthEnabled = true
    g_Botmater_ShotESP.LastWorld = nil
    g_Botmater_ESPStartTick()
    print("[ESP] Name&Health ON")
end
function _G.ESPNameHealthOff()
    _G.ESPNameHealthEnabled = false
    pcall(g_Botmater_ESPDestroyAllNames)
    if not (_G.ESPLineEnabled or _G.ESPDistanceEnabled) then
        g_Botmater_ShotESP.Enemies = {}
        g_Botmater_ShotESP.RealCount = 0
        g_Botmater_ShotESP.BotCount = 0
        g_Botmater_ShotESP._BotCache = nil
        g_Botmater_ShotESP.LastWorld = nil
        g_Botmater_ShotESP.LastScanClock = -999.0
        g_Botmater_ShotESP.LastTransformClock = -999.0
        g_Botmater_ShotESP.Canvas = nil
        g_Botmater_ShotESP.CanvasScaleX = 1.0
        g_Botmater_ShotESP.CanvasScaleY = 1.0
        g_Botmater_ShotESP.CanvasOffsetX = 0.0
        g_Botmater_ShotESP.CanvasOffsetY = 0.0
        g_Botmater_ShotESP.Running = false
        g_Botmater_ShotESP.TickRegistered = false
        g_Botmater_DistLabelCache = {}
        for k in pairs(g_Botmater_ActiveSet) do g_Botmater_ActiveSet[k] = nil end
    end
    print("[ESP] Name&Health OFF")
end
function _G.ESPNameHealthToggle()
    if _G.ESPNameHealthEnabled then _G.ESPNameHealthOff() else _G.ESPNameHealthOn() end
    return _G.ESPNameHealthEnabled
end

function _G.ESPDistanceOn()
    if _G.ESPDistanceEnabled == true and g_Botmater_ShotESP.TickRegistered then return end
    _G.ESPDistanceEnabled = true
    g_Botmater_ShotESP.LastWorld = nil
    g_Botmater_ESPStartTick()
    print("[ESP] Distance ON")
end
function _G.ESPDistanceOff()
    _G.ESPDistanceEnabled = false
    pcall(g_Botmater_ESPDestroyAllNames)
    if not (_G.ESPLineEnabled or _G.ESPNameHealthEnabled) then
        g_Botmater_ShotESP.Enemies = {}
        g_Botmater_ShotESP.RealCount = 0
        g_Botmater_ShotESP.BotCount = 0
        g_Botmater_ShotESP._BotCache = nil
        g_Botmater_ShotESP.LastWorld = nil
        g_Botmater_ShotESP.LastScanClock = -999.0
        g_Botmater_ShotESP.LastTransformClock = -999.0
        g_Botmater_ShotESP.Canvas = nil
        g_Botmater_ShotESP.CanvasScaleX = 1.0
        g_Botmater_ShotESP.CanvasScaleY = 1.0
        g_Botmater_ShotESP.CanvasOffsetX = 0.0
        g_Botmater_ShotESP.CanvasOffsetY = 0.0
        g_Botmater_ShotESP.Running = false
        g_Botmater_ShotESP.TickRegistered = false
        g_Botmater_DistLabelCache = {}
        for k in pairs(g_Botmater_ActiveSet) do g_Botmater_ActiveSet[k] = nil end
    end
    print("[ESP] Distance OFF")
end
function _G.ESPDistanceToggle()
    if _G.ESPDistanceEnabled then _G.ESPDistanceOff() else _G.ESPDistanceOn() end
    return _G.ESPDistanceEnabled
end


-- ============================================================
-- STEP 6: BOTMASTER MENU (PBC + ESP Line/NameHealth/Distance + Aimbot)
-- ============================================================
local function g_botmaster_InitMenu()
    if _G._BYPASS_DONE ~= true then
        print("[BOTMASTER] Menu load blocked — waiting for bypass")
        return
    end

    if _G.BotmasterMenuInitialized == "BOTMASTER_MENU_V2" then return end
    _G.BotmasterMenuInitialized = "BOTMASTER_MENU_V2"

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog    = require("client.logic.NewSetting.SettingCatalog")
    local AliasMap          = require("client.slua.umg.NewSetting.Item.AliasMap")

    local Stack = {
        {
            Key  = "BotmasterESP",
            UI   = AliasMap.Switcher,
            Text = "Botmaster ESP (PBC)",
            GetFunc = function()
                if _G.PBCEnabled == nil then _G.PBCEnabled = false end
                return _G.PBCEnabled
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.PBCOn  then pcall(_G.PBCOn)  end
                else
                    if _G.PBCOff then pcall(_G.PBCOff) end
                end
                return true
            end
        },
        {
            Key  = "BotmasterESPLine",
            UI   = AliasMap.Switcher,
            Text = "Player ESP Line",
            GetFunc = function()
                if _G.ESPLineEnabled == nil then _G.ESPLineEnabled = false end
                return _G.ESPLineEnabled
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.ESPLineOn then pcall(_G.ESPLineOn) end
                else
                    if _G.ESPLineOff then pcall(_G.ESPLineOff) end
                end
                return true
            end
        },
        {
            Key  = "BotmasterESPNameHealth",
            UI   = AliasMap.Switcher,
            Text = "Player ESP Name & Health",
            GetFunc = function()
                if _G.ESPNameHealthEnabled == nil then _G.ESPNameHealthEnabled = false end
                return _G.ESPNameHealthEnabled
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.ESPNameHealthOn then pcall(_G.ESPNameHealthOn) end
                else
                    if _G.ESPNameHealthOff then pcall(_G.ESPNameHealthOff) end
                end
                return true
            end
        },
        {
            Key  = "BotmasterESPDistance",
            UI   = AliasMap.Switcher,
            Text = "Player ESP Distance",
            GetFunc = function()
                if _G.ESPDistanceEnabled == nil then _G.ESPDistanceEnabled = false end
                return _G.ESPDistanceEnabled
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.ESPDistanceOn then pcall(_G.ESPDistanceOn) end
                else
                    if _G.ESPDistanceOff then pcall(_G.ESPDistanceOff) end
                end
                return true
            end
        },
        {
            Key  = "BotmasterAimbot",
            UI   = AliasMap.Switcher,
            Text = "Botmaster Aimbot",
            GetFunc = function()
                if _G.AimbotEnabled == nil then _G.AimbotEnabled = false end
                return _G.AimbotEnabled
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.AimbotOn  then pcall(_G.AimbotOn)  end
                else
                    if _G.AimbotOff then pcall(_G.AimbotOff) end
                end
                return true
            end
        }
    }

    SettingPageDefine.BotmasterMenu = {
        Key     = "BotmasterMenu",
        Text    = "BOTMASTER",
        UIKey   = "Setting_Page_Privacy",
        Category = {
            { Key = "Cat_Botmaster", Text = "Botmaster", Stack = Stack }
        }
    }

    local foundPage = false
    for i, page in ipairs(SettingCatalog) do
        if type(page) == "table" and page.Key == "BotmasterMenu" then
            SettingCatalog[i] = SettingPageDefine.BotmasterMenu
            foundPage = true
            break
        end
    end
    if not foundPage then
        table.insert(SettingCatalog, 1, SettingPageDefine.BotmasterMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._BotmasterMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...)
            if config and config.keyName then
                local lowerKeyName = string.lower(config.keyName)
                if string.find(lowerKeyName, "setting_main") and not string.find(lowerKeyName, "custom") then
                    local catalog = args[1]
                    if type(catalog) == "table" and catalog[1] and type(catalog[1]) == "table" and catalog[1].Key then
                        local hasBotmaster = false
                        for _, page in ipairs(catalog) do
                            if type(page) == "table" and page.Key == "BotmasterMenu" then
                                hasBotmaster = true
                                break
                            end
                        end
                        if not hasBotmaster then
                            table.insert(catalog, 1, SettingPageDefine.BotmasterMenu)
                        end
                    end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._BotmasterMenuHooked = true
    end

    print("[BOTMASTER] Menu loaded (PBC + 3 ESP + Aimbot)")
end

_G.InitBotmasterMenu = g_botmaster_InitMenu


-- ============================================================
-- STEP 7: BYPASS INTEGRATION (Player Detection Gate + Anti-Cheat Spoof)
-- ============================================================
if not table.contains then
    function table.contains(t, v)
        for _, x in ipairs(t) do
            if x == v then return true end
        end
        return false
    end
end

local okMark, InGameMarkTools = pcall(require, "GameLua.Mod.BaseMod.Common.InGameMarkTools")
if not okMark then InGameMarkTools = nil end

local _BypassGameplayData = nil
pcall(function()
    _BypassGameplayData = require("GameLua.GameCore.Data.GameplayData")
end)

-- ---- Player detection gate ----
local function Bypass_IsEnemyDetected()
    if not _BypassGameplayData or not _BypassGameplayData.GetPlayerCharacter then
        return false
    end

    local me = _BypassGameplayData.GetPlayerCharacter()
    if not slua.isValid(me) then return false end

    local pawns = nil
    pcall(function()
        if Game and Game.GetAllPlayerPawns then
            pawns = Game:GetAllPlayerPawns()
        end
    end)
    if not pawns then return false end

    local myTeam = me.TeamID
    if myTeam == nil then return false end

    for _, c in pairs(pawns) do
        if slua.isValid(c) and c ~= me then
            if c.Health and c.Health > 0 then
                if c.TeamID ~= nil and myTeam ~= c.TeamID then
                    return true
                end
            end
        end
    end
    return false
end

_G.IsEnemyDetected = Bypass_IsEnemyDetected

-- ---- LAYER: Ultimate Wallhack / ESP detection bypass ----
local function InstallUltimateWallhackBypass()
    if _G.__ULTIMATE_WH_BYPASS_LOADED then return end

    local nop = function() end

    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end

    ---------- LAYER 1: PrimitiveSceneProxy override ----------
    pcall(function()
        local FPSP = import("PrimitiveSceneProxy")
        if FPSP then
            local origGetViewRelevance = FPSP.GetViewRelevance
            FPSP.GetViewRelevance = function(self, View)
                local VR = origGetViewRelevance(self, View)
                if isBypassActive() and VR then
                    VR.bRenderCustomDepth = false
                    VR.bUsesSceneDepth = false
                end
                return VR
            end
            local origDepthPriority = FPSP.GetDepthPriorityGroup
            FPSP.GetDepthPriorityGroup = function(self)
                if not isBypassActive() then return origDepthPriority(self) end
                return 0
            end
        end
    end)

    ---------- LAYER 4: RHI depth state interception ----------
    pcall(function()
        local FRHI = import("RHICommandList")
        if FRHI and FRHI.SetDepthState then
            local origSetDepth = FRHI.SetDepthState
            FRHI.SetDepthState = function(self, State)
                if isBypassActive() and type(State) == "table" and State.DepthEnable ~= nil then
                    State.DepthEnable = true
                end
                return origSetDepth(self, State)
            end
        end
    end)

    ---------- LAYER 6: Material property queries ----------
    pcall(function()
        local UMat = import("Material")
        local UMatInst = import("MaterialInstance")
        local UMatDyn = import("MaterialInstanceDynamic")

        if UMat then
            UMat.__origDDT = UMat.GetDisableDepthTest
            UMat.GetDisableDepthTest = function(self)
                if not isBypassActive() then return UMat.__origDDT(self) end
                return false
            end

            UMat.__origBM = UMat.GetBlendMode
            UMat.GetBlendMode = function(self)
                if not isBypassActive() then return UMat.__origBM(self) end
                return 0
            end

            UMat.__origHash = UMat.GetMaterialHash
            UMat.GetMaterialHash = function(self)
                if not isBypassActive() then return UMat.__origHash(self) end
                return "FAKE_HASH"
            end

            UMat.__origVM = UMat.VerifyMaterial
            UMat.VerifyMaterial = function(self)
                if not isBypassActive() then return UMat.__origVM(self) end
                return true
            end
        end

        if UMatInst then
            UMatInst.__origDDT = UMatInst.GetDisableDepthTest
            UMatInst.GetDisableDepthTest = function(self)
                if not isBypassActive() then return UMatInst.__origDDT(self) end
                return false
            end

            UMatInst.__origBM = UMatInst.GetBlendMode
            UMatInst.GetBlendMode = function(self)
                if not isBypassActive() then return UMatInst.__origBM(self) end
                return 0
            end

            UMatInst.__origBM2 = UMatInst.GetBaseMaterial
            UMatInst.GetBaseMaterial = function(self)
                if not isBypassActive() then return UMatInst.__origBM2(self) end
                return nil
            end
        end

        if UMatDyn then
            local oldGetVec = UMatDyn.K2_GetVectorParameterValue
            UMatDyn.K2_GetVectorParameterValue = function(self, name)
                if not isBypassActive() then return oldGetVec(self, name) end
                local n = tostring(name or "")
                if n:find("Color") or n:find("Emissive") or n:find("Tint") then
                    return {R=255,G=255,B=255,A=255}
                end
                return oldGetVec(self, name)
            end

            local oldGetScal = UMatDyn.K2_GetScalarParameterValue
            UMatDyn.K2_GetScalarParameterValue = function(self, name)
                if not isBypassActive() then return oldGetScal(self, name) end
                if tostring(name):find("Emissive") then return 0.0 end
                return oldGetScal(self, name)
            end
        end
    end)

    ---------- LAYER 8: Kernel & memory spoof ----------
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local kc = SubMgr:Get("ClientKernelCheckSubsystem")
            if kc and not kc.__akhooked then
                local origIKC = kc.IsKernelClean
                kc.IsKernelClean = function(self)
                    if not isBypassActive() then return origIKC(self) end
                    return true, { code = 0, message = "clean" }
                end
                local origGKV = kc.GetKernelVersion
                kc.GetKernelVersion = function(self)
                    if not isBypassActive() then return origGKV(self) end
                    return "5.4.0-generic"
                end
                kc.__akhooked = true
            end

            local mg = SubMgr:Get("ClientMemoryGuardSubsystem")
            if mg and not mg.__akhooked then
                local origIMC = mg.IsMemoryClean
                mg.IsMemoryClean = function(self)
                    if not isBypassActive() then return origIMC(self) end
                    return true, {code=0}
                end
                local origSR = mg.ScanResult
                mg.ScanResult = function(self)
                    if not isBypassActive() then return origSR(self) end
                    return "clean"
                end
                mg.__akhooked = true
            end
        end
    end)

    local ourMarkGroups = {1006, 9999}

    ---------- LAYER 9: MARK SYSTEM COMPLETE SPOOF ----------
    pcall(function()
        local MarkMgr = InGameMarkTools and InGameMarkTools.ScreenMarkManager
        if MarkMgr then
            if MarkMgr.GetAllActiveMarks then
                local orig = MarkMgr.GetAllActiveMarks
                MarkMgr.GetAllActiveMarks = function(self, ...)
                    local marks = orig(self, ...)
                    if not isBypassActive() or not marks then return marks end
                    if type(marks) ~= "table" then return marks end
                    local filtered = {}
                    for _, m in ipairs(marks) do
                        if m.MarkGroupID and not table.contains(ourMarkGroups, m.MarkGroupID) then
                            table.insert(filtered, m)
                        end
                    end
                    return filtered
                end
            end

            if MarkMgr.GetMarkCount then
                local orig = MarkMgr.GetMarkCount
                MarkMgr.GetMarkCount = function(self, ...)
                    local count = orig(self, ...)
                    if isBypassActive() then count = math.max(0, count - #ourMarkGroups) end
                    return count
                end
            end

            if MarkMgr.GetMarksByGroup then
                local orig = MarkMgr.GetMarksByGroup
                MarkMgr.GetMarksByGroup = function(self, groupId)
                    if isBypassActive() and table.contains(ourMarkGroups, groupId) then return {} end
                    return orig(self, groupId)
                end
            end

            if MarkMgr.OnAddMark then MarkMgr.OnAddMark = nop end
            if MarkMgr.OnRemoveMark then MarkMgr.OnRemoveMark = nop end
        end
    end)

    ---------- LAYER 10: REPLAY UI DETECTION KILL ----------
    pcall(function()
        if _G.Replay_IsEnemyFrameUIExisted then
            local orig = _G.Replay_IsEnemyFrameUIExisted
            _G.Replay_IsEnemyFrameUIExisted = function(...)
                if isBypassActive() then return false end
                return orig(...)
            end
        end

        if _G.Replay_CreateEnemyFrameUI then
            local orig = _G.Replay_CreateEnemyFrameUI
            _G.Replay_CreateEnemyFrameUI = function(...)
                if isBypassActive() then
                    local backup = _G.ReportEnemyFrameUI or nop
                    _G.ReportEnemyFrameUI = nop
                    local res = orig(...)
                    _G.ReportEnemyFrameUI = backup
                    return res
                end
                return orig(...)
            end
        end
    end)

    ---------- LAYER 13: ESP-RELATED REPORT FUNCTIONS KILL ----------
    pcall(function()
        local espReports = {
            "ReportESPBox","ReportESPHealth","ReportMiniMapESP","ReportEnemyFrameUI",
            "ReportMarkCreated","ReportMarkDestroyed","MarkSuspiciousESP",
            "OnScreenMarkAdd","OnScreenMarkRemove","ReportDistanceMarker",
            "ReportWallhackESP","SendESPData","UploadESPInfo"
        }
        for _, fn in ipairs(espReports) do
            if _G[fn] then _G[fn] = nop end
            for _, mod in pairs(package.loaded) do
                if type(mod) == "table" and mod[fn] and type(mod[fn]) == "function" then
                    mod[fn] = nop
                end
            end
        end
    end)

    ---------- LAYER 14: NETWORK ESP PACKET BLOCK ----------
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(pname, ...)
                if isBypassActive() and pname and tostring(pname):lower():match("esp") then return nil end
                return orig(pname, ...)
            end
        end

        if _G.SendRPC then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpcName, ...)
                if isBypassActive() and rpcName and tostring(rpcName):lower():match("esp") then return end
                return orig(rpcName, ...)
            end
        end
    end)

    _G.__ULTIMATE_WH_BYPASS_LOADED = true
    print("[ok] Ultimate Wallhack + ESP Detection Bypass Installed")
end

-- ---- WHABypass table + detection subsystem spoof ----
local function setupWHABypassTable()
    local bypass = {}
    local function nop() end
    local function returnTrue() return true end
    local function returnFalse() return false end

    local function safe_require(mod)
        local ok, res = pcall(require, mod)
        return ok and res or nil
    end

    local function tryImport(name)
        local ok, lib = pcall(import, name)
        return ok and lib or nil
    end

    local function blockScreenshots()
        pcall(function()
            local SS = tryImport("ScreenshotMaker") or tryImport("ScreenshotMTDer")
            if SS then
                SS.MakePicture = function() return "" end
                SS.ReMakePicture = function() return "" end
                SS.HasCaptured = returnTrue
            end
        end)
    end

    local function blockGameplayCallbacks()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        local GC = _G.GameplayCallbacks
        if GC._WHABlocked then return end

        local reportFuncs = {
            "ReportAttackFlow","ReportSecAttackFlow","ReportHurtFlow","ReportFireArms",
            "ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior","ReportTeammatHurt",
            "ReportPlayerMoveRoute","ReportPlayerPosition","ReportAimFlow","ReportHitFlow",
            "ReportWallHack","ReportAimbot","ReportSpeedHack","ReportMagicBullet",
            "ReportAbnormalMaterial","ReportDepthTestChange","ReportMemoryException",
            "ReportMaterialScan","ReportShaderOverride","ReportCircleFlow",
            "OnPlayerRPCValidateFailed","OnPlayerActorChannelError",
            "OnPlayerSpectateException","OnShutdownAfterError"
        }
        for _, fn in ipairs(reportFuncs) do GC[fn] = nop end

        local oldStateChanged = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(UID, state, ...)
            if state and type(state) == "string" then
                local s = state:lower()
                if s:find("cheat") or s:find("ban") or s:find("integrity") then return end
            end
            if oldStateChanged then return oldStateChanged(UID, state, ...) end
        end

        GC._WHABlocked = true
    end

    local function spoofTssSdk()
        pcall(function()
            local t = _G.TssSdk
            if t then
                t.GetFileMD5 = function() return "" end
                t.VerifyFileSignature = returnTrue
                t.CheckIntegrity = returnTrue
                t.ScanMemory = function() return true, {} end
                t.IsEmulator = returnFalse
                t.OnRecvData = nop
            end
        end)
    end

    local function disableDetectionSubsystems()
        local sm = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not sm then return end

        local targetSubs = {
            "ClientWallhackDetectionSubsystem", "ClientESPDetectionSubsystem",
            "ClientAimTrackingSubsystem", "ShootVerifySubSystemClient",
            "ClientRenderCheckSubsystem", "ClientMemoryGuardSubsystem",
            "ClientKernelCheckSubsystem", "ClientHawkEyePatrolSubsystem",
            "ClientAntiCheatSubsystem", "IntegrityCheckSubsystem",
            "FileCheckSubsystem", "AvatarExceptionSubsystem"
        }

        for _, sn in ipairs(targetSubs) do
            local sub = sm:Get(sn)
            if sub and type(sub) == "table" then
                local keysToNop = {}
                for k, v in pairs(sub) do
                    if type(v) == "function" then
                        if k:find("Report") or k:find("Send") or k:find("Verify") or
                           k:find("Check") or k:find("Detect") or k:find("Scan") then
                            table.insert(keysToNop, k)
                        end
                    end
                end

                for _, k in ipairs(keysToNop) do sub[k] = nop end

                if sn == "ClientWallhackDetectionSubsystem" then
                    sub.IsVisionNormal = returnTrue
                    sub.GetVisibilityRate = function() return math.random(60, 85) end
                elseif sn == "ClientESPDetectionSubsystem" then
                    sub.HasESP = returnFalse
                    sub.CheckOverlay = function() return "clean" end
                elseif sn == "ClientAimTrackingSubsystem" then
                    sub.GetAimData = function()
                        return { accuracy = math.random(45,65), headshotRate = math.random(15,35) }
                    end
                    sub.IsAimNormal = returnTrue
                elseif sn == "ClientMemoryGuardSubsystem" then
                    sub.IsMemoryClean = function() return true, {code=0} end
                    sub.ScanResult = function() return "clean" end
                elseif sn == "ShootVerifySubSystemClient" then
                    sub.OnShootVerifyFailed = nop
                    sub.VerifyShot = returnTrue
                end
            end
        end
    end

    local function disableHiggsBoson()
        pcall(function()
            local hbc = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
            if hbc then
                hbc.bMHActive = false
                hbc.bCallPreReplication = false
                if hbc.ControlMHActive then hbc.ControlMHActive = nop end
                if hbc.StartAvatarCheck then hbc.StartAvatarCheck = nop end
                if hbc.BlackList then
                    for k in pairs(hbc.BlackList) do hbc.BlackList[k] = nil end
                end
            end

            if _G.AvatarCheckCallback then
                _G.AvatarCheckCallback.StartAvatarCheck = nop
                _G.AvatarCheckCallback.OnReportItemID = nop
            end
            _G.BlackList = {}
        end)
    end

    function bypass.Init()
        blockScreenshots()
        blockGameplayCallbacks()
        spoofTssSdk()
        disableDetectionSubsystems()
        disableHiggsBoson()
    end

    _G.WHABypass = bypass
end

-- ---- Bypass gate state ----
_G._BYPASS_DONE        = _G._BYPASS_DONE or false
_G._WHA_BYPASS_ACTIVE  = _G._WHA_BYPASS_ACTIVE or false
_G._BYPASS_LOCK_REASON = _G._BYPASS_LOCK_REASON or "not_started"

local _gateTimer    = nil
local _gateElapsed  = 0
local _gateRetries  = 0
local GATE_MAX_WAIT = 15.0
local GATE_TICK     = 0.5

local function _ExecuteBypassNow()
    if _G._BYPASS_DONE == true and _G._WHA_BYPASS_ACTIVE == true then
        return
    end

    local ok = pcall(function()
        _G._MOD_EXPIRED = false
        _G._WHA_BYPASS_ACTIVE = true

        InstallUltimateWallhackBypass()
        setupWHABypassTable()

        if _G.WHABypass and type(_G.WHABypass.Init) == "function" then
            _G.WHABypass.Init()
        end
    end)

    if not ok or type(_G.WHABypass) ~= "table" then
        _G._WHA_BYPASS_ACTIVE = false
        _G._BYPASS_DONE = false
        _G._BYPASS_LOCK_REASON = "install_failed"
        print("[BYPASS] install FAILED")
        return false
    end

    _G._BYPASS_DONE = true
    _G._BYPASS_LOCK_REASON = "ok"
    print("[BYPASS] All bypasses executed successfully")

    if type(_G.InitBotmasterMenu) == "function" then
        local menuOk, menuErr = pcall(_G.InitBotmasterMenu)
        if not menuOk then
            print("[BYPASS] InitBotmasterMenu ERROR: " .. tostring(menuErr))
        end
    end

    if type(_G.CreateDsDemonBanner) == "function" then
        local bannerOk, bannerErr = pcall(_G.CreateDsDemonBanner)
        if not bannerOk then
            print("[BYPASS] CreateDsDemonBanner ERROR: " .. tostring(bannerErr))
        end
    end

    return true
end

local function _StopGateTimer()
    if _gateTimer then
        pcall(function()
            if _G.Game and _G.Game.RemoveGameTimer then
                _G.Game:RemoveGameTimer(_gateTimer)
            end
        end)
        _gateTimer = nil
    end
end

local function _GateTick()
    if _G._BYPASS_DONE == true then
        _StopGateTimer()
        return
    end

    _gateElapsed = _gateElapsed + GATE_TICK

    if Bypass_IsEnemyDetected() then
        print("[BYPASS] Player detected — installing bypass...")
        _StopGateTimer()
        _ExecuteBypassNow()
        return
    end

    _gateRetries = _gateRetries + 1
    if _gateElapsed >= GATE_MAX_WAIT then
        print("[BYPASS] Gate timeout — forcing install")
        _StopGateTimer()
        _ExecuteBypassNow()
    end
end

local function _StartBypassGate()
    if _G._BYPASS_DONE == true then return end

    if Bypass_IsEnemyDetected() then
        print("[BYPASS] Player already detected — installing immediately")
        _ExecuteBypassNow()
        return
    end

    print("[BYPASS] Waiting for player detection...")

    _gateElapsed = 0
    _gateRetries = 0

    _StopGateTimer()

    if _G.Game and _G.Game.AddGameTimer then
        _gateTimer = _G.Game:AddGameTimer(GATE_TICK, true, _GateTick)
        return
    end

    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        _gateTimer = pc:AddGameTimer(GATE_TICK, true, _GateTick)
        return
    end

    pcall(function()
        if _G.Game and _G.Game.AddGameTimer then
            _G.Game:AddGameTimer(1.0, false, _StartBypassGate)
        elseif slua_GameFrontendHUD then
            local pc2 = slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc2) and pc2.AddGameTimer then
                pc2:AddGameTimer(1.0, false, _StartBypassGate)
            end
        end
    end)
end

function _G.StartBypass()
    if _G._BYPASS_DONE == true then return end
    _StartBypassGate()
end


-- ============================================================
-- STEP 8: AUTO INIT (bypass + counter auto-start + resync all)
-- ============================================================
_G._AUTO_INIT_DONE = _G._AUTO_INIT_DONE or false

local function _autoInit()
    if _G._AUTO_INIT_DONE then return end
    _G._AUTO_INIT_DONE = true

    if type(_G.StartBypass) == "function" then
        pcall(_G.StartBypass)
    end

    -- Counter independent auto-start
    g_Botmater_CounterAutoStart()

    -- Resync ESP if switch ON
    if _G.PBCEnabled == true and not _PBC.WH_TIMER then
        if type(_G.PBCOn) == "function" then
            pcall(_G.PBCOn)
        end
    end

    -- Resync Aimbot if switch ON
    if _G.AimbotEnabled == true and not _AIM.TIMER then
        if type(_G.AimbotOn) == "function" then
            pcall(_G.AimbotOn)
        end
    end

    -- Resync ESP features if any ON
    local anyESP = _G.ESPLineEnabled or _G.ESPNameHealthEnabled or _G.ESPDistanceEnabled
    if anyESP and not g_Botmater_ShotESP.TickRegistered then
        g_Botmater_ESPStartTick()
    end
end

if _G.Game and _G.Game.AddGameTimer then
    pcall(function()
        _G.Game:AddGameTimer(0.5, false, _autoInit)
    end)
end


-- ============================================================
-- STEP 9: GAME LOGIC FUNCTIONS
-- ============================================================
function BRPlayerCharacterBase:ctor() end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true

  if Client then
    if not _G._POST_CONSTRUCT_INITED then
      _G._POST_CONSTRUCT_INITED = true
      if self.AddGameTimer then
        pcall(function()
          self:AddGameTimer(0.5, false, _autoInit)
        end)
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)

  if Client then
    if _G._AUTO_INIT_DONE ~= true then
      _autoInit()
    end
    -- ensure counter is running even on respawn
    if not g_Botmater_EnemyCounter.TickRegistered then
      g_Botmater_CounterAutoStart()
    end
    if _G.PBCEnabled == true and not _PBC.WH_TIMER then
      if type(_G.PBCOn) == "function" then
        pcall(_G.PBCOn)
      end
    end
    if _G.AimbotEnabled == true and not _AIM.TIMER then
      if type(_G.AimbotOn) == "function" then
        pcall(_G.AimbotOn)
      end
    end
    local anyESP = _G.ESPLineEnabled or _G.ESPNameHealthEnabled or _G.ESPDistanceEnabled
    if anyESP and not g_Botmater_ShotESP.TickRegistered then
      g_Botmater_ESPStartTick()
    end
  end

  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)

  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end

  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end

  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = { "bCanSelfRescue" }
    }, self.CharacterAttrChangeEvent, self)
  end

  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then return end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  if self.HandleOnLanded then self:HandleOnLanded(-1) end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  end
  return false
end

function BRPlayerCharacterBase:BPOnRecycled()
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:BPOnRespawned()
  if Client then self:ResetMeshRelativeLocationAndRotation() end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord() end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then return end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then return end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then return end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then return end
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then return end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then return end
  if not Lifter.AddCharacter then return end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then return false end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then return end
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then return end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then return end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")

  local function _loadLater()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  asset_util.GetAssetsArrayAsyncParallel(tb, _loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Move then
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ============================================================
-- STEP 10: CLASS DECLARATION + DECLAREFEATURE
-- ============================================================
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  { SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
  { CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
  { SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
  { TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
  { LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
  { FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
  { CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature" },
  { BuildSkateFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.PlayerCharacterBuildVehicleFeature" },
  { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
  { ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" },
  { SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature" },
  { GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature" }
}, "BRPlayerCharacterBase")