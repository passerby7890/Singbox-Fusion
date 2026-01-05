#!/bin/bash

# ==============================================================================
#  V2bX Enterprise Deployer - Ultimate Fixed Edition
#  功能：
#    1. 完整保留系统优化 (BBR, zRAM, Swap, GSO, OOM Protect)
#    2. 修复 Docker 镜像为 tracermy/v2bx-wyx2685
#    3. 修复 Core Type 兼容性 (sing vs sing-box)
#    4. 修复 NTP 权限 (operation not permitted)
# ==============================================================================

# --- [0] 基础定义 ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 锁定镜像 (您指定的版本)
IMAGE_NAME="tracermy/v2bx-wyx2685:latest"

# --- [1] 变量检查 ---
if [[ -z "$API_HOST" || -z "$API_KEY" || -z "$NODE_IDS" || -z "$SITE_TAG" ]]; then
    echo -e "${RED}[Error] 变量缺失！${PLAIN}"
    echo -e "请先执行 export 命令，例如："
    echo -e "  export SITE_TAG=\"hash234\""
    echo -e "  export API_HOST=\"https://www.hash234.com\""
    echo -e "  export API_KEY=\"your_key\""
    echo -e "  export NODE_IDS=\"1,2,3,4,5\""
    exit 1
fi

CONTAINER_NAME="v2bxx-${SITE_TAG}"
HOST_CONFIG_DIR="/etc/V2bX_${SITE_TAG}"

echo -e "------------------------------------------------"
echo -e "准备部署 V2bX (Site: ${SITE_TAG})"
echo -e "🔗 面板: ${GREEN}${API_HOST}${PLAIN}"
echo -e "📦 镜像: ${GREEN}${IMAGE_NAME}${PLAIN}"
echo -e "🛠️  优化: ${GREEN}GSO, BBR, zRAM, Swap, Kernel Tuning${PLAIN}"
echo -e "------------------------------------------------"

# --- [2] 模块：系统稳定性与内存优化 ---
configure_stability() {
    echo -e "${YELLOW}[优化] 配置 OOM 保护与 Swappiness...${PLAIN}"
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
    echo -e "${YELLOW}[优化] 配置 zRAM 内存压缩...${PLAIN}"
    # 简单的 zRAM 初始化逻辑
    modprobe zram num_devices=1
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
    # Systemd 服务
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

# --- [3] 模块：快捷管理工具 ---
install_shortcut() {
    cat > /usr/bin/v2bx <<EOF
#!/bin/bash
docker logs -f --tail 100 ${CONTAINER_NAME}
EOF
    chmod +x /usr/bin/v2bx
    echo -e "${GREEN}[Info] 已安装快捷指令 'v2bx' (查看日志)${PLAIN}"
}

# --- [4] 主部署流程 ---

# 4.1 执行优化
configure_stability
configure_zram
check_disk_swap

# 4.2 环境准备
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}安装 Docker...${PLAIN}"
    curl -fsSL https://get.docker.com | bash -s docker
    systemctl enable docker; systemctl start docker
fi

# 4.3 BBR 与内核优化
echo -e "${YELLOW}[优化] 检查 BBR 与 IP 转发...${PLAIN}"
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi
sysctl -p >/dev/null 2>&1
ulimit -n 65535

# 4.4 生成配置文件 (已包含 GSO 优化 + 修复 Core Type)
echo -e "${YELLOW}生成配置文件...${PLAIN}"
mkdir -p "${HOST_CONFIG_DIR}"

NODE_IDS_JSON="[${NODE_IDS}]"

# *** 核心修正：Type: sing (旧版写法) + EnableGSO: true ***
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

# 4.5 启动容器
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${YELLOW}删除旧容器...${PLAIN}"
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

echo -e "${YELLOW}拉取镜像 ${IMAGE_NAME}...${PLAIN}"
docker pull ${IMAGE_NAME}

echo -e "${YELLOW}启动容器...${PLAIN}"
# 修正参数：--cap-add=SYS_TIME (修复NTP), --network=host, GOGC优化
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

# 4.6 验证与完成
install_shortcut
sleep 5
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${GREEN}✅ 部署成功！所有优化已应用。${PLAIN}"
    echo -e "日志最后 10 行:"
    echo "------------------------------------------------"
    docker logs --tail 10 ${CONTAINER_NAME}
    echo "------------------------------------------------"
else
    echo -e "${RED}❌ 部署失败，请检查 logs${PLAIN}"
fi
