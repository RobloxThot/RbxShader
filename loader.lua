getgenv().shadeloadfile = function(file)
    if isfile(file) and not shared.GBDeveloper then
        data = readfile(file)
    else
        data = game:HttpGet('https://raw.githubusercontent.com/Roblox-Thot/RBX-gameboy/refs/heads/main/' .. file:gsub('shaders/','src/'), true)
        writefile(file, data)
    end
    return loadstring(data,file)()
end

