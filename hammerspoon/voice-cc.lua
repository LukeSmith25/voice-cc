-- voice-cc — push-to-talk → STT → keystroke injection.
-- Default hotkey: Cmd+Alt+Space (hold to record, release to transcribe+inject).
-- Edit MODS/KEY below to remap.

local SCRIPTS = os.getenv("HOME") .. "/.claude/voice-cc/hooks"
local DATA    = os.getenv("HOME") .. "/.claude-data/voice-cc"
local LOG     = DATA .. "/log/stt.log"

local MODS = {"ctrl", "alt"}
local KEY  = "space"

local recordTask = nil
local recordingPath = nil

local function log(line)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("[%FT%T] ") .. line .. "\n"); f:close() end
end

local function startRecord()
  if recordTask then return end
  -- Interrupt any in-flight TTS so we can barge in
  hs.task.new(SCRIPTS .. "/interrupt.sh", nil, {}):start()
  recordingPath = string.format("%s/recordings/%s.wav", DATA, os.date("%Y%m%dT%H%M%S"))
  recordTask = hs.task.new("/bin/bash", nil, {SCRIPTS .. "/record.sh", recordingPath})
  recordTask:start()
  hs.alert.closeAll()
  hs.alert.show("● rec", 0.3)
  log("rec start " .. recordingPath)
end

local function stopRecord()
  if not recordTask then return end
  recordTask:terminate()
  recordTask = nil
  local wav = recordingPath
  recordingPath = nil
  if not wav then return end
  log("rec stop, transcribing " .. wav)
  hs.task.new("/usr/bin/env", function(_, stdout, stderr)
    local text = (stdout or ""):gsub("^%s+", ""):gsub("%s+$", "")
    log("stt: '" .. text .. "'")
    if #text == 0 then return end
    hs.task.new(SCRIPTS .. "/inject.sh", nil, {text}):start()
  end, {"python3", SCRIPTS .. "/transcribe.py", wav}):start()
end

hs.hotkey.bind(MODS, KEY, startRecord, stopRecord)
log("voice-cc loaded: " .. table.concat(MODS, "+") .. "+" .. KEY)
