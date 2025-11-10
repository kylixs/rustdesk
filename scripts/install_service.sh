#!/bin/bash
# setup_unattended.sh

# 设置永久密码
sudo rustdesk --password "MySecurePassword123"

# 配置无人值守
sudo rustdesk --option approve-mode "password"
sudo rustdesk --option allow-logon-screen-password "Y"
sudo rustdesk --option verification-method "use-permanent-password"
sudo rustdesk --option allow-hide-cm "Y"
sudo rustdesk --option direct-server "Y"

# 启动服务
sudo rustdesk --install-service
