# leigod-acc-pause

OpenWrt 雷神加速器「无人值守」时长保护工具 —— 路由器侧自动暂停/恢复计费，带独立手机访问页面。

- **无人玩游戏超过阈值时间（默认 15 分钟）** → 自动调用雷神云端接口**暂停时长计费**
- **设备恢复流量活动** → 可选自动**恢复计费**
- **计费开关按钮** → 网页上一键开始/暂停计费（暂停计费不影响游戏加速通道）
- **云端状态实时同步** → 手机 App 手动恢复/暂停计费，网页 10 秒内自动反映
- **快捷登录获取 token** → LuCI 页面弹窗登录雷神账号（手机验证码 / 密码），自动写入 account_token
- **独立访问页面** → 无需登录 LuCI，端口与访问密钥均在 LuCI 页面设置，手机当独立 App 用
- LuCI 网页管理 + procd 崩溃自动拉起 + 开机自启

> 仓库内所有密码/密钥/Token 均为空占位，**不含任何个人信息**。按下方流程在你自己的私有副本中填入配置后一键安装。

---

## 快速开始（Fork 部署流程）

### 第一步：获取你自己的私有副本

GitHub 的 fork 无法直接转为私有，推荐用 **Import** 方式复制：

1. 打开 https://github.com/new/import
2. **Your old repository's clone URL** 填：`https://github.com/bboy2000/leigod-acc-pause.git`
3. 选择你自己的账号，仓库名自定义（如 `leigod-acc-pause`），可见性选 **Private**
4. 点 Begin import

（或者：本仓库页面 → Code → Download ZIP 下载，之后手动新建私有仓库上传，效果相同。）

### 第二步：在你的私有副本中修改配置

所有需要个性化修改的位置如下，**其他文件不用动**：

| 文件 | 修改位置 | 说明 |
|---|---|---|
| `install.sh` | 顶部 `PORT=8081` | 独立页面**初始端口**（默认 8081，安装后在 LuCI 页面可随时改） |
| `install.sh` | 顶部 `AUTH_PASS=""` | 独立页面**初始访问密钥**（推荐在此填写，安装时自动写入路由器配置） |

说明：

- **端口与密钥安装后都在 LuCI 页面管理**：LuCI → 服务 → 雷神加速器 → 无人值守 → **独立状态页设置**，修改端口或密钥保存即生效，无需重装
- **端口冲突处理**：若设置的端口已被网关上其他服务占用，守护不会强行切换；此时访问独立页面会提示**"端口冲突请重设"**，回到 LuCI 页面换一个端口保存即可
- **访问密钥**：独立页面只需填一个密钥，**无需用户名**。密钥留空则独立页面拒绝所有访问
- **雷神账号 token 和游戏设备 IP** 不需要改仓库文件——安装后在 LuCI 页面填写（属于个人运行时配置）
- 其余参数（空闲阈值、采样间隔等）安装后在 LuCI「无人值守」页面随时可调

### 第三步：上传到网关

把整个仓库传到路由器（任选其一）：

```sh
# 方式A: 从你的电脑 scp 上传(在仓库目录执行)
scp -r . root@<网关IP>:/tmp/leigod-install

# 方式B: 先 Download ZIP 解压后上传, 或用 WinSCP 等图形工具拖上去
```

### 第四步：一键安装

```sh
ssh root@<网关IP>
sh /tmp/leigod-install/install.sh
```

脚本自动完成：文件复制与权限（**保留已有 UCI 运行配置**）、初始端口/密钥写入路由器配置、8081 独立页面与 uhttpd 第二实例、LuCI 缓存清理、服务开机自启。安装完成后按提示操作。

### 第五步：填写雷神账号配置

LuCI（`http://<网关IP>/cgi-bin/luci`）→ 服务 → 雷神加速器 → **无人值守**：

1. **account_token**（必填）——两种方式任选：
   - **快捷登录（推荐）**：点 token 输入框下方的 **"🔑 快捷登录雷神"** 按钮，弹窗中选择**手机验证码登录**（输入手机号 → 发送验证码 → 输入短信码 → 登录），token 自动写入配置并重启守护，无需手动保存。也支持**密码登录**，但受雷神官方风控（极验滑块）限制可能无法使用，失败时请改用验证码方式
   - **手动获取**：电脑浏览器登录 `leigod.com` → F12 控制台输入：
     ```js
     JSON.parse(localStorage.getItem("account_token")).account_token
     ```
     把输出字符串粘贴进 token 输入框
2. **游戏设备IP**（必填）：要监控的设备，可加多台（建议设静态 IP）
3. **独立状态页设置**（同页面下方）：设置**独立页面端口**和**独立页面访问密钥**，这两个设置好才能访问独立页面；端口被占用时访问独立页面会提示"端口冲突请重设"
4. 其余项默认即可，保存后守护自动重启生效

### 完成：访问独立页面

```
http://<网关IP>:8081
```

输入你设置的访问密钥即可进入。页面功能：三张状态卡、倒计时仪表盘、计费开关、设备表、日志，10 秒自动刷新，跟随系统深色模式。

---

## 更新版本

你的私有副本更新后（同步了上游或自己改了代码）：

```sh
git pull   # 或重新下载 ZIP 覆盖
scp -r . root@<网关IP>:/tmp/leigod-install
ssh root@<网关IP> "sh /tmp/leigod-install/install.sh"
```

重新安装会覆盖路由器上的程序文件，但**不会**动你已配置的 account_token、设备列表等 UCI 运行配置。

## 卸载

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
| `install.sh` | — | 一键安装脚本（端口/密钥配置项在顶部） |

## 前提条件

- 已安装 [luci-app-leigod-manager](https://github.com/Arlen-Du/luci-app-leigod-manager/releases)（雷神官方网关插件）
- OpenWrt 为 **Lua 版 LuCI**（QWRT/iStoreOS 等国产固件基本是；官方 21.02+ 原版是 JS 版不适用）
- 网关已安装 `curl`、`jsonfilter`、`iptables`、`lua`（QWRT 默认都有）

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
