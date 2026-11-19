local koreader_root = assert(arg[1], "Usage: luajit tests/run.lua /path/to/koreader [plugin-directory]")
dofile(koreader_root .. "/ffi/linux_fb_h.lua")
dofile(koreader_root .. "/ffi/mxcfb_kindle_h.lua")

local plugin_dir = arg[2] or "kindle-eink-temperature.koplugin"
local plugin_file = assert(io.open(plugin_dir .. "/main.lua", "rb"))
local source = assert(plugin_file:read("*a"))
plugin_file:close()

local ffi = require('ffi')
local C = ffi.C
assert(ffi.sizeof('struct mxcfb_panel_info') == 112)
assert(C.MXCFB_SET_TEMPERATURE == 0x4004462C and C.MXCFB_GET_PANEL_INFO_MTK == 0x80704730)
assert(C.FBIOGET_FSCREENINFO == 0x4602 and C.TEMP_USE_AMBIENT == 0x1000)

local state, message, menu, next_tick
local function menuItem(label)
    for _, entry in ipairs(menu) do
        if entry.text == label then return entry end
    end
    error('No menu item: ' .. label)
end

local function refreshScreen(screen, waveform, width)
    assert(screen == package.loaded.device.screen and waveform == 'full' and width == 1236)
    state.last_refresh_temperature = state.temperature
    return 'refreshed', width
end
local function setTemp(temp)
    table.insert(state.writes, temp)
    if state.fail_write then return false end
    if not state.ignore_write then
        state.temperature = temp == 4096 and 25 or temp
    end
    return true
end

package.loaded['ffi'] = setmetatable({ C = setmetatable({ ioctl = function(fd, command, buffer)
    assert(fd == 5)
    if command == C.FBIOGET_FSCREENINFO then
        ffi.copy(buffer[0].id, state.driver)
        return 0
    elseif command == C.MXCFB_GET_PANEL_INFO_MTK then
        if state.fail_read then ffi.errno(25); return -1 end
        buffer[0].temp = state.temperature
        buffer[0].temp_zone = math.floor(state.temperature / 5)
        return 0
    elseif command == C.MXCFB_GET_TEMPERATURE then
        assert(state.driver == 'hwtcon')
        if state.fail_temperature_read then ffi.errno(25); return -1 end
        buffer[0] = state.temperature
        return 0
    end
    assert(command == C.MXCFB_SET_TEMPERATURE and state.driver == 'hwtcon')
    if setTemp(buffer[0]) then return 0 end
    ffi.errno(5)
    return -1
end }, { __index = C }) }, { __index = ffi })
package.loaded['ffi/mxcfb_kindle_h'] = true
package.loaded['ffi/linux_fb_h'] = true
package.loaded['ffi/util'] = { writeToSysfs = function(command, path)
    assert(path == '/proc/hwtcon/cmd' and state.driver == 'hwtcon_v2')
    return setTemp(tonumber(command:match('^write_temp (%d+)$')))
end }
package.loaded['logger'] = { warn = function() end, info = function() end }
package.loaded['ui/uimanager'] = {
    show = function(_, args) message = args.text end,
    nextTick = function(_, cb) next_tick = cb end,
}
package.loaded['ui/widget/infomessage'] = { new = function(_, args) return args end }
package.loaded['ui/widget/container/widgetcontainer'] = { extend = function(_, prototype) return prototype end }

