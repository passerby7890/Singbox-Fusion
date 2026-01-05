#!/bin/bash

# =================================================================
#   V2bX Multi-Site Deployment Script (Isolation Mode)
#   特性：支援多網站並存、Docker 隔離、Sing-box 核心修復
#   包含優化：GSO, BBR, Swap, Docker 自動安裝
#   修正紀錄：移除 NTP 校時功能 (解決 i/o timeout 報錯)
#   版本狀態：黃金備份版 (Final Stable)
# =================================================================

# 0. 變數檢查 (確保外部變數已輸入)
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$INSTALL_TYPE" || -z "$SITE_TAG" ]]; then
    echo -e "\033[0;31m[Error] 缺少必要變數！\033[0m"
    echo -e "為了實現多站點隔離，請務必 export 以下變數："
    echo -e "  - SITE_TAG (例如: hash234, siteA, siteB)"
    echo -e "  - API_HOST, API_KEY, NODE_IDS, INSTALL_TYPE"
    exit 1
fi

# 1. 定義隔離與核心變數
# 使用 tracermy/v2bx-wyx2685 以確保 Sing-box 核心功能正常 (修復 unknown core type 錯誤)
: "${IMAGE_NAME:=tracermy/v2bx-wyx2685:latest}"
: "${V2RAY_PROTOCOL:=vmess}"

# 根據 SITE_TAG 生成唯一的容器名與路徑
UNIQUE_ID="${INSTALL_TYPE}-${SITE_TAG}"
CONTAINER_NAME="v2bx-${UNIQUE_ID}"
HOST_CONFIG_DIR="/etc/V2bX_${UNIQUE_ID}"
SHORTCUT_CMD="v2bx-${SITE_TAG}"

# 初始化額外參數
EXTRA_DOCKER_ARGS=""

# 根據安裝類型設定參數
case "$INSTALL_TYPE" in
    ss|shadowsocks)
        TARGET_NODE_TYPE="shadowsocks"
        DISPLAY_NAME="Shadowsocks [${SITE_TAG}]"
        ;;
    v2ray|vmess|vless)
        TARGET_NODE_TYPE="${V2RAY_PROTOCOL}"
        DISPLAY_NAME="V2Ray [${SITE_TAG}]"
        ;;
    hy2|hysteria2)
        TARGET_NODE_TYPE="hysteria2"
        DISPLAY_NAME="Hysteria2 [${SITE_TAG}]"
        EXTRA_DOCKER_ARGS="--cap-add=NET_ADMIN"
        ;;
    *)
        echo -e "\033[0;31m[Error] 未知的 INSTALL_TYPE: $INSTALL_TYPE\033[0m"
        exit 1
        ;;
esac

# --- [模組] 系統全方位優化 (GSO, BBR, Swap, Docker) ---
system_optimization() {
    echo -e "\033[0;32m[Info] 正在執行系統全方位優化...\033[0m"

    # 1. 安裝基礎工具
    if [ -x "$(command -v apt-get)" ]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget ethtool >/dev/null 2>&1
    elif [ -x "$(command -v yum)" ]; then
        yum install -y curl wget ethtool >/dev/null 2>&1
    fi

    # 2. 開啟 BBR 與 網路優化
    if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
        echo -e "\033[0;33m[Opt] 開啟 BBR...\033[0m"
        echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_notsent_lowat = 16384" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi

    # 3. 記憶體與 Swap 優化
    # 建立 2G Swap (如果不存在)
    if [ $(free -m | grep Swap | awk '{print $2}') -eq 0 ]; then
        echo -e "\033[0;33m[Opt] 檢測到無 Swap，正在建立 2GB Swap...\033[0m"
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    # 調整記憶體參數 (傾向使用實體記憶體，減少 Swap 頻率，但保留快取)
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness = 10" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure = 50" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi

    # 4. GSO (Generic Segmentation Offload) 網卡優化
    DEFAULT_NIC=$(ip route show | grep default | awk '{print $5}' | head -n1)
    if [ -n "$DEFAULT_NIC" ]; then
        echo -e "\033[0;33m[Opt] 正在對網卡 $DEFAULT_NIC 開啟 GSO/GRO 優化...\033[0m"
        ethtool -K "$DEFAULT_NIC" gso on gro on tso on >/dev/null 2>&1 || true
    fi

    # 5. Docker 安裝檢查
    if ! command -v docker &> /dev/null; then
        echo -e "\033[0;33m[Info] 正在安裝 Docker...\033[0m"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    else
        echo -e "\033[0;32m[Check] Docker 已安裝\033[0m"
    fi
}

# --- [模組] 安裝專屬快捷管理工具 ---
install_shortcut() {
    cat > /usr/bin/${SHORTCUT_CMD} <<EOF
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

NAME="${CONTAINER_NAME}"
DIR="${HOST_CONFIG_DIR}"
IMG="${IMAGE_NAME}"

# 容器操作
docker_op() {
    ACTION=\$1
    case "\$ACTION" in
        start)   docker start \$NAME && echo -e "\${GREEN}\$NAME 已啟動\${PLAIN}" ;;
        stop)    docker stop \$NAME && echo -e "\${GREEN}\$NAME 已停止\${PLAIN}" ;;
        restart) docker restart \$NAME && echo -e "\${GREEN}\$NAME 已重啟\${PLAIN}" ;;
        logs)    docker logs -f --tail 100 \$NAME ;;
    esac
}

