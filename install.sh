#!/bin/bash

# =================================================================
#  V2bX Unified Install Script (SS / V2Ray / Hy2) - Ultimate Pro
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
: "${IMAGE_NAME:=ghcr.io/passerby7890/v2bxx:latest}"
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

# --- [模組] 配置系統穩定性參數 ---
configure_stability() {
    echo -e "\033[0;32m[Info] 正在配置系統穩定性參數 (OOM Protection)...\033[0m"
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

# --- [模組] 配置 zRAM ---
configure_zram() {
    if lsmod | grep -q zram; then return; fi
    echo -e "\033[0;32m[Info] 正在配置 zRAM 內存壓縮技術...\033[0m"
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
    systemctl daemon-reload
    systemctl enable zram-config
    systemctl start zram-config
}

# --- [模組] 檢查磁碟 Swap ---
check_disk_swap() {
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -lt 1024 ]; then
        echo -e "\033[0;33m[Warn] 檢測到 Swap 不足，正在創建 2GB 備用 Swap 文件...\033[0m"
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
}

# --- [模組] 安裝 v2bx 全能管理工具 (Pro) ---
install_shortcut() {
    cat > /usr/bin/v2bx <<EOF
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# 定義容器與目錄
C_SS="v2bx-ss";     D_SS="/etc/V2bX_SS"
C_V2="v2bx-v2ray";  D_V2="/etc/V2bX_V2RAY"
C_HY="v2bx-hy2";    D_HY="/etc/V2bX_HY2"
IMG="${IMAGE_NAME}"

# 檢查容器狀態
check_status() {
    if docker ps --format '{{.Names}}' | grep -q "^\$1$"; then
        echo -e "\${GREEN}運行中\${PLAIN}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^\$1$"; then
        echo -e "\${RED}已停止\${PLAIN}"
    else
        echo -e "\${YELLOW}未安裝\${PLAIN}"
    fi
}

# 容器操作
docker_op() {
    ACTION=\$1; NAME=\$2
    case "\$ACTION" in
        start)   docker start \$NAME && echo -e "\${GREEN}\$NAME 已啟動\${PLAIN}" ;;
        stop)    docker stop \$NAME && echo -e "\${GREEN}\$NAME 已停止\${PLAIN}" ;;
        restart) docker restart \$NAME && echo -e "\${GREEN}\$NAME 已重啟\${PLAIN}" ;;
        logs)    docker logs -f --tail 100 \$NAME ;;
    esac
}

# 更新容器
update_container() {
    NAME=\$1; DIR=\$2; ARGS=\$3
    if ! docker ps -a --format '{{.Names}}' | grep -q "^\$NAME$"; then
        echo -e "\${YELLOW}容器 \$NAME 不存在，跳過。\${PLAIN}"; return
    fi
    echo -e "\${GREEN}正在更新 \$NAME ...\${PLAIN}"
    docker pull \$IMG
    docker stop \$NAME >/dev/null 2>&1
    docker rm \$NAME >/dev/null 2>&1
    
    # 確保參數與安裝時一致 (含時區)
    docker run -d --name \$NAME --restart always --network host --cap-add=SYS_TIME \\
        --ulimit nofile=65535:65535 --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \\
        -e GOGC=50 \$ARGS -v \$DIR:/etc/V2bX -v /etc/localtime:/etc/localtime:ro \$IMG
    echo -e "\${GREEN}\$NAME 更新完成！\${PLAIN}"
}

# 卸載容器
uninstall_container() {
    NAME=\$1; DIR=\$2
    read -p "確定要刪除 \$NAME 及其配置嗎？(y/n): " confirm
    if [[ "\$confirm" == "y" ]]; then
        docker stop \$NAME >/dev/null 2>&1; docker rm \$NAME >/dev/null 2>&1
        rm -rf \$DIR
        echo -e "\${GREEN}\$NAME 已卸載。\${PLAIN}"
    fi
}

