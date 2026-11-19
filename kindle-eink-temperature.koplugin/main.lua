local Device = require("device")
local epdc_layouts = {
    KindlePaperWhite = "struct mxcfb_update_data",
    KindlePaperWhite2 = "struct mxcfb_update_data",
    KindleVoyage = "struct mxcfb_update_data",
    KindlePaperWhite3 = "struct mxcfb_update_data",
    KindleOasis = "struct mxcfb_update_data",
    KindleOasis2 = "struct mxcfb_update_data_zelda",
    KindleOasis3 = "struct mxcfb_update_data_zelda",
    KindlePaperWhite4 = "struct mxcfb_update_data_rex",
    KindleBasic = "struct mxcfb_update_data",
    KindleBasic2 = "struct mxcfb_update_data",
    KindleBasic3 = "struct mxcfb_update_data_rex",
}
local mtk_models = {
    KindlePaperWhite5 = true,
    KindlePaperWhite5SE = true,
    KindlePaperWhite6 = true,
    KindleBasic4 = true,
    KindleBasic5 = true,
}
local epdc_layout = epdc_layouts[Device.model]
if not epdc_layout and not mtk_models[Device.model] then
    return { disabled = true }
end

local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local C = ffi.C
local hold_temperature

local TemperaturePlugin = WidgetContainer:extend{ name = "kindle-eink-temperature" }

local function showMessage(message, timeout)
    UIManager:show(InfoMessage:new{ text = message, timeout = timeout })
end

local function describeTemperature(panel)
    if panel.zone then
        return ("%d°C (zone %d)"):format(panel.temperature, panel.zone)
    end
    if panel.temperature >= 0x1000 then
        return "Auto"
    end
    return ("%d°C requested"):format(panel.temperature)
end

function TemperaturePlugin:init()
    if not Device.screen or type(Device.screen.fd) ~= "number" or Device.screen.fd < 0 then
        return
    end
    self.fd = Device.screen.fd
    local supported, err = pcall(function()
        require("ffi/linux_fb_h")
        require("ffi/mxcfb_kindle_h")
        local screen_info = ffi.new("struct fb_fix_screeninfo[1]")
        assert(C.ioctl(self.fd, C.FBIOGET_FSCREENINFO, screen_info) == 0)
        self.driver = ffi.string(screen_info[0].id, 16):match("^[^%z]*")
        if epdc_layout then
            assert(self.driver == "mxc_epdc_fb" or self.driver == "mxc_epdc_v2_fb", "unexpected EPDC driver")
            local update = Device.screen.update_data
            assert(update and ffi.istype(epdc_layout, update), "unexpected EPDC update structure")
            local default = update.temp
            assert(default == C.TEMP_USE_AUTO or default == C.TEMP_USE_AMBIENT, "EPDC already has a temperature override")
            self.epdc_update = update
            self.ambient_temperature = default
            return
        end
        assert(self.driver == "hwtcon" or self.driver == "hwtcon_v2", "unexpected HWTCON driver")
        assert(ffi.istype("struct mxcfb_update_data_mtk", Device.screen.update_data), "unexpected MTK update structure")
        self.panel_info = ffi.new("struct mxcfb_panel_info[1]")
        self.temperature = ffi.new("int32_t[1]")
        self.get_panel_info = C.MXCFB_GET_PANEL_INFO_MTK
        self.get_temperature = C.MXCFB_GET_TEMPERATURE
        self.set_temperature = C.MXCFB_SET_TEMPERATURE
        self.ambient_temperature = C.TEMP_USE_AMBIENT
    end)
    if not supported then
        logger.warn("Kindle E Ink Temperature: unsupported framebuffer", Device.model, err)
        return
    end
    self.ui.menu:registerToMainMenu(self)
end

function TemperaturePlugin:readPanel()
    if self.epdc_update then
        if not rawequal(self.epdc_update, Device.screen.update_data) then
            return nil, "framebuffer update data changed"
        end
        return { temperature = self.epdc_update.temp }
    end
    if C.ioctl(self.fd, self.get_panel_info, self.panel_info) ~= 0 then
        return nil, "ioctl errno " .. ffi.errno()
    end
    return { temperature = self.panel_info[0].temp, zone = self.panel_info[0].temp_zone }
end

function TemperaturePlugin:writeTemperature(value)
    if self.epdc_update then
        -- On EPDC this field is copied into each request by KOReader's own refresh code.
        self.epdc_update.temp = value
        return true
    end
    if self.driver == "hwtcon_v2" then
        -- v2's ioctl writes the sensor cache. The debug override has its own Auto state.
        local written = ffiUtil.writeToSysfs("write_temp " .. value, "/proc/hwtcon/cmd")
        return written == true, "HWTCON v2 write_temp"
    end
    self.temperature[0] = value
    if C.ioctl(self.fd, self.set_temperature, self.temperature) ~= 0 then
        return false, "ioctl errno " .. ffi.errno()
    end
    return true
end

