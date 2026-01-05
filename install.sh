#!/bin/bash

# ==============================================================================
#  V2bX Enterprise Deployer - Final Perfect Edition
#  功能：
#    1. [强制外置变量]：必须先 export 变量，否则拒绝运行 (防止配置错乱)
#    2. [核心修复]：Docker 镜像 (tracermy) + 核心类型 (sing) + NTP 时间权限
#    3. [系统全优化]：GSO + BBR + zRAM + Swap + OOM 保护
# ==============================================================================

# --- [0] 基础定义 ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 锁定镜像 (您指定的版本)
IMAGE_NAME="tracermy/v2bx-wyx2685:latest"

# --- [1] 强制检查外部变量 (您要求的“变数外置”检测) ---
# 如果没检测到 export 的变量，直接报错退出，不给默认值
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$SITE_TAG" ]]; then
    echo -e "${RED}[Error] 未检测到环境变量！禁止运行。${PLAIN}"
    echo -e "请在运行脚本前，务必先执行以下 export 命令："
    echo -e "${YELLOW}  export SITE_TAG=\"hash234\"${PLAIN}"
    echo -e "${YELLOW}  export API_HOST=\"https://www.hash234.com\"${PLAIN}"
    echo -e "${YELLOW}  export API_KEY=\"您的KEY\"${PLAIN}"
    echo -e "${YELLOW}  export NODE_IDS=\"1,2,3,4,5\"${PLAIN}"
    exit 1
fi

# 基于 SITE_TAG 计算隔离路径
CONTAINER_NAME="v2bxx-${SITE_TAG}"
HOST_CONFIG_DIR="/etc/V2bX_${SITE_TAG}"

echo -e "------------------------------------------------"
echo -e "检测到配置，准备部署："
echo -e "🔗 面板: ${GREEN}${API_HOST}${PLAIN}"
echo -e "🆔 节点: ${GREEN}${NODE_IDS}${PLAIN}"
echo -e "🏷️  标识: ${GREEN}${SITE_TAG}${PLAIN}"
echo -e "📦 镜像: ${GREEN}${IMAGE_NAME}${PLAIN}"
echo -e "------------------------------------------------"

# --- [2] 系统深度优化模块 (GSO, BBR, zRAM, Swap) ---

# 2.1 稳定性与 OOM 保护
configure_stability() {
    echo -e "${YELLOW}[优化] 配置 OOM 保护与 Swappiness...${PLAIN}"
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness = 60" >> /etc/sysctl.conf
    else
        sed -i 's/^vm.swappiness.*/vm.swappiness = 60/' /etc/sysctl.conf
    fi
    # 保护进程不被内存不足杀掉
    if ! grep -q "vm.panic_on_oom" /etc/sysctl.conf; then
        echo "vm.panic_on_oom = 1" >> /etc/sysctl.conf
        echo "kernel.panic = 10" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
}

# 2.2 zRAM 内存压缩
configure_zram() {
    if lsmod | grep -q zram; then return; fi
    echo -e "${YELLOW}[优化] 配置 zRAM 内存压缩...${PLAIN}"
    modprobe zram num_devices=1
    # 写入开机加载
    echo "zram" > /etc/modules-load.d/zram.conf
    echo "options zram num_devices=1" > /etc/modprobe.d/zram.conf
    # 创建初始化脚本
    cat > /usr/local/bin/init-zram.sh <<EOF
#!/bin/bash
modprobe zram num_devices=1
TOTAL_MEM=\$(grep MemTotal /proc/meminfo | awk '{print \$2 * 1024}')
ZRAM_SIZE=\$((TOTAL_MEM / 2))
echo \$ZRAM_SIZE > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon /dev/zram0 -p 100
EOF
    chmod +x /usr/local/bin/init-zram.sh
    # 创建服务
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
    systemctl daemon-reload
    systemctl enable zram-config
    systemctl start zram-config
}

# 2.3 磁盘 Swap 检查
check_disk_swap() {
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -lt 1024 ]; then
        echo -e "${YELLOW}[优化] Swap 不足，创建 2GB 备用 Swap...${PLAIN}"
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
}

# 2.4 BBR 与内核网络优化
configure_bbr() {
    echo -e "${YELLOW}[优化] 启用 BBR 与 IP 转发...${PLAIN}"
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
    ulimit -n 65535
}

# --- [3] 执行部署 ---

# 3.1 运行优化函数
configure_stability
configure_zram
check_disk_swap
configure_bbr

# 3.2 Docker 检查
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker 未安装，正在自动安装...${PLAIN}"
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable docker; systemctl start docker
fi

# 3.3 生成配置文件 (核心修正点)
echo -e "${YELLOW}生成配置文件 (含 GSO 优化)...${PLAIN}"
mkdir -p "${HOST_CONFIG_DIR}"

NODE_IDS_JSON="[${NODE_IDS}]"

# 重要：这里 Type 必须是 "sing"，Name 必须是 "sing1"，且开启 EnableGSO
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

# 3.4 启动容器
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${YELLOW}发现旧容器，正在清理...${PLAIN}"
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

echo -e "${YELLOW}拉取镜像 ${IMAGE_NAME}...${PLAIN}"
docker pull ${IMAGE_NAME}

echo -e "${YELLOW}启动容器...${PLAIN}"
# 启动参数修正：
# --cap-add=SYS_TIME : 修复 NTP 权限
# --network=host     : 修复连接拒绝
# -e GOGC=50         : 内存优化
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

# --- [4] 验证结果 ---
sleep 5
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${GREEN}✅ 部署成功！${PLAIN}"
    echo -e "日志检测 (最后 10 行):"
    echo "------------------------------------------------"
    docker logs --tail 10 ${CONTAINER_NAME}
    echo "------------------------------------------------"
    echo -e "${GREEN}如无报错，说明安装成功。${PLAIN}"
else
    echo -e "${RED}❌ 部署失败，容器未启动。请检查 docker logs ${CONTAINER_NAME}${PLAIN}"
fi
