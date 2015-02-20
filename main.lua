---
-- This is a sample program file for the MoonDrop IRC Bot Framework.
-- This file will create a bot, bind a couple of functions to it, and
-- connect it to a local IRC server running on port 6667.

local MoonDrop = require("moondrop")
local txt = require("moondrop.textutils")

Client = MoonDrop()
Client:setNick("MoonDrop")
Client:setUserName("MoonDrop")
Client:setRealName("MoonDrop Bot")

Client:on("ready", function(self)
  local channel = self:open("#channel")
  channel:on("ready", function(self)
    self:on("PRIVMSG", function(self, user, message)
      if message == "Hello, MoonDrop!" then
        self:message("Hello, " .. txt.nick_from_address(user) .. "!")
      end
    end)

    self:on("PRIVMSG", function(self, user, message)
      if message == "Go away, MoonDrop!" then
        self:message("Okay, " .. txt.nick_from_address(user) .. "!")
        self:getClient():quit()
      end
    end)
  end)
end)

Client:connect("localhost", 6667)
