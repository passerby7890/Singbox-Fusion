#!/bin/bash

# =================================================================
#  V2bX Unified Install Script (SS / V2Ray / Hy2)
#  Hosted at: https://github.com/nick0425-ops/Singbox-Fusion
# =================================================================

# 0. 變數檢查
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$INSTALL_TYPE" ]]; then
    echo -e "\033[0;31m[Error] 缺少必要變數！\033[0m"
    echo -e "請確保設定了以下變數："
    echo -e "  - API_HOST"
    echo -e "  - API_KEY"
    echo -e "  - NODE_IDS"
    echo -e "  - INSTALL_TYPE (ss | v2ray | hy2)"
    exit 1
fi

# 設定預設變數
: "${IMAGE_NAME:=ghcr.io/nick0425-ops/v2bxx:latest}"
: "${V2RAY_PROTOCOL:=vmess}" # 僅當 INSTALL_TYPE=v2ray 時生效

# 初始化額外參數，避免環境污染
EXTRA_DOCKER_ARGS=""

# 根據安裝類型設定環境參數
case "$INSTALL_TYPE" in
    ss|shadowsocks)
        CONTAINER_NAME="v2bx-ss"
        HOST_CONFIG_DIR="/etc/V2bX_SS"
        TARGET_NODE_TYPE="shadowsocks"
        DISPLAY_NAME="Shadowsocks"
        ;;
    v2ray|vmess|vless)
        CONTAINER_NAME="v2bx-v2ray"
        HOST_CONFIG_DIR="/etc/V2bX_V2RAY"
        TARGET_NODE_TYPE="${V2RAY_PROTOCOL}"
        DISPLAY_NAME="V2Ray (${V2RAY_PROTOCOL})"
        ;;
    hy2|hysteria2)
        CONTAINER_NAME="v2bx-hy2"
        HOST_CONFIG_DIR="/etc/V2bX_HY2"
        TARGET_NODE_TYPE="hysteria2"
        DISPLAY_NAME="Hysteria2"
        # Hy2 建議增加 NET_ADMIN 權限以優化 UDP
        EXTRA_DOCKER_ARGS="--cap-add=NET_ADMIN"
        ;;
    *)
        echo -e "\033[0;31m[Error] 未知的 INSTALL_TYPE: $INSTALL_TYPE\033[0m"
        echo -e "請設定為: ss, v2ray, 或 hy2"
        exit 1
        ;;
esac

