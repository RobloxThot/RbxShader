
--[[
	================== RbxShader ===================
	
	Last updated: 12/05/2025
	Version: 1.8.5 (191)
	
	Learn more about the engine via: https://github.com/AnotherSubatomo/RbxShader
	
	Copyright (c) 2024, AnotherSubatomo
	SPDX-License-Identifier: MIT
]]

--!native
--!nonstrict

-- // Types
local Types = shadeloadfile('shaders/utils/Common.luau')
export type EngineConfiguration = Types.EngineConfiguration
export type ShaderBuffer = Types.ShaderBuffer
export type Shader = Types.Shader

-- // Dependencies
local STRegistry = game:GetService('SharedTableRegistry')
local Run = game:GetService('RunService')
local Culler = shadeloadfile('shaders/Culler.luau')
local argue = shadeloadfile('shaders/utils/Argue.luau')

local Client = game.Players.LocalPlayer
local Mouse = Client:GetMouse()

local function GuiIsAWorldspaceGui(Screen: BillboardGui | SurfaceGui): boolean
	return Screen:IsA('SurfaceGui') or Screen:IsA('BillboardGui')
end

-- // Defaults
local MOUSE_REF = '@Mouse'

local ERROR = {
	"Configs.ScreenDivision must be divisible by 4 for maximum performance." ,
	"Canvas size too big, it's subdivisions are greater than 1024 x 1024 (EditableImage dimension limit)." ,
	"CanvasSize was unspecified." ,
	"Invalid shader given." ,
	"Shaders can't be ran on the server-side. I mean, just why?" ,
	"A ShaderID is necessary in manipulating specific shaders that run on the same script." ,
	"ShaderID has already been used." ,
	"Given ShaderID to fetch shader is not in use, are you sure it's typed correctly?" ,
	"Canvas size too small, minimum size is 4 x 4." ,
	"Given screen to display the shader in was invalid."
}

local DEFAULT_CONFIGURATIONS = {
	InterlaceFactor = 2 ,
	DualAxisInterlacing = true ,
	ScreenDivision = 16 ,
	IsBlurred = false ,
	OriginOffset = Vector2.yAxis, --> by OpenGL convention
	CountDirection = Vector2.new(1, -1) --> by OpenGL convention
} :: EngineConfiguration

argue( Run:IsClient() , ERROR[5] )

local MoveConnections = {}
local ShaderPrograms = {}
local RbxShader = {}

