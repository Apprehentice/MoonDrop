local textutils = {}

function textutils.nick_from_address(addr)
  return string.match(addr, "[^%a%[%]%\`_{|}%^]*([%a%[%]%\`_{|}%^][%w%[%]%\`_{|}%-%^]*)!?.*") or ""
end

function textutils.user_from_address(addr)
  return string.match(addr, ".*!([^@]+).*") or ""
end

function textutils.host_from_address(addr)
  return string.match(addr, ".*!.*@(.*)") or ""
end

return textutils
