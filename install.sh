#!/bin/bash

# =========================================================
# V2bX Auto-Installer (Multi-Instance & Optimized)
# 核心逻辑：基于环境变量动态生成配置与容器
# 优化策略：GSO=ON, Mux=OFF, TFO=OFF
# =========================================================

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 1. 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 错误: 必须使用 root 权限运行此脚本！${PLAIN}" 
    exit 1
fi

# 2. 检查必要变量
# 如果关键变量缺失，报错退出
if [ -z "$API_HOST" ] || [ -z "$API_KEY" ] || [ -z "$NODE_IDS" ]; then
    echo -e "${RED}❌ 错误: 缺少必要的环境变量！${PLAIN}"
    echo "请确保已设置以下变量:"
    echo "  - API_HOST (例如: https://xxx.com)"
    echo "  - API_KEY  (例如: xxxxxxx)"
    echo "  - NODE_IDS (例如: 1,2,3)"
    exit 1
fi

# 3. 处理 SITE_TAG (多开核心)
# 如果没传 SITE_TAG，默认给 "default"，防止脚本报错
SITE_TAG=${SITE_TAG:-"default"}

# 定义基于 TAG 的动态变量
CONTAINER_NAME="v2bxx-${SITE_TAG}"    # 容器名：v2bxx-hash234
HOST_CONFIG_PATH="/etc/V2bX_${SITE_TAG}"  # 配置目录：/etc/V2bX_hash234
IMAGE_NAME="wyx2685/v2bx:latest"      # 镜像名

echo -e "${GREEN}=============================================${PLAIN}"
echo -e "${GREEN}      V2bX 自动化部署脚本 (Sing-box)      ${PLAIN}"
echo -e "${GREEN}=============================================${PLAIN}"
echo -e "🏷️  实例标签 (Tag):  ${YELLOW}${SITE_TAG}${PLAIN}"
echo -e "📦 容器名称 (Name): ${YELLOW}${CONTAINER_NAME}${PLAIN}"
echo -e "📂 配置目录 (Dir):  ${YELLOW}${HOST_CONFIG_PATH}${PLAIN}"
echo -e "🔗 面板地址:        ${API_HOST}"
echo -e "🆔 节点 IDs:        ${NODE_IDS}"
echo -e "⚙️  优化策略:        GSO[开启], Mux[关闭], TFO[关闭]"
echo -e "${GREEN}=============================================${PLAIN}"

# 4. 安装/检查 Docker 环境
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}检测到未安装 Docker，正在安装...${PLAIN}"
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable docker
    systemctl start docker
else
    echo -e "${GREEN}✅ Docker 环境已就绪${PLAIN}"
fi

# 5. 生成配置文件 (config.json)
echo -e "${YELLOW}正在生成配置文件与优化参数...${PLAIN}"

# 创建目录
mkdir -p "${HOST_CONFIG_PATH}"

# 处理 Node IDs (把 "1,2,3" 转换成 JSON 数组 "[1,2,3]")
# 注意：这里直接把变量放入 [] 中，V2bX 能识别数字 ID
NODE_IDS_JSON="[${NODE_IDS}]"

cat > "${HOST_CONFIG_PATH}/config.json" <<EOF
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

echo -e "${GREEN}✅ 配置文件生成完毕: ${HOST_CONFIG_PATH}/config.json${PLAIN}"

# 6. 清理同名旧容器
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${YELLOW}♻️  发现同名旧容器，正在删除: ${CONTAINER_NAME}${PLAIN}"
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

# 7. 启动新容器
echo -e "${YELLOW}🚀 正在启动容器...${PLAIN}"

docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart=always \
    --network=host \
    -v "${HOST_CONFIG_PATH}:/etc/V2bX" \
    -v "${HOST_CONFIG_PATH}/sing-box:/var/lib/sing-box" \
    -v /etc/localtime:/etc/localtime:ro \
    -e SITE_TAG="${SITE_TAG}" \
    "${IMAGE_NAME}"

# 8. 最终验证
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${GREEN}=============================================${PLAIN}"
    echo -e "${GREEN}🎉 安装成功！服务已运行。${PLAIN}"
    echo -e "   - 容器名称: ${CONTAINER_NAME}"
    echo -e "   - 查看日志: docker logs -f ${CONTAINER_NAME}"
    echo -e "${GREEN}=============================================${PLAIN}"
else
    echo -e "${RED}❌ 安装失败，容器未能启动。请检查 docker logs ${CONTAINER_NAME}${PLAIN}"
    exit 1
fi
