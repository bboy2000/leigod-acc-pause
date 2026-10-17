#!/bin/sh
# leigod-acc-pause 一键安装脚本 (OpenWrt, Lua 版 LuCI)
# 用法: 把整个仓库传到路由器后, 在仓库目录执行 sh install.sh

# ================= 部署配置(按需修改) =================
PORT=8081        # 独立页面初始端口(安装后可在 LuCI「无人值守」页修改, 被占用会提示端口冲突)
AUTH_PASS=""     # 独立页面初始访问密钥; 也可安装后在 LuCI「无人值守」页的"独立页面访问密钥"设置
# =====================================================

REPO_DIR=$(dirname "$0")
cd "$REPO_DIR" || exit 1

echo "== leigod-acc-pause 安装 =="

# 前置检查
if [ ! -f /etc/config/leigod-manager ]; then
	echo "错误: 未检测到 luci-app-leigod-manager (雷神官方插件)，请先安装"
	exit 1
fi

# 复制 LuCI 相关文件
cp -f usr/bin/leigod-guard.sh /usr/bin/leigod-guard.sh
cp -f etc/init.d/leigod-guard /etc/init.d/leigod-guard
# uci 配置: 已有配置(含 token/设备/密钥)时不覆盖, 避免重复安装清空用户数据
if [ ! -f /etc/config/leigod-guard ]; then
	cp -f etc/config/leigod-guard /etc/config/leigod-guard
	echo "已创建默认配置 /etc/config/leigod-guard"
else
	echo "检测到已有 /etc/config/leigod-guard, 保留现有配置(token/设备/密钥等)"
fi
cp -f usr/lib/lua/luci/controller/leigod.lua /usr/lib/lua/luci/controller/leigod.lua
cp -f usr/lib/lua/luci/model/cbi/leigod-guard.lua /usr/lib/lua/luci/model/cbi/leigod-guard.lua
cp -f usr/lib/lua/luci/model/cbi/leigod-settings.lua /usr/lib/lua/luci/model/cbi/leigod-settings.lua
mkdir -p /usr/lib/lua/luci/view/leigod
cp -f usr/lib/lua/luci/view/leigod/overview.htm /usr/lib/lua/luci/view/leigod/overview.htm
cp -f usr/lib/lua/luci/view/leigod/logs.htm /usr/lib/lua/luci/view/leigod/logs.htm
cp -f usr/lib/lua/luci/view/leigod/login-widget.htm /usr/lib/lua/luci/view/leigod/login-widget.htm

chmod 755 /usr/bin/leigod-guard.sh /etc/init.d/leigod-guard
chmod 600 /etc/config/leigod-guard
chmod 644 /usr/lib/lua/luci/controller/leigod.lua \
	/usr/lib/lua/luci/model/cbi/leigod-guard.lua \
	/usr/lib/lua/luci/model/cbi/leigod-settings.lua \
	/usr/lib/lua/luci/view/leigod/overview.htm \
	/usr/lib/lua/luci/view/leigod/logs.htm \
	/usr/lib/lua/luci/view/leigod/login-widget.htm

# 独立端口页面 (uhttpd 第二实例, 无需登录 LuCI)
mkdir -p /www-leigod/cgi-bin
cp -f www-leigod/cgi-bin/leigod /www-leigod/cgi-bin/leigod
chmod 755 /www-leigod/cgi-bin/leigod
# 端口/密钥统一写入 uci: CGI 与守护运行时都从这里读取, 后续直接在 LuCI「无人值守」页修改即可生效
uci -q set leigod-guard.config.standalone_port="$PORT"
if [ -n "$AUTH_PASS" ]; then
	uci set leigod-guard.config.standalone_key="$AUTH_PASS"
	echo "访问密钥已写入配置"
fi
uci commit leigod-guard
echo '<!DOCTYPE html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=/cgi-bin/leigod"></head><body></body></html>' > /www-leigod/index.html

uci -q del uhttpd.leigod
uci set uhttpd.leigod=uhttpd
uci set uhttpd.leigod.listen_http="0.0.0.0:$PORT"
uci set uhttpd.leigod.home="/www-leigod"
uci set uhttpd.leigod.cgi_prefix="/cgi-bin"
uci set uhttpd.leigod.network_timeout="30"
uci commit uhttpd

# 语法检查
lua -e "local f,e=loadfile('/usr/lib/lua/luci/controller/leigod.lua'); print(f and 'controller OK' or e)"
lua -e "local f,e=loadfile('/www-leigod/cgi-bin/leigod'); print(f and 'standalone CGI OK' or e)"
sh -n /usr/bin/leigod-guard.sh && echo "guard.sh OK"

# 清 LuCI 缓存 (QWRT 的 ccache 不校验文件更新, 必须手动清)
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache /tmp/luci-templatecache 2>/dev/null

# 启动服务与 web 实例
/etc/init.d/leigod-guard enable
/etc/init.d/leigod-guard restart
/etc/init.d/uhttpd restart

echo "== 安装完成 =="
echo "LuCI 入口: LuCI -> 服务 -> 雷神加速器 -> 无人值守"
echo "  - account_token: 可用页面上的\"快捷登录\"按钮自动获取(推荐手机验证码登录)"
echo "  - 独立页面端口/访问密钥: 在\"独立状态页设置\"中修改, 保存即生效"
echo "独立页面:  http://<网关IP>:$PORT  (仅限内网使用, 勿暴露公网)"
if [ -z "$AUTH_PASS" ]; then
	echo ""
	echo "【部署必做】设置独立页面访问密钥: 到 LuCI「雷神加速器 -> 无人值守 -> 独立状态页设置\","
	echo "  填写\"独立页面访问密钥\"并保存。未设置密钥前, 独立页面将拒绝所有访问"
fi
