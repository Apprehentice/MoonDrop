local class = require("middleclass")
local User = class("MoonDrop.User")

function User:initialize(address, realname)
  self.address = address or ""
  self.realName = realname or ""
  self.channels = {}
  self.data = {}
end

function User:getAddress()
  return self.address
end

function User:setAddress(address)
  assert(type(address) == "string", "bad argument #1 to 'setAddress' (string expected, got " .. type(address) .. ")")
  self.address = address
end

function User:getRealName()
  return self.realName
end

function User:setRealName(realname)
  self.realName = realname
end

function User:getChannels()
  return {unpack(self.channels)}
end

function User:addChannel(chan)
  self.channels[chan] = true
end

function User:removeChannel(chan)
  self.channels[chan] = nil
end

function User:isInChannel(chan)
  return self.channels[chan] ~= nil
end

function User:clearChannels()
  self.channels = {}
end

function User:setData(key, value)
  self.data[key] = value
end

function User:getData(key)
  return self.data[key]
end

return User
