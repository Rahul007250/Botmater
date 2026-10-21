-- ============================================================
-- SECTION 1: RPC DECLARATIONS
-- ============================================================
local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}

-- ============================================================
-- SECTION 2: IMPORTS
-- ============================================================
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ECharacterHideMovementAcive = import("ECharacterHideMovementAcive")
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

local LinearColor = import("LinearColor")

-- ============================================================
-- SECTION 3: BANNER FUNCTION
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
-- SECTION 4: WALLHACK ENGINE (PBC)
-- ============================================================
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
        local KSL = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KSL or not world then return end
        KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
        KSL.ExecuteConsoleCommand(world, "r.CustomDepth 3")
        KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
        KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
        _PBC.CONSOLE_READY = true
        print("[PBC] Console ready")
    end)
end

local function PBC_DisableConsole()
    pcall(function()
        local KSL = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if not KSL or not world then return end
        KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 0")
        KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 0")
        KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 0")
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
    if not Game or not Game.GetAllPlayerPawns then return end
    pcall(function()
        local SKC = import("SkeletalMeshComponent")
        local SMC = import("StaticMeshComponent")
        local allPawns = Game:GetAllPlayerPawns() or {}
        for _, pawn in pairs(allPawns) do
            if slua.isValid(pawn) then
                pcall(function()
                    if slua.isValid(pawn.Mesh) then PBC_ClearMeshVisuals(pawn.Mesh) end
                    local av = pawn.CharacterAvatarComp2_BP or pawn:getAvatarComponent2()
                    if av and av.GetMeshCompBySlot then
                        for _, s in ipairs(PBC_AVATAR_SLOTS) do
                            local m = av:GetMeshCompBySlot(s)
                            if slua.isValid(m) then PBC_ClearMeshVisuals(m) end
                        end
                    end
                    if SKC then
                        local sk = pawn:GetComponentsByClass(SKC)
                        if sk then
                            for i = 0, sk:Num() - 1 do
                                local c = sk:Get(i)
                                if slua.isValid(c) and c ~= pawn.Mesh then PBC_ClearMeshVisuals(c) end
                            end
                        end
                    end
                    if SMC then
                        local st = pawn:GetComponentsByClass(SMC)
                        if st then
                            for i = 0, st:Num() - 1 do PBC_ClearMeshVisuals(st:Get(i)) end
                        end
                    end
                    local w = pawn:GetCurrentWeapon()
                    if slua.isValid(w) and slua.isValid(w.Mesh) then PBC_ClearMeshVisuals(w.Mesh) end
                end)
            end
        end
    end)
end

local function PBC_IsPawnAlive(p)
    if not slua.isValid(p) then return false end
    if p.Health and p.Health > 0 then return true end
    return false
end

local function PBC_DetectIsBot(pawn)
    if not slua.isValid(pawn) then return false end
    local pk = pawn.PlayerKey
    if pk and _PBC.BotDetectCache[pk] ~= nil then return _PBC.BotDetectCache[pk] end
    local r = false
    pcall(function()
        if Game and Game.IsAI then
            local a = Game:IsAI(pawn)
            if a == true or a == 1 then r = true end
        end
    end)
    if not r then
        if pawn.bIsAI == true or pawn.IsAI == true then r = true end
        if pawn.bIsABot == true or pawn.bBot == true then r = true end
    end
    if not r then
        local ps = pawn.PlayerState
        if slua.isValid(ps) and (ps.bIsABot or ps.bIsBot or ps.bIsAI) then r = true end
    end
    if pk then _PBC.BotDetectCache[pk] = r end
    return r
end

local function PBC_tick()
    if _G.PBCEnabled ~= true then return end
    pcall(function()
        local lp = GameplayData.GetPlayerCharacter()
        if not slua.isValid(lp) then return end
        PBC_SetupConsole()
        if not _PBC.colors then return end

        _PBC.TICK_COUNT = _PBC.TICK_COUNT + 1
        if _PBC.TICK_COUNT % PBC_RESET_EVERY == 0 then _PBC.PROCESSED_PAWNS = {} end
        if _PBC.TICK_COUNT % (PBC_RESET_EVERY * 20) == 0 then _PBC.BotDetectCache = {} end

        local myTeam = lp.TeamID or 0
        local allPawns = Game:GetAllPlayerPawns() or {}
        local cnt = 0
        local SKC = import("SkeletalMeshComponent")
        local SMC = import("StaticMeshComponent")

        for _, pawn in pairs(allPawns) do
            if cnt >= PBC_MAX_PAWNS_PER_TICK then break end
            local skip = false
            if not slua.isValid(pawn) or pawn == lp then skip = true
            elseif pawn.PlayerKey and _PBC.PROCESSED_PAWNS[pawn.PlayerKey] then skip = true end

            if not skip and PBC_IsPawnAlive(pawn) and pawn.TeamID and pawn.TeamID ~= myTeam then
                local isAI = PBC_DetectIsBot(pawn)
                local vis = isAI and _PBC.colors.bVis or _PBC.colors.vis
                local occ = isAI and _PBC.colors.bOcc or _PBC.colors.occ
                pcall(function()
                    if slua.isValid(pawn.Mesh) then PBC_ApplyToMesh(pawn.Mesh, vis, occ) end
                    local av = pawn.CharacterAvatarComp2_BP or pawn:getAvatarComponent2()
                    if av and av.GetMeshCompBySlot then
                        for _, s in ipairs(PBC_AVATAR_SLOTS) do
                            local m = av:GetMeshCompBySlot(s)
                            if slua.isValid(m) then PBC_ApplyToMesh(m, vis, occ) end
                        end
                    end
                    if SKC then
                        local sk = pawn:GetComponentsByClass(SKC)
                        if sk then
                            for i = 0, sk:Num() - 1 do
                                local c = sk:Get(i)
                                if slua.isValid(c) and c ~= pawn.Mesh then PBC_ApplyToMesh(c, vis, occ) end
                            end
                        end
                    end
                    if SMC then
                        local st = pawn:GetComponentsByClass(SMC)
                        if st then
                            for i = 0, st:Num() - 1 do
                                local c = st:Get(i)
                                if slua.isValid(c) then PBC_ApplyToMesh(c, vis, occ) end
                            end
                        end
                    end
                    local w = pawn:GetCurrentWeapon()
                    if slua.isValid(w) and slua.isValid(w.Mesh) then PBC_ApplyToMesh(w.Mesh, vis, occ) end
                end)
                if pawn.PlayerKey then _PBC.PROCESSED_PAWNS[pawn.PlayerKey] = true end
                cnt = cnt + 1
            end
        end
    end)
end

local function PBC_Start()
    if _G.PBCEnabled ~= true then return false end
    PBC_SetupConsole()
    if not _PBC.colors then return false end
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

_G.PBCEnabled = _G.PBCEnabled or false

function _G.PBCOn()
    if _G.PBCEnabled == true and _PBC.WH_TIMER then return end
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
-- SECTION 5: AIMBOT ENGINE
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

local function AIM_Start()
    if _G.AimbotEnabled ~= true then return false end

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
-- SECTION 5.5: iPAD VIEW ENGINE (BOTMASTER iPAD VIEW)
-- ============================================================
_G.LexusConfig = _G.LexusConfig or {}
_G.LexusConfig.IpadView = _G.LexusConfig.IpadView or false
_G.LexusState = _G.LexusState or {}
_G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
_G.LexusState.CustomTextData.IpadViewFOV = _G.LexusState.CustomTextData.IpadViewFOV or 120

local _iPadViewTimer = nil
local _iPadViewTimerOwner = nil

local function g_masterahsanyt_GetLocalPlayer()
    local ok, GDP = pcall(require, "GameLua.GameCore.Data.GameplayData")
    if not ok or not GDP then return nil end
    local player = GDP.GetPlayerCharacter()
    if player and slua.isValid(player) then return player end
    return nil
end

local function g_masterahsanyt_ApplyiPadView()
    local player = g_masterahsanyt_GetLocalPlayer()
    if not player then return end
    local cam = player.ThirdPersonCameraComponent
    if not cam or not slua.isValid(cam) then return end
    if player.bIsWeaponAiming then return end

    if _G.LexusConfig.IpadView then
        local targetFOV = _G.LexusState.CustomTextData.IpadViewFOV or 120
        if cam.FieldOfView ~= targetFOV then
            cam.FieldOfView = targetFOV
        end
    else
        if cam.FieldOfView ~= 90 then
            cam.FieldOfView = 90
        end
    end
end

local function _iPadViewTick()
    if _G.LexusConfig.IpadView ~= true then return end
    pcall(g_masterahsanyt_ApplyiPadView)
    
    if _G.Game and _G.Game.AddGameTimer then
        _iPadViewTimerOwner = _G.Game
        _iPadViewTimer = _G.Game:AddGameTimer(0.5, false, _iPadViewTick)
    else
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) and pc.AddGameTimer then
            _iPadViewTimerOwner = pc
            _iPadViewTimer = pc:AddGameTimer(0.5, false, _iPadViewTick)
        end
    end
