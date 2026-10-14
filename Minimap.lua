local _, ns = ...

-- A plain minimap button (no LibDBIcon): left-click sleeps or wakes the addon,
-- right-click opens settings, drag moves it around the minimap.
local button
local atan2 = math.atan2 or math.atan

local function Place()
	local angle = math.rad(ns.db.minimapAngle or 225)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Runs only while the button is being dragged.
local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	ns.db.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
	Place()
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Simply Fishing")
	if ns.db.asleep then
		GameTooltip:AddLine(ns.db.autoSlept and "Sleeping (In an Instance)" or "Sleeping", 1, 0.33, 0.33)
	else
		GameTooltip:AddLine("Awake", 0.25, 1, 0.25)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(ns.db.asleep and "Left-Click: Wake" or "Left-Click: Sleep", 1, 1, 1)
	GameTooltip:AddLine("Right-Click: Settings", 1, 1, 1)
	GameTooltip:AddLine("Middle-Click: Hide", 1, 1, 1)
	GameTooltip:AddLine("Drag: Move", 1, 1, 1)
	GameTooltip:Show()
end

function ns.UpdateMinimap()
	if not button then return end
	button:SetShown(not ns.db.minimapHidden)
	local asleep = ns.db.asleep and true or false
	button.icon:SetDesaturated(asleep)
	button.icon:SetAlpha(asleep and 0.6 or 1)
	if GameTooltip:IsOwned(button) then ShowTooltip(button) end
end

function ns.CreateMinimapButton()
	if button then return end
	button = CreateFrame("Button", "SimplyFishingMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- Same geometry as LibDBIcon on Retail: icon and background centered (1px up)
	-- in the 50px border's opening, so the icon fills the ring evenly.
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(24, 24)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("CENTER", 0, 1)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetTexture("Interface\\Icons\\Trade_Fishing")
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("CENTER", 0, 1)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then return ns.ToggleUI() end
		if mouse == "MiddleButton" then
			GameTooltip:Hide()
			ns.SetOption("minimapHidden", true)
			return ns.Print("Minimap button hidden. Tick Minimap Button in /sfish to show it again.")
		end
		local _, msg = ns.SetAsleep(not ns.db.asleep)
		ns.Print(msg)
	end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", FollowCursor)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)

	Place()
	ns.UpdateMinimap()
end