# 備份配置
backup_config() {
    BACKUP_FILE="/root/v2bx_backup_\$(date +%Y%m%d).tar.gz"
    echo -e "\${GREEN}正在打包所有設定檔...\${PLAIN}"
    DIRS=""
    [ -d "\$D_SS" ] && DIRS="\$DIRS \$D_SS"
    [ -d "\$D_V2" ] && DIRS="\$DIRS \$D_V2"
    [ -d "\$D_HY" ] && DIRS="\$DIRS \$D_HY"
    
    if [ -z "\$DIRS" ]; then
        echo -e "\${RED}未發現任何設定檔目錄。\${PLAIN}"
        return
    fi
    
    tar -czf \$BACKUP_FILE \$DIRS
    echo -e "\${GREEN}備份完成！檔案位置: \$BACKUP_FILE\${PLAIN}"
    echo -e "下載此檔案到本地即可保存所有節點設定。"
}

# 診斷
diagnose_system() {
    echo -e "\n\${YELLOW}--- 1. 系統時間檢查 ---\${PLAIN}"
    echo "本地時間: \$(date)"
    echo "注意：V2Ray/Hy2 要求時間誤差在 90秒內。"
    
    echo -e "\n\${YELLOW}--- 2. Docker 服務檢查 ---\${PLAIN}"
    systemctl status docker | grep Active
    
    echo -e "\n\${YELLOW}--- 3. 端口監聽檢查 ---\${PLAIN}"
    if command -v netstat >/dev/null; then
        netstat -tulnp | grep V2bX
    else
        echo "netstat 未安裝，跳過。"
    fi
    
    echo -e "\n\${YELLOW}--- 4. 磁碟空間 ---\${PLAIN}"
    df -h / | awk 'NR==2 {print "可用空間: " \$4}'
}

# 主菜單
clear
echo -e "\${GREEN}================================================\${PLAIN}"
echo -e "\${GREEN}        V2bX 融合怪管理面板 (Ultimate Pro)        \${PLAIN}"
echo -e "\${GREEN}================================================\${PLAIN}"
echo -e " 狀態: SS:\$(check_status \$C_SS) | V2Ray:\$(check_status \$C_V2) | Hy2:\$(check_status \$C_HY)"
echo -e "------------------------------------------------"
echo -e " \${SKYBLUE}[基礎管理]\${PLAIN}"
echo -e " 1. 查看日誌 (SS/V2/Hy2)"
echo -e " 2. 重啟服務 (SS/V2/Hy2)"
echo -e " 3. 停止服務 (SS/V2/Hy2)"
echo -e "------------------------------------------------"
echo -e " \${YELLOW}[高級維護]\${PLAIN}"
echo -e " 4. 更新鏡像 (Update All)"
echo -e " 5. 卸載刪除 (Uninstall)"
echo -e " 6. \${GREEN}備份設定檔 (Backup Config)\${PLAIN}"
echo -e " 7. \${GREEN}系統健康診斷 (Diagnose)\${PLAIN}"
echo -e " 8. 查看系統資源 (Free/ZRAM)"
echo -e " 0. 退出"
echo -e "\${GREEN}================================================\${PLAIN}"
read -p " 請輸入選項: " CHOICE

case "\$CHOICE" in
    1) 
        read -p "查看哪個? (1.SS 2.V2 3.Hy2): " O; 
        [ "\$O" == "1" ] && docker_op logs \$C_SS
        [ "\$O" == "2" ] && docker_op logs \$C_V2
        [ "\$O" == "3" ] && docker_op logs \$C_HY
        ;;
    2)
        read -p "重啟哪個? (1.SS 2.V2 3.Hy2): " O; 
        [ "\$O" == "1" ] && docker_op restart \$C_SS
        [ "\$O" == "2" ] && docker_op restart \$C_V2
        [ "\$O" == "3" ] && docker_op restart \$C_HY
        ;;
    3)
        read -p "停止哪個? (1.SS 2.V2 3.Hy2): " O; 
        [ "\$O" == "1" ] && docker_op stop \$C_SS
        [ "\$O" == "2" ] && docker_op stop \$C_V2
        [ "\$O" == "3" ] && docker_op stop \$C_HY
        ;;
    4)
        echo "開始更新..."
        update_container \$C_SS \$D_SS ""
        update_container \$C_V2 \$D_V2 ""
        update_container \$C_HY \$D_HY "--cap-add=NET_ADMIN"
        ;;
    5)
        read -p "卸載哪個? (1.SS 2.V2 3.Hy2): " O; 
        [ "\$O" == "1" ] && uninstall_container \$C_SS \$D_SS
        [ "\$O" == "2" ] && uninstall_container \$C_V2 \$D_V2
        [ "\$O" == "3" ] && uninstall_container \$C_HY \$D_HY
        ;;
    6) backup_config ;;
    7) diagnose_system ;;
    8) free -h; echo ""; zramctl 2>/dev/null ;;
    0) exit 0 ;;
    *) echo "無效輸入" ;;