end

function _G.BotmasterIPadViewOn()
    if _G.LexusConfig.IpadView == true then return end
    _G.LexusConfig.IpadView = true
    pcall(g_masterahsanyt_ApplyiPadView)
    _iPadViewTick()
    print("[BOTMASTER] iPad View ON")
end

function _G.BotmasterIPadViewOff()
    if _G.LexusConfig.IpadView == false then return end
    _G.LexusConfig.IpadView = false
    if _iPadViewTimer and _iPadViewTimerOwner then
        pcall(function()
            if _iPadViewTimerOwner.RemoveGameTimer then
                _iPadViewTimerOwner:RemoveGameTimer(_iPadViewTimer)
            end
        end)
        _iPadViewTimer = nil
        _iPadViewTimerOwner = nil
    end
    pcall(g_masterahsanyt_ApplyiPadView)
    print("[BOTMASTER] iPad View OFF")
end

function _G.BotmasterIPadViewToggle()
    if _G.LexusConfig.IpadView then _G.BotmasterIPadViewOff() else _G.BotmasterIPadViewOn() end
    return _G.LexusConfig.IpadView
end


-- ============================================================
-- SECTION 6: BYPASS INTEGRATION (Layers + Gate)
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

local function InstallUltimateWallhackBypass()
    if _G.__ULTIMATE_WH_BYPASS_LOADED then return end
    local nop = function() end
    local function isBypassActive()
        return _G._WHA_BYPASS_ACTIVE and not _G._MOD_EXPIRED
    end
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
-- SECTION 7: MENU FUNCTION
-- ============================================================
local function g_botmaster_InitMenu()
    if _G._BYPASS_DONE ~= true then
        print("[BOTMASTER] Menu load blocked — waiting for bypass")
        return
    end

    if _G.BotmasterMenuInitialized == "BOTMASTER_MENU_V1" then return end
    _G.BotmasterMenuInitialized = "BOTMASTER_MENU_V1"

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog    = require("client.logic.NewSetting.SettingCatalog")
    local AliasMap          = require("client.slua.umg.NewSetting.Item.AliasMap")

    local Stack = {
        {
            Key  = "BotmasterESP",
            UI   = AliasMap.Switcher,
            Text = "Player ESP (Wallhack)",
            GetFunc = function()
                if _G.PBCEnabled == nil then _G.PBCEnabled = false end
                return _G.PBCEnabled
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.PBCOn then pcall(_G.PBCOn) end
                else
                    if _G.PBCOff then pcall(_G.PBCOff) end
                end
                return true
            end
        },
        {
            Key  = "BotmasterAimbot",
            UI   = AliasMap.Switcher,
            Text = "Hard Aimbot",
            GetFunc = function()
                if _G.AimbotEnabled == nil then _G.AimbotEnabled = false end
                return _G.AimbotEnabled
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.AimbotOn then pcall(_G.AimbotOn) end
                else
                    if _G.AimbotOff then pcall(_G.AimbotOff) end
                end
                return true
            end
        },
        {
            Key  = "BotmasterIPadView",
            UI   = AliasMap.Switcher,
            Text = "Player iPad View",
            GetFunc = function()
                if _G.LexusConfig.IpadView == nil then _G.LexusConfig.IpadView = false end
                return _G.LexusConfig.IpadView
            end,
            SetFunc = function(c, v)
                local on = (v == true or v == 1)
                if on then
                    if _G.BotmasterIPadViewOn then pcall(_G.BotmasterIPadViewOn) end
                else
                    if _G.BotmasterIPadViewOff then pcall(_G.BotmasterIPadViewOff) end
                end
                return true
            end
        }
    }

    SettingPageDefine.BotmasterMenu = {
        Key      = "BotmasterMenu",
        Text     = "BOTMASTER",
        UIKey    = "Setting_Page_Privacy",
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

    local UIMgr = _G.UIManager
    if UIMgr and not UIMgr._BotmasterMenuHooked then
        local old_ShowUI = UIMgr.ShowUI
        UIMgr.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...)
            if config and config.keyName then
                local lk = string.lower(config.keyName)
                if string.find(lk, "setting_main") and not string.find(lk, "custom") then
                    local cat = args[1]
                    if type(cat) == "table" and cat[1] and type(cat[1]) == "table" and cat[1].Key then
                        local has = false
                        for _, p in ipairs(cat) do
                            if type(p) == "table" and p.Key == "BotmasterMenu" then
                                has = true; break
                            end
                        end
                        if not has then table.insert(cat, 1, SettingPageDefine.BotmasterMenu) end
                    end
                end
            end
            local unpack_fn = table.unpack or unpack
            return old_ShowUI(config, unpack_fn(args, 1, n))
        end
        UIMgr._BotmasterMenuHooked = true
    end

    print("[BOTMASTER] Menu loaded")
