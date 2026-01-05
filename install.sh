#!/bin/bash

# ==============================================================================
#  V2bX Enterprise Deployer - Google SRE Edition
#  功能：多实例隔离、自动内核优化、Docker 进程守护
#  架构：Sing-box Core + V2bX Controller
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
# 必须从外部传入变量，否则拒绝运行，防止配置错乱
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$SITE_TAG" ]]; then
    log_err "变量缺失！这是生产环境脚本，请严谨操作。"
    echo "请先执行 export 命令設定以下變數："
    echo "  export SITE_TAG=\"hash234\"      (用于隔离不同网站)"
    echo "  export API_HOST=\"https://xxx.com\""
    echo "  export API_KEY=\"sk-xxxxxx\""
    echo "  export NODE_IDS=\"1,2,3\""
    exit 1
fi

# --- [2] 资源隔离计算 (核心逻辑) ---
# 所有资源名称都基于 SITE_TAG 生成，确保绝对隔离
CONTAINER_NAME="v2bxx-${SITE_TAG}"       # 容器名：v2bxx-hash234
HOST_CONFIG_DIR="/etc/V2bX_${SITE_TAG}"  # 配置目录：/etc/V2bX_hash234
IMAGE_NAME="wyx2685/v2bx:latest"         # 官方稳定镜像

log_info "----------------------------------------------------"
log_info "启动 V2bX 部署流程 (Site: ${SITE_TAG})"
log_info "----------------------------------------------------"
echo -e "📦 容器名称: ${YELLOW}${CONTAINER_NAME}${PLAIN}"
echo -e "📂 配置路径: ${YELLOW}${HOST_CONFIG_DIR}${PLAIN}"
echo -e "🔗 面板地址: ${API_HOST}"
echo -e "🆔 节点 IDs: ${NODE_IDS}"
log_info "----------------------------------------------------"

# --- [3] 系统内核优化 (Kernel Tuning) ---
log_info "正在检查系统内核参数..."

# 开启 IP 转发 (流量转发基础)
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
fi

# 开启 BBR (拥塞控制)
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    log_info "已启用 BBR 拥塞控制"
fi

# 优化文件描述符 (防止高并发 Too many open files)
ulimit -n 65535

# --- [4] Docker 环境准备 ---
if ! command -v docker &> /dev/null; then
    log_warn "Docker 未安装，正在自动安装..."
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable docker
    systemctl start docker
fi

# --- [5] 生成配置文件 (Config Generation) ---
# 采用 V2bX 标准 Protocol 结构，稳定性最高
log_info "正在生成隔离配置文件..."

mkdir -p "${HOST_CONFIG_DIR}"

# 将 "1,2,3" 转换为 JSON 数组 "[1,2,3]"
NODE_IDS_JSON="[${NODE_IDS}]"

cat > "${HOST_CONFIG_DIR}/config.json" <<EOF
{
  "Log": {
    "Level": "warning",
    "Output": ""
  },
  "Cores": [
    {
      "Type": "sing-box",
      "Log": {
        "Level": "error",
        "Output": ""
      },
      "Path": "/var/lib/sing-box/sing-box"
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
    "VLESS": {
      "EnableReality": true
    }
  }
}
EOF
# 注：GSO 开启，Mux/TFO 关闭，这是最稳的生产环境配置。

log_info "配置文件已写入: ${HOST_CONFIG_DIR}/config.json"

# --- [6] 容器部署 (Deployment) ---

# 6.1 清理旧实例 (只清理同 Tag 的，绝不误杀其他网站)
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    log_warn "发现旧的同名容器 (${CONTAINER_NAME})，正在停止并移除..."
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

# 6.2 拉取最新镜像
log_info "拉取最新 V2bX 镜像..."
docker pull ${IMAGE_NAME} > /dev/null 2>&1

# 6.3 启动容器
# 关键参数解析：
# --network=host: 性能最佳，无 NAT 损耗
# -e GOGC=50: 内存优化，让 Go 语言更积极地回收内存
# -v ...: 挂载刚才生成的独立目录
log_info "正在启动容器..."

docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart=always \
    --network=host \
    -v "${HOST_CONFIG_DIR}:/etc/V2bX" \
    -v "${HOST_CONFIG_DIR}/sing-box:/var/lib/sing-box" \
    -v /etc/localtime:/etc/localtime:ro \
    -e SITE_TAG="${SITE_TAG}" \
    -e GOGC=50 \
    "${IMAGE_NAME}"

# --- [7] 最终验证 (Validation) ---
sleep 3
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    log_info "✅ 部署成功！服务运行中。"
    echo "------------------------------------------------"
    echo -e "容器状态: $(docker inspect -f '{{.State.Status}}' ${CONTAINER_NAME})"
    echo -e "日志查看: docker logs -f ${CONTAINER_NAME}"
    echo "------------------------------------------------"
else
    log_err "❌ 部署失败！容器启动后立即退出。"
    log_err "请检查日志: docker logs ${CONTAINER_NAME}"
    exit 1
fi
