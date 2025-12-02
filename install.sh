#!/bin/bash

# =================================================================
#  V2bX Unified Install Script (SS / V2Ray / Hy2)
#  Hosted at: https://github.com/nick0425-ops/Singbox-Fusion
# =================================================================

# 0. 變數檢查
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$INSTALL_TYPE" ]]; then
    echo -e "\033[0;31m[Error] 缺少必要變數！\033[0m"
    echo -e "請確保設定了以下變數："
    echo -e "  - API_HOST, API_KEY, NODE_IDS, INSTALL_TYPE"
    exit 1
fi

# 設定預設變數
: "${IMAGE_NAME:=ghcr.io/nick0425-ops/v2bxx:latest}"
: "${V2RAY_PROTOCOL:=vmess}"

# 初始化額外參數
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
        EXTRA_DOCKER_ARGS="--cap-add=NET_ADMIN"
        ;;
    *)
        echo -e "\033[0;31m[Error] 未知的 INSTALL_TYPE: $INSTALL_TYPE\033[0m"
        exit 1
        ;;
esac

deploy_v2bx() {
    echo -e "\033[0;32m[Info] 開始部署 V2bX [${DISPLAY_NAME}] 版...\033[0m"
    echo -e "面板地址: ${API_HOST}"
    echo -e "輸入 ID : ${NODE_IDS}"
    echo -e "容器名稱: ${CONTAINER_NAME}"
    echo -e "配置目錄: ${HOST_CONFIG_DIR}"

    # --- 1. 智能 ID 合併邏輯 ---
    FINAL_NODE_IDS_LIST=""
    
    # 檢查是否已存在舊配置
    if [ -f "${HOST_CONFIG_DIR}/config.json" ]; then
        echo -e "\033[0;33m[Info] 檢測到舊配置文件，正在讀取舊節點 ID...\033[0m"
        # 使用 grep 提取舊 ID
        OLD_IDS=$(grep -oE '"NodeID":\s*[0-9]+' "${HOST_CONFIG_DIR}/config.json" | grep -oE '[0-9]+' | tr '\n' ',' | sed 's/,$//')
        
        if [ -n "$OLD_IDS" ]; then
            echo -e "舊節點 ID: ${OLD_IDS}"
            # 合併舊 ID 和新輸入的 ID (使用換行符分隔，排序，去重，再轉回逗號分隔)
            COMBINED_IDS=$(echo "${OLD_IDS},${NODE_IDS}" | tr ',' '\n' | sort -n | uniq | tr '\n' ',' | sed 's/,$//')
            FINAL_NODE_IDS_LIST="$COMBINED_IDS"
            echo -e "\033[0;32m[Info] 合併後的節點 ID: ${FINAL_NODE_IDS_LIST}\033[0m"
        else
            FINAL_NODE_IDS_LIST="$NODE_IDS"
        fi
    else
        FINAL_NODE_IDS_LIST="$NODE_IDS"
    fi
    # ---------------------------

    # 2. 環境檢查 (Docker)
    if ! command -v docker &> /dev/null; then
        echo -e "\033[0;33m[Warn] 未檢測到 Docker，正在安裝...\033[0m"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi

    # 3. BBR 優化 (略過重複代碼，保持之前的優化邏輯)
    NEED_SYSCTL_RELOAD=0
    if grep -q "net.core.default_qdisc" /etc/sysctl.conf; then
        if ! grep -q "net.core.default_qdisc = fq" /etc/sysctl.conf; then
            sed -i 's/^net.core.default_qdisc.*/net.core.default_qdisc = fq/' /etc/sysctl.conf
            NEED_SYSCTL_RELOAD=1
        fi
    else
        echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
        NEED_SYSCTL_RELOAD=1
    fi
    if grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
        if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
            sed -i 's/^net.ipv4.tcp_congestion_control.*/net.ipv4.tcp_congestion_control = bbr/' /etc/sysctl.conf
            NEED_SYSCTL_RELOAD=1
        fi
    else
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
        NEED_SYSCTL_RELOAD=1
    fi
    if [[ $NEED_SYSCTL_RELOAD -eq 1 ]] || ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        sysctl -p >/dev/null 2>&1
    fi

    # 4. 生成設定檔
    mkdir -p ${HOST_CONFIG_DIR}
    echo "{}" > ${HOST_CONFIG_DIR}/sing_origin.json
    
    NODES_JSON=""
    IFS=',' read -ra ID_ARRAY <<< "$FINAL_NODE_IDS_LIST"
    COMMA=""
    for id in "${ID_ARRAY[@]}"; do
        clean_id=$(echo "$id" | tr -d '[:space:]')
        [ -z "$clean_id" ] && continue
        
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

    cat > ${HOST_CONFIG_DIR}/config.json <<EOF
{
  "Log": { "Level": "error", "Output": "" },
  "Cores": [
    {
      "Type": "sing", "Name": "sing1",
      "Log": { "Level": "error", "Timestamp": true },
      "NTP": { "Enable": true, "Server": "pool.ntp.org", "ServerPort": 123 },
      "OriginalPath": "/etc/V2bX/sing_origin.json"
    }
  ],
  "Nodes": [ ${NODES_JSON} ]
}
EOF

    # 5. 容器部署
    echo -e "\033[0;32m[Info] 正在拉取鏡像: ${IMAGE_NAME} ...\033[0m"
    if ! docker pull $IMAGE_NAME; then
        echo -e "\033[0;31m[Error] 鏡像拉取失敗。\033[0m"
        exit 1
    fi
    
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        --network host \
        --cap-add=SYS_TIME \
        --ulimit nofile=65535:65535 \
        $EXTRA_DOCKER_ARGS \
        -v ${HOST_CONFIG_DIR}:/etc/V2bX \
        $IMAGE_NAME
        
    # 6. 結果展示與日誌檢測
    echo -e "\033[0;32m[Success] 部署指令已完成！\033[0m"
    echo "------------------------------------------------"
    echo "容器名稱: ${CONTAINER_NAME}"
    echo -e "目前生效的 Node ID: \033[0;36m${FINAL_NODE_IDS_LIST}\033[0m"
    echo "------------------------------------------------"
    echo -e "\033[0;33m[Check] 正在獲取最後 10 行運行日誌...\033[0m"
    echo "------------------------------------------------"
    sleep 3 # 等待容器啟動
    docker logs --tail 10 ${CONTAINER_NAME}
    echo "------------------------------------------------"
    echo -e "\033[0;32m如果上方日誌無 Error，則代表運行正常。\033[0m"
}

deploy_v2bx
