#!/bin/bash
# DSDNS 一键安装脚本（带管理工具 + 冲突检测）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 root
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户运行此脚本"
    exit 1
fi

# 检查依赖
for cmd in wget tar gzip; do
    if ! command -v $cmd &> /dev/null; then
        print_error "未找到 $cmd，请先安装: apt install $cmd -y 或 yum install $cmd -y"
        exit 1
    fi
done

# ========== 冲突检测 ==========
if command -v dsdns &> /dev/null; then
    OLD_DSDNS=$(which dsdns)
    print_warn "检测到已存在的 dsdns 命令: $OLD_DSDNS"
    if [[ "$OLD_DSDNS" == "/usr/local/bin/dsdns" ]]; then
        print_info "该路径即将被覆盖，继续安装..."
    else
        read -p "是否覆盖原命令并备份？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_error "已取消安装，请手动处理冲突后重试"
            exit 1
        fi
        mv "$OLD_DSDNS" "${OLD_DSDNS}.bak"
        print_info "已备份原命令至 ${OLD_DSDNS}.bak"
    fi
fi

# 创建目录
mkdir -p /opt/dsdns/data
cd /opt/dsdns

# 下载文件（如果已存在则跳过）
download_if_missing() {
    local url=$1
    local file=$2
    if [ ! -f "$file" ]; then
        print_info "下载 $file ..."
        wget -q --show-progress "$url" -O "$file"
    else
        print_info "$file 已存在，跳过下载"
    fi
}

download_if_missing "https://raw.githubusercontent.com/lisi-123/DSDNS-QIG/main/config.yaml" "config.yaml"
download_if_missing "https://github.com/lisi-123/DSDNS-QIG/raw/refs/heads/main/dsdns.tar.gz" "dsdns.tar.gz"
download_if_missing "https://github.com/lisi-123/DSDNS-QIG/raw/refs/heads/main/ip2region.tar.gz" "ip2region.tar.gz"

# 解压
print_info "解压文件..."
tar -xzf dsdns.tar.gz
tar -xzf ip2region.tar.gz -C data/
chmod +x dsdns

# 自动生成随机 JWT 密钥（如果当前 secret 是默认值）
if grep -q 'secret: "change-me-to-a-random-string"' config.yaml; then
    NEW_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    sed -i "s/secret: \"change-me-to-a-random-string\"/secret: \"$NEW_SECRET\"/" config.yaml
    print_info "已自动生成 JWT 密钥: $NEW_SECRET"
    print_warn "请妥善保存此密钥，丢失将导致已登录用户需要重新登录"
else
    print_info "JWT 密钥已存在，保留原值"
fi

# 创建 systemd 服务（可选）
cat > /etc/systemd/system/dsdns.service <<EOF
[Unit]
Description=DSDNS GeoDNS Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/dsdns
ExecStart=/opt/dsdns/dsdns
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
print_info "systemd 服务已创建（可选）"

# ==================== 创建管理工具 ====================
print_info "创建管理命令 /usr/local/bin/dsdns ..."

cat > /usr/local/bin/dsdns <<'EOF'
#!/bin/bash

# DSDNS 管理工具
# 用法: dsdns [start|stop|restart|status|logs|config|help]
# 直接输入 dsdns 进入交互菜单

INSTALL_DIR="/opt/dsdns"
SERVICE_NAME="dsdns"
PID_FILE="/var/run/dsdns.pid"
LOG_FILE="/var/log/dsdns.log"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检测是否有 systemd
if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
    USE_SYSTEMD=true
else
    USE_SYSTEMD=false
fi

# 启动服务
start_service() {
    if $USE_SYSTEMD; then
        systemctl start $SERVICE_NAME
        echo -e "${GREEN}服务已通过 systemd 启动${NC}"
    else
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo -e "${YELLOW}服务已在运行中 (PID: $(cat $PID_FILE))${NC}"
        else
            cd $INSTALL_DIR
            nohup ./dsdns > "$LOG_FILE" 2>&1 &
            echo $! > "$PID_FILE"
            echo -e "${GREEN}服务已启动 (PID: $!)${NC}"
        fi
    fi
}

# 停止服务
stop_service() {
    if $USE_SYSTEMD; then
        systemctl stop $SERVICE_NAME
        echo -e "${GREEN}服务已停止${NC}"
    else
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 $PID 2>/dev/null; then
                kill $PID
                echo -e "${GREEN}服务已停止 (PID: $PID)${NC}"
            else
                echo -e "${YELLOW}服务未运行${NC}"
            fi
            rm -f "$PID_FILE"
        else
            echo -e "${YELLOW}服务未运行${NC}"
        fi
    fi
}

# 重启服务
restart_service() {
    stop_service
    sleep 1
    start_service
}

# 查看状态
status_service() {
    if $USE_SYSTEMD; then
        systemctl status $SERVICE_NAME --no-pager
    else
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            PID=$(cat "$PID_FILE")
            echo -e "${GREEN}服务运行中${NC}，PID: $PID"
            ps aux | grep -v grep | grep "$INSTALL_DIR/dsdns"
        else
            echo -e "${RED}服务未运行${NC}"
        fi
    fi
}

# 查看日志
show_logs() {
    if $USE_SYSTEMD; then
        journalctl -u $SERVICE_NAME -f
    else
        if [ -f "$LOG_FILE" ]; then
            tail -f "$LOG_FILE"
        else
            echo -e "${RED}日志文件不存在${NC}"
        fi
    fi
}

