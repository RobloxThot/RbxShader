
--[=[
	Host
	A sample script on how you would
	run a shader.
]=]

--!native

getgenv().shadeloadfile = function(file)
    if isfile(file) and not shared.GBDeveloper then
        data = readfile(file)
    else
        data = game:HttpGet('https://raw.githubusercontent.com/Roblox-Thot/RBX-gameboy/refs/heads/main/' .. file:gsub('shaders/','src/'), true)
        writefile(file, data)
    end
    return loadstring(data,file)()
end

-- // Dependencies
local Client = game.Players.LocalPlayer
local RbxShader = shadeloadfile('shaders/init.luau')

-- // Configurations
local CONFIGURATIONS = {
	InterlaceFactor = 2 ,
	DualAxisInterlacing = true ,
	ScreenDivision = 4 ,
	IsBlurred = false
}

local CANVAS_SIZE = Vector2.new(180, 120) -- try (192, 108) too!
local SHADER = script.Shaders.VoxelShader

local SCREEN = Instance.new('ScreenGui')
SCREEN.Parent = Client.PlayerGui
SCREEN.IgnoreGuiInset = true
SCREEN.ResetOnSpawn = false

RbxShader.new( SHADER.Name, SHADER, CONFIGURATIONS, script, SCREEN, CANVAS_SIZE)
RbxShader.run( SHADER.Name )

task.wait(5)

RbxShader.pause( SHADER.Name )

task.wait(5)

RbxShader.resume( SHADER.Name )