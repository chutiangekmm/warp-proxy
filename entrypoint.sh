#!/bin/bash
set -e

# 启动 dbus (warp-cli 与后台服务通信依赖此组件)
/etc/init.d/dbus start
sleep 1

# 后台启动 warp 核心服务
warp-svc &
sleep 3

# 尝试注册一个全新 WARP 匿名账户 (如果曾经挂载注册过会报错，使用 || true 让其忽略继续往下走)
warp-cli --accept-tos registration new || true

# 设置为 Proxy 代理模式 (默认内部端口为 40000，且不会改变服务器本机的路由环境)
warp-cli --accept-tos mode proxy

# 连接 WARP 主网
warp-cli --accept-tos connect

echo "Waiting for WARP to connect..."
sleep 5

# ================= 新增：自动刷新 WARP IP 逻辑 =================
# 判断 REFRESH_INTERVAL 是否为正整数（非0）
if [[ "$REFRESH_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    echo "WARP IP refresh enabled, interval: ${REFRESH_INTERVAL} minutes."
    # 开启一个后台子进程进行循环刷新
    (
        while true; do
            sleep $(( REFRESH_INTERVAL * 60 ))
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Refreshing WARP connection to get a new IP..."
            warp-cli --accept-tos disconnect || true
            sleep 3
            warp-cli --accept-tos connect || true
        done
    ) &
else
    echo "WARP IP refresh disabled (REFRESH_INTERVAL is 0 or not set)."
fi
# ===============================================================

# 构造 GOST 所需的鉴权字符串
AUTH_STRING=""
# 【修复点】下面这里 if 和 [ 之间加了空格
if [ -n "$PROXY_USER" ] &&[ -n "$PROXY_PASS" ]; then
    AUTH_STRING="${PROXY_USER}:${PROXY_PASS}@"
    echo "Proxy credentials loaded -> user: $PROXY_USER"
else
    echo "WARNING: NO PROXY CREDENTIALS SET. THIS IS DANGEROUS."
fi

echo "Starting GOST forwarding SOCKS5 & HTTP to internal WARP..."

# 启动 Gost 开启外部监听并将流量转发给内部的 WARP(127.0.0.1:40000)
exec gost -L http://${AUTH_STRING}:8080 -L socks5://${AUTH_STRING}:1080 -F socks5://127.0.0.1:40000
