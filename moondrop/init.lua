local logger = require("moondrop.logger")

local class = require("middleclass")
local socket = require("socket")
local Stream = require("moondrop.Stream")
local MoonDrop = class("MoonDrop")

function MoonDrop:initialize()
  self.nick = ""
  self.user = ""
  self.realName = ""
  self.mode = 0
  self.server = ""
  self.port = 0
  self.password = ""

  self.interval = 0.333

  self.channels = {}
  self.users = {}
  self.events = {}
  self.isupport = {}

  self._connectTime = 0
  self._ready = false
  self._quit = false
  self._msgQueue = {}
  self._msgTime = socket.gettime()

  self:on("tick", function(self)
    if socket.gettime() > self._msgTime + self.interval and self._msgQueue[1] then
      local msg = table.remove(self._msgQueue, 1)
      logger:info("-> " .. msg)
      self._socket:send(msg .. "\n")
      self._msgTime = socket.gettime()
    end
  end)

  self:on("PRIVMSG", function(self, prefix, channel, message)
    self:fireChannel("PRIVMSG", channel, prefix, message)
  end)

  self:on("NOTICE", function(self, prefix, channel, message)
    self:fireChannel("NOTICE", channel, prefix, message)
  end)

  self:on("JOIN", function(self, prefix, channel)
    self:fireChannel("JOIN", channel, prefix)
  end)

  self:on("PART", function(self, prefix, channel, reason)
    self:fireChannel("PART", channel, prefix, reason)
  end)

  self:on("QUIT", function(self, prefix, channel)
    self:fireChannel("QUIT", channel, prefix)
  end)

  self:on("MODE", function(self, prefix, channel, modes, ...)
    self:fireChannel("MODE", channel, prefix, modes, ...)
  end)

  self:on("NICK", function(self, prefix, newnick)
    for k, v in pairs(self.channels) do
      v:fire("NICK", prefix, newnick)
    end

    local u = self:getUser(prefix)
    if u then
      local suffix = u:getAddress():match(".*(!.*)")
      u:setAddress(newnick .. suffix)
    end

    if txt.nick_from_address(prefix):lower() == self.nick:lower() then
      self.nick = newnick
    end
  end)

  self:on("PING", function(self, prefix, echo)
    self:send("PONG :" .. echo)
  end)

  -- RPL_ISUPPORT
  self:on("005", function(self, prefix, target, ...)
    local options = {...}
    for i, v in ipairs(options) do
      local key, value = v:match("(.*)=(.*)")
      if key and value then
        self.isupport[key] = value
      end
    end
  end)

  -- RPL_WHOISUSER
  self:on("311", function(self, prefix, target, nick, user, host, _, realname)
    local u = self:getUser(nick .. "!" .. user .. "@" .. host)
    if u then
      u:setAddress(nick .. "!" .. user .. "@" .. host)
      u:setRealName(realname)
    else
      self:addUser(nick .. "!" .. user .. "@" .. host, realname)
    end
  end)

  -- RPL_WHOISCHANNELS
  self:on("319", function(self, prefix, target, nick, ...)
    local channels = {...}
    local u = self:findUsers(nick .. "!.*")[1]
    if u then
      u:clearChannels()
      for i, v in ipairs(channels) do
        u:addChannel(v)
      end
    end
  end)

  -- RPL_CHANNELMODEIS
  self:on("324", function(self, prefix, target, channel, modes, ...)
    self:fireChannel("324", channel, prefix, modes, ...)
  end)

  -- RPL_TOPIC
  self:on("332", function(self, prefix, target, channel, topic)
    self:fireChannel("332", channel, prefix, topic)
  end)

  -- RPL_TOPICWHOTIME
  self:on("333", function(self, prefix, target, channel, user, time)
    self:fireChannel("333", channel, prefix, user, time)
  end)

  -- RPL_INVITELIST
  self:on("346", function(self, prefix, target, channel, id)
    self:fireChannel("367", channel, id)
  end)

  -- RPL_ENDOFINVITELIST
  self:on("347", function(self, prefix, target, channel, id)
    self:fireChannel("367", channel)
  end)

  -- RPL_EXCEPTLIST
  self:on("348", function(self, prefix, target, channel, id)
    self:fireChannel("367", channel, id)
  end)

  -- RPL_ENDOFEXCEPTLIST
  self:on("349", function(self, prefix, target, channel, id)
    self:fireChannel("367", channel)
  end)

  -- RPL_NAMEREPLY
  self:on("353", function(self, prefix, target, unused1, channel, names)
    self:fireChannel("353", channel, prefix, names)
  end)

  -- RPL_ENDOFNAMES
  self:on("366", function(self, prefix, target, channel)
    self:fireChannel("366", channel, prefix)
  end)

  -- RPL_BANLIST
  self:on("367", function(self, prefix, target, channel, id)
    self:fireChannel("367", channel, id)
  end)

  -- RPL_ENDOFBANLIST
  self:on("368", function(self, prefix, target, channel, id)
    self:fireChannel("367", channel)
  end)

  self:on("KICK", function(self, prefix, channel, target)
    self:fireChannel("KICK", channel, prefix, target, reason)
  end)
end

function MoonDrop:getNick()
  return self.nick
end

function MoonDrop:setNick(nick)
  self.nick = nick
end

function MoonDrop:getRealName()
  return self.realName
end

