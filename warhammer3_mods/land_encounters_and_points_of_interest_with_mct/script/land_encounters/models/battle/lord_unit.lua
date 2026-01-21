require("script/land_encounters/utils/random")

-------------------------
--- Properties definition
-------------------------
local LordUnit = {
    level_ranges = {},
    possible_subtypes = {},
    possible_forenames = {},
    possible_clan_names = {},
    possible_family_names = {},
    possible_other_names = {},
    possible_skills = {},
    possible_ancillaries = {},
    possible_traits = {}
}


-------------------------
--- Class Methods
-------------------------
function LordUnit:generate_random_level()
    out("DEBUG - random_number(): " .. self.level_ranges[2] .. " - " .. self.level_ranges[1])
    return random_number(self.level_ranges[2], self.level_ranges[1])
end


function LordUnit:generate_subtype()
    if #self.possible_subtypes > 0 then
        local random_subtype = self.possible_subtypes[random_number(#self.possible_subtypes)]
        return random_subtype
    end
    return ""
end


function LordUnit:generate_random_forename()
    if #self.possible_forenames > 0 then
        return self.possible_forenames[random_number(#self.possible_forenames)]
    end
    return ""
end


function LordUnit:generate_random_clan_name()
    if #self.possible_clan_names > 0 then
        return self.possible_clan_names[random_number(#self.possible_clan_names)]
    end
    return ""
end


function LordUnit:generate_random_family_name()
    if #self.possible_family_names > 0 then
        return self.possible_family_names[random_number(#self.possible_family_names)]
    end
    return ""
end


function LordUnit:generate_random_other_name()
    if #self.possible_other_names > 0 then
        return self.possible_other_names[random_number(#self.possible_other_names)]
    end
    return ""
end

function LordUnit:generate_ancillaries(selected_lord_subtype)
    if next(self.possible_ancillaries) ~= nil and next(self.possible_ancillaries[selected_lord_subtype]) ~= nil then
        local active_ancillaries = {}
        for i = 1, #self.possible_ancillaries[selected_lord_subtype] do
            if self.possible_ancillaries[selected_lord_subtype][i][2] >= random_number(100) then
                table.insert(active_ancillaries, self.possible_ancillaries[selected_lord_subtype][i][1])
            end
        end
        return active_ancillaries
    else
        return {}
    end
end

function LordUnit:generate_trait(selected_lord_subtype)
    if next(self.possible_traits) ~= nil then
        return self.possible_traits[selected_lord_subtype] 
    end
    return nil
end

-------------------------
--- Constructors
-------------------------
function LordUnit:newFrom(lord_data)
    local t = { 
        subtype= nil, 
        level_ranges= lord_data.level_ranges, 
        possible_subtypes = lord_data.possible_subtypes,
        possible_forenames= lord_data.possible_forenames, 
        possible_clan_names= lord_data.possible_clan_names,
        possible_family_names= lord_data.possible_family_names,
        possible_other_names= lord_data.possible_other_names,
        possible_skills = lord_data.skills,
        possible_ancillaries = lord_data.ancillaries,
        possible_traits = lord_data.traits
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return LordUnit