# 编辑配置
edit_config() {
    if command -v vim &> /dev/null; then
        vim $INSTALL_DIR/config.yaml
    else
        nano $INSTALL_DIR/config.yaml
    fi
    echo -e "${YELLOW}配置文件已修改，需要重启服务生效${NC}"
}

# 修改 JWT 密钥
change_jwt_secret() {
    NEW_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    sed -i "s/secret: \".*\"/secret: \"$NEW_SECRET\"/" $INSTALL_DIR/config.yaml
    echo -e "${GREEN}JWT 密钥已更新为: $NEW_SECRET${NC}"
    echo -e "${YELLOW}请重启服务生效${NC}"
}

# 开放防火墙端口（简化版）
open_firewall() {
    DNS_PORT=$(grep -oP '(?<=listen: ")[0-9]+' $INSTALL_DIR/config.yaml | head -1)
    WEB_PORT=$(grep -oP '(?<=listen: ")[0-9]+' $INSTALL_DIR/config.yaml | tail -1)
    if command -v ufw &> /dev/null; then
        ufw allow $DNS_PORT/tcp
        ufw allow $DNS_PORT/udp
        ufw allow $WEB_PORT/tcp
        echo -e "${GREEN}已开放端口 $DNS_PORT 和 $WEB_PORT${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$DNS_PORT/tcp
        firewall-cmd --permanent --add-port=$DNS_PORT/udp
        firewall-cmd --permanent --add-port=$WEB_PORT/tcp
        firewall-cmd --reload
        echo -e "${GREEN}已开放端口 $DNS_PORT 和 $WEB_PORT${NC}"
    else
        echo -e "${YELLOW}未检测到防火墙，请手动开放端口${NC}"
    fi
}

# 设置开机自启
enable_autostart() {
    if $USE_SYSTEMD; then
        systemctl enable $SERVICE_NAME
        echo -e "${GREEN}已设置开机自启${NC}"
    else
        if ! grep -q "$INSTALL_DIR/dsdns" /etc/rc.local 2>/dev/null; then
            echo "$INSTALL_DIR/dsdns &" >> /etc/rc.local
            chmod +x /etc/rc.local
            echo -e "${GREEN}已添加开机启动（通过 rc.local）${NC}"
        else
            echo -e "${YELLOW}开机启动已配置过${NC}"
        fi
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       DSDNS 管理工具 v1.0            ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} 1) 启动 DSDNS 服务                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 2) 停止 DSDNS 服务                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 3) 重启 DSDNS 服务                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 4) 查看服务状态                      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 5) 实时查看日志                      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 6) 编辑配置文件 (config.yaml)        ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 7) 修改 JWT 密钥                     ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 8) 开放防火墙端口                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 9) 设置开机自启                      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} 0) 退出                              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo -n "请选择 [0-9]: "
}

# 命令行参数处理
case "$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        status_service
        ;;
    logs)
        show_logs
        ;;
    config)
        edit_config
        ;;
    help|--help|-h)
        echo "用法: dsdns [命令]"
        echo "命令:"
        echo "  start    启动服务"
        echo "  stop     停止服务"
        echo "  restart  重启服务"
        echo "  status   查看状态"
        echo "  logs     查看实时日志"
        echo "  config   编辑配置文件"
        echo "  help     显示帮助"
        echo "直接运行 dsdns 进入交互菜单"
        ;;
    "")
        # 交互菜单
        while true; do
            show_menu
            read choice
            case $choice in
                1) start_service; read -p "按回车键继续..." ;;
                2) stop_service; read -p "按回车键继续..." ;;
                3) restart_service; read -p "按回车键继续..." ;;
                4) status_service; read -p "按回车键继续..." ;;
                5) show_logs ;;
                6) edit_config; read -p "按回车键继续..." ;;
                7) change_jwt_secret; read -p "按回车键继续..." ;;
                8) open_firewall; read -p "按回车键继续..." ;;
                9) enable_autostart; read -p "按回车键继续..." ;;
                0) echo "退出"; exit 0 ;;
                *) echo -e "${RED}无效输入${NC}"; sleep 1 ;;
            esac
        done
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        echo "使用 'dsdns help' 查看帮助"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/dsdns
print_info "管理命令已创建: /usr/local/bin/dsdns"
print_info "现在你可以在任意位置输入 'dsdns' 来管理服务"

print_warn "服务尚未启动，请运行 'dsdns start' 或 输入 'dsdns' 进入菜单启动"

# 显示完成信息
WEB_PORT=$(grep -oP '(?<=listen: ")[0-9]+' config.yaml | tail -1)
echo ""
echo "=========================================="
echo -e "${GREEN}DSDNS 安装完成！${NC}"
echo "=========================================="
echo "安装目录: /opt/dsdns"
echo "配置文件: /opt/dsdns/config.yaml"
echo "管理命令: dsdns"
echo ""
echo "快速上手:"
echo "  dsdns start      # 启动服务"
echo "  dsdns            # 打开交互菜单"
echo ""
echo "首次使用请修改 config.yaml 中的 jwt.secret"
echo "Web 管理地址: http://$(curl -s ifconfig.me):$WEB_PORT/static/login.html"
echo "=========================================="
