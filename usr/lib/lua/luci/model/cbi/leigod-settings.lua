local m, s, o

m = Map("leigod-manager", "雷神加速器 - 基本设置")

s = m:section(NamedSection, "base", "leigod-manager", "基本配置")
s.addremove = false

o = s:option(Flag, "enabled", "启用加速器")
o.rmempty = false

o = s:option(ListValue, "mode", "加速模式")
o:value("tun", "TUN")
o:value("proxy", "PROXY")
o.rmempty = false

o = s:option(ListValue, "log_level", "日志等级")
o:value("info", "info")
o:value("debug", "debug")
o:value("warn", "warn")
o:value("error", "error")
o.rmempty = false

m.on_after_commit = function()
	luci.sys.call("/etc/init.d/leigod-acc restart >/dev/null 2>&1")
end

return m
