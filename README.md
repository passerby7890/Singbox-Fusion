V2bX Sing-box Unified Install Script (SS / V2Ray / Hy2)

本腳本將 Shadowsocks, V2Ray, Hysteria2 三種協議的安裝邏輯融合為一。
透過設定環境變數 INSTALL_TYPE，您可以輕鬆決定要安裝哪種節點。三種協議使用獨立的容器與配置目錄，支援在同一台伺服器上完美共存。

✨ 功能特點

🧬 三合一腳本：一個腳本搞定 SS、V2Ray、Hy2。

🛡️ 完美隔離：各自擁有獨立的 Docker 容器名稱與 /etc 配置目錄，互不衝突。

🚀 核心鎖定：全系列強制使用 Sing-box 內核，效能最優。

⚡ 自動優化：自動開啟 BBR + FQ、TFO，Hy2 自動開啟 NET_ADMIN 權限。

📦 快速安裝

請依照您的需求設定變數，複製貼上執行即可。您可以多次執行此腳本（每次修改不同變數）來同時安裝多種協議。

1️⃣ 安裝 Shadowsocks

export API_HOST="[https://面板地址.com](https://面板地址.com)"

export API_KEY="通信密鑰"

export NODE_IDS="1,2"

export INSTALL_TYPE="ss"   # 設定為 ss

bash <(curl -Ls [https://raw.githubusercontent.com/nick0425-ops/Singbox-Fusion/refs/heads/main/install.sh](https://raw.githubusercontent.com/nick0425-ops/Singbox-Fusion/refs/heads/main/install.sh))


2️⃣ 安裝 V2Ray (VMess/VLESS)

export API_HOST="[https://面板地址.com](https://面板地址.com)"

export API_KEY="通信密鑰"

export NODE_IDS="3,4"

export INSTALL_TYPE="v2ray"  # 設定為 v2ray

export V2RAY_PROTOCOL="vmess" # (可選) vmess 或 vless，預設 vmess

bash <(curl -Ls [https://raw.githubusercontent.com/nick0425-ops/Singbox-Fusion/refs/heads/main/install.sh](https://raw.githubusercontent.com/nick0425-ops/Singbox-Fusion/refs/heads/main/install.sh))


3️⃣ 安裝 Hysteria2

export API_HOST="[https://面板地址.com](https://面板地址.com)"

export API_KEY="通信密鑰"

export NODE_IDS="5"

export INSTALL_TYPE="hy2"    # 設定為 hy2

bash <(curl -Ls [https://raw.githubusercontent.com/nick0425-ops/Singbox-Fusion/refs/heads/main/install.sh](https://raw.githubusercontent.com/nick0425-ops/Singbox-Fusion/refs/heads/main/install.sh))


📋 變數說明

變數名稱

必填

說明

可選值

API_HOST

✅

面板網址

https://v2board.com

API_KEY

✅

通信密鑰

mysecretkey

NODE_IDS

✅

節點 ID

1 或 1,2,3

INSTALL_TYPE

✅

安裝類型

ss, v2ray, hy2

V2RAY_PROTOCOL

❌

V2Ray 協議 (僅在 type=v2ray 時有效)

vmess (預設), vless

🛠️ 管理指令

由於容器名稱不同，請根據您安裝的類型使用對應指令：

類型

容器名稱

配置目錄

Shadowsocks

v2bx-ss

/etc/V2bX_SS

V2Ray

v2bx-v2ray

/etc/V2bX_V2RAY

Hysteria2

v2bx-hy2

/etc/V2bX_HY2

範例：查看 SS 的日誌

docker logs -f --tail 100 v2bx-ss


範例：重啟 Hy2

docker restart v2bx-hy2


範例：卸載 V2Ray

docker stop v2bx-v2ray && docker rm v2bx-v2ray

rm -rf /etc/V2bX_V2RAY
