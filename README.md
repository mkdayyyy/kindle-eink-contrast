# Kindle E Ink Temperature for KOReader

[Tiếng Việt](README.vi.md)

Choose an E Ink refresh temperature preset of 15°C, 10°C, 5°C or 0°C while reading. This started as a workaround for low contrast on a Paperwhite 5 at its default setting. The outcome depends on the panel and firmware. This is an experimental release with an English interface.

## Install

1. Exit KOReader. Copy `kindle-eink-temperature.koplugin` to `koreader/plugins/` on the Kindle. If you installed an earlier preview, remove the old `ppw5einktemp.koplugin` folder before reopening KOReader.
2. Reopen KOReader, open a book and go to **Settings → Screen → Kindle E Ink Temperature**.
3. Select **Hold 15°C while reading**, **Hold 10°C while reading**, **Hold 5°C while reading** or **Hold 0°C while reading**. Turn a page to see the effect. Select another preset or **Restore Auto** whenever you want to change it.
4. Your choice lasts for the current KOReader session. The plugin restores Auto when you close a book or put the Kindle to sleep, then reapplies your choice when you resume reading in the same session. A fresh KOReader launch starts with the plugin inactive.

If KOReader stops responding or cannot restore Auto, restart the Kindle. To uninstall, exit KOReader and remove `kindle-eink-temperature.koplugin` from `koreader/plugins/`.

## Device status

| Models | Driver path | Validation |
| --- | --- | --- |
| Paperwhite 5 and Paperwhite 5 Signature Edition (2021) | MediaTek HWTCON or HWTCON v2 | The user reported improved contrast on a Paperwhite 5 with the earlier single-model plugin at 10°C. This release was tested with mocked driver calls. |
| Paperwhite 6 family (2024), Kindle Basic (2022 and 2024) | MediaTek HWTCON or HWTCON v2 | Driver interface and KOReader model checks covered in simulation. Hardware reports welcome. |
| Paperwhite 1 (2012), Paperwhite 2 (2013), Paperwhite 3, Voyage, Oasis 1, Kindle Basic (2014 and 2016) | NXP i.MX EPDC | The legacy request layout and model checks were covered in simulation. Hardware reports welcome. |
| Oasis 2, Oasis 3, Paperwhite 4, Kindle Basic (2019) | NXP i.MX EPDC, Zelda or Rex request layout | Both request layouts and model checks were covered in simulation. Hardware reports welcome. |

The menu appears when the model, framebuffer driver name and request structure match. Other devices and incompatible driver combinations skip the plugin. The release has no test results on physical devices yet.

## How it works

- **MediaTek HWTCON:** Uses `MXCFB_SET_TEMPERATURE`. The driver may overwrite it with a sensor reading. In Hold mode the plugin checks just before a KOReader refresh and reapplies the selected temperature if the value changed.
- **MediaTek HWTCON v2:** Uses the driver's `write_temp` command to set or clear its temperature override. On both HWTCON drivers, **Show current setting** reads the effective temperature and zone reported by the driver.
- **NXP i.MX EPDC:** Sets the temperature field in KOReader's existing framebuffer request and restores the original Auto value. **Show current setting** reports what KOReader requests. The plugin has no driver readback for the temperature zone on this path.

The preset selects from the device's existing waveforms. It can change refresh speed, flashing and contrast. While a MediaTek override is active, the framebuffer driver may use it for refresh requests from other processes as well.

To report a result, include your Kindle model, Kindle firmware, KOReader version, the driver shown in **Show current setting**, and what changed at each temperature you tried. Include the result of **Restore Auto** and, for Hold mode, sleep and resume.

## Run the tests

From the repository root, run `luajit tests/run.lua /path/to/koreader`. Use an extracted KOReader package that contains `ffi/linux_fb_h.lua` and `ffi/mxcfb_kindle_h.lua`. The tests load those declarations and simulate framebuffer operations. They cover model detection, selecting each of the four presets, sleep and resume, and restoring Auto.

References: [Amazon's published Kindle kernel sources](https://digprjsurvey.amazon.com/csad/help/node/200203720) · [KOReader Kindle model detection](https://github.com/koreader/koreader/blob/master/frontend/device/kindle/device.lua) · [KOReader framebuffer refresh paths](https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer_mxcfb.lua)
