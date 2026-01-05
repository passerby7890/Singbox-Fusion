#!/bin/bash

# ==============================================================================
#  V2bX Enterprise Deployer - 0n21 Customized (Full Variables)
#  功能：
#    1. 强制检查所有 5 个变量 (含 INSTALL_TYPE)
#    2. 修复 Docker 镜像 (tracermy) + 核心类型 (sing)
#    3. 完整系统优化 (GSO, BBR, zRAM, Swap, OOM保护)
# ==============================================================================

# --- [0] 基础定义 ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 锁定镜像
IMAGE_NAME="tracermy/v2bx-wyx2685:latest"

# --- [1] 强制变量检查 (您指定的5个变量) ---
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$SITE_TAG" || -z "$INSTALL_TYPE" ]]; then
    echo -e "${RED}[Error] 变量缺失！${PLAIN}"
    echo -e "请检查是否已 Export 以下变量："
    echo -e "  - SITE_TAG"
    echo -e "  - API_HOST"
    echo -e "  - API_KEY"
    echo -e "  - NODE_IDS"
    echo -e "  - INSTALL_TYPE"
    exit 1
fi

# 定义容器与路径
CONTAINER_NAME="v2bxx-${SITE_TAG}"
HOST_CONFIG_DIR="/etc/V2bX_${SITE_TAG}"

echo -e "------------------------------------------------"
echo -e "准备部署 V2bX (${INSTALL_TYPE} 模式)"
echo -e "🔗 面板: ${GREEN}${API_HOST}${PLAIN}"
echo -e "🆔 节点: ${GREEN}${NODE_IDS}${PLAIN}"
echo -e "🏷️  标识: ${GREEN}${SITE_TAG}${PLAIN}"
echo -e "📦 镜像: ${GREEN}${IMAGE_NAME}${PLAIN}"
echo -e "------------------------------------------------"

# --- [2] 系统全优化模块 ---

configure_stability() {
    echo -e "${YELLOW}[优化] 配置 OOM 保护...${PLAIN}"
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness = 60" >> /etc/sysctl.conf
    else
        sed -i 's/^vm.swappiness.*/vm.swappiness = 60/' /etc/sysctl.conf
    fi
    if ! grep -q "vm.panic_on_oom" /etc/sysctl.conf; then
        echo "vm.panic_on_oom = 1" >> /etc/sysctl.conf
        echo "kernel.panic = 10" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
}

configure_zram() {
    if lsmod | grep -q zram; then return; fi
    echo -e "${YELLOW}[优化] 配置 zRAM...${PLAIN}"
    modprobe zram num_devices=1
    echo "zram" > /etc/modules-load.d/zram.conf
    echo "options zram num_devices=1" > /etc/modprobe.d/zram.conf
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
    systemctl daemon-reload; systemctl enable zram-config; systemctl start zram-config
}

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

# 3.1 运行优化
configure_stability
configure_zram
check_disk_swap
configure_bbr

# 3.2 Docker 检查
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}安装 Docker...${PLAIN}"
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable docker; systemctl start docker
fi

# 3.3 生成配置文件
echo -e "${YELLOW}生成配置文件...${PLAIN}"
mkdir -p "${HOST_CONFIG_DIR}"

NODE_IDS_JSON="[${NODE_IDS}]"

# 核心修正：Type: sing, Name: sing1 (适配 tracermy 镜像)
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
    echo -e "${YELLOW}清理旧容器...${PLAIN}"
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

echo -e "${YELLOW}拉取镜像...${PLAIN}"
docker pull ${IMAGE_NAME}

echo -e "${YELLOW}启动容器...${PLAIN}"
# 修正：--cap-add=SYS_TIME (修复NTP), --network=host
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

# 3.5 验证
sleep 5
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${GREEN}✅ 部署成功！${PLAIN}"
    docker logs --tail 10 ${CONTAINER_NAME}
else
    echo -e "${RED}❌ 启动失败！请检查日志。${PLAIN}"
fi
