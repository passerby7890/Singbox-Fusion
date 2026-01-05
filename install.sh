#!/bin/bash

# ==============================================================================
#  V2bX Enterprise Deployer - Google SRE Edition (Fix v2)
#  功能：多实例隔离、自动内核优化、修正 Core Type 兼容性
# ==============================================================================

# --- [0] 基础定义与颜色 ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

log_info() { echo -e "${GREEN}[INFO] $1${PLAIN}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${PLAIN}"; }
log_err() { echo -e "${RED}[ERROR] $1${PLAIN}"; }

# --- [1] 安全检查：核心变量验证 ---
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$SITE_TAG" ]]; then
    log_err "变量缺失！"
    echo "请先执行 export 命令設定以下變數："
    echo "  export SITE_TAG=\"hash234\""
    echo "  export API_HOST=\"https://xxx.com\""
    echo "  export API_KEY=\"sk-xxxxxx\""
    echo "  export NODE_IDS=\"1,2,3\""
    exit 1
fi

# --- [2] 资源隔离计算 ---
CONTAINER_NAME="v2bxx-${SITE_TAG}"
HOST_CONFIG_DIR="/etc/V2bX_${SITE_TAG}"

# *** 锁定镜像 (您指定的) ***
IMAGE_NAME="tracermy/v2bx-wyx2685:latest"

log_info "----------------------------------------------------"
log_info "启动 V2bX 部署流程 (Site: ${SITE_TAG})"
echo -e "📦 容器名称: ${YELLOW}${CONTAINER_NAME}${PLAIN}"
echo -e "📂 配置路径: ${YELLOW}${HOST_CONFIG_DIR}${PLAIN}"
log_info "----------------------------------------------------"

# --- [3] 系统内核优化 ---
log_info "正在检查系统内核参数..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
fi
ulimit -n 65535

# --- [4] Docker 环境准备 ---
if ! command -v docker &> /dev/null; then
    log_warn "Docker 未安装，正在自动安装..."
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable docker
    systemctl start docker
fi

# --- [5] 生成配置文件 (核心修正) ---
log_info "正在生成隔离配置文件..."

mkdir -p "${HOST_CONFIG_DIR}"

# 将 "1,2,3" 转换为 JSON 数组 "[1,2,3]"
NODE_IDS_JSON="[${NODE_IDS}]"

# *** 修正重点：Type 改为 'sing'，增加 'Name'，兼容旧版 V2bX ***
cat > "${HOST_CONFIG_DIR}/config.json" <<EOF
{
  "Log": {
    "Level": "warning",
    "Output": ""
  },
  "Cores": [
    {
      "Type": "sing",
      "Name": "sing1",
      "Log": {
        "Level": "error",
        "Output": ""
      },
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
    "VLESS": {
      "EnableReality": true
    }
  }
}
EOF

log_info "配置文件已写入: ${HOST_CONFIG_DIR}/config.json"

# --- [6] 容器部署 ---

# 6.1 清理旧实例
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    log_warn "发现旧容器 (${CONTAINER_NAME})，正在重置..."
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

# 6.2 拉取镜像
log_info "拉取镜像 ${IMAGE_NAME}..."
docker pull ${IMAGE_NAME}

if [ $? -ne 0 ]; then
    log_err "镜像拉取失败！"
    exit 1
fi

# 6.3 启动容器
log_info "正在启动容器..."

# 注意：这里挂载路径微调，确保兼容性
docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart=always \
    --network=host \
    -v "${HOST_CONFIG_DIR}/config.json:/etc/v2bx/config.json" \
    -v "${HOST_CONFIG_DIR}/logs:/var/log/v2bx" \
    -v /etc/localtime:/etc/localtime:ro \
    -e SITE_TAG="${SITE_TAG}" \
    -e GOGC=50 \
    "${IMAGE_NAME}"

# --- [7] 最终验证 ---
sleep 3
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    log_info "✅ 部署成功！"
    echo "------------------------------------------------"
    echo -e "日志查看: docker logs -f ${CONTAINER_NAME}"
    echo "------------------------------------------------"
    
    # 自动检查是否有 'new core failed' 错误
    if docker logs ${CONTAINER_NAME} 2>&1 | grep -q "new core failed"; then
         log_err "检测到 'new core failed' 错误！可能是配置文件仍不兼容。"
         log_err "请尝试手动查看日志: docker logs ${CONTAINER_NAME}"
    else
         echo -e "${GREEN}日志检查正常，未发现内核启动错误。${PLAIN}"
    fi
else
    log_err "❌ 部署失败！容器启动后立即退出。"
    exit 1
fi
