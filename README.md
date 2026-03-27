# warp-proxy

一个基于 Docker 的 Cloudflare WARP 代理容器方案。

它会在容器内启动 Cloudflare WARP，将 WARP 的本地 SOCKS5 代理（默认 `127.0.0.1:40000`）再通过 GOST 转发为可对外访问的：

- SOCKS5 代理：`1080`
- HTTP 代理：`8080`

适合需要通过 WARP 出口提供代理访问的场景。

---

## 功能特性

- 自动安装并启动 Cloudflare WARP
- 以 `proxy` 模式连接 WARP，不直接修改宿主机路由
- 使用 GOST 同时提供：
  - HTTP 代理
  - SOCKS5 代理
- 支持通过数据卷持久化 WARP 注册状态
- 支持按时间间隔自动断开重连，以尝试刷新出口 IP
- 支持为代理设置用户名/密码认证

---

## 项目结构

```text
.
├── Dockerfile
├── docker-compose.yml
└── entrypoint.sh
```

文件说明：

- [Dockerfile](Dockerfile)：构建镜像，安装 WARP 与 GOST
- [docker-compose.yml](docker-compose.yml)：定义容器运行参数、端口映射、网络、环境变量等
- [entrypoint.sh](entrypoint.sh)：容器启动脚本，负责拉起 dbus、warp-svc、warp-cli 和 gost

---

## 工作原理

启动流程大致如下：

1. 启动 `dbus`
2. 启动 `warp-svc`
3. 执行 `warp-cli registration new` 尝试注册 WARP 账户
4. 将 WARP 设置为 `proxy` 模式
5. 连接 WARP 网络
6. 使用 GOST 将 WARP 的内部 SOCKS5 代理转发为外部 HTTP/SOCKS5 代理
7. 如果设置了 `REFRESH_INTERVAL`，则定时断开再重连 WARP

相关实现可以参考：