local function instance(klass, document)
    local writes_before = #state.writes
    local test = setmetatable({ document = document, ui = { menu = { registerToMainMenu = function(_, obj)
        local items = {}
        obj:addToMainMenu(items)
        menu = items.kindle_eink_temperature.sub_item_table
    end } } }, { __index = klass })
    test:init()
    assert(#state.writes == writes_before)
    return test
end

local function create(model, driver, layout, default)
    state = { temperature = 25, writes = {}, driver = driver }
    message, menu, next_tick = nil, nil, nil
    local update_data = ffi.new(layout or 'struct mxcfb_update_data_mtk')
    update_data.temp = default or C.TEMP_USE_AMBIENT
    package.loaded.device = { model = model, screen = { fd = 5, mech_refresh = refreshScreen, update_data = update_data } }
    local klass = assert(loadstring(source))()
    if klass.disabled then return klass end
    return instance(klass, {}), klass, update_data
end

local function hold(value)
    return menuItem(('Hold %d°C while reading'):format(value))
end

assert(create('KindleScribe', 'hwtcon').disabled and not menu)
assert(create('KindleColorSoft', 'hwtcon_v2').disabled and not menu)
create('KindlePaperWhite5', 'unknown')
assert(not menu)
create('KindleOasis', 'hwtcon')
assert(not menu)
create('KindlePaperWhite5', 'hwtcon', 'struct mxcfb_update_data')
assert(not menu)

for _, driver in ipairs{'hwtcon', 'hwtcon_v2'} do
    local plugin, klass = create('KindlePaperWhite5', driver)
    assert(#menu == 6 and hold(15).enabled_func())
    plugin:onReaderReady()
    assert(state.temperature == 25 and #state.writes == 0)

    local screen = package.loaded.device.screen
    for _, value in ipairs{15, 10, 5, 0} do
        hold(value).callback()
        assert(state.temperature == value and plugin.active_temperature == value)
        menuItem('Show current setting').callback()
        assert(message:find(('Holding %d°C'):format(value), 1, true))
        local writes = #state.writes
        local result, width = screen:mech_refresh('full', 1236)
        assert(result == 'refreshed' and width == 1236 and #state.writes == writes)
        if driver == 'hwtcon' then
            assert(screen.mech_refresh ~= refreshScreen)
            state.temperature = 25
            screen:mech_refresh('full', 1236)
            assert(state.last_refresh_temperature == value and #state.writes == writes + 1)
        else
            assert(screen.mech_refresh == refreshScreen)
        end
    end

    assert(plugin:onSuspend() == nil and state.temperature == 25 and screen.mech_refresh == refreshScreen)
    plugin:onResume()
    assert(state.temperature == 0 and plugin.holding)
    plugin:onCloseDocument()
    assert(state.temperature == 25 and screen.mech_refresh == refreshScreen)

    local library = instance(klass)
    assert(not hold(0).enabled_func())
    library:onResume()
    assert(state.temperature == 25)

    local book = instance(klass, {})
    book:onReaderReady()
    assert(state.temperature == 0 and book.holding)
    menuItem('Restore Auto').callback()
    book:onSuspend()
    book:onResume()
    assert(state.temperature == 25 and screen.mech_refresh == refreshScreen)

    state.fail_read = true
    local initial = #state.writes
    hold(15).callback()
    assert(#state.writes == initial and message:find('Could not read', 1, true))
    state.fail_read = false

    state.fail_write = true
    hold(15).callback()
    assert(state.temperature == 25 and message:find('Could not set', 1, true))
    state.fail_write = false

    state.ignore_write = true
    hold(15).callback()
    assert(state.writes[#state.writes] == C.TEMP_USE_AMBIENT and not book.active_temperature)
    assert(message:find('Could not confirm', 1, true))
    state.ignore_write = false

    hold(5).callback()
    state.fail_write = true
    menuItem('Restore Auto').callback()
    assert(state.temperature == 5 and book.active_temperature == 5)
    assert(screen.mech_refresh == refreshScreen and message:find('Could not restore Auto', 1, true))
    state.fail_write = false
    menuItem('Restore Auto').callback()
    assert(state.temperature == 25 and not book.active_temperature)

    if driver == 'hwtcon' then
        hold(0).callback()
        state.fail_temperature_read = true
        screen:mech_refresh('full', 1236)
        assert(state.last_refresh_temperature == 25 and screen.mech_refresh == refreshScreen and next_tick)
        next_tick()
        assert(message:find('Could not keep 0°C', 1, true))
        book:onResume()
        assert(state.temperature == 25)
        state.fail_temperature_read = false
    end

    hold(10).callback()
    book:stopPlugin()
    book:onResume()
    assert(state.temperature == 25 and screen.mech_refresh == refreshScreen)
end

for _, model in ipairs{'KindlePaperWhite5SE', 'KindlePaperWhite6', 'KindleBasic4', 'KindleBasic5'} do
    for _, driver in ipairs{'hwtcon', 'hwtcon_v2'} do
        local plugin = create(model, driver)
        assert(menu and #state.writes == 0)
        hold(5).callback()
        assert(state.temperature == 5)
        plugin:onCloseWidget()
        assert(state.temperature == 25)
    end
end

local epdc_models = {
    KindlePaperWhite = 'struct mxcfb_update_data',
    KindlePaperWhite2 = 'struct mxcfb_update_data',
    KindleVoyage = 'struct mxcfb_update_data',
    KindlePaperWhite3 = 'struct mxcfb_update_data',
    KindleOasis = 'struct mxcfb_update_data',
    KindleOasis2 = 'struct mxcfb_update_data_zelda',
    KindleOasis3 = 'struct mxcfb_update_data_zelda',
    KindlePaperWhite4 = 'struct mxcfb_update_data_rex',
    KindleBasic = 'struct mxcfb_update_data',
    KindleBasic2 = 'struct mxcfb_update_data',
    KindleBasic3 = 'struct mxcfb_update_data_rex',
}

create('KindleOasis2', 'mxc_epdc_fb', 'struct mxcfb_update_data')
assert(not menu)
create('KindleOasis', 'mxc_epdc_fb', epdc_models.KindleOasis, 5)
assert(not menu and package.loaded.device.screen.update_data.temp == 5)

for model, layout in pairs(epdc_models) do
    local default = layout == 'struct mxcfb_update_data' and C.TEMP_USE_AUTO or C.TEMP_USE_AMBIENT
    local plugin, klass, update_data = create(model, 'mxc_epdc_fb', layout, default)
    local screen = package.loaded.device.screen
    assert(menu and update_data.temp == default)
    for _, value in ipairs{15, 10, 5, 0} do
        hold(value).callback()
        assert(update_data.temp == value and screen.mech_refresh == refreshScreen)
        menuItem('Show current setting').callback()
        assert(message:find(('%d°C requested'):format(value), 1, true))
    end
    plugin:onSuspend()
    assert(update_data.temp == default)
    plugin:onResume()
    assert(update_data.temp == 0)
    plugin:onCloseDocument()
    assert(update_data.temp == default)

    local book = instance(klass, {})
    book:onReaderReady()
    assert(update_data.temp == 0)
    menuItem('Restore Auto').callback()
    assert(update_data.temp == default and #state.writes == 0)

    screen.update_data = ffi.new(layout)
    screen.update_data.temp = default
    hold(10).callback()
    assert(update_data.temp == default and screen.update_data.temp == default)
    assert(message:find('framebuffer update data changed', 1, true))
end

print("Passed Kindle E Ink Temperature simulations.")
