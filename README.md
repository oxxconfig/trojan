# trojan
更短的快捷命令（使用 curl -fsSL 管道）：
如果你连下载到本地文件都不想，也可以提供这种直接通过管道（Pipe）执行的超级一键命令：

Bash
bash <(curl -fsSL https://raw.githubusercontent.com/oxxconfig/trojan/refs/heads/main/install_trojan.sh)


注意 Nginx 服务名的兼容性：
在某些更新的 Debian/Ubuntu 系统中，安装 nginx 后默认的系统服务名是 nginx.service。 Nginx 的部分修改为更标准的形式：

Bash
systemctl daemon-reload

systemctl enable nginx

systemctl restart nginx

systemctl enable trojan

systemctl restart trojan