# 更新容器
update_container() {
    echo -e "\${GREEN}正在更新 \$NAME ...\${PLAIN}"
    docker pull \$IMG
    docker stop \$NAME >/dev/null 2>&1
    docker rm \$NAME >/dev/null 2>&1
    
    # 重新運行容器
    docker run -d --name \$NAME --restart always --network host --cap-add=SYS_TIME \\
        --ulimit nofile=65535:65535 --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \\
        -e GOGC=50 ${EXTRA_DOCKER_ARGS} -v \$DIR:/etc/V2bX -v /etc/localtime:/etc/localtime:ro \$IMG
    echo -e "\${GREEN}\$NAME 更新完成！\${PLAIN}"
}

# 菜單
clear
echo -e "\${GREEN}================================================\${PLAIN}"
echo -e "\${GREEN}   V2bX 管理面板 - 站點: ${SITE_TAG}   \${PLAIN}"
echo -e "\${GREEN}================================================\${PLAIN}"
echo -e " 容器名稱: \${NAME}"
echo -e " 配置目錄: \${DIR}"
echo -e "------------------------------------------------"
echo -e " 1. 查看日誌 (Logs)"
echo -e " 2. 重啟服務 (Restart)"
echo -e " 3. 停止服務 (Stop)"
echo -e " 4. 更新鏡像 (Update)"
echo -e " 5. 卸載此節點 (Uninstall)"
echo -e " 0. 退出"
echo -e "------------------------------------------------"
read -p " 請輸入選項: " CHOICE

case "\$CHOICE" in
    1) docker_op logs ;;
    2) docker_op restart ;;
    3) docker_op stop ;;
    4) update_container ;;
    5) 
       read -p "確定刪除此站點節點嗎？(y/n): " C
       if [[ "\$C" == "y" ]]; then docker rm -f \$NAME; rm -rf \$DIR; rm /usr/bin/${SHORTCUT_CMD}; echo "已刪除"; fi
       ;;
    0) exit 0 ;;
    *) echo "無效輸入" ;;
esac
EOF
    chmod +x /usr/bin/${SHORTCUT_CMD}
}

deploy_v2bx() {
    echo -e "\033[0;32m[Info] 開始部署 V2bX [${DISPLAY_NAME}]...\033[0m"
    echo -e "容器標識: ${CONTAINER_NAME}"
    echo -e "配置路徑: ${HOST_CONFIG_DIR}"
    
    # 1. 執行系統優化 (包含 Docker 安裝)
    system_optimization
    
    # 2. 生成 Config (強制使用 sing 核心)
    # [修正] 移除了 NTP 區塊，解決 UDP 連線超時問題
    mkdir -p ${HOST_CONFIG_DIR}
    echo "{}" > ${HOST_CONFIG_DIR}/sing_origin.json
    
    NODES_JSON=""
    IFS=',' read -ra ID_ARRAY <<< "$NODE_IDS"
    COMMA=""
    for id in "${ID_ARRAY[@]}"; do
        clean_id=$(echo "$id" | tr -d '[:space:]')
        [ -z "$clean_id" ] && continue
        # 這裡強制 Core: sing，配合 wyx2685/tracermy 鏡像
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
      "Type": "sing", "Name": "sing1",
      "Log": { "Level": "error", "Timestamp": true },
      "OriginalPath": "/etc/V2bX/sing_origin.json"
    }
  ],
  "Nodes": [ ${NODES_JSON} ]
}
EOF

    # 3. 容器部署
    echo -e "\033[0;32m[Info] 拉取鏡像: ${IMAGE_NAME} ...\033[0m"
    docker pull $IMAGE_NAME
    
    # 清理舊的同名容器（針對當前 SITE_TAG）
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    # [備註] 若遇到 TLS handshake timeout，請在下方加入 --dns 8.8.8.8 --add-host 域名:IP
    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        --network host \
        --cap-add=SYS_TIME \
        --ulimit nofile=65535:65535 \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        -e GOGC=50 \
        $EXTRA_DOCKER_ARGS \
        -v ${HOST_CONFIG_DIR}:/etc/V2bX \
        -v /etc/localtime:/etc/localtime:ro \
        $IMAGE_NAME
        
    # 4. 完成
    install_shortcut
    echo -e "\033[0;32m[Success] 部署成功！\033[0m"
    echo "------------------------------------------------"
    echo -e "專屬管理指令: \033[0;33m${SHORTCUT_CMD}\033[0m"
    echo "------------------------------------------------"
    echo -e "正在檢查日誌..."
    sleep 3
    docker logs --tail 10 ${CONTAINER_NAME}
}

deploy_v2bx
