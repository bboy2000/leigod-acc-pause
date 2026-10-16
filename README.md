# leigod-acc-pause

OpenWrt 雷神加速器「无人值守」时长保护工具 —— 路由器侧自动暂停/恢复计费，带独立手机访问页面。

- **无人玩游戏超过阈值时间（默认 15 分钟）** → 自动调用雷神云端接口**暂停时长计费**
- **设备恢复流量活动** → 可选自动**恢复计费**
- **计费开关按钮** → 网页上一键开始/暂停计费（暂停计费不影响游戏加速通道）
- **云端状态实时同步** → 手机 App 手动恢复/暂停计费，网页 10 秒内自动反映
- **快捷登录获取 token** → LuCI 页面弹窗登录雷神账号（手机验证码 / 密码），自动写入 account_token
- **独立访问页面** → 无需登录 LuCI，端口与访问密钥均在 LuCI 页面设置，手机当独立 App 用
- LuCI 网页管理 + procd 崩溃自动拉起 + 开机自启

> 仓库内不含任何密码/密钥/Token。独立页端口、访问密钥、account_token **全部安装后在 LuCI 页面设置**，无需修改任何仓库文件。

---

## 快速开始（一条命令安装）

### 第一步：SSH 登录网关

用 FinalShell / WinSCP 等工具 SSH 登录你的 OpenWrt 网关（`root@<网关IP>`）。以下命令都是**登录网关之后、在网关命令行里直接执行**的。

### 第二步：一键安装

先进入 /tmp，然后一条命令下载安装脚本并自动运行（脚本会自己从 CDN 下载所需文件）：

```sh
cd /tmp
sh -c "$(curl -fsSL https://fastly.jsdelivr.net/gh/bboy2000/leigod-acc-pause@main/install.sh)"
```

脚本自动完成：前置检查（curl、雷神官方插件）→ 从 jsDelivr CDN 下载程序文件 → 复制文件与权限 → 注册 LuCI 页面与独立页面（8081）→ 清 LuCI 缓存 → 服务开机自启。

> 提示：jsDelivr 对 `@main` 分支有缓存（最长约 12 小时）。刚更新完想立即安装最新版，可把命令里的 `@main` 换成 `@<提交号>`（仓库主页每个提交的短 hash）。

> 备选方式（CDN 不可用或想离线装）：用 FinalShell / WinSCP 把**整个仓库目录**拖到网关 `/tmp/leigod-install`，然后在网关命令行执行：
> ```sh
> cd /tmp/leigod-install
> sh install.sh
> ```
> 脚本检测到本地有仓库文件时直接使用，不再联网下载。

### 第三步：在 LuCI 完成配置

浏览器打开 LuCI（`http://<网关IP>/cgi-bin/luci`）→ 服务 → 雷神加速器 → **无人值守**：

1. **account_token**（必填）——两种方式任选：
   - **快捷登录（推荐）**：点 token 输入框下方的 **"🔑 快捷登录雷神"** 按钮，弹窗中选择**手机验证码登录**（输入手机号 → 发送验证码 → 输入短信码 → 登录），token 自动写入配置并重启守护，无需手动保存。也支持**密码登录**，但受雷神官方风控（极验滑块）限制可能无法使用，失败时请改用验证码方式
   - **手动获取**：电脑浏览器登录 `leigod.com` → F12 控制台输入：
     ```js
     JSON.parse(localStorage.getItem("account_token")).account_token
     ```
     把输出字符串粘贴进 token 输入框
2. **游戏设备IP**（必填）：要监控的设备，可加多台（建议设静态 IP）
3. **独立状态页设置**（同页面下方）：设置**独立页面端口**（默认 8081，可改）和**独立页面访问密钥**（必设，未设置前独立页面拒绝所有访问），这两个设置好才能访问独立页面；端口被占用时访问独立页面会提示"端口冲突请重设"，换一个端口保存即可
4. 其余项默认即可，保存后守护自动重启生效

### 完成：访问独立页面

```
http://<网关IP>:8081
```

输入你设置的访问密钥即可进入。页面功能：三张状态卡、倒计时仪表盘、计费开关、设备表、日志，10 秒自动刷新，跟随系统深色模式。

---

## 更新版本

SSH 登录网关后，重新执行同一条一键命令即可（脚本自动下载最新文件覆盖安装）：

```sh
cd /tmp
sh -c "$(curl -fsSL https://fastly.jsdelivr.net/gh/bboy2000/leigod-acc-pause@main/install.sh)"
```

> jsDelivr 对 `@main` 有缓存（最长约 12 小时），急用可把 `@main` 换成 `@<提交号>`。

重新安装会覆盖路由器上的程序文件，但**不会**动你已配置的 account_token、设备列表、独立页端口/密钥等 UCI 运行配置。

## 卸载

SSH 登录网关后，在网关命令行执行：

