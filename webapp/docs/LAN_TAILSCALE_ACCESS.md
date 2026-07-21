# EMP 局域网 + Tailscale 外网访问

本机启动后，API / 前端默认绑定 `0.0.0.0`，同一局域网设备与 Tailscale 设备均可访问。

## 快速启动

```bash
bash webapp/scripts/init_runtime_config.sh
bash webapp/scripts/start_local.sh
```

启动成功后终端会打印：

- 本机：`http://127.0.0.1:8080`
- 局域网：`http://<LAN-IP>:8080`
- Tailscale：`http://<100.x.x.x>:8080`（需先上线）

## 多服务对外（Funnel 多端口）

Tailscale Funnel **不能**用任意端口（例如 `:8080`）。公网只允许：

| 公网端口 | 示例 |
|----------|------|
| **443**（默认） | `https://liweimac-studio.tail577190.ts.net/` |
| **8443** | `https://liweimac-studio.tail577190.ts.net:8443/` |
| **10000** | `https://liweimac-studio.tail577190.ts.net:10000/` |

当前推荐映射：

| 服务 | 外网地址 | 本机后端 |
|------|----------|----------|
| **EMP** | https://liweimac-studio.tail577190.ts.net/ | gateway `:8090` → UI `:8080` + API `:8000` |
| **Agent Hub** | https://liweimac-studio.tail577190.ts.net:8443/ | `:8765` |

第三个服务可挂到 `:10000`：

```bash
tailscale funnel --bg --yes --https=10000 <本地端口>
```

本机 `http://127.0.0.1:8080` 仍只在本机/局域网用；外网请走上面的 HTTPS Funnel 地址。

## 手机外网访问（推荐 Funnel HTTPS）

`http://100.x.x.x:8080` **只在手机也安装并登录 Tailscale 时可用**。  
手机在普通 4G/Wi‑Fi、没开 Tailscale App 时，请用 Funnel 公网 HTTPS：

```bash
bash webapp/scripts/start_local.sh
# 或单独切换 Funnel：
bash webapp/scripts/enable_emp_funnel.sh
```

手机打开：

```text
https://liweimac-studio.tail577190.ts.net/
```

## Tailscale App 方式（两端都装 Tailscale）

1. 手机安装 Tailscale，登录**同一账号**
2. 确认 App 里本机 Mac 在线
3. 打开：`http://100.99.230.106:8080`

## 安全机制（非本机绑定时强制）

绑定 `0.0.0.0` 时，服务端要求：

| 变量 | 作用 |
|------|------|
| `EMP_API_TOKEN` | API Bearer；启动脚本自动生成并写入 `runtime.env` |
| `EMP_CORS_ORIGIN=reflect-private` | 仅反射局域网 / Tailscale / 本机 Origin |

Token 文件 `webapp/frontend/js/runtime_auth.local.js` 已 gitignore，勿提交。

## 配置项（`webapp/config/runtime.env`）

| 变量 | 默认 | 说明 |
|------|------|------|
| `API_HOST` | `0.0.0.0` | API 监听地址；仅本机可改 `127.0.0.1` |
| `WEB_HOST` | `0.0.0.0` | 前端静态服务监听地址 |
| `API_PORT` | `8000` | API 端口 |
| `WEB_PORT` | `8080` | 前端端口 |
| `EMP_CORS_ORIGIN` | `reflect-private` | LAN/Tailscale CORS |
| `EMP_API_TOKEN` | 自动生成 | 非本机绑定时必需 |

## 安全注意

- Tailscale 已做身份与加密隧道，一般**不必**再对公网开端口映射
- 不要把 `0.0.0.0` 服务直接暴露到公网路由器端口转发
- Code Lab / Agent 的 `EMP_ENABLE_USER_R` 默认关闭；对不可信网络访问保持关闭

## 仅本机访问（可选）

```bash
# webapp/config/runtime.env
API_HOST=127.0.0.1
WEB_HOST=127.0.0.1
```

然后重新运行 `bash webapp/scripts/start_local.sh`。
