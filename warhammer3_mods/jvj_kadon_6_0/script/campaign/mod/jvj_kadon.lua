--- Entry point for Kadon's Scrolls of Binding. Registers the MCT settings listeners and the script-owned scroll drops.

--- Publish CA engine globals into `_G` before any `require`. Some mod loadouts run `script/campaign/mod/*.lua` in a custom environment that
--- does not share `cm`, `core` and `out` with required modules (same workaround as LEAPOI).
_G.core = core
_G.cm = cm
_G.out = out
_G.get_mct = get_mct

local settings = require("script/jvj_kadon/settings")
local drops = require("script/jvj_kadon/drops")

settings.register_listeners()
drops.register_listeners()
