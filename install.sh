#!/bin/bash

# =================================================================
#  V2bX Install Script (Fixed Image & Syntax)
# =================================================================

# 0. 变量检查 (依赖外部 export 的变量)
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$INSTALL_TYPE" ]]; then
    echo -e "\033[0;31m[Error] 缺少必要变量！\033[0m"
    echo -e "请先 export 以下变量: API_HOST, API_KEY, NODE_IDS, INSTALL_TYPE"
    exit 1
fi

# --- 核心修正 1: 更改默认镜像为官方可用版本 ---
: "${IMAGE_NAME:=ghcr.io/passerby7890/v2bxx:latest}"
: "${V2RAY_PROTOCOL:=vmess}"

# 初始化额外参数
EXTRA_DOCKER_ARGS=""

# 根据安装类型设定环境参数
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

# --- [模块] 系统优化 (保留原功能) ---
configure_stability() {
    echo -e "\033[0;32m[Info] 配置系统稳定性...\033[0m"
    grep -q "vm.swappiness" /etc/sysctl.conf || echo "vm.swappiness = 60" >> /etc/sysctl.conf
    grep -q "vm.panic_on_oom" /etc/sysctl.conf || { echo "vm.panic_on_oom = 1" >> /etc/sysctl.conf; echo "kernel.panic = 10" >> /etc/sysctl.conf; }
    sysctl -p >/dev/null 2>&1
}

# --- [模块] 生成配置 ---
deploy_v2bx() {
    echo -e "\033[0;32m[Info] 开始部署 V2bX [${DISPLAY_NAME}] ...\033[0m"
    
    configure_stability

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "\033[0;33m[Warn] 安装 Docker...\033[0m"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi

    # 生成 config.json
    mkdir -p ${HOST_CONFIG_DIR}
    echo "{}" > ${HOST_CONFIG_DIR}/sing_origin.json
    
    NODES_JSON=""
    IFS=',' read -ra ID_ARRAY <<< "$NODE_IDS"
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

    # 拉取镜像
    echo -e "\033[0;32m[Info] 拉取镜像: ${IMAGE_NAME} ...\033[0m"
    if ! docker pull $IMAGE_NAME; then
        echo -e "\033[0;31m[Error] 镜像拉取失败 (Permission Denied 或 网络错误)\033[0m"
        exit 1
    fi
    
    # 清理旧容器
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    # --- 核心修正 2: 修复 Docker Run 断行/空变量 Bug ---
    echo -e "\033[0;32m[Info] 启动容器...\033[0m"
    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        --network host \
        --cap-add=SYS_TIME \
        --ulimit nofile=65535:65535 \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        -e GOGC=50 $EXTRA_DOCKER_ARGS \
        -v ${HOST_CONFIG_DIR}:/etc/V2bX \
        -v /etc/localtime:/etc/localtime:ro \
        $IMAGE_NAME
        
    echo -e "\033[0;32m[Success] 部署完成！容器名称: ${CONTAINER_NAME}\033[0m"
    echo -e "\033[0;33m正在检查日志...\033[0m"
    sleep 3
    docker logs --tail 10 ${CONTAINER_NAME}
}

# 执行部署
deploy_v2bx
