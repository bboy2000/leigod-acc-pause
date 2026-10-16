# leigod-acc-pause

OpenWrt 雷神加速器「无人值守」时长保护工具 —— 路由器侧自动暂停/恢复计费，带独立手机访问页面。

## 这是做什么的

雷神加速器网关版（luci-app-leigod-manager 插件）只有"停止加速"，**没有停止计费**：人下线了加速器还在扣时长。本项目在 OpenWrt 路由器上跑一个守护脚本，通过 iptables 计数器监控游戏设备的流量：

- **无人玩游戏超过阈值时间（默认 15 分钟）** → 自动调用雷神云端接口**暂停时长计费**
- **设备恢复流量活动** → 可选自动**恢复计费**
- **计费开关按钮** → 网页上一键开始/暂停计费（暂停计费不影响游戏加速通道）
- **云端状态实时同步** → 手机 App 手动恢复/暂停计费，网页 10 秒内自动反映，守护自动重置暂停周期
- 全程记录日志，LuCI 网页管理，procd 托管崩溃自动拉起、开机自启

## 独立访问页面（无需登录 LuCI）

安装脚本会在网关上自动创建第二个 uhttpd 实例（**8081 端口**），手机/电脑浏览器直接访问：

```
http://<网关IP>:8081
```

- 与 LuCI 版功能完全一致：状态卡、倒计时大数字、计费开关、设备表、日志
- 无 QWRT 框架，响应式布局，跟随系统深色模式
- 10 秒 AJAX 自动刷新，手机浏览器"添加到主屏幕"可当独立 App 使用
- **访问密钥**：HTTP Basic 认证，**用户名任意**，密码为部署时自行设置的密钥
- **安全提醒**：仅供家庭内网使用，**切勿暴露到公网**；account_token 不会出现在页面中，云端 API 调用均在网关服务端完成

**设置访问密钥（部署必做）**：编辑 `/www-leigod/cgi-bin/leigod`，找到：

```lua
local AUTH_PASS = ""
```

在引号内填入你的密钥，保存后立即生效（无需重启服务）。**留空则页面拒绝所有访问**（fail-closed）。密钥不要提交到任何仓库。

## 工作原理

```
游戏设备 ──流量──> [iptables mangle LEIGUARD 计数链]
                        │ 每 N 秒采样字节数增量
                        v
              leigod-guard.sh (守护脚本)
                │ 空闲超阈值 / 手动计费开关
                v
        webapi.leigod.com 云端接口
        /api/user/pause  (暂停计费)
        /api/user/recover (恢复计费)
        /api/user/info   (查询状态/防假暂停/云端同步)
```

