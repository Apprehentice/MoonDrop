local logger = require("moondrop.logger")

local class = require("middleclass")
local User = require("moondrop.User")
local txt = require("moondrop.textutils")
local Stream = class("moondrop.Stream")

function Stream:initialize(client, name, password, prefix, chantypes, chanmodes)
  assert(client, "bad client")
  assert(type(name) == "string", "bad name (expected string)")
  assert(password == nil or type(password) == "string", "bad password (expected string)")
  assert(prefix == nil or type(prefix) == "string", "bad prefix (expected string)")
  assert(chantypes == nil or type(chantypes) == "string", "bad chantypes (expected string)")
  assert(chanmodes == nil or type(chanmodes) == "string", "bad chanmodes (expected string)")
  self.events = {}

  self.nicks = {}
  self.topic = ""
  self.topicUser = ""
  self.topicTime = os.time()

  self._client = client
  self._name = name
  self._password = password or ""
  self._closed = false
  self._ready = false

  self._chanTypes = chantypes or "#&"
  self._isChannel = false

  for t in self._chanTypes:gmatch(".") do
    if string.sub(self._name, 1, 1) == t then
      self._isChannel = true
      break
    end
  end

  self._inNames = false
  self._inBans = false
  self._inExcepts = false
  self._inInvites = false
  self._namesBuffer = {}

  if chanmodes then
    local a, b, c, d = chanmodes:match("([^,]),([^,]),([^,]),([^,])")
    self.aModes = {}
    for m in a:gmatch(".") do
      self.aModes[m] = {}
    end

    self.bModes = {}
    for m in b:gmatch(".") do
      self.bModes[m] = ""
    end

    self.cModes = {}
    for m in c:gmatch(".") do
      self.cModes[m] = ""
    end

    self.dModes = {}
    for m in d:gmatch(".") do
      self.dModes[m] = false
    end
  else
    self.aModes = {
      b = {},
      e = {},
      I = {}
    }

    self.bModes = {
      k = false
    }

    self.cModes = {
      l = false
    }

    self.dModes = {
      a = false,
      i = false,
      m = false,
      n = false,
      q = false,
      p = false,
      s = false,
      r = false,
      t = false
    }
  end

  if prefix then
    self.uModes = {}
    self.prefixes = {}
    local modes, symbols = prefix:gmatch("%((.*)%)(.*)")

    for i = 1, #modes do
      local m = string.sub(modes, i, i)
      local s = string.sub(symbols, i, i)
      self.prefixes[s] = m
      self.uModes[m] = {}
    end
  else
    self.prefixes = {
      ["@"] = "o",
      ["+"] = "v"
    }
    self.uModes = {
      v = {},
      o = {}
    }
  end

  if string.sub(self._name, 1, 1) == "#" then
    self._client:send("JOIN " .. self._name .. " " .. self._password)
  end

  local function partquit(self, prefix)
    for k, _ in pairs(self.nicks) do
      local n = txt.nick_from_address(prefix)
      if self:hasNick(n) then
        self:removeNick(n)
      end
    end
  end

  local function modeset(self, prefix, mode, ...)
    local operation = true
    local args = {...}
    for i = 1, #mode do
      local c = string.sub(mode, i, i)
      if c == "+" then
        operation = true
      elseif c == "-" then
        operation = false
      else
        if self.aModes[c] ~= nil then
          if operation then
            local id = table.remove(args, 1)
            if id then
              table.insert(self.aModes[c], id)
            end
          else
            for i, v in ipairs(self.aModes[c]) do
              if v == args[1] then
                table.remove(self.aModes[c], i)
                break
              end
            end
          end
        elseif self.bModes[c] ~= nil then
          if args[1] and operation then
            self.bModes[c] = table.remove(args, 1)
            if c == "k" then
              self._password = self.bModes[c]
            end
          elseif args[1] == self.bModes[c] then
            self.bModes[c] = false
            if c == "k" then
              self._password = ""
            end
          end
        elseif self.cModes[c] ~= nil then
          if args[1] and operation then
            self.cModes[c] = table.remove(args, 1)
          else
            self.cModes[c] = false
          end
        elseif self.dModes[c] ~= nil then
          self.dModes[c] = operation
        elseif self.uModes[c] ~= nil then
          if operation then
            local val = table.remove(args, 1)
            if val ~= "" then
              table.insert(self.uModes[c], val)
            end
          else
            for i, v in ipairs(self.uModes[c]) do
              if v == args[1] then
                table.remove(self.uModes[c], i)
                break
              end
            end
          end
        end
      end
    end
  end

  self:on("JOIN", function(self, prefix)
    if txt.nick_from_address(prefix):lower() == self:getClient():getNick():lower() and not self._ready then
      self._ready = true
      self:fire("ready")
    end
    self:addNick(txt.nick_from_address(prefix))
  end)

  self:on("PART", partquit)

  self:on("QUIT", partquit)

  self:on("KICK", function(self, kicker, target, reason)
    if target == self._client:getNick() then
      self._closed = true
    else
      self.removeNick(target)
    end
  end)

  self:on("TOPIC", function(self, prefix, topic)
    self._topic = topic
    self._topicUser = prefix
    self._topicTime = os.time()
  end)

  self:on("NICK", function(self, prefix, newnick)
    local n = txt.nick_from_address(prefix)
    if self:hasNick(n) then
      self:removeNick(n)
      self:addNick(newnick)
    end

    for _, m in pairs(self.uModes) do
      for i, u in ipairs(m) do
        if u == n then
          m[i] = newnick
        end
      end
    end
  end)

  self:on("MODE", modeset)

  self:on("324", modeset)

  self:on("332", function(self, prefix, topic)
    self._topic = topic
  end)
  self:on("333", function(self, prefix, user, time)
    self._topicUser = user
    self._topicTime = time
  end)

  self:on("346", function(self, id)
    if not self._inInvites then
      if self.aModes["I"] then
        self.aModes["I"] = {}
      end
      self._inInvites = true
    end

    if self.aModes["I"] and id ~= "" then
      table.insert(self.aModes["I"], id)
    end
  end)

  self:on("347", function(self)
    self._inInvites = false
  end)

  self:on("348", function(self, id)
    if not self._inExcepts then
      if self.aModes["e"] then
        self.aModes["e"] = {}
      end
      self._inExcepts = true
    end

    if self.aModes["e"] and id ~= "" then
      table.insert(self.aModes["e"], id)
    end
  end)

  self:on("349", function(self)
    self._inExcepts = false
  end)

  self:on("353", function(self, prefix, names)
    if not self._inNames then
      self._namesBuffer = {}
      self._inNames = true
    end

    local patternprefixes = ""
    for k, _ in pairs(self.prefixes) do
      patternprefixes = patternprefixes .. "%" ..  k
    end

    for name in names:gmatch("([" .. patternprefixes .. "]*[^%a%[%]%\`]*[%a%[%]%\`_{|}%^][%w%[%]%\`_{|}%-%^]*)%s*") do
      table.insert(self._namesBuffer, name)
    end
  end)

  self:on("366", function(self, prefix)
    self._inNames = false

    local patternprefixes = ""
    for k, _ in pairs(self.prefixes) do
      patternprefixes = patternprefixes .. "%" ..  k
    end

    for i, v in ipairs(self._namesBuffer) do
      local modes, nick = v:match("([" .. patternprefixes .. "]*)([^%a%[%]%\`]*[%a%[%]%\`_{|}%^][%w%[%]%\`_{|}%-%^]*)")
      if not self:hasNick(nick) then
        self:addNick(nick)
      end

      for m in modes:gmatch(".") do
        if self.prefixes[m] and self.uModes[self.prefixes[m]] then
          table.insert(self.uModes[self.prefixes[m]], nick)
        end
      end
    end
  end)

  self:on("367", function(self, id)
    if not self._inBans then
      if self.aModes["b"] then
        self.aModes["b"] = {}
      end
      self._inBans = true
    end

    if self.aModes["b"] and id ~= "" then
      table.insert(self.aModes["b"], id)
    end
  end)

  self:on("368", function(self)
    self._inBans = false
  end)

  self:on("ready", function(self)
    if self._isChannel then
      client:send("MODE " .. self._name)
      if self.aModes["b"] then
        client:send("MODE " .. self._name .. " +b")
      end
      if self.aModes["e"] then
        client:send("MODE " .. self._name .. " +e")
      end
      if self.aModes["I"] then
        client:send("MODE " .. self._name .. " +I")
      end
    end
  end)

  if not self._isChannel then
    self._ready = true
    self:fire("ready")
  end