- [Dockerfile](Dockerfile)
- [entrypoint.sh:3-55](entrypoint.sh#L3-L55)
- [docker-compose.yml:1-29](docker-compose.yml#L1-L29)

---

## 运行要求

在运行前，请确认宿主机满足以下条件：

- 已安装 Docker
- 已安装 Docker Compose（或支持 `docker compose`）
- Linux 环境或支持 `/dev/net/tun` 的 Docker 运行环境
- 允许容器使用以下能力：
  - `NET_ADMIN`
  - `/dev/net/tun`
- 已创建 compose 中引用的外部网络：`warp-proxy-net`

如果尚未创建网络，可执行：

```bash
docker network create warp-proxy-net
```

---

## 快速开始

### 1. 克隆或准备项目文件
确保目录中至少包含以下文件：

- `Dockerfile`
- `docker-compose.yml`
- `entrypoint.sh`

### 2. 修改 `docker-compose.yml`
按需调整端口、监听 IP、认证信息和刷新间隔。

当前示例里暴露的是：

- `10.126.126.51:1081 -> 容器 1080`（SOCKS5）
- `10.126.126.51:1082 -> 容器 8080`（HTTP）

如果你的宿主机 IP 不同，请改成你自己的地址，或者直接改成：

```yaml
ports:
  - "1081:1080"
  - "1082:8080"
```

### 3. 设置代理认证信息（强烈建议）
在 `docker-compose.yml` 的 `environment` 中加入：

```yaml
environment:
  - PROXY_USER=your_username
  - PROXY_PASS=your_strong_password
  - REFRESH_INTERVAL=30
```

### 4. 启动容器

```bash
docker compose up -d --build
```

### 5. 查看日志

```bash
docker compose logs -f
```

如果正常，你会在日志中看到类似信息：

- WARP 成功连接
- GOST 开始监听 `8080` 和 `1080`

---

## 使用方法

### SOCKS5 代理

容器启动后，可通过以下地址使用 SOCKS5：

```text
<宿主机IP>:1081
```

例如：

```text
10.126.126.51:1081
```

如果配置了认证，则使用：

```text
用户名: PROXY_USER
密码: PROXY_PASS
```

### HTTP 代理

容器启动后，也可通过以下地址使用 HTTP 代理：

```text
<宿主机IP>:1082
```

例如：

```text
10.126.126.51:1082
```

如已启用认证，同样需要输入对应的用户名和密码。

---

## 参数说明

### `docker-compose.yml` 中的主要参数

#### `cap_add`

```yaml
cap_add:
  - NET_ADMIN
```

含义：

- 允许容器执行网络相关管理操作
- WARP 运行通常需要该能力

#### `devices`

```yaml
devices:
  - /dev/net/tun:/dev/net/tun
```

含义：

- 将宿主机 TUN 设备映射进容器
- WARP 依赖该设备建立隧道/代理能力

#### `ports`

```yaml
ports:
  - "10.126.126.51:1081:1080"
  - "10.126.126.51:1082:8080"
```

含义：

- 左侧是宿主机监听地址与端口
- 右侧是容器内部端口
- `1080`：容器内 GOST 提供的 SOCKS5 端口
- `8080`：容器内 GOST 提供的 HTTP 端口

建议：

- 如果只想本机使用，可绑定 `127.0.0.1`
- 如果要给局域网设备使用，可绑定宿主机内网 IP
- 不建议直接监听 `0.0.0.0`，除非你明确知道暴露范围和风险

#### `volumes`

```yaml
volumes:
  - ./warp-data:/var/lib/cloudflare-warp
```

含义：

- 持久化 WARP 注册信息和相关状态
- 避免每次容器重建后重新注册

#### `networks`

```yaml
networks:
  warp-proxy-net:
    external: true
```

含义：

- 使用一个已存在的 Docker 外部网络
- 便于其他容器通过同一网络访问该代理服务

---

## 环境变量说明

以下环境变量由 [docker-compose.yml](docker-compose.yml) 传入，供 [entrypoint.sh](entrypoint.sh) 使用。

### `PROXY_USER`

代理认证用户名。

- 未设置时：不会启用认证用户名
- 建议：务必设置

### `PROXY_PASS`

代理认证密码。

- 未设置时：不会启用认证密码
- 建议：务必设置强密码

### `REFRESH_INTERVAL`

WARP 刷新间隔，单位为分钟。

示例：

```yaml
- REFRESH_INTERVAL=30
```

含义：

- 当值为正整数时，容器会每隔对应分钟数执行一次：
  1. `warp-cli disconnect`
  2. `warp-cli connect`
- 目的：尝试重新获取新的 WARP 出口 IP

规则：

- 正整数：启用自动刷新
- `0`、空值、未设置、非法值：关闭自动刷新

注意：

- 自动刷新会短暂中断现有连接
- 如果你需要长期稳定连接，不建议设置过短的刷新时间
- 刷新并不保证一定获取到新的出口 IP

---

## 常见操作

### 构建镜像

```bash
docker compose build
```

### 后台启动

```bash
docker compose up -d
```

### 查看运行状态

```bash
docker compose ps
```

### 查看实时日志

```bash
docker compose logs -f
```

### 重启容器

```bash
docker compose restart
```

### 停止并删除容器

```bash
docker compose down
```

### 停止并删除容器，同时保留 WARP 注册数据
默认 `./warp-data` 不会被删除。

### 清理 WARP 缓存数据
如需重新注册 WARP，可在确认不再需要旧状态后删除本地数据目录：

```bash
rm -rf ./warp-data
```

然后重新启动：

```bash
docker compose up -d --build
```

---

## 连接测试示例

### 使用 curl 测试 HTTP 代理

```bash
curl -x http://<宿主机IP>:1082 https://www.cloudflare.com/cdn-cgi/trace
```

如果启用了认证：

```bash
curl -x http://用户名:密码@<宿主机IP>:1082 https://www.cloudflare.com/cdn-cgi/trace
```

### 使用支持 SOCKS5 的客户端测试

SOCKS5 地址：

```text
socks5://<宿主机IP>:1081
```

如果启用了认证，请在客户端中填写对应用户名和密码。

---

## 安全建议

这一部分很重要，强烈建议认真检查。

### 1. 一定要启用认证
如果不设置 `PROXY_USER` 和 `PROXY_PASS`，代理将可能以无认证方式对外提供服务。

这会带来以下风险：

- 被他人扫描并滥用
- 被当成开放代理使用
- 大量异常请求占满带宽和连接数
- 你的出口被用于不可控流量

至少应设置：

```yaml
environment:
  - PROXY_USER=your_user
  - PROXY_PASS=please_use_a_long_random_password
```

### 2. 限制监听地址
不要为了省事直接监听所有网卡。

更安全的做法：

- 仅本机使用：绑定 `127.0.0.1`
- 局域网使用：绑定单独的内网 IP
- 公网暴露：不推荐，除非你额外配置了防火墙、访问控制和审计

例如仅本机监听：

```yaml
ports:
  - "127.0.0.1:1081:1080"
  - "127.0.0.1:1082:8080"
```

### 3. 配置防火墙白名单
如果必须给局域网或特定主机使用，建议在宿主机防火墙中仅允许可信 IP 访问对应端口。

建议限制的端口：

- `1081`
- `1082`

### 4. 使用强密码
密码建议满足：

- 至少 16 位
- 包含大小写字母、数字、符号
- 不使用常见单词或简单组合
- 不与其他服务复用

### 5. 不要把凭据写进公开仓库
`PROXY_USER`、`PROXY_PASS` 不应提交到公开代码仓库。

更稳妥的方式包括：

- 使用 `.env` 文件配合 Compose
- 使用私有配置文件
- 使用部署平台的 secret 管理能力

例如：

```yaml
environment:
  - PROXY_USER=${PROXY_USER}
  - PROXY_PASS=${PROXY_PASS}
  - REFRESH_INTERVAL=${REFRESH_INTERVAL:-30}
```

然后在 `.env` 中填写真实值。

### 6. 谨慎使用自动刷新
频繁断开/重连虽然可能改变出口 IP，但也会带来：

- 当前连接中断
- 应用重试增多
- 日志噪音增加
- 某些业务连接不稳定

如果主要目标是稳定代理，建议关闭或适当拉长刷新周期。

### 7. 定期检查日志
建议定期查看日志，关注：

- 认证失败次数是否异常
- 是否有大量未知来源访问
- WARP 是否频繁掉线
- GOST 是否正常监听

查看命令：

```bash
docker compose logs --tail=200
```

---

## 故障排查

### 1. 容器启动失败，提示 `/dev/net/tun` 相关错误
请检查：

- 宿主机是否支持 TUN
- Docker 是否允许映射 `/dev/net/tun`
- `devices` 配置是否正确

### 2. 提示网络 `warp-proxy-net` 不存在
先创建外部网络：

```bash
docker network create warp-proxy-net
```

### 3. WARP 无法连接
排查方向：

- 宿主机网络是否正常
- 容器是否能访问 Cloudflare 服务
- 是否存在 DNS / 防火墙限制
- 是否是 WARP 服务端临时异常

可通过日志观察：

```bash
docker compose logs -f
```

### 4. 代理端口无响应
检查：

- 容器是否正常运行
- 端口映射是否正确
- 监听 IP 是否写错
- 宿主机防火墙是否拦截
- GOST 是否正常启动

### 5. 认证无效或代理未要求密码
请确认：

- `PROXY_USER` 与 `PROXY_PASS` 是否都已设置
- compose 修改后是否已重新创建容器

建议在变更环境变量后执行：

```bash
docker compose down
docker compose up -d --build
```

---

## 进阶建议

### 使用 `.env` 管理配置
可以将敏感信息放入 `.env`：

```env
PROXY_USER=your_user
PROXY_PASS=your_long_random_password
REFRESH_INTERVAL=30
```

然后在 `docker-compose.yml` 中引用：

```yaml
environment:
  - PROXY_USER=${PROXY_USER}
  - PROXY_PASS=${PROXY_PASS}
  - REFRESH_INTERVAL=${REFRESH_INTERVAL}
```

### 只暴露一种代理协议
如果你只需要 HTTP 或只需要 SOCKS5，可以自行调整 GOST 启动参数，但当前项目默认会同时暴露两种代理协议。

---

## 已知注意事项

- 当前项目依赖 Cloudflare WARP 官方 Linux 客户端
- 当前项目依赖 GOST `v2.11.5`
- WARP 以 `proxy` 模式运行，目标是提供代理出口，而不是接管整个宿主机网络
- `warp-data` 中保存的是 WARP 的本地状态，删除后可能触发重新注册

---

## 免责声明

请仅在你有权使用的网络环境和合规场景下使用本项目，并自行承担部署、访问控制与安全加固责任。
