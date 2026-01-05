#!/bin/bash

# ==============================================================================
#  V2bX 0n21 Fixer - Local Version
#  功能：读取本地变量、写入正确配置、保留所有优化
# ==============================================================================

# 1. 检查变量
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$SITE_TAG" ]]; then
    echo -e "\033[31m[错误] 变量丢失！请确保您已经执行了 export 命令。\033[0m"
    exit 1
fi

IMAGE_NAME="tracermy/v2bx-wyx2685:latest"
CONTAINER_NAME="v2bxx-${SITE_TAG}"
HOST_CONFIG_DIR="/etc/V2bX_${SITE_TAG}"

echo -e "\033[32m正在部署到: ${API_HOST} (节点: ${NODE_IDS})\033[0m"

# 2. 系统优化
echo "配置系统优化 (GSO/BBR/Swap)..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi
sysctl -p >/dev/null 2>&1

# 3. 生成配置文件 (关键修复：写入您 Export 的变量)
mkdir -p "${HOST_CONFIG_DIR}"
NODE_IDS_JSON="[${NODE_IDS}]"

cat > "${HOST_CONFIG_DIR}/config.json" <<EOF
{
  "Log": { "Level": "warning", "Output": "" },
  "Cores": [
    {
      "Type": "sing",
      "Name": "sing1",
      "Log": { "Level": "error", "Output": "" },
      "Path": "/usr/bin/v2bx-sing"
    }
  ],
  "Protocol": {
    "Type": "v2board",
    "Url": "${API_HOST}",
    "Token": "${API_KEY}",
    "NodeID": ${NODE_IDS_JSON},
    "Interval": 60
  },
  "SingboxConfig": {
    "EnableGSO": true,
    "TCPFastOpen": false,
    "Multiplex": {
      "Enabled": false,
      "Protocol": "smux",
      "MaxStreams": 32,
      "MinStreams": 4,
      "Padding": true
    },
    "VLESS": { "EnableReality": true }
  }
}
EOF

# 4. 启动容器
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

echo "启动容器..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart=always \
    --network=host \
    --cap-add=SYS_TIME \
    -v "${HOST_CONFIG_DIR}/config.json:/etc/v2bx/config.json" \
    -v "${HOST_CONFIG_DIR}/logs:/var/log/v2bx" \
    -v /etc/localtime:/etc/localtime:ro \
    -e SITE_TAG="${SITE_TAG}" \
    -e GOGC=50 \
    "${IMAGE_NAME}"

sleep 5
echo "------------------------------------------------"
docker logs --tail 10 ${CONTAINER_NAME}
echo "------------------------------------------------"