end

function Stream:on(event, func)
  assert(self._closed == false, "Stream closed")
  if not self.events[event] then self.events[event] = {} end
  table.insert(self.events[event], func)
end

function Stream:fire(event, ...)
  assert(self._closed == false, "Stream closed")
  if self.events[event] then
    for i, f in ipairs(self.events[event]) do
      f(self, ...)
    end
  end
end

function Stream:close(reason)
  if not self._closed then
    if string.sub(channel, 1, 1) == "#" then
      self._client:send("PART " .. self._name .. " " .. (reason or ""))
    end
    self._closed = true
    self.events = {}
  end
end

function Stream:message(message)
  assert(self._closed == false, "Stream closed")
  message = tostring(message)
  local lines = {}
  for line in message:gmatch("[^\r\n]+") do
    self._client:send("PRIVMSG " .. self._name .. " :" .. line)
  end
end

function Stream:notice(message)
  assert(self._closed == false, "Stream closed")
  message = tostring(message)
  local lines = {}
  for line in message:gmatch("[^\r\n]+") do
    self._client:send("NOTICE " .. self._name .. " :" .. line)
  end
end

function Stream:mode(modes)
  assert(self._closed == false, "Stream closed")
  assert(type(modes) == "string", "bad argument #1 to 'mode' (string expected, got " .. type(mode) .. ")")
  modes = tostring(modes):gsub("[\r\n]+", "")
  self._client:send("MODE " .. self._name .. " " .. modes)
end

function Stream:kick(user, reason)
  assert(self._closed == false, "Stream closed")
  user = tostring(user):gsub("[\r\n]+", "")
  reason = tostring(reason):gsub("[\r\n]+", "")
  self._client:send("KICK " .. self._name .. " " .. user .. " :" .. reason)
end

function Stream:addNick(nick)
  assert(self._closed == false, "Stream closed")
  self.nicks[nick] = true
end

function Stream:removeNick(nick)
  assert(self._closed == false, "Stream closed")
  self.nicks[nick] = nil
end

function Stream:getNicks()
  return self.nicks
end

function Stream:hasNick(nick)
  return self.nicks[nick] ~= nil
end

function Stream:getName()
  return self._name
end

function Stream:getPassword()
  return self._password
end

function Stream:isOpen()
  return not self._closed
end

function Stream:isChannel()
  return self._isChannel
end

function Stream:getMode(mode)
  return self.aModes[mode] or self.bModes[mode] or self.cModes[mode] or self.dModes[mode] or self.uModes[mode]
end

function Stream:getClient()
  return self._client
end

function Stream:getTopic()
  return self.topic
end

function Stream:getTopicUser()
  return self.topicUser
end

function Stream:getTopicTime()
  return self.topicTime
end

return Stream