end

_G.InitBotmasterMenu = g_botmaster_InitMenu

-- ============================================================
-- SECTION 8: AUTO INIT + SCHEDULE
-- ============================================================
_G._AUTO_INIT_DONE = _G._AUTO_INIT_DONE or false

local function _autoInit()
    if _G._AUTO_INIT_DONE then return end
    _G._AUTO_INIT_DONE = true

    if type(_G.StartBypass) == "function" then
        pcall(_G.StartBypass)
    end

    if _G.PBCEnabled == true and not _PBC.WH_TIMER then
        if type(_G.PBCOn) == "function" then pcall(_G.PBCOn) end
    end

    if _G.AimbotEnabled == true and not _AIM.TIMER then
        if type(_G.AimbotOn) == "function" then pcall(_G.AimbotOn) end
    end

    if _G.LexusConfig and _G.LexusConfig.IpadView == true and not _iPadViewTimer then
        if type(_G.BotmasterIPadViewOn) == "function" then pcall(_G.BotmasterIPadViewOn) end
    end

    print("[BOTMASTER] Auto-init complete (0.5s)")
end

local function _scheduleAutoInit()
    if _G.Game and _G.Game.AddGameTimer then
        pcall(function() _G.Game:AddGameTimer(0.5, false, _autoInit) end)
        return
    end
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(pc) and pc.AddGameTimer then
        pcall(function() pc:AddGameTimer(0.5, false, _autoInit) end)
        return
    end
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(0.5, _autoInit)
        end
    end)