deploy_v2bx() {
    echo -e "\033[0;32m[Info] 開始部署 V2bX [${DISPLAY_NAME}] 版...\033[0m"
    echo -e "面板地址: ${API_HOST}"
    echo -e "節點 ID : ${NODE_IDS}"
    echo -e "容器名稱: ${CONTAINER_NAME}"
    echo -e "配置目錄: ${HOST_CONFIG_DIR}"
    echo -e "使用鏡像: ${IMAGE_NAME}"

    # 1. 環境檢查：安裝 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "\033[0;33m[Warn] 未檢測到 Docker，正在安裝...\033[0m"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y wget curl
        elif command -v yum &> /dev/null; then
            yum install -y wget curl
        fi
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    else
        echo -e "\033[0;32m[Info] Docker 已安裝。\033[0m"
    fi

    # 2. 系統優化：自動開啟 BBR + FQ (防重複寫入優化)
    echo -e "\033[0;32m[Info] 檢查 BBR 加速狀態...\033[0m"
    
    # 檢查是否需要修改 sysctl.conf
    NEED_SYSCTL_RELOAD=0

    # 優化 qdisc
    if grep -q "net.core.default_qdisc" /etc/sysctl.conf; then
        # 如果存在，替換它
        if ! grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf; then
            sed -i 's/^net.core.default_qdisc.*/net.core.default_qdisc = fq/' /etc/sysctl.conf
            NEED_SYSCTL_RELOAD=1
        fi
    else
        # 如果不存在，追加它
        echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
        NEED_SYSCTL_RELOAD=1
    fi

    # 優化 congestion_control
    if grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
        if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
            sed -i 's/^net.ipv4.tcp_congestion_control.*/net.ipv4.tcp_congestion_control = bbr/' /etc/sysctl.conf
            NEED_SYSCTL_RELOAD=1
        fi
    else
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
        NEED_SYSCTL_RELOAD=1
    fi

    # 只有在修改了配置或當前未生效時才重載
    if [[ $NEED_SYSCTL_RELOAD -eq 1 ]] || ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        sysctl -p >/dev/null 2>&1
        echo -e "\033[0;32m[Info] BBR + FQ 優化已應用。\033[0m"
    else
        echo -e "\033[0;32m[Info] BBR 已經開啟，無需變更。\033[0m"
    fi

    # 3. 設定檔生成 (寫入到對應的獨立目錄)
    echo -e "\033[0;32m[Info] 正在生成 V2bX 配置文件...\033[0m"
    mkdir -p ${HOST_CONFIG_DIR}
    echo "{}" > ${HOST_CONFIG_DIR}/sing_origin.json
    
    NODES_JSON=""
    IFS=',' read -ra ID_ARRAY <<< "$NODE_IDS"
    COMMA=""
    for id in "${ID_ARRAY[@]}"; do
        clean_id=$(echo "$id" | tr -d '[:space:]')
        [ -z "$clean_id" ] && continue
        
        # 構建 JSON 對象
        NODES_JSON="${NODES_JSON}${COMMA}
        {
            \"Name\": \"${INSTALL_TYPE}_Node_${clean_id}\",
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

    # 寫入完整配置
    cat > ${HOST_CONFIG_DIR}/config.json <<EOF
{
  "Log": { "Level": "error", "Output": "" },
  "Cores": [
    {
      "Type": "sing", "Name": "sing1",
      "Log": { "Level": "error", "Timestamp": true },
      "NTP": { "Enable": true, "Server": "time.apple.com", "ServerPort": 0 },
      "OriginalPath": "/etc/V2bX/sing_origin.json"
    }
  ],
  "Nodes": [ ${NODES_JSON} ]
}
EOF

    # 4. 容器部署
    echo -e "\033[0;32m[Info] 正在拉取鏡像: ${IMAGE_NAME} ...\033[0m"
    
    # 優化：先拉取鏡像，失敗則終止，避免刪除舊容器後無法啟動新容器
    if ! docker pull $IMAGE_NAME; then
        echo -e "\033[0;31m[Error] 鏡像拉取失敗，請檢查網絡連線。\033[0m"
        exit 1
    fi
    
    # 停止舊容器
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    # 啟動容器
    # --network host: 極致效能
    # --cap-add=SYS_TIME: NTP 校時權限
    # $EXTRA_DOCKER_ARGS: 額外參數 (如 Hy2 的 NET_ADMIN)
    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        --network host \
        --cap-add=SYS_TIME \
        --ulimit nofile=65535:65535 \
        $EXTRA_DOCKER_ARGS \
        -v ${HOST_CONFIG_DIR}:/etc/V2bX \
        $IMAGE_NAME
        
    # 5. 狀態檢查
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "\033[0;32m[Success] V2bX [${DISPLAY_NAME}] 部署成功！\033[0m"
        echo "------------------------------------------------"
        echo "配置目錄: ${HOST_CONFIG_DIR}"
        echo "容器名稱: ${CONTAINER_NAME}"
        echo "版本資訊："
        docker exec $CONTAINER_NAME /usr/bin/V2bX version
        echo "------------------------------------------------"
    else
        echo -e "\033[0;31m[Error] 啟動失敗，請檢查變數或日誌 (docker logs ${CONTAINER_NAME})。\033[0m"
    fi
}

deploy_v2bx