esac
EOF
    chmod +x /usr/bin/v2bx
}

deploy_v2bx() {
    echo -e "\033[0;32m[Info] 開始部署 V2bX [${DISPLAY_NAME}] 版...\033[0m"
    
    # 1. 執行系統級優化
    configure_stability
    configure_zram
    check_disk_swap

    # 2. 環境檢查
    if ! command -v docker &> /dev/null; then
        echo -e "\033[0;33m[Warn] 未檢測到 Docker，正在自動安裝...\033[0m"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi

    # 3. BBR 優化
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

    # 4. 智能 ID 合併
    FINAL_NODE_IDS_LIST=""
    if [ -f "${HOST_CONFIG_DIR}/config.json" ]; then
        echo -e "\033[0;33m[Info] 檢測到舊配置，正在合併節點 ID...\033[0m"
        OLD_IDS=$(grep -oE '"NodeID":\s*[0-9]+' "${HOST_CONFIG_DIR}/config.json" | grep -oE '[0-9]+' | tr '\n' ',' | sed 's/,$//')
        if [ -n "$OLD_IDS" ]; then
            COMBINED_IDS=$(echo "${OLD_IDS},${NODE_IDS}" | tr ',' '\n' | sort -n | uniq | tr '\n' ',' | sed 's/,$//')
            FINAL_NODE_IDS_LIST="$COMBINED_IDS"
            echo -e "\033[0;32m[Info] 合併後的 ID: ${FINAL_NODE_IDS_LIST}\033[0m"
        else
            FINAL_NODE_IDS_LIST="$NODE_IDS"
        fi
    else
        FINAL_NODE_IDS_LIST="$NODE_IDS"
    fi

    # 5. 生成 Config
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
      "Type": "sing",
      "Name": "sing1",
      "Log": { "Level": "error", "Timestamp": true },
      "NTP": { "Enable": true, "Server": "pool.ntp.org", "ServerPort": 123 },
      "OriginalPath": "/etc/V2bX/sing_origin.json"
    }
  ],
  "Nodes": [ ${NODES_JSON} ]
}
EOF

    # 6. 容器部署
    echo -e "\033[0;32m[Info] 正在拉取鏡像: ${IMAGE_NAME} ...\033[0m"
    if ! docker pull $IMAGE_NAME; then
        echo -e "\033[0;31m[Error] 鏡像拉取失敗，請檢查網絡。\033[0m"
        exit 1
    fi
    
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    # 增加 -v /etc/localtime:/etc/localtime:ro 確保日誌時間正確
    docker run -d \
        --name $CONTAINER_NAME \
        --restart always \
        --network host \
        --cap-add=SYS_TIME \
        --ulimit nofile=65535:65535 \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        -e GOGC=50 \
        $EXTRA_DOCKER_ARGS \
        -v ${HOST_CONFIG_DIR}:/etc/V2bX \
        -v /etc/localtime:/etc/localtime:ro \
        $IMAGE_NAME
        
    # 7. 安裝完成
    install_shortcut
    echo -e "\033[0;32m[Success] V2bX [${DISPLAY_NAME}] 部署指令已下達！\033[0m"
    echo "------------------------------------------------"
    echo "容器名稱: ${CONTAINER_NAME}"
    echo -e "目前生效的 Node ID: \033[0;36m${FINAL_NODE_IDS_LIST}\033[0m"
    echo -e "快捷指令: \033[0;33mv2bx\033[0m (直接在終端機輸入即可)"
    echo "------------------------------------------------"
    echo -e "\033[0;33m[Check] 正在獲取最後 10 行運行日誌...\033[0m"
    sleep 3
    docker logs --tail 10 ${CONTAINER_NAME}
    echo "------------------------------------------------"
    echo -e "\033[0;32m如果上方日誌無 Error，則代表運行正常。\033[0m"
}

deploy_v2bx
