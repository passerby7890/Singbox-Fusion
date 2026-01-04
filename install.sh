#!/bin/bash

# =================================================================
#  V2bX Multi-Instance Deploy Script (Google SRE Standard)
#  Version: 3.6 (Integrated Query Feature)
#  Usage: 
#    Install: bash install.sh
#    Query:   bash install.sh list
# =================================================================

# --- [Feature] 实例查询功能 (List Mode) ---
# 放在最前面，确保不需要环境变量也能运行
if [[ "$1" == "list" ]]; then
    echo -e "\033[0;34m[INFO] 正在扫描本机已安装的 V2bX 实例...\033[0m"
    echo "==================================================================="
    printf "\033[1;33m%-15s %-25s %-15s %-10s\033[0m\n" "SITE_TAG" "容器名称" "运行状态" "管理指令"
    echo "-------------------------------------------------------------------"

    # 1. 扫描多开标签 (v2bx_*)
    FOUND_ANY=0
    
    # 使用 find 避免 glob 为空时的报错
    for file in $(find /usr/bin -maxdepth 1 -name "v2bx_*" 2>/dev/null); do
        FOUND_ANY=1
        TAG_NAME=$(basename "$file" | sed 's/v2bx_//')
        
        # 尝试模糊匹配容器 (匹配 v2bx-ss-TAG, v2bx-v2ray-TAG 等)
        # 逻辑：查找名字以 TAG 结尾的容器
        CONTAINER_NAME=$(docker ps -a --format "{{.Names}}" | grep -E "\-${TAG_NAME}$" | head -n 1)
        
        if [ -n "$CONTAINER_NAME" ]; then
            STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
            if [ "$STATUS" == "running" ]; then
                COLOR_STATUS="\033[0;32m${STATUS}\033[0m"
            else
                COLOR_STATUS="\033[0;31m${STATUS}\033[0m"
            fi
        else
            CONTAINER_NAME="(容器已丢失)"
            COLOR_STATUS="\033[0;31mLost\033[0m"
        fi
        
        printf "%-15s %-25s %-24b %-10s\n" "$TAG_NAME" "$CONTAINER_NAME" "$COLOR_STATUS" "v2bx_${TAG_NAME}"
    done

    # 2. 扫描默认实例 (v2bx)
    if [ -f "/usr/bin/v2bx" ]; then
        FOUND_ANY=1
        # 默认容器名通常不带后缀
        CONTAINER_NAME=$(docker ps -a --format "{{.Names}}" | grep -E "^v2bx-(ss|v2ray|hy2|vmess)$" | head -n 1)
        
        if [ -n "$CONTAINER_NAME" ]; then
            STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
             if [ "$STATUS" == "running" ]; then
                COLOR_STATUS="\033[0;32m${STATUS}\033[0m"
            else
                COLOR_STATUS="\033[0;31m${STATUS}\033[0m"
            fi
        else
            CONTAINER_NAME="(容器已丢失)"
            COLOR_STATUS="\033[0;31mLost\033[0m"
        fi
        printf "%-15s %-25s %-24b %-10s\n" "(默认/无Tag)" "$CONTAINER_NAME" "$COLOR_STATUS" "v2bx"
    fi

    if [ $FOUND_ANY -eq 0 ]; then
        echo -e "\033[0;33m未发现任何通过此脚本安装的实例。\033[0m"
    fi
    echo "==================================================================="
    exit 0
fi

# =================================================================
#  以下为部署逻辑 (Deploy Logic)
# =================================================================

# --- [Check 0] 严格变量检查 ---
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$INSTALL_TYPE" ]]; then
    echo -e "\033[0;31m[CRITICAL] 缺少必要变量！\033[0m"
    echo -e "安装用法: export SITE_TAG='siteA'; export API_HOST='...'; bash $0"
    echo -e "查询用法: bash $0 list"
    exit 1
fi

# --- [Check 1] 多开标签与隔离策略 ---
if [[ -z "$SITE_TAG" ]]; then
    echo -e "\033[0;33m[WARN] 未设定 SITE_TAG。将运行在默认模式 (单开模式)。\033[0m"
    SUFFIX_NAME=""
    SUFFIX_DIR=""
    SHORTCUT_NAME="v2bx"
