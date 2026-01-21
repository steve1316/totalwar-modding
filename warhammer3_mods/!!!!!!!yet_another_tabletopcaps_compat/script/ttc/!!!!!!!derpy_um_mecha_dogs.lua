-- derpy_um_mecha_dogs
local caps = {
    -- Chaos Dwarfs
    {"chd_mecha_dog_flamer", "rare", 2},
    {"chd_mecha_biped_walker", "rare", 3},
    {"chd_mecha_dog_cannon", "rare", 2},
    {"chd_mecha_biped_walker_ror", "rare", 3}
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end