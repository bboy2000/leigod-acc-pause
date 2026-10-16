local m, s, o

m = Map("leigod-guard", "雷神无人值守 - 自动暂停时长")
m.description = "监控游戏设备流量：无人玩游戏超过设定时间后，自动调用雷神云端接口暂停时长计费；设备重新活动可自动恢复。account_token 获取：可点下方\"快捷登录\"按钮自动获取，或电脑浏览器登录 leigod.com 后按 F12 打开控制台，输入 JSON.parse(localStorage.getItem(\"account_token\")).account_token 回车，把结果粘贴到下面。token 过期后（日志出现 400006/400007）重新按此方法获取。"

s = m:section(NamedSection, "config", "guard", "监控设置")
s.addremove = false

o = s:option(Value, "token", "account_token")
o.password = true
o.rmempty = true

o = s:option(DummyValue, "_quicklogin", "快捷登录")
o.description = "弹窗登录雷神账号，自动把获取到的 account_token 写入上方配置"
o.template = "leigod/login-widget"

o = s:option(DynamicList, "devices", "游戏设备IP")
o.description = "要监控的局域网设备IP，可填多台。IP 最好在设备上设置静态IP或DHCP绑定"

o = s:option(Value, "idle_minutes", "空闲暂停阈值(分钟)")
o.default = "15"
o.datatype = "range(1,720)"

o = s:option(Value, "poll_seconds", "流量采样间隔(秒)")
o.default = "30"
o.datatype = "range(5,600)"

o = s:option(Value, "min_bytes", "活跃判定阈值(字节/采样)")
o.description = "单个采样周期内设备流量超过该字节数视为在玩游戏。默认 102400（约 27KB/s），过滤系统后台流量"
o.default = "102400"
o.datatype = "uinteger"

o = s:option(Flag, "auto_resume", "设备活动时自动恢复计费")
o.default = o.disabled

s2 = m:section(NamedSection, "config", "guard", "独立状态页设置")
s2.addremove = false

o = s2:option(Value, "standalone_port", "独立页面端口")
o.default = "8081"
o.datatype = "port"
o.description = "脱离 QWRT 框架的独立状态页端口（http://网关IP:端口）。保存后由守护自动应用切换；若端口已被其他服务占用，访问独立页面会提示\"端口冲突请重设\""

o = s2:option(Value, "standalone_key", "独立页面访问密钥")
o.password = true
o.rmempty = true
o.description = "访问独立状态页所需的密钥（无需用户名），留空则独立页面拒绝所有访问"

m.on_after_commit = function()
	luci.sys.call("/etc/init.d/leigod-guard restart >/dev/null 2>&1")
end

return m