function TemperaturePlugin:removeRefreshCheck()
    if self.checked_refresh and Device.screen.mech_refresh == self.checked_refresh then
        Device.screen.mech_refresh = self.original_refresh
    end
    self.checked_refresh = nil
    self.original_refresh = nil
end

function TemperaturePlugin:installRefreshCheck(value)
    local original_refresh = Device.screen.mech_refresh
    local function refresh(screen, ...)
        -- First-generation HWTCON may overwrite the setting with a sensor reading.
        if self.checked_refresh == refresh then
            local ok = C.ioctl(self.fd, self.get_temperature, self.temperature) == 0
            if ok and self.temperature[0] ~= value then
                ok = self:writeTemperature(value)
            end
            if not ok then
                hold_temperature = nil
                local restored = self:restoreAuto()
                UIManager:nextTick(function()
                    if restored then
                        showMessage(("Could not keep %d°C. Restored Auto."):format(value))
                    else
                        showMessage(("Could not keep %d°C or restore Auto. Select Restore Auto or restart the Kindle."):format(value))
                    end
                end)
            end
        end
        return original_refresh(screen, ...)
    end
    self.original_refresh = original_refresh
    self.checked_refresh = refresh
    Device.screen.mech_refresh = refresh
end

function TemperaturePlugin:restoreAuto(force)
    self.holding = nil
    self:removeRefreshCheck()
    if not self.active_temperature and not force then
        return true
    end
    local ok, err = self:writeTemperature(self.ambient_temperature)
    if ok then
        self.active_temperature = nil
    else
        logger.warn("Kindle E Ink Temperature: failed to restore Auto", err)
    end
    return ok, err
end

function TemperaturePlugin:onSuspend()
    self:restoreAuto()
end

function TemperaturePlugin:onResume()
    if hold_temperature and self.document and self.ambient_temperature and not self.holding then
        if not self:setTemperature(hold_temperature, true) then
            hold_temperature = nil
        end
    end
end

TemperaturePlugin.onReaderReady = TemperaturePlugin.onResume
TemperaturePlugin.onCloseDocument = TemperaturePlugin.onSuspend
TemperaturePlugin.onCloseWidget = TemperaturePlugin.onSuspend

function TemperaturePlugin:stopPlugin()
    hold_temperature = nil
    self:restoreAuto()
end

function TemperaturePlugin:setTemperature(value, quiet)
    if self.driver == "hwtcon" and type(Device.screen.mech_refresh) ~= "function" then
        showMessage("This version of KOReader does not support holding a temperature on this device.")
        return
    end
    local before, read_error = self:readPanel()
    if not before then
        showMessage(("Could not read the current setting (%s)."):format(read_error))
        return
    end
    local ok, err = self:writeTemperature(value)
    if not ok then
        showMessage(("Could not set the temperature (%s)."):format(err))
        return
    end

    self.active_temperature = value
    self:removeRefreshCheck()
    hold_temperature = nil

    local after = self:readPanel()
    if not after or after.temperature ~= value then
        if self:restoreAuto() then
            showMessage("Could not confirm the requested setting. Restored Auto.")
        else
            showMessage("Could not confirm the requested setting or restore Auto. Select Restore Auto or restart the Kindle.")
        end
        return
    end

    local after_label = describeTemperature(after)
    logger.info("Kindle E Ink Temperature:", Device.model, self.driver, describeTemperature(before), after_label)
    self.holding = true
    hold_temperature = value
    if self.driver == "hwtcon" then
        self:installRefreshCheck(value)
    end
    if not quiet then
        showMessage(("Holding %s while reading. Select Restore Auto to stop."):format(after_label), 3)
    end
    return true
end

function TemperaturePlugin:showPanel()
    local panel, read_error = self:readPanel()
    if not panel then
        showMessage(("Could not read the current setting (%s)."):format(read_error))
        return
    end
    local status = "Plugin override inactive."
    if self.holding then
        status = ("Holding %d°C while reading."):format(self.active_temperature)
    elseif self.active_temperature then
        status = ("Last setting: %d°C"):format(self.active_temperature)
    end
    showMessage(("%s · %s\n%s\n%s"):format(Device.model, self.driver, describeTemperature(panel), status))
end

function TemperaturePlugin:addToMainMenu(menu_items)
    local function holdItem(value)
        return {
            text = ("Hold %d°C while reading"):format(value),
            enabled_func = function() return self.document ~= nil end,
            callback = function() self:setTemperature(value) end,
        }
    end
    menu_items.kindle_eink_temperature = {
        text = "Kindle E Ink Temperature",
        sorting_hint = "screen",
        sub_item_table = {
            holdItem(15),
            holdItem(10),
            holdItem(5),
            holdItem(0),
            { text = "Show current setting", callback = function() self:showPanel() end },
            { text = "Restore Auto", callback = function()
                hold_temperature = nil
                local ok, err = self:restoreAuto(true)
                if ok then
                    showMessage("Restored Auto. Turn a page to compare.", 2)
                else
                    showMessage(("Could not restore Auto (%s). Restart the Kindle."):format(err))
                end
            end },
        },
    }
end

return TemperaturePlugin
