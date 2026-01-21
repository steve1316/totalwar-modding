function log(text, test)
    local mod_header_text = "LEAPOI";
    local logText = tostring(text)
    local logContext = tostring(mod_header_text)
    out(logContext .. ":  "..logText .. "\n")
end