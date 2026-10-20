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

--==========×==========×==========×==========×==========×==========×==========--
                -- WALLHACK + ALL CODES HERE 
--==========×==========×==========×==========×==========×==========×==========--
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

-- ============================================================
-- PBC PUBLIC CONTROL
-- ============================================================
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
-- BOTMASTER MENU + SWITCHES
-- ============================================================
local function g_botmaster_InitMenu()
    if _G.BotmasterMenuInitialized == "BOTMASTER_MENU_V1" then return end
    _G.BotmasterMenuInitialized = "BOTMASTER_MENU_V1"

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog    = require("client.logic.NewSetting.SettingCatalog")
    local AliasMap          = require("client.slua.umg.NewSetting.Item.AliasMap")

    local Stack = {
        {
            Key  = "BotmasterESP",
            UI   = AliasMap.Switcher,
            Text = "Botmaster ESP (Wallhack)",
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
-- AUTO INIT — 0.5s baad auto-run (NO BYPASS, NO EXPIRY)
-- ============================================================
_G._AUTO_INIT_DONE = _G._AUTO_INIT_DONE or false

local function _autoInit()
    if _G._AUTO_INIT_DONE then return end
    _G._AUTO_INIT_DONE = true

    if _G.InitBotmasterMenu then
        local ok, err = pcall(_G.InitBotmasterMenu)
        if not ok then print("[BOTMASTER] InitBotmasterMenu ERROR: " .. tostring(err)) end
    end

    if _G.PBCEnabled == true and not _PBC.WH_TIMER then
        if type(_G.PBCOn) == "function" then pcall(_G.PBCOn) end
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
    local _retryCount = 0
    local function _retry()
        _retryCount = _retryCount + 1
        if _retryCount > 20 then
            print("[BOTMASTER] Auto-init FAILED — Game/PC never available")
            return
        end
        if _G.Game and _G.Game.AddGameTimer then
            pcall(function() _G.Game:AddGameTimer(0.5, false, _autoInit) end)
            return
        end
        local p = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(p) and p.AddGameTimer then
            pcall(function() p:AddGameTimer(0.5, false, _autoInit) end)
            return
        end
        pcall(function()
            if _G.Game and _G.Game.AddGameTimer then
                _G.Game:AddGameTimer(0.5, false, _retry)
            end
        end)
    end
    _retry()
end

_scheduleAutoInit()


--==========×==========×==========×==========×==========×==========×==========--
function BRPlayerCharacterBase:ctor()
end
function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")

  if Client then
    if not _G._POST_CONSTRUCT_INITED then
      _G._POST_CONSTRUCT_INITED = true
      if self.AddGameTimer then
        pcall(function() self:AddGameTimer(0.5, false, _autoInit) end)
      end
    end
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
    if _G.PBCEnabled == true and not _PBC.WH_TIMER then
      if type(_G.PBCOn) == "function" then pcall(_G.PBCOn) end
    end
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
FPPAnimMonitor = "GameLua.Mod.BaseMod.GamePlay.Feature.Player.FPPAnimMonitorFeature"}
}, "BRPlayerCharacterBase")