else
    if [[ ! "$SITE_TAG" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "\033[0;31m[ERROR] SITE_TAG 只能包含字母、数字或下划线。\033[0m"
        exit 1
    fi
    SUFFIX_NAME="-${SITE_TAG}"
    SUFFIX_DIR="_${SITE_TAG}"
    SHORTCUT_NAME="v2bx_${SITE_TAG}"
    echo -e "\033[0;32m[INFO] 多开模式已启用。当前实例标签: ${SITE_TAG}\033[0m"
fi

# 默认参数
: "${IMAGE_NAME:=ghcr.io/passerby7890/v2bxx:latest}"
: "${V2RAY_PROTOCOL:=vmess}"
EXTRA_DOCKER_ARGS=""

# 路径定义
case "$INSTALL_TYPE" in
    ss|shadowsocks)
        CONTAINER_NAME="v2bx-ss${SUFFIX_NAME}"
        HOST_CONFIG_DIR="/etc/V2bX_SS${SUFFIX_DIR}"
        TARGET_NODE_TYPE="shadowsocks"
        ;;
    v2ray|vmess|vless)
        CONTAINER_NAME="v2bx-v2ray${SUFFIX_NAME}"
        HOST_CONFIG_DIR="/etc/V2bX_V2RAY${SUFFIX_DIR}"
        TARGET_NODE_TYPE="${V2RAY_PROTOCOL}"
        ;;
    hy2|hysteria2)
        CONTAINER_NAME="v2bx-hy2${SUFFIX_NAME}"
        HOST_CONFIG_DIR="/etc/V2bX_HY2${SUFFIX_DIR}"
        TARGET_NODE_TYPE="hysteria2"
        EXTRA_DOCKER_ARGS="--cap-add=NET_ADMIN"
        ;;
    *)
        echo -e "\033[0;31m[ERROR] 未知的类型: $INSTALL_TYPE\033[0m"
        exit 1
        ;;
esac

# --- [Module 1] 系统包管理器修复 (安全版) ---
fix_package_lock() {
    if ! command -v docker &> /dev/null; then
        echo -e "\033[0;34m[SYSTEM] 检测系统包管理器状态...\033[0m"
        if pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null; then
            echo -e "\033[0;33m[WARN] 发现卡死的 apt 进程，正在清理...\033[0m"
            killall apt apt-get 2>/dev/null
            sleep 2
        fi
        
        if fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || [ -f /var/lib/dpkg/lock ]; then
            echo -e "\033[0;33m[WARN] 删除残留锁文件...\033[0m"
            rm -f /var/lib/dpkg/lock
            rm -f /var/lib/dpkg/lock-frontend
            rm -f /var/lib/apt/lists/lock
            dpkg --configure -a
            echo -e "\033[0;32m[FIX] 解锁完成。\033[0m"
        fi
    fi
}

# --- [Module 2] 系统内核参数 (强制执行版) ---
configure_system_global() {
    local SYSCTL_CONF="/etc/sysctl.conf"
    local NEED_RELOAD=0
    declare -A KERNEL_PARAMS=(
        ["vm.swappiness"]="60"
        ["net.core.default_qdisc"]="fq"
        ["net.ipv4.tcp_congestion_control"]="bbr"
        ["vm.panic_on_oom"]="1"
        ["kernel.panic"]="10"
    )
    echo -e "\033[0;34m[SYSTEM] 正在强制校准内核参数...\033[0m"
    for param in "${!KERNEL_PARAMS[@]}"; do
        expected_value="${KERNEL_PARAMS[$param]}"
        if grep -q "^$param" "$SYSCTL_CONF"; then
            current_value=$(grep "^$param" "$SYSCTL_CONF" | awk -F= '{print $2}' | tr -d ' ')
            if [ "$current_value" != "$expected_value" ]; then
                sed -i "s|^$param.*|$param = $expected_value|" "$SYSCTL_CONF"
                NEED_RELOAD=1
            fi
        else
            echo "$param = $expected_value" >> "$SYSCTL_CONF"
            NEED_RELOAD=1
        fi
    done
    if [ $NEED_RELOAD -eq 1 ]; then
        sysctl -p >/dev/null 2>&1
        echo -e "\033[0;32m[SYSTEM] 内核参数已校准并重载。\033[0m"
    fi
}

# --- [Module 3] Swap 内存 ---
configure_swap() {
    if [ -f "/swapfile" ]; then return; fi
    local CURRENT_SWAP=$(free -m | grep Swap | awk '{print $2}')
    if [ "$CURRENT_SWAP" -gt 1024 ]; then return; fi

    echo -e "\033[0;33m[SYSTEM] 正在创建 2GB Swap...\033[0m"
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
}

# --- [Module 4] ZRAM 内存压缩 (深度检测版) ---
configure_zram() {
    if grep -q "zram" /proc/swaps; then 
        echo -e "\033[0;32m[SYSTEM] ZRAM Swap 已激活，跳过配置。\033[0m"
        return
    fi
    echo -e "\033[0;34m[SYSTEM] 正在配置 ZRAM 内存压缩...\033[0m"
    modprobe zram num_devices=1
    cat > /usr/local/bin/init-zram.sh <<EOF
#!/bin/bash
modprobe zram num_devices=1
TOTAL_MEM_KB=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
ZRAM_SIZE_BYTES=\$((TOTAL_MEM_KB * 512))
echo \$ZRAM_SIZE_BYTES > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon /dev/zram0 -p 100
EOF
    chmod +x /usr/local/bin/init-zram.sh
    cat > /etc/systemd/system/zram-config.service <<EOF
[Unit]
Description=Configure zRAM swap
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/init-zram.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable zram-config >/dev/null 2>&1
    systemctl start zram-config >/dev/null 2>&1
    echo -e "\033[0;32m[SYSTEM] ZRAM 配置完成。\033[0m"
}

