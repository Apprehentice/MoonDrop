local logger = {}

function logger:info(line)
  line = tostring(line)
  print(string.format("%s [INFO] %s", os.date("%Y-%m-%d %H:%M:%S", os.time()), line))
end

function logger:warn(line)
  line = tostring(line)
  print(string.format("%s [WARN] %s", os.date("%Y-%m-%d %H:%M:%S", os.time()), line))
end

function logger:error(line)
  line = tostring(line)
  print(string.format("%s [ERROR] %s", os.date("%Y-%m-%d %H:%M:%S", os.time()), line))
end

return logger
