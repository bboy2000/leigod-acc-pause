#!/bin/sh
# leigod-acc-pause 一键安装脚本 (OpenWrt, Lua 版 LuCI)
# 用法一(推荐): SSH 登录网关后, 一条命令安装, 无需上传整个仓库:
#   sh -c "$(curl -fsSL https://fastly.jsdelivr.net/gh/bboy2000/leigod-acc-pause@main/install.sh)"
# 用法二: 用 FinalShell/WinSCP 把整个仓库上传到网关后, 在仓库目录执行 sh install.sh
#
# 独立页端口 / 访问密钥 / account_token 全部安装后在 LuCI「无人值守」页设置, 无需修改本文件

REPO_RAW="https://fastly.jsdelivr.net/gh/bboy2000/leigod-acc-pause@main"
WORKDIR="/tmp/leigod-install"

echo "== leigod-acc-pause 安装 =="

# 前置检查
if [ ! -f /etc/config/leigod-manager ]; then
	echo "错误: 未检测到 luci-app-leigod-manager (雷神官方插件)，请先安装"
	exit 1
fi

# ---- 依赖自动安装 (雷神插件必要组件 + 本项目组件, 参考 miaoermua/openwrt-leigodacc-manager) ----
DEPS="libpcap iptables kmod-ipt-nat iptables-mod-tproxy kmod-ipt-tproxy kmod-ipt-ipset ipset kmod-tun curl miniupnpd jsonfilter lua uhttpd tc-full kmod-netem conntrack conntrackd"
MISSING=""
for p in $DEPS; do
	opkg list-installed 2>/dev/null | grep -q "^$p " || MISSING="$MISSING $p"
done
if [ -n "$MISSING" ]; then
	echo "检测到缺少依赖:$MISSING"
	echo "正在自动安装 (opkg update 可能较慢, 请耐心等待)..."
	opkg update >/dev/null 2>&1
	opkg install $MISSING
	STILL=""
	for p in $MISSING; do
		opkg list-installed 2>/dev/null | grep -q "^$p " || STILL="$STILL $p"
	done
	if [ -n "$STILL" ]; then
		echo "警告: 以下依赖安装失败:$STILL"
		echo "  (一般是固件软件源不含该组件; tc-full/conntrack 等为非必要组件可忽略,"
		echo "   libpcap/tproxy/ipset/kmod-tun 等必要组件缺失请先更换固件软件源)"
	else
		echo "依赖已补齐"
	fi
else
	echo "依赖检查通过"
fi
command -v curl >/dev/null 2>&1 || { echo "错误: 缺少 curl 且自动安装失败, 请手动执行: opkg update && opkg install curl"; exit 1; }

# ---- 文件来源: 当前目录有仓库文件则直接用(整包上传方式); 否则从 CDN 自动下载 ----
if [ -f usr/bin/leigod-guard.sh ]; then
	echo "检测到本地仓库文件, 直接安装"
else
	echo "正在从 CDN 下载程序文件到 $WORKDIR ..."
	rm -rf "$WORKDIR"
	mkdir -p "$WORKDIR"
	DL_FAILED=0
	while read -r f; do
		[ -z "$f" ] && continue
		mkdir -p "$WORKDIR/$(dirname "$f")"
		if curl -fsSL "$REPO_RAW/$f" -o "$WORKDIR/$f"; then
			echo "  下载 $f"
		else
			echo "  下载失败: $f"
			DL_FAILED=1
		fi
	done <<'FILELIST'
usr/bin/leigod-guard.sh
etc/init.d/leigod-guard
etc/config/leigod-guard
usr/lib/lua/luci/controller/leigod.lua
usr/lib/lua/luci/model/cbi/leigod-guard.lua
usr/lib/lua/luci/model/cbi/leigod-settings.lua
usr/lib/lua/luci/view/leigod/overview.htm
usr/lib/lua/luci/view/leigod/logs.htm
usr/lib/lua/luci/view/leigod/login-widget.htm
www-leigod/cgi-bin/leigod
FILELIST
	if [ "$DL_FAILED" = "1" ]; then
		echo "有文件下载失败, 已中止。请检查网络后重试, 或改用整包上传方式"
		exit 1
	fi
	cd "$WORKDIR" || exit 1
fi

# ---- 复制 LuCI 相关文件 ----
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

# ---- 独立端口页面 (uhttpd 第二实例, 无需登录 LuCI) ----
mkdir -p /www-leigod/cgi-bin
cp -f www-leigod/cgi-bin/leigod /www-leigod/cgi-bin/leigod
chmod 755 /www-leigod/cgi-bin/leigod
# 端口/密钥/token 全部安装后在 LuCI「无人值守」页设置, 本脚本不做任何注入
# 独立页初始端口仅首次写入(8081), 之后以 LuCI 设置为准
uci -q get leigod-guard.config.standalone_port >/dev/null 2>&1 || uci set leigod-guard.config.standalone_port='8081'
uci commit leigod-guard
echo '<!DOCTYPE html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=/cgi-bin/leigod"></head><body></body></html>' > /www-leigod/index.html

if uci -q get uhttpd.leigod >/dev/null 2>&1; then
	echo "保留现有独立页 uhttpd 配置"
else
	uci set uhttpd.leigod=uhttpd
	uci set uhttpd.leigod.listen_http="0.0.0.0:8081"
	uci set uhttpd.leigod.home="/www-leigod"
	uci set uhttpd.leigod.cgi_prefix="/cgi-bin"
	uci set uhttpd.leigod.network_timeout="30"
	uci commit uhttpd
fi

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

echo ""
echo "== 安装完成 =="
echo "下一步(LuCI -> 服务 -> 雷神加速器 -> 无人值守):"
echo "  1. account_token: 点\"快捷登录雷神\"按钮自动获取(推荐手机验证码登录)"
echo "  2. 添加游戏设备IP"
echo "  3. 独立状态页设置: 填写\"独立页面访问密钥\"(必设, 未设置前独立页拒绝所有访问); 端口默认 8081 可改"
echo "独立页面:  http://<网关IP>:8081  (仅限内网使用, 勿暴露公网)"
