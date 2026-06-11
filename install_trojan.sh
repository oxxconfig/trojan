#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用root用户运行此脚本！${PLAIN}" && exit 1

# 1. 输入自定义信息
echo -e "${YELLOW}=== Trojan 一键安装脚本 ===${PLAIN}"
read -p "请输入你的域名 (例如: trojan.example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}域名不能为空！${PLAIN}" && exit 1
fi

read -p "请设置你的 Trojan 密码 (留空将随机生成): " PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi

# 2. 安装基础依赖和 Nginx
echo -e "${GREEN}正在安装依赖和 Nginx...${PLAIN}"
if [[ -f /etc/redhat-release ]]; then
    yum install -y epel-release
    yum install -y curl wget unzip nginx socat
else
    apt update -y
    apt install -y curl wget unzip nginx socat
fi

# 3. 申请 SSL 证书 (使用 acme.sh 独立模式)
echo -e "${GREEN}正在申请 SSL 证书...${PLAIN}"
systemctl stop nginx
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --upgrade --auto-upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone
if [ $? -ne 0 ]; then
    echo -e "${RED}SSL 证书申请失败，请检查域名解析是否正确，以及 80 端口是否被占用。${PLAIN}"
    exit 1
fi

# 创建证书目录
mkdir -p /etc/trojan/
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
    --key-file /etc/trojan/private.key \
    --fullchain-file /etc/trojan/cert.crt

# 4. 下载并安装 Trojan
echo -e "${GREEN}正在下载并安装 Trojan...${PLAIN}"
LAST_VERSION=$(curl -FsSL https://api.github.com/repos/trojan-gfw/trojan/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
wget https://github.com/trojan-gfw/trojan/releases/download/${LAST_VERSION}/trojan-${LAST_VERSION:1}-linux-amd64.tar.xz
tar -xf trojan-${LAST_VERSION:1}-linux-amd64.tar.xz
mv trojan/trojan /usr/local/bin/
mv trojan/examples/client.json-example /etc/trojan/client.json
rm -rf trojan*

# 5. 配置 Trojan 服务端
cat > /etc/trojan/config.json <<EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "${PASSWORD}"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/etc/trojan/cert.crt",
        "key": "/etc/trojan/private.key",
        "key_password": "",
        "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384",
        "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256",
        "prefer_server_cipher": true,
        "alpn": [
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": true,
        "session_timeout": 600,
        "plain_http_resubmit": true,
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "prefer_ipv4": false,
        "no_delay": true,
        "keep_alive": true,
        "reuse_port": false,
        "fast_open": false,
        "fast_open_qlen": 20
    }
}
EOF

# 6. 配置 Trojan Systemd 服务
cat > /etc/systemd/system/trojan.service <<EOF
[Unit]
Description=Trojan Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/trojan -c /etc/trojan/config.json
Restart=on-failure
RestartSec=10s

[Unit]
[Install]
WantedBy=multi-user.target
EOF

# 7. 配置 Nginx 伪装站点（当非 Trojan 流量访问 443 时，由 Trojan 转发到这里的 80 端口）
cat > /etc/nginx/nginx.conf <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    server {
        listen       127.0.0.1:80 default_server;
        server_name  $DOMAIN;
        root         /usr/share/nginx/html;

        location / {
            index  index.html index.htm;
        }
    }
}
EOF

# 8. 启动服务
systemctl daemon-reload
systemctl track nginx || true # 适配部分系统的nginx服务名
systemctl start nginx
systemctl enable nginx
systemctl start trojan
systemctl enable trojan

# 9. 打印结果
echo -e "\n${GREEN}===============================================${PLAIN}"
echo -e "${GREEN} Trojan 安装成功！${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"
echo -e "域名 (Domain):     ${YELLOW}${DOMAIN}${PLAIN}"
echo -e "端口 (Port):       ${YELLOW}443${PLAIN}"
echo -e "密码 (Password):   ${YELLOW}${PASSWORD}${PLAIN}"
echo -e "\n${YELLOW}客户端配置提示:${PLAIN}"
echo -e "请在客户端中填入上述 域名、端口(443) 和 密码。"
echo -e "建议开启 TLS, 允许不安全证书选择 'false' (因为我们申请的是正规证书)。"
echo -e "${GREEN}===============================================${PLAIN}"