end

_scheduleAutoInit()

-- ============================================================
-- SECTION 9: GAME LOGIC FUNCTIONS
-- ============================================================
function BRPlayerCharacterBase:ctor()
end
function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")

  if Client then
    if not _G._AUTO_INIT_DONE then _autoInit() end
  end
end
function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
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
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
    
    if _G._AUTO_INIT_DONE ~= true then _autoInit() end
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
    self:AddControlEvent(self, "OnPawnRespawnDelegate", self.OnRespawnRehideCheck, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:OnRespawnRehideCheck()
  if not self:GetEnsure() then
    return
  end
  self:AddGameTimer(0.5, false, function()
    if not slua.isValid(self.Object) then
      return
    end
    if self:HasState(EPawnState.InPlane) then
      self:SetCharacterHideInGame(true, true, true, 1, ECharacterHideMovementAcive.Normal)
      print(bWriteLog and "BRPlayerCharacterBase:OnRespawnRehideCheck re-hide AI on plane, PlayerKey:", self.PlayerKey)
    end
  end)
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
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
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
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
    if type(_G.PBCOff) == "function" then pcall(_G.PBCOff) end
    if type(_G.AimbotOff) == "function" then pcall(_G.AimbotOff) end
    if type(_G.BotmasterIPadViewOff) == "function" then pcall(_G.BotmasterIPadViewOff) end
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
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
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
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
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
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
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
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
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")

  local function loadLater()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end

  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
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
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
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
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
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
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

local VICTORY_DANCE_FX_MAP = {
  [12219601] = 22010089
}
local PublishRegionMacros = require("client.slua.config.ClientMacros.PublishRegionMacros")
local isFitVersion = PublishRegionMacros.IsFITVersion()

local function ResolveEmoteResID(ItemID)
  local FxID = VICTORY_DANCE_FX_MAP[ItemID]
  if not FxID or FxID == ItemID then
    return ItemID
  end
  local model_util = require("client.common.model_util")
  local FxBPID = model_util.GetBPID(FxID)
  local ResID = ItemID
  if FxBPID and 0 < FxBPID and model_util.IsBattleItemHandleExist("Emote", FxBPID, false, false) then
    ResID = FxID
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase 11 ResolveEmoteResID ItemID:%s, FxID:%s, FxBPID:%s, ResID:%s", tostring(ItemID), tostring(FxID), tostring(FxBPID), tostring(ResID)))
  if isFitVersion and ResID == 12219601 then
    print(bWriteLog and "BRPlayerCharacterBase ResolveEmoteResID 12219601 to 12222069")
    return 12222069
  end
  return ResID
end

function BRPlayerCharacterBase:GetEmoteHandlePath(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandlePath(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return ""
  end
  return model_util.GetPath("Emote", BPID, false, false) or ""
end

function BRPlayerCharacterBase:GetEmoteHandle(ItemID)
  local ResID = ResolveEmoteResID(ItemID)
  if self.Super then
    return self.Super:GetEmoteHandle(ResID)
  end
  local model_util = require("client.common.model_util")
  local BPID = model_util.GetBPID(ResID)
  if not BPID or BPID <= 0 then
    return nil
  end
  local HandleClass = model_util.GetClass("Emote", BPID, false, false)
  if not HandleClass then
    return nil
  end
  local Handle = HandleClass()
  if not slua.isValid(Handle) then
    return nil
  end
  return Handle
end

-- ============================================================
-- SECTION 10: CLASS DECLARATION
-- ============================================================
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
{
SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"},{
CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"},{
SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"},{
TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"},{
LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"},{
FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"},{
CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"},{
BuildAircraftVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"},{
UnifiedBuildVehicleFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.UnifiedBuildVehicleFeature"},{
CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"},{
ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"},{
ParachuteSprint = "GameLua.Mod.BaseMod.GamePlay.Feature.Parachute.ParachuteSprintFeature"},{
GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"},{
FPPAnimMonitor = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.FPPAnimMonitorFeature"}
}, "BRPlayerCharacterBase")