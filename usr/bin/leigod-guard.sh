#!/bin/sh
# leigod-guard.sh - 雷神加速器无人值守时长保护
# 原理: iptables mangle 计数器监控游戏设备流量
#       空闲超过阈值 -> 调雷神云API暂停时长
#       检测到活动   -> 可选自动恢复计费
# API 参考: FXSCZXCJ/leigod-pause API_NOTES.md (2026-09 实测)

API_HOST="https://webapi.leigod.com"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
STDIR="/tmp/leigod-guard"
LOG="$STDIR/guard.log"

case "$1" in
	cleanup)
		iptables -t mangle -D PREROUTING -j LEIGUARD 2>/dev/null
		iptables -t mangle -F LEIGUARD 2>/dev/null
		iptables -t mangle -X LEIGUARD 2>/dev/null
		exit 0
		;;
esac

mkdir -p "$STDIR"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$LOG"; }
cfg() { uci -q get leigod-guard.config.$1; }

log "leigod-guard 启动"
# conntrack 字节统计需要 acct 开启: 新版加速核心(acc-gw v1.2.2.71+)以 TPROXY/自建
# nft 规则接管流量, 已建立连接的持续数据包不再经过 iptables mangle 计数链,
# 只有 conntrack 层字节计数能看到全量流量(实测游戏流量 20s +92KB 上行/+836KB 下行)
sysctl -w net.netfilter.nf_conntrack_acct=1 >/dev/null 2>&1