-- /* Create the environment for running the shader. */
function RbxShader.new(
	ShaderID : string ,
	Shader : string ,
	Configuration : EngineConfiguration ,
	Host : Script ,
	Screen : GuiBase2d ,
	CanvasSize : Vector2
)
	-- /* Set default values */
	local BuiltConfiguration = loadstring(Shader)().CONFIGURATION
	Configuration = if type(Configuration) ~= "table" then {} else Configuration
	
	for Field : string , Default : any in DEFAULT_CONFIGURATIONS do
		Configuration[Field] = Configuration[Field] or BuiltConfiguration[Field] or Default
	end
	
	-- /* Screen can only be divided into multiples-of-4 parts */
	argue( Configuration.ScreenDivision % 4 == 0 , ERROR[1] )
	argue( CanvasSize , ERROR[3] )
	argue( typeof(Shader) == 'Instance', ERROR[4] )
	argue( CanvasSize:Min(Vector2.one*4) == Vector2.one*4 , ERROR[9] )
	
	-- /* Calculate the dimensions of each subdivisions */
	local Subdivisions = Vector2.new(Configuration.ScreenDivision / 4, 4)
	local SubcanvasSize = (CanvasSize / Subdivisions):Floor()
	local ExcessSize = CanvasSize - SubcanvasSize * Subdivisions
	
	argue( SubcanvasSize:Max((Vector2.one*1025)) == Vector2.one*1025 , ERROR[2] )
	
	-- /* Create the screen from where we'll drawn on */
	argue( Screen and Screen:IsA('GuiBase2d') , ERROR[10] )
	Screen.Name = 'SHADERSCREEN@'..Shader.Name
	
	local Background = Instance.new('Frame')
	Background.Parent = Screen
	Background.Size = UDim2.fromScale(1, 1)
	Background.BackgroundColor3 = Color3.new()
	Background.Name = 'Background'
	
	local Centerer = Instance.new('UIListLayout')
	Centerer.Parent = Background
	Centerer.HorizontalAlignment = 'Center'
	Centerer.VerticalAlignment = 'Center'

	local Easel = Instance.new('ImageButton')
	Easel.Parent = Background
	Easel.Size = UDim2.fromScale(1, 1)
	Easel.BackgroundTransparency = 1
	Easel.Name = 'Easel'
	Easel.Image = ''
	
	local AspectRatio = Instance.new('UIAspectRatioConstraint')
	AspectRatio.Parent = Easel
	AspectRatio.AspectRatio = CanvasSize.X / CanvasSize.Y

	-- /* Create shader host. */
	argue( ShaderID, ERROR[6] )
	argue( not ShaderPrograms[ShaderID] , ERROR[7] )

	local Parent = Instance.new('Folder')
	Parent.Parent = Host
	Parent.Name = 'SHADER@'..ShaderID
	ShaderPrograms[ShaderID] = Parent
	
	local Link = Instance.new('ObjectValue')
	Link.Parent = Parent
	Link.Value = Screen
	Link.Name = 'ScreenLink'
	
	-- /* Assume inputs are needed */
	local iMouse = SharedTable.new({ X = 1, Y = 1 })
	
	Easel.MouseButton1Down:Connect( function ()
		-- # Only consider input when mouse is at the display of the shader.
		MoveConnections[ShaderID] = Mouse.Move:Connect( function ()
			local vs = workspace.CurrentCamera.ViewportSize		--@ viewport pixel size
			local eas = Easel.AbsoluteSize						--@ easel absolute pixel size
			local e = vs - eas									--@ excess viewport space
			local mp = Vector2.new(
				Mouse.X + Easel.AbsolutePosition.X,
				Mouse.Y + 48 + e.Y / 2
			)
			local rmp = mp - e									--@ relative mouse position (to easel)
			
			local Position = (rmp / eas * CanvasSize):Ceil()	--@ mouse position relative to canvas size

			SharedTable.update( iMouse, 'X', function()
				return Position.X
			end)
			SharedTable.update( iMouse, 'Y', function()
				return Position.Y
			end)
		end)
	end)

	local function DisconnectMoveConnection()
		if MoveConnections[ShaderID] ~= nil then
			MoveConnections[ShaderID]:Disconnect()
		end
	end
	
	Easel.MouseButton1Up:Connect(DisconnectMoveConnection)
	Easel.MouseLeave:Connect(DisconnectMoveConnection)
	
	STRegistry:SetSharedTable(ShaderID..MOUSE_REF, iMouse)
	
	-- /* Parallelize canvas calculations */
	local Workers : {Actor} = {}
	
	-- # Create worker threads
	for _ = 1, Configuration.ScreenDivision do
		local Actor = Instance.new('Actor')
		script.Worker:Clone().Parent = Actor
		table.insert(Workers, Actor)
	end
	
	script.Worker:Destroy()
	
	-- # Parent all actors under self
	for _, Actor : Actor in Workers do
		Actor.Parent = Parent
	end
	
	task.defer( function ()
		-- /* Set environment context */
		for y = 1, Subdivisions.Y do
			for x = 1, Subdivisions.X do
				local Actor = Workers[y+4*(x-1)]
				local CanvasCoords = Vector2.new(x, y)
				Actor:SendMessage('SetContext', ShaderID, Shader, CanvasSize, CanvasCoords, Configuration)
			end
		end

		-- /* Create the subcanvases */
		for y = 1, Subdivisions.Y do
			for x = 1, Subdivisions.X do
				local Actor = Workers[y+4*(x-1)]
				Actor.Worker.Name = 'Worker@'..y+4*(x-1)

				local Size : Vector2 = SubcanvasSize
				if y == Subdivisions.Y then Size += Vector2.new(0, ExcessSize.Y) end
				if x == Subdivisions.X then Size += Vector2.new(ExcessSize.X, 0) end

				local Scale : Vector2 = Size / CanvasSize
				Actor:SendMessage('MakeCanvas', Easel, Scale, Size)
			end
		end
	end)
	
	-- /* Put culler into action (if `Screen` is a SurfaceGui or BillboardGui) */
	-- * Runs the program if the part that the Gui is adorned to is still visible
	--	 on the user viewport or is within the max distance, pauses it if not.
	
	local WorldspaceGui = GuiIsAWorldspaceGui(Screen) and Screen
		or Screen:FindFirstChildOfClass('SurfaceGui') or Screen:FindFirstChildOfClass('BillboardGui')
	
	if WorldspaceGui then
		Culler.add(WorldspaceGui, ShaderID, function ()
			for _, Actor : Actor in Workers do
				Actor:SendMessage( 'Resume' , ShaderID )
			end
		end, function ()
			for _, Actor : Actor in Workers do
				Actor:SendMessage( 'Pause' , ShaderID )
			end
		end)
	end
