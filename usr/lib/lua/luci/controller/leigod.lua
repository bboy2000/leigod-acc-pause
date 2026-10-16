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
	entry({"admin", "services", "leigod", "lg_sms_send"}, call("lg_sms_send")).leaf = true
	entry({"admin", "services", "leigod", "lg_login"}, call("lg_login")).leaf = true
end

-- ===== 雷神快捷登录: 自动获取 account_token =====
local LG_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

local function lg_api(path, body)
	return luci.sys.exec("curl -s -m 12 -A '" .. LG_UA .. "' -H 'Origin: https://www.leigod.com' -H 'Referer: https://www.leigod.com/' -H 'Content-Type: application/json' --data '" .. body .. "' 'https://webapi.leigod.com" .. path .. "?os_type=4&region_code=1&src_channel=guanwang&lang=zh_CN'" .. " 2>/dev/null")
end

local function lg_json(s)
	luci.http.prepare_content("application/json")
	luci.http.write(s)
end

local function lg_jesc(s)
	return (tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("[\r\n]", " "))
end

-- 发送短信验证码: POST /tools/smscode -> data.smscode_key
function lg_sms_send()
	local phone = tostring(luci.http.formvalue("phone") or ""):gsub("%s", "")
	if not phone:match("^1%d%d%d%d%d%d%d%d%d%d$") then
		lg_json('{"code":-1,"msg":"手机号格式不正确"}')
		return
	end
	local out = lg_api("/tools/smscode", '{"phone":"' .. phone .. '","country_code":86,"state":4}')
	local skey = out:match('"smscode_key"%s*:%s*"([^"]+)"')
	if skey and skey ~= "" then
		lg_json('{"code":0,"smscode_key":"' .. skey .. '","msg":"验证码已发送，请查收短信"}')
	else
		local m = out:match('"msg"%s*:%s*"([^"]*)"') or "验证码发送失败"
		lg_json('{"code":-1,"msg":"' .. lg_jesc(m) .. '"}')
	end
end

-- 登录: mode=sms 短信验证码登录 / mode=pwd 密码登录(受官方极验风控影响可能失败)
function lg_login()
	local mode = tostring(luci.http.formvalue("mode") or "sms")
	local uci = require "luci.model.uci".cursor()

	if mode == "pwd" then
		-- 密码登录走 /api/auth/login/v2, 需极验滑块; 无极验字段时官方会拒绝, 如实回传错误
		local acct = tostring(luci.http.formvalue("account") or ""):gsub("%s", "")
		local pwd = tostring(luci.http.formvalue("password") or "")
		if acct == "" or pwd == "" then
			lg_json('{"code":-1,"msg":"请填写账号和密码"}')
			return
		end
		local out = lg_api("/api/auth/login/v1", '{"account":"' .. lg_jesc(acct) .. '","password":"' .. lg_jesc(pwd) .. '","country_code":86,"code":"","refer_code":""}')
		local token = out:match('"account_token"%s*:%s*"([^"]+)"')
		if token and token ~= "" then
			uci:set("leigod-guard", "config", "token", token)
			uci:commit("leigod-guard")
			luci.sys.call("/etc/init.d/leigod-guard restart >/dev/null 2>&1")
			lg_json('{"code":0,"msg":"登录成功，account_token 已写入并重启守护"}')
		else
			local m = out:match('"msg"%s*:%s*"([^"]*)"')
			if m == nil or m == "" then m = "密码登录被雷神官方风控拦截（需滑块验证），请改用手机验证码登录" end
			lg_json('{"code":-1,"msg":"' .. lg_jesc(m) .. '"}')
		end
		return
	end

	-- 短信验证码登录
	local phone = tostring(luci.http.formvalue("phone") or ""):gsub("%s", "")
	local skey = tostring(luci.http.formvalue("smscode_key") or "")
	local smscode = tostring(luci.http.formvalue("smscode") or ""):gsub("%s", "")
	if not phone:match("^1%d%d%d%d%d%d%d%d%d%d$") or skey == "" or smscode == "" then
		lg_json('{"code":-1,"msg":"参数不完整，请重新获取验证码"}')
		return
	end
	local body = '{"country_code":86,"mobile_num":"' .. phone .. '","smscode_key":"' .. skey .. '","smscode":"' .. smscode .. '","code":"","password":"","refer_code":""}'
	local out = lg_api("/api/auth/login/code", body)
	local token = out:match('"account_token"%s*:%s*"([^"]+)"')
	if token and token ~= "" then
		uci:set("leigod-guard", "config", "token", token)
		uci:commit("leigod-guard")
		luci.sys.call("/etc/init.d/leigod-guard restart >/dev/null 2>&1")
		lg_json('{"code":0,"msg":"登录成功，account_token 已写入并重启守护"}')
	else
		local m = out:match('"msg"%s*:%s*"([^"]*)"') or "登录失败，请核对验证码"
		lg_json('{"code":-1,"msg":"' .. lg_jesc(m) .. '"}')
	end
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