云端暂停是**账号级**操作，与加速跑在网关还是客户端无关。API 细节参考 [FXSCZXCJ/leigod-pause](https://github.com/FXSCZXCJ/leigod-pause) 的 API_NOTES.md（短信登录换 token 的方案实测可用；密码登录已被 CloudWAF 拦截，不可用）。

## 文件结构（对应路由器路径）

| 仓库路径 | 路由器路径 | 说明 |
|---|---|---|
| `usr/bin/leigod-guard.sh` | `/usr/bin/leigod-guard.sh` | 守护脚本（核心） |
| `etc/init.d/leigod-guard` | `/etc/init.d/leigod-guard` | procd 开机自启服务 |
| `etc/config/leigod-guard` | `/etc/config/leigod-guard` | UCI 配置（含 token，建议 600 权限） |
| `usr/lib/lua/luci/controller/leigod.lua` | 同路径 | LuCI 菜单注册 + 启停/计费开关动作 |
| `usr/lib/lua/luci/model/cbi/leigod-guard.lua` | 同路径 | 「无人值守」设置页 |
| `usr/lib/lua/luci/model/cbi/leigod-settings.lua` | 同路径 | 插件「基本设置」页 |
| `usr/lib/lua/luci/view/leigod/overview.htm` | 同路径 | 「运行状态」页（KPI 卡/倒计时仪表盘/计费开关） |
| `usr/lib/lua/luci/view/leigod/logs.htm` | 同路径 | 「运行日志」页 |
| `www-leigod/cgi-bin/leigod` | `/www-leigod/cgi-bin/leigod` | 独立端口页面 CGI（8081，Lua） |
| `install.sh` | — | 一键安装脚本 |

## 安装

前提：已安装 [luci-app-leigod-manager](https://github.com/Arlen-Du/luci-app-leigod-manager/releases)（雷神官方网关插件），OpenWrt 需为 **Lua 版 LuCI**（QWRT/iStoreOS 等国产固件基本是；官方 21.02+ 原版是 JS 版不适用）。

```sh
# 把仓库文件传到路由器任意目录后:
sh install.sh
```

脚本会自动完成：文件复制、权限设置、8081 独立页面与 uhttpd 第二实例配置、LuCI 缓存清理、服务自启。

手动安装则按「文件结构」表复制到对应路径后：

```sh
chmod 755 /usr/bin/leigod-guard.sh /etc/init.d/leigod-guard
chmod 600 /etc/config/leigod-guard
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache   # 清 LuCI 缓存(必须)
/etc/init.d/leigod-guard enable && /etc/init.d/leigod-guard start
```

## 配置

LuCI → 服务 → 雷神加速器 → **无人值守**：

| 配置项 | 默认 | 说明 |
|---|---|---|
| account_token | 空 | **必填**，获取方法见下 |
| 游戏设备IP | 空 | **必填**，要监控的设备，可多台（建议设备上设静态 IP） |
| 空闲暂停阈值(分钟) | 15 | 无人玩游戏超过该时长自动暂停 |
| 流量采样间隔(秒) | 30 | iptables 计数器采样周期 |
| 活跃判定阈值(字节/采样) | 102400 | 采样周期内流量超过它才算在玩游戏（过滤后台流量） |
| 设备活动时自动恢复计费 | 关 | 开启后检测到设备活动自动调 recover 接口 |

**获取 account_token**：电脑浏览器登录 `leigod.com` → F12 打开控制台 → 输入：

```js
JSON.parse(localStorage.getItem("account_token")).account_token
```

把输出的字符串粘贴进配置。token 失效后（日志出现 400006/400007）重新获取即可。

## 运行状态页

「运行状态」页显示：

- 页头右侧：加速核心 启动/停止/重启 按钮
- 三张 KPI 状态卡：守护进程 / 插件监控(monitor_running) / 计时状态（优先云端实时状态）
- 倒计时仪表盘：空闲时显示距自动暂停的大数字倒计时 + 进度条（≤30 秒转橙色脉冲）；暂停/活动/守护异常各有对应大字状态
- 计费开关按钮：▶ 开始计费 / ⏸ 暂停计费（账号级，立即生效）
- 游戏设备监控表：最近活动 / 已空闲 / 距自动暂停倒计时
- 守护日志（最近 10 条，终端暗色风格）
- 每 10 秒 AJAX 局部刷新，免手动刷新页面

**注意**：无游戏流量时手动点的"开始计费"约 1 分钟内会被守护重新自动暂停（保护逻辑）。想保持计费，先开游戏或把设备 IP 加入监控列表。

## 运行时文件

| 路径 | 说明 |
|---|---|
| `/tmp/leigod-guard/guard.log` | 守护日志 |
| `/tmp/leigod-guard/state` | 计时状态: active / counting / paused |
| `/tmp/leigod-guard/last_seen.<IP>` | 各设备最近活动时间戳 |
| `/tmp/leigod-guard/bytes.<IP>` | 各设备累计字节快照 |

## 常见问题

- **改了 LuCI 文件页面不生效**：QWRT 固件的 `luci.ccache` 字节码缓存（`/tmp/luci-modulecache`）不校验源文件更新时间，必须手动清掉，清 `/tmp/luci-indexcache` 不够。
- **App 手动恢复/暂停计费后页面不同步**：v1.01 起页面直查云端实时状态，10 秒内自动反映；守护暂停期间每 30 秒复核云端，识别手动操作后重置暂停周期。
- **日志出现 400006/400007/400008**：token 已失效，重新获取。
- **暂停接口返回 400803**：服务端本来就是暂停状态，无需处理（脚本已自动识别）。
- **加速核心起不来，日志报 modprobe tun 失败**：部分定制内核已内置 tun 驱动，此报错可能是误报，用 `ip tuntap add dev test mode tun` 实测即可确认。
- **固件是 fw4/nftables 但插件走 iptables**：tun 加速模式不受影响；本守护只用 iptables mangle 计数器，与防火墙后端无关。

## 卸载

```sh
/etc/init.d/leigod-guard stop && /etc/init.d/leigod-guard disable
rm -f /usr/bin/leigod-guard.sh /etc/init.d/leigod-guard /etc/config/leigod-guard
rm -rf /www-leigod
uci -q del uhttpd.leigod && uci commit uhttpd && /etc/init.d/uhttpd restart
rm -rf /tmp/leigod-guard /tmp/luci-modulecache /tmp/luci-indexcache
```

（`luci-app-leigod-manager` 官方插件本体不受影响。）

## 致谢

- [FXSCZXCJ/leigod-pause](https://github.com/FXSCZXCJ/leigod-pause) — 雷神云端 API 逆向文档
- [Arlen-Du/luci-app-leigod-manager](https://github.com/Arlen-Du/luci-app-leigod-manager) — 雷神网关插件
