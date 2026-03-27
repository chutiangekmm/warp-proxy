FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 安装核心依赖包、Cloudflare WARP 以及 GOST
RUN apt-get update && \
    apt-get install -y curl gnupg lsb-release ca-certificates wget iproute2 iptables dbus && \
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    apt-get clean

# 安装 GOST (版本 2.11.5) 用来实现将 SOCKS5 同时映射为带有密码验证的 HTTP 和 SOCKS5 并对外暴露
RUN wget -O gost.gz https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz && \
    gzip -d gost.gz && \
    mv gost /usr/local/bin/gost && \
    chmod +x /usr/local/bin/gost

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]