while :; do
	TOKEN=$(cfg token)
	if [ -z "$TOKEN" ]; then
		log "未配置 account_token，请在 LuCI 雷神加速器->无人值守 页面填入"
		sleep 60
		continue
	fi

	DEVICES=$(uci -q get leigod-guard.config.devices)
	if [ -z "$DEVICES" ]; then
		log "未配置监控设备IP，请在 LuCI 页面添加游戏设备IP"
		sleep 60
		continue
	fi

	IDLE_MIN=$(cfg idle_minutes);    IDLE_MIN=${IDLE_MIN:-15}
	POLL=$(cfg poll_seconds);        POLL=${POLL:-30}
	MIN_BYTES=$(cfg min_bytes);      MIN_BYTES=${MIN_BYTES:-102400}
	AUTO_RESUME=$(cfg auto_resume);  AUTO_RESUME=${AUTO_RESUME:-0}

	api_call() {
		curl -s -m 10 -A "$UA" \
			-H "Origin: https://www.leigod.com" \
			-H "Referer: https://www.leigod.com/" \
			-H "Content-Type: application/json" \
			-d "{\"account_token\":\"$TOKEN\"}" \
			"$API_HOST$1?os_type=4&region_code=1&src_channel=guanwang&lang=zh_CN"
	}

	# 确保防火墙计数链存在
	iptables -t mangle -L LEIGUARD >/dev/null 2>&1 || iptables -t mangle -N LEIGUARD
	iptables -t mangle -C PREROUTING -j LEIGUARD 2>/dev/null || iptables -t mangle -A PREROUTING -j LEIGUARD

	# 独立页面端口应用与冲突检测(端口/密钥在LuCI无人值守页配置)
	SPORT=$(cfg standalone_port)
	if [ -n "$SPORT" ]; then
		CURPORT=$(uci -q get uhttpd.leigod.listen_http 2>/dev/null | sed 's/.*://')
		if [ "$SPORT" != "$CURPORT" ]; then
			if netstat -tln 2>/dev/null | awk '{print $4}' | grep -q ":$SPORT\$"; then
				[ "$(cat "$STDIR/port_conflict" 2>/dev/null)" != "$SPORT" ] && log "端口 $SPORT 已被占用(冲突), 独立页面未切换, 请重设端口"
				echo "$SPORT" > "$STDIR/port_conflict"
			else
				uci -q set uhttpd.leigod=uhttpd
				uci -q set uhttpd.leigod.listen_http="0.0.0.0:$SPORT"
				uci -q set uhttpd.leigod.home="/www-leigod"
				uci -q set uhttpd.leigod.cgi_prefix="/cgi-bin"
				uci -q set uhttpd.leigod.network_timeout="30"
				uci commit uhttpd
				/etc/init.d/uhttpd restart 2>/dev/null
				rm -f "$STDIR/port_conflict"
				log "独立页面端口已切换为 $SPORT"
			fi
		else
			rm -f "$STDIR/port_conflict"
		fi
	fi

	ensure_rule() {
		iptables -t mangle -C LEIGUARD -s "$1" -j RETURN 2>/dev/null || iptables -t mangle -A LEIGUARD -s "$1" -j RETURN
	}

	# 流量统计: 优先读 conntrack 字节计数(该设备所有连接双向字节之和),
	# 不受加速核心 TPROXY 接管影响; conntrack 不可用时回退 iptables 计数链
	bytes_of() {
		local ip="$1"
		if [ -r /proc/net/nf_conntrack ]; then
			awk -v ip="$ip" '
				{
					line = $0 " "
					if (index(line, "src=" ip " ") > 0 || index(line, "dst=" ip " ") > 0) {
						n = split(line, f, " ")
						for (i = 1; i <= n; i++)
							if (f[i] ~ /^bytes=/) { sub(/^bytes=/, "", f[i]); s += f[i] }
					}
				}
				END { print s + 0 }' /proc/net/nf_conntrack 2>/dev/null
			return
		fi
		iptables -t mangle -L LEIGUARD -v -n -x 2>/dev/null | awk -v ip="$ip" '$3=="RETURN" && $8==ip {print $2; exit}'
	}

	now=$(date +%s)
	active=0

	# 手动开始计费信号: 空闲计时归零重算, 给用户完整的窗口期
	if [ -f "$STDIR/reset_timer" ]; then
		rm -f "$STDIR/reset_timer"
		for ip in $DEVICES; do
			echo "$now" > "$STDIR/last_seen.$ip"
		done
		paused_period=0
		log "手动开始计费, 空闲计时已归零重算"
	fi

	for ip in $DEVICES; do
		ensure_rule "$ip"
		# 新设备首次纳入监控时, 以当前时间作为空闲起算点, 避免误判为长期空闲
		if [ ! -f "$STDIR/last_seen.$ip" ]; then
			echo "$now" > "$STDIR/last_seen.$ip"
			log "设备 $ip 纳入监控, 空闲计时从现在开始"
		fi
		cur=$(bytes_of "$ip"); cur=${cur:-0}
		prev=$(cat "$STDIR/bytes.$ip" 2>/dev/null)
		if [ -z "$prev" ] || [ "$cur" -lt "$prev" ]; then prev=$cur; fi
		delta=$((cur - prev))
		echo "$cur" > "$STDIR/bytes.$ip"
		if [ "$delta" -ge "$MIN_BYTES" ]; then
			active=1
			echo "$now" > "$STDIR/last_seen.$ip"
			echo 1 > "$STDIR/active.$ip"
		else
			echo 0 > "$STDIR/active.$ip"
		fi
	done

	# 有活动: 本轮空闲期结束, 可选自动恢复
	if [ "$active" = 1 ]; then
		echo "active" > "$STDIR/state"
		if [ "$paused_period" = "1" ]; then
			paused_period=0
			resume_edge=0
		fi
		if [ "$resume_edge" != "1" ]; then
			resume_edge=1
			log "检测到游戏设备活动"
			if [ "$AUTO_RESUME" = "1" ]; then
				info=$(api_call /api/user/info)
				code=$(jsonfilter -s "$info" -e '@.code' 2>/dev/null)
				pid=$(jsonfilter -s "$info" -e '@.data.pause_status_id' 2>/dev/null)
				if [ "$code" = "0" ] && [ "$pid" = "1" ]; then
					resp=$(api_call /api/user/recover)
					rcode=$(jsonfilter -s "$resp" -e '@.code' 2>/dev/null)
					log "自动恢复计费: code=$rcode"
				fi
			fi
		fi
	else
		# 空闲: 计算所有设备中最近一次活动时间
		maxls=0
		for ip in $DEVICES; do
			ls=$(cat "$STDIR/last_seen.$ip" 2>/dev/null || echo 0)
			[ "$ls" -gt "$maxls" ] && maxls=$ls
		done
		idle_s=$((now - maxls))
		threshold=$((IDLE_MIN * 60))
		if [ "$idle_s" -ge "$threshold" ] && [ "$paused_period" != "1" ]; then
			paused_period=1
			info=$(api_call /api/user/info)
			code=$(jsonfilter -s "$info" -e '@.code' 2>/dev/null)
			case "$code" in
				0)
					pid=$(jsonfilter -s "$info" -e '@.data.pause_status_id' 2>/dev/null)
					if [ "$pid" != "1" ]; then
						resp=$(api_call /api/user/pause)
						pcode=$(jsonfilter -s "$resp" -e '@.code' 2>/dev/null)
						if [ "$pcode" = "0" ]; then
							log "无人活动超过 ${IDLE_MIN} 分钟，已自动暂停时长"
						elif [ "$pcode" = "400803" ]; then
							log "服务端已是暂停状态(400803)"
						else
							log "暂停失败 code=$pcode resp=$resp"
						fi
					else
						log "云端标记已暂停, 无需操作(防假暂停)"
					fi
					;;
				400006|400007|400008|400816|400334|400027)
					paused_period=0
					log "token 已失效(code=$code)，请在 LuCI 无人值守页面更新 account_token"
					;;
				*)
					paused_period=0
					log "查询账号信息异常 code=$code"
					;;
			esac
		fi
		# 用户可能在App手动恢复计费: 暂停期间每轮复核云端状态
		if [ "$paused_period" = "1" ]; then
			info=$(api_call /api/user/info)
			code=$(jsonfilter -s "$info" -e '@.code' 2>/dev/null)
			pid=$(jsonfilter -s "$info" -e '@.data.pause_status_id' 2>/dev/null)
			if [ "$code" = "0" ] && [ -n "$pid" ] && [ "$pid" != "1" ]; then
				paused_period=0
				for ip in $DEVICES; do
					echo "$now" > "$STDIR/last_seen.$ip"
				done
				log "检测到云端已恢复计费(可能为App手动操作), 重置暂停周期与空闲计时"
			fi
		fi
		if [ "$paused_period" = "1" ]; then
			echo "paused" > "$STDIR/state"
		else
			echo "counting" > "$STDIR/state"
		fi
	fi

	sleep "$POLL"
done
