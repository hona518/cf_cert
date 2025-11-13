#!/bin/bash

# --- 脚本配置 ---
# 推荐使用 Let's Encrypt 作为默认 CA
CA_SERVER="https://acme-v02.api.letsencrypt.org/directory"
ACME_HOME="$HOME/.acme.sh/acme.sh"

# 检查 acme.sh 是否已安装，如果没有则安装
check_and_install_acme() {
    if [ ! -f "$ACME_HOME" ]; then
        echo "🤔 未检测到 acme.sh 客户端，开始安装..."
        # 注意: 首次安装可能需要用户输入 email，这里使用 placeholder
        curl https://get.acme.sh | sh -s email=placeholder@example.com
        
        # 重新加载 profile 以确保 acme.sh 别名生效
        source "$HOME/.bashrc" 2>/dev/null || source "$HOME/.profile" 2>/dev/null
        
        if [ $? -ne 0 ]; then
            echo "❌ acme.sh 安装失败，请检查网络或权限。"
            exit 1
        fi
        echo "✅ acme.sh 安装成功！"
    fi
}

# 获取用户输入
get_user_input() {
    echo "--- 🌟 Cloudflare/acme.sh 证书自动化脚本 🌟 ---"
    
    # 1. 主域名输入
    read -p "请输入您要申请证书的主域名 (例如: example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo "❌ 域名不能为空！"
        exit 1
    fi
    
    # 2. API Token 输入
    echo ""
    echo "🚨 请确保您的 Cloudflare Token 具有 Zone:Read 和 DNS:Edit 权限。"
    read -p "请输入您的 Cloudflare API Token (CF_Token): " CF_Token
    if [ -z "$CF_Token" ]; then
        echo "❌ API Token 不能为空！"
        exit 1
    fi
    
    # 3. 安装路径输入
    echo ""
    DEFAULT_INSTALL_PATH="/etc/ssl/$DOMAIN"
    echo "💡 证书文件将被复制到该路径下，例如 /etc/ssl/example.com/example.com.key"
    read -p "请输入证书安装的绝对路径 (默认: $DEFAULT_INSTALL_PATH): " INSTALL_PATH
    if [ -z "$INSTALL_PATH" ]; then
        INSTALL_PATH="$DEFAULT_INSTALL_PATH"
    fi
    
    # 确认
    echo ""
    echo "--- 确认信息 ---"
    echo "申请域名: $DOMAIN"
    echo "安装路径: $INSTALL_PATH"
    read -p "信息确认无误？ (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "操作取消。"
        exit 0
    fi
}

# 执行证书申请和安装
issue_and_install_cert() {
    
    # 确保安装目录存在
    # 需要使用 sudo，因为 /etc/ssl 目录通常需要 root 权限
    sudo mkdir -p "$INSTALL_PATH"
    if [ $? -ne 0 ]; then
        echo "❌ 无法创建安装目录 $INSTALL_PATH，请检查权限！"
        exit 1
    fi
    
    # 导出 Cloudflare API 凭证
    export CF_Token="$CF_Token"
    
    echo "--- 1. 证书申请阶段 (DNS 验证) ---"
    
    # 仅申请主域名证书
    "$ACME_HOME" --issue \
        -d "$DOMAIN" \
        --server "$CA_SERVER" \
        --dns dns_cf \
        --keylength ec-256 \
        --log

    if [ $? -ne 0 ]; then
        echo "❌ 证书申请失败！请检查您的 Cloudflare Token 权限和日志文件 (~/.acme.sh/*.log)。"
        unset CF_Token
        exit 1
    fi
    
    echo "✅ 证书申请成功！"
    echo "--- 2. 证书安装到指定路径 ---"
    
    # 安装证书到指定路径，**不设置** --reloadcmd
    # 这里使用一个空的 reloadcmd 来覆盖可能存在的默认设置，确保不会自动重载服务
    "$ACME_HOME" --install-cert \
        -d "$DOMAIN" \
        --key-file       "$INSTALL_PATH/$DOMAIN.key" \
        --fullchain-file "$INSTALL_PATH/$DOMAIN.fullchain.cer" \
        --reloadcmd      ""
        
    if [ $? -ne 0 ]; then
        echo "❌ 证书安装失败！请手动检查安装命令。"
        unset CF_Token
        exit 1
    fi
    
    echo "🎉🎉🎉 恭喜！证书已成功安装！"
    echo "密钥文件: $INSTALL_PATH/$DOMAIN.key"
    echo "证书文件: $INSTALL_PATH/$DOMAIN.fullchain.cer"
    echo ""
    echo "🔔 重要的下一步：请手动配置您的 Web 服务器使用这些文件，并手动重载服务。"
    echo "acme.sh 已为您设置了自动续期，续期后您需要手动重载服务器。"
    
    # 清除环境变量
    unset CF_Token
}

# --- 脚本执行流程 ---

check_and_install_acme
get_user_input
issue_and_install_cert