function MoonDrop:setRealName(realName)
  self.realName = realName
end

function MoonDrop:getUserName()
  return self.user
end

function MoonDrop:setUserName(user)
  self.user = user
end

function MoonDrop:getMode()
  return self.mode
end

function MoonDrop:setMode(mode)
  self.mode = mode
end

function MoonDrop:getInterval()
  return self.interval
end

function MoonDrop:setInterval(interval)
  self.interval = interval
end

function MoonDrop:open(channel, password)
  assert(type(channel) == "string", "bad argument #1 to 'open' (string expected, got " .. type(channel) .. ")")
  channel = string.lower(channel)
  if not self.channels[channel] then
    self.channels[channel] = Stream(self, channel, password, self.isupport["prefix"], self.isupport["chantypes"], self.isupport["chanmodes"])
  end

  return self.channels[channel]
end

function MoonDrop:close(channel, reason)
  if self.channels[channel] then
    channel:close(reason)
    self.channels[channel] = nil
  end
end

function MoonDrop:addUser(u, realname)
  if type(u) == "string" then
    local u = User(u, realname)
  elseif type(u) == "table" then
    table.insert(self.users, u)
  end
end

function MoonDrop:removeUser(user)
  for i, v in ipairs(self.users) do
    if v == user then
      table.remove(self.users, i)
      break
    end
  end
end

function MoonDrop:getUser(address)
  for i, v in ipairs(self.users) do
    if v:getAddress() == address then
      return v
    end
  end
end

function MoonDrop:getUsers()
  return unpack(self.users)
end

function MoonDrop:findUsers(pattern)
  local results = {}
  for i, v in ipairs(self.users) do
    if v:getAddress():match(address) then
      table.insert(results, v)
    end
  end
  return results
end

function MoonDrop:send(msg)
  for line in msg:gmatch("[^\r\n]+") do
    table.insert(self._msgQueue, line)
  end
end

function MoonDrop:on(event, func)
  if not self.events[event] then self.events[event] = {} end
  table.insert(self.events[event], func)
end

function MoonDrop:fire(event, ...)
  if self.events[event] then
    for i, f in ipairs(self.events[event]) do
      local res = f(self, ...)
      if res then return end
    end
  end
end

function MoonDrop:fireChannel(event, channel, ...)
  if self.channels[channel] then
    self.channels[channel]:fire(event, ...)
  end
end

function MoonDrop:connect(server, port, pass)
  self.server = server
  self.port = port
  self.password = pass

  local err
  self._socket = socket.tcp()
  local res, err = self._socket:connect(server, port)
  assert(res, "Failed to connect to server (" .. tostring(err) .. ")")

  self._socket:settimeout(0)
  if pass then
    logger:info("-> PASS " .. pass)
    self._socket:send("PASS " .. pass .. "\n")
  end
  logger:info("-> NICK " .. self.nick)
  self._socket:send("NICK " .. self.nick .. "\n")
  logger:info("-> USER " .. self.user .. " " .. self.mode .. " * :" .. self.realName)
  self._socket:send("USER " .. self.user .. " " .. self.mode .. " * :" .. self.realName .. "\n")
  logger:info("Firing connect triggers...")
  self:fire("connect")
  logger:info("Connect triggers finished.")
  logger:info("Starting message loop...")
  self._connectTime = os.time()
  while err == nil or err == "timeout" and not self._quit do
    local msg
    msg, err = self._socket:receive("*l")
    if err and err ~= "timeout" then
      logger:error(err)
      break
    end

    if msg then
      local fullmsg = msg
      local prefix = ""
      local args = {}
      local trailing = ""

      if string.sub(msg, 1, 1) == ":" then
        prefix = string.sub(msg, 2, string.find(msg, " ") - 1)
        msg = string.sub(msg, string.find(msg, " ") + 1, #msg)
      end

      if string.find(msg, " :") then
        trailing = string.sub(msg, string.find(msg, " :") + 2, #msg):match("(.*%S)")
        msg = string.sub(msg, 1, string.find(msg, " :") - 1)
      end

      local argpart = string.sub(msg, #prefix + 2, #msg - (#trailing - 1))
      for arg in msg:gmatch("%S+") do
        table.insert(args, arg)
      end
      table.insert(args, trailing)

      command = args[1]

      table.remove(args, 1)

      logger:info("<- " .. fullmsg)

      self:fire("raw", fullmsg)
      self:fire(command, prefix, unpack(args))

      if command == "PING" and not self._ready then
        logger:info("Bot is ready!")
        self._ready = true
        self:fire("ready")
      end
    end

    -- Some servers require you respond to a PING before doing anything.
    -- I have no idea if waiting 5 seconds here is necessary, but
    -- I don't think it hurts anything, either.
    if os.time() - self._connectTime >= 5 and not self._ready then
      logger:info("Bot is ready!")
      self._ready = true
      self:fire("ready")
    end

    for k, v in pairs(self.channels) do
      if not v:isOpen() then
        self.channels[k] = nil
      end
    end

    if self._ready then
      self:fire("tick")
    end
  end
  self:fire("disconnect")
  self._socket:close()

  if not self._quit and err ~= "closed" then
    error(tostring(err))
  end
end

function MoonDrop:disconnect()
  self._quit = true
end

function MoonDrop:quit(reason)
  self:send("QUIT :" .. (reason or ""))
end

return MoonDrop
