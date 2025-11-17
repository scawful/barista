-- Minimal JSON encode/decode (Derived from rxi/json.lua, MIT License)
-- https://github.com/rxi/json.lua

local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\\\",
  [ "\"" ] = "\\\"",
  [ "\b" ] = "\\b",
  [ "\f" ] = "\\f",
  [ "\n" ] = "\\n",
  [ "\r" ] = "\\r",
  [ "\t" ] = "\\t",
}

local escape_char = function(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_nil()
  return "null"
end

local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  if stack[val] then error("circular reference") end
  stack[val] = true

  if rawget(val, 1) ~= nil or next(val) == nil then
    local n = 0
    for k in pairs(val) do
      if type(k) ~= "number" then
        error("invalid array index " .. tostring(k))
      end
      n = n + 1
    end
    if n ~= #val then
      error("invalid array (non-sequential keys)")
    end
    for i, v in ipairs(val) do
      table.insert(res, encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"
  else
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid object key " .. tostring(k))
      end
      table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end

local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_number(val)
  if val ~= val or val <= -math.huge or val >= math.huge then
    error("invalid number " .. tostring(val))
  end
  return string.format("%.14g", val)
end

local encode_map = {
  [ "nil"     ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
}

encode = function(val, stack)
  local t = type(val)
  local f = encode_map[t]
  if f then
    return f(val, stack)
  end
  error("cannot encode type " .. t)
end

function json.encode(val)
  return encode(val)
end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = {
  [ '"'  ] = '"',
  [ "\\" ] = "\\",
  [ "/"  ] = "/",
  [ "b"  ] = "\b",
  [ "f"  ] = "\f",
  [ "n"  ] = "\n",
  [ "r"  ] = "\r",
  [ "t"  ] = "\t",
}
local literals      = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil,
}
local literal_chars = create_set("t", "f", "n")
local valid_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")

local function decode_error(str, idx, msg)
  error(string.format("Error: %s at position %d", msg, idx))
end

local function skip_whitespace(str, idx)
  while space_chars[str:sub(idx, idx)] do
    idx = idx + 1
  end
  return idx
end

local function parse_literal(str, idx)
  local literal = str:sub(idx, idx + 3)
  if literals[literal] ~= nil then
    return literals[literal], idx + #literal
  end

  literal = str:sub(idx, idx + 4)
  if literals[literal] ~= nil then
    return literals[literal], idx + #literal
  end

  decode_error(str, idx, "invalid literal")
end

local function parse_number(str, idx)
  local end_idx = idx
  local chr = str:sub(end_idx, end_idx)
  local acceptable = "+-0123456789eE."

  while acceptable:find(chr, 1, true) do
    end_idx = end_idx + 1
    chr = str:sub(end_idx, end_idx)
  end

  local number = tonumber(str:sub(idx, end_idx - 1))
  if not number then
    decode_error(str, idx, "invalid number")
  end
  return number, end_idx
end

local function unicode_codepoint_as_utf8(n)
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    local byte0 = 0xc0 + math.floor(n / 0x40)
    local byte1 = 0x80 + (n % 0x40)
    return string.char(byte0, byte1)
  elseif n <= 0xffff then
    local byte0 = 0xe0 + math.floor(n / 0x1000)
    local byte1 = 0x80 + (math.floor(n / 0x40) % 0x40)
    local byte2 = 0x80 + (n % 0x40)
    return string.char(byte0, byte1, byte2)
  elseif n <= 0x10ffff then
    local byte0 = 0xf0 + math.floor(n / 0x40000)
    local byte1 = 0x80 + (math.floor(n / 0x1000) % 0x40)
    local byte2 = 0x80 + (math.floor(n / 0x40) % 0x40)
    local byte3 = 0x80 + (n % 0x40)
    return string.char(byte0, byte1, byte2, byte3)
  end
  error(string.format("invalid unicode codepoint '%x'", n))
end

local function parse_string(str, idx)
  idx = idx + 1
  local res = ""
  local start = idx

  while idx <= #str do
    local c = str:sub(idx, idx)

    if c == '"' then
      res = res .. str:sub(start, idx - 1)
      return res, idx + 1
    end

    if c == "\\" then
      res = res .. str:sub(start, idx - 1)
      local esc = str:sub(idx + 1, idx + 1)
      if esc == "u" then
        local hex = str:sub(idx + 2, idx + 5)
        if not hex:match("%x%x%x%x") then
          decode_error(str, idx, "invalid unicode escape")
        end
        res = res .. unicode_codepoint_as_utf8(tonumber(hex, 16))
        idx = idx + 6
      else
        local mapped = escape_chars[esc]
        if not mapped then
          decode_error(str, idx, "invalid escape char '" .. esc .. "'")
        end
        res = res .. mapped
        idx = idx + 2
      end
      start = idx
    else
      idx = idx + 1
    end
  end

  decode_error(str, idx, "unterminated string")
end

local function parse_array(str, idx)
  idx = idx + 1
  local res = {}
  local n = 1

  idx = skip_whitespace(str, idx)
  if str:sub(idx, idx) == "]" then
    return res, idx + 1
  end

  while idx <= #str do
    local val
    val, idx = parse(str, idx)
    res[n] = val
    n = n + 1

    idx = skip_whitespace(str, idx)
    local chr = str:sub(idx, idx)
    if chr == "]" then
      return res, idx + 1
    end
    if chr ~= "," then
      decode_error(str, idx, "expected ']' or ','")
    end
    idx = skip_whitespace(str, idx + 1)
  end

  decode_error(str, idx, "unterminated array")
end

local function parse_object(str, idx)
  idx = idx + 1
  local res = {}

  idx = skip_whitespace(str, idx)
  if str:sub(idx, idx) == "}" then
    return res, idx + 1
  end

  while idx <= #str do
    if str:sub(idx, idx) ~= '"' then
      decode_error(str, idx, "expected string for key")
    end

    local key
    key, idx = parse_string(str, idx)

    idx = skip_whitespace(str, idx)
    if str:sub(idx, idx) ~= ":" then
      decode_error(str, idx, "expected ':'")
    end

    idx = skip_whitespace(str, idx + 1)
    local val
    val, idx = parse(str, idx)

    res[key] = val

    idx = skip_whitespace(str, idx)
    local chr = str:sub(idx, idx)
    if chr == "}" then
      return res, idx + 1
    end
    if chr ~= "," then
      decode_error(str, idx, "expected '}' or ','")
    end
    idx = skip_whitespace(str, idx + 1)
  end

  decode_error(str, idx, "unterminated object")
end

parse = function(str, idx)
  idx = idx or 1
  idx = skip_whitespace(str, idx)
  if idx > #str then
    decode_error(str, idx, "unexpected end of input")
  end

  local chr = str:sub(idx, idx)

  if chr == '"' then
    return parse_string(str, idx)
  elseif chr == "{" then
    return parse_object(str, idx)
  elseif chr == "[" then
    return parse_array(str, idx)
  elseif chr == "-" or chr:match("%d") then
    return parse_number(str, idx)
  elseif literal_chars[chr] then
    return parse_literal(str, idx)
  end

  decode_error(str, idx, "invalid character '" .. chr .. "'")
end

function json.decode(str)
  local res, idx = parse(str, 1)
  idx = skip_whitespace(str, idx)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end

return json