# --- [Module 5] 快捷指令 ---
install_shortcut() {
    cat > /usr/bin/${SHORTCUT_NAME} <<EOF
#!/bin/bash
# V2bX Shortcut for Tag: ${SITE_TAG:-Default}
C_NAME="${CONTAINER_NAME}"
IMG="${IMAGE_NAME}"
CONF_DIR="${HOST_CONFIG_DIR}"

case "\$1" in
    start)   docker start \$C_NAME ;;
    stop)    docker stop \$C_NAME ;;
    restart) docker restart \$C_NAME ;;
    logs)    docker logs -f --tail 100 \$C_NAME ;;
    update)
        docker pull \$IMG
        docker stop \$C_NAME
        docker rm \$C_NAME
        docker run -d --name \$C_NAME --restart always --network host --cap-add=SYS_TIME \\
            --ulimit nofile=65535:65535 --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \\
            -e GOGC=50 ${EXTRA_DOCKER_ARGS} \\
            -v \$CONF_DIR:/etc/V2bX -v /etc/localtime:/etc/localtime:ro \$IMG
        ;;
    *) echo "Usage: ${SHORTCUT_NAME} {start|stop|restart|logs|update}" ;;
esac
EOF
    chmod +x /usr/bin/${SHORTCUT_NAME}
}

# --- [Main] 部署主流程 ---
deploy() {
    echo -e "\033[0;34m[DEPLOY] 开始部署实例: ${CONTAINER_NAME}\033[0m"
    
    fix_package_lock
    configure_system_global
    configure_swap
    configure_zram
    
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        apt-get update -y >/dev/null 2>&1
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker >/dev/null 2>&1
        systemctl start docker >/dev/null 2>&1
    fi

    mkdir -p ${HOST_CONFIG_DIR}
    
    NODES_JSON=""
    IFS=',' read -ra ID_ARRAY <<< "$NODE_IDS"
    COMMA=""
    for id in "${ID_ARRAY[@]}"; do
        clean_id=$(echo "$id" | tr -d '[:space:]')
        [ -z "$clean_id" ] && continue
        
        NODES_JSON="${NODES_JSON}${COMMA}
        {
            \"Name\": \"${SITE_TAG}_${INSTALL_TYPE}_${clean_id}\",
            \"Core\": \"sing\", \"CoreName\": \"sing1\",
            \"ApiHost\": \"${API_HOST%/}\", \"ApiKey\": \"${API_KEY}\",
            \"NodeID\": ${clean_id}, \"NodeType\": \"${TARGET_NODE_TYPE}\",
            \"Timeout\": 30, \"ListenIP\": \"0.0.0.0\", \"SendIP\": \"0.0.0.0\",
            \"DeviceOnlineMinTraffic\": 100, \"EnableProxyProtocol\": true,
            \"EnableTFO\": true,
            \"MultiplexConfig\": { \"Enable\": true, \"Padding\": true }
        }"
        COMMA=","
    done

    cat > ${HOST_CONFIG_DIR}/config.json <<EOF
{
  "Log": { "Level": "error", "Output": "" },
  "Cores": [
    {
      "Type": "sing",
      "Name": "sing1",
      "Log": { "Level": "error", "Timestamp": true },
      "NTP": { "Enable": true, "Server": "pool.ntp.org", "ServerPort": 123 },
      "OriginalPath": "/etc/V2bX/sing_origin.json"
    }
  ],
  "Nodes": [ ${NODES_JSON} ]
}
EOF

    echo -e "\033[0;34m[DOCKER] 拉取镜像并启动...\033[0m"
    docker pull $IMAGE_NAME >/dev/null 2>&1
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        --network host \
        --cap-add=SYS_TIME \
        --ulimit nofile=65535:65535 \
        --log-driver json-file \
        --log-opt max-size=10m --log-opt max-file=3 \
        -e GOGC=50 \
        $EXTRA_DOCKER_ARGS \
        -v ${HOST_CONFIG_DIR}:/etc/V2bX \
        -v /etc/localtime:/etc/localtime:ro \
        $IMAGE_NAME >/dev/null

    install_shortcut
    
    echo -e "\033[0;33m[CHECK] 启动后健康检查 (5秒)...\033[0m"
    sleep 5
    
    LOG_CHECK=$(docker logs --tail 20 $CONTAINER_NAME 2>&1)
    
    if echo "$LOG_CHECK" | grep -qiE "address already in use|bind: address in use"; then
        echo -e "\033[0;31m"
        echo "========================================================"
        echo " [严重警告] 启动失败：检测到端口冲突！"
        echo "========================================================"
        echo -e "\033[0m"
        echo "$LOG_CHECK" | grep -iE "address already in use|bind: address in use"
    elif echo "$LOG_CHECK" | grep -qiE "error|panic|fatal"; then
         echo -e "\033[0;31m[WARNING] 检测到 Error，请手动检查：${SHORTCUT_NAME} logs\033[0m"
    else
        echo -e "\033[0;32m[SUCCESS] 部署成功！所有 SRE 检查项目已通过。\033[0m"
        echo -e "实例名称: ${CONTAINER_NAME}"
        echo -e "管理指令: \033[0;33m${SHORTCUT_NAME} logs\033[0m"
    fi
}

deploy