end

--==============================
--[=[ SHADER PROGRAM ACTIONS ]=]
--==============================

local function GetWorkers ( Engine : LocalScript )
	local Workers = {}

	for _, Child : Instance in Engine:GetChildren() do
		if Child:IsA('Actor') then
			table.insert(Workers, Child)
		end
	end

	return Workers
end

local function CallAction( Action : string , ShaderID : string )
	argue( ShaderID, ERROR[6] )
	argue( ShaderPrograms[ShaderID], ERROR[8] )

	local Workers = GetWorkers( ShaderPrograms[ShaderID] )
	
	task.defer( function ()
		for _, Actor : Actor in Workers do
			Actor:SendMessage( Action )
		end
	end)
end

-- /* Halts a shader from running. */
function RbxShader.stop( ShaderID : string )
	CallAction( 'Stop', ShaderID )
end

-- /* Runs a shader. (Not a resume function) */
function RbxShader.run( ShaderID : string )
	CallAction( 'Run' , ShaderID )
end

-- /* Pauses the shader. */
function RbxShader.pause( ShaderID : string )
	CallAction( 'Pause', ShaderID )
end

-- /* Resumes the shader. */
function RbxShader.resume( ShaderID : string )
	CallAction( 'Resume', ShaderID )
end

-- /* Halts and terminates a shader program. */
function RbxShader.clear( ShaderID : string )
	argue( ShaderID, ERROR[6] )
	argue( ShaderPrograms[ShaderID], ERROR[8] )

	local Host = ShaderPrograms[ShaderID]
	local Screen = Host.ScreenLink.Value
	local Workers = GetWorkers( Host )

	for _, Actor : Actor in Workers do
		Actor:SendMessage( 'Stop' )
	end
	
	if GuiIsAWorldspaceGui(Screen) then
		Culler.remove(ShaderID)
	end
	
	STRegistry:SetSharedTable(ShaderID..MOUSE_REF, nil)
	Screen:Destroy()
	Host:ClearAllChildren()
	Host:Destroy()
end

-- /* Sets the configuration of the shader to something else. */
function RbxShader.set(
	ShaderID : string ,
	Configuration : EngineConfiguration
)
	argue( ShaderID, ERROR[6] )
	argue( ShaderPrograms[ShaderID], ERROR[8] )
	
	local Workers = GetWorkers( ShaderPrograms[ShaderID] )
	
	for Field : string , Default : any in DEFAULT_CONFIGURATIONS do
		Configuration[Field] = Configuration[Field] or Default
	end
	
	RbxShader.pause( ShaderID )
	
	for _, Actor : Actor in Workers do
		Actor:SendMessage( 'Set' , Configuration )
	end

	RbxShader.resume( ShaderID )
end



--================================
--[=[ SHADER UTILITY LIBRARIES ]=]
--================================

-- /* Retrieve the graphics-specific math library. */
function RbxShader:GetMathLib()
	return shadeloadfile('shaders/GraphicsMathLib.luau')
end

return RbxShader