```sh
/etc/init.d/leigod-guard stop && /etc/init.d/leigod-guard disable
rm -f /usr/bin/leigod-guard.sh /etc/init.d/leigod-guard /etc/config/leigod-guard
rm -rf /www-leigod
uci -q del uhttpd.leigod && uci commit uhttpd && /etc/init.d/uhttpd restart
rm -rf /tmp/leigod-guard /tmp/luci-modulecache /tmp/luci-indexcache
```

（`luci-app-leigod-manager` 官方插件本体不受影响。）

---

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
| `etc/config/leigod-guard` | `/etc/config/leigod-guard` | UCI 配置模板（token/密钥留空，安装后页面填写；重装不覆盖已有配置） |
| `usr/lib/lua/luci/controller/leigod.lua` | 同路径 | LuCI 菜单注册 + 启停/计费开关动作 + 雷神快捷登录接口 |
| `usr/lib/lua/luci/model/cbi/leigod-guard.lua` | 同路径 | 「无人值守」设置页（token/设备/独立页端口与密钥） |
| `usr/lib/lua/luci/model/cbi/leigod-settings.lua` | 同路径 | 插件「基本设置」页 |
| `usr/lib/lua/luci/view/leigod/overview.htm` | 同路径 | 「运行状态」页（KPI 卡/倒计时仪表盘/计费开关） |
| `usr/lib/lua/luci/view/leigod/login-widget.htm` | 同路径 | 「快捷登录雷神」弹窗组件（验证码/密码两种方式） |
| `usr/lib/lua/luci/view/leigod/logs.htm` | 同路径 | 「运行日志」页 |
| `www-leigod/cgi-bin/leigod` | `/www-leigod/cgi-bin/leigod` | 独立端口页面 CGI（Lua，含密钥登录页） |
| `install.sh` | — | 一键安装脚本（支持 CDN 自动下载模式与整包上传模式） |

## 前提条件

- 已安装 [luci-app-leigod-manager](https://github.com/Arlen-Du/luci-app-leigod-manager/releases)（雷神官方网关插件）
- OpenWrt 为 **Lua 版 LuCI**（QWRT/iStoreOS 等国产固件基本是；官方 21.02+ 原版是 JS 版不适用）
- 依赖包（libpcap、iptables/tproxy/ipset 系列、kmod-tun、curl、miniupnpd、jsonfilter、lua、uhttpd、tc、conntrack 等）由安装脚本**自动检测并安装**，无需手动准备；固件源不含的非必要组件缺失会被跳过并提示

## 常见问题

- **改了 LuCI 文件页面不生效**：QWRT 固件的 `luci.ccache` 字节码缓存（`/tmp/luci-modulecache`）不校验源文件更新时间，必须手动清掉，清 `/tmp/luci-indexcache` 不够。
- **App 手动恢复/暂停计费后页面不同步**：页面直查云端实时状态，10 秒内自动反映；守护暂停期间每 30 秒复核云端，识别手动操作后重置暂停周期与空闲计时。
- **手动"开始计费"后又被自动暂停**：无游戏流量时守护会在阈值时间后重新暂停（保护逻辑）。想保持计费，先开游戏或把设备 IP 加入监控列表。
- **日志出现 400006/400007/400008**：token 已失效，到 LuCI「无人值守」页用快捷登录按钮重新登录获取（或手动 F12 获取）。
- **快捷登录密码方式失败**：雷神官方对密码登录启用了极验滑块风控，接口可能被拦截，请改用**手机验证码登录**（实测可用）。
- **访问独立页面提示"端口冲突请重设"**：设置的端口已被网关上其他服务占用，到 LuCI「无人值守 → 独立状态页设置」换一个端口保存即可。
- **独立页面打不开/提示未配置密钥**：到 LuCI「无人值守 → 独立状态页设置」设置访问密钥并保存，密钥留空时页面拒绝所有访问。
- **暂停接口返回 400803**：服务端本来就是暂停状态，无需处理（脚本已自动识别）。
- **加速核心日志报 modprobe tun 失败**：部分定制内核已内置 tun 驱动，此报错可能是误报，用 `ip tuntap add dev test mode tun` 实测确认。
- **固件是 fw4/nftables 但插件走 iptables**：tun 加速模式不受影响；本守护只用 iptables mangle 计数器，与防火墙后端无关。

## 安全说明

- 独立页面**无用户名**，仅靠访问密钥保护，且为 HTTP 明文——仅供家庭内网使用，**切勿端口映射暴露到公网**
- account_token 属于个人运行时配置，存于路由器 `/etc/config/leigod-guard`（建议 600 权限），**不会出现在任何仓库文件中**
- 雷神云端 API 调用均由网关服务端发起，页面不接触 token

## 致谢

- [FXSCZXCJ/leigod-pause](https://github.com/FXSCZXCJ/leigod-pause) — 雷神云端 API 逆向文档
- [Arlen-Du/luci-app-leigod-manager](https://github.com/Arlen-Du/luci-app-leigod-manager) — 雷神网关插件
