-- luci-app-leigod-manager Lua controller (for QWRT Lua dispatcher)
-- 含无人值守(leigod-guard)页面
module("luci.controller.leigod", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/leigod-manager") then
		return
	end

	entry({"admin", "services", "leigod"}, firstchild(), "雷神加速器", 60).dependent = false

	entry({"admin", "services", "leigod", "overview"}, template("leigod/overview"), "运行状态", 10).leaf = true
	entry({"admin", "services", "leigod", "settings"}, cbi("leigod-settings"), "基本设置", 20).leaf = true
	entry({"admin", "services", "leigod", "guard"}, cbi("leigod-guard"), "无人值守", 25).leaf = true
	entry({"admin", "services", "leigod", "logs"}, template("leigod/logs"), "运行日志", 30).leaf = true
	entry({"admin", "services", "leigod", "action"}, call("action")).leaf = true
end

function action()
	local act = tostring(luci.http.formvalue("act") or "")
	if act == "start" or act == "stop" or act == "restart" then
		luci.sys.call("ubus call leigod " .. act .. " >/dev/null 2>&1")
	elseif act == "billpause" or act == "billresume" then
		-- 云端计费开关: pause=暂停计费 / resume=恢复计费
		local uci = require "luci.model.uci".cursor()
		local token = uci:get("leigod-guard", "config", "token") or ""
		if token ~= "" then
			local api = (act == "billresume") and "/api/user/recover" or "/api/user/pause"
			luci.sys.call("curl -s -m 8 -A 'Mozilla/5.0' -H 'Origin: https://www.leigod.com' -H 'Referer: https://www.leigod.com/' -H 'Content-Type: application/json' --data '{\"account_token\":\"" .. token .. "\"}' 'https://webapi.leigod.com" .. api .. "?os_type=4&region_code=1&src_channel=guanwang&lang=zh_CN' >/dev/null 2>&1 &")
		end
		-- 恢复计费时通知守护重置空闲计时
		if act == "billresume" then
			luci.sys.call("touch /tmp/leigod-guard/reset_timer")
		end
	end
	luci.http.redirect(luci.dispatcher.build_url("admin/services/leigod/overview"))
end
