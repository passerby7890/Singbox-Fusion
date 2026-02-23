# V2bX 全能部署腳本 (Multi-Site Isolation Mode)

> 一鍵完成 V2bX 節點的 Docker 自動化部署，支援**多站點隔離共存**、系統級網路優化與智能管理。
> 鏡像源：`tinyserve/v2bx:latest`

---

## ✨ 核心特性

### 🛡️ 多實例隔離 (Multi-Instance)

透過 `SITE_TAG` 變數實現同一台伺服器上運行多個不同面板、不同協議的節點，**容器、配置目錄、管理指令**完全隔離，互不干擾。

### 🚀 系統自動優化

- **BBR + FQ** 擁塞控制自動啟用
- **GSO / GRO / TSO** 網卡卸載自動開啟
- 核心參數（`tcp_notsent_lowat`）自動校準

### 💾 智能記憶體管理

- **Smart Swap**：自動偵測，無 Swap 時自動建立 2GB Swap（防重複建立）
- **記憶體參數調優**：`swappiness=10` + `vfs_cache_pressure=50`，小記憶體 VPS 也能穩定高併發

### 🔧 容錯與自癒

- Docker 未安裝時自動呼叫官方腳本安裝
- 容器設定 `--restart always` 自動守護
- **Log Rotation**：日誌限制 `10MB × 3` 份，防止撐爆硬碟
- `ulimit nofile=65535` 防高併發檔案描述符耗盡

### 🔍 快捷管理

安裝完成後自動生成專屬管理指令 `v2bx-{SITE_TAG}`，支援日誌、重啟、停止、更新、卸載等操作。

---

## 📥 安裝與使用

### 第一步：下載腳本

```bash
wget -N https://raw.githubusercontent.com/passerby7890/Singbox-Fusion/main/install.sh
chmod +x install.sh
```

### 第二步：配置並安裝

> [!IMPORTANT]
> 安裝前請先 `export` 以下必要變數，腳本會自動檢查。

---

#### 場景 1️⃣：安裝 Shadowsocks 節點 (Site A)

```bash
# 1. 定義變數
export SITE_TAG="siteA"           # [關鍵] 實例標籤，用於隔離容器
export API_HOST="https://a.com"   # 面板地址
export API_KEY="通訊密鑰A"        # 面板 Key
export NODE_IDS="1,2"             # 節點 ID（多個用逗號分隔）
export INSTALL_TYPE="ss"          # 安裝類型

# 2. 運行腳本
bash install.sh
```

#### 場景 2️⃣：安裝 V2Ray (VMess/VLESS) 節點 (Site B)

```bash
export SITE_TAG="siteB"
export API_HOST="https://b.com"
export API_KEY="通訊密鑰B"
export NODE_IDS="3,4"
export INSTALL_TYPE="v2ray"
export V2RAY_PROTOCOL="vmess"     # (可選) vmess 或 vless，預設 vmess

bash install.sh
```

#### 場景 3️⃣：安裝 Hysteria2 節點 (Site C)

```bash
export SITE_TAG="siteC"
export API_HOST="https://c.com"
export API_KEY="通訊密鑰C"
export NODE_IDS="5"
export INSTALL_TYPE="hy2"         # 自動加入 --cap-add=NET_ADMIN

bash install.sh
```

---

## 📋 環境變數說明

| 變數名稱 | 必填 | 說明 | 示例值 |
|---|---|---|---|
| `SITE_TAG` | ✅ | 實例標籤（多開核心），只允許字母/數字/底線 | `siteA`, `hk_node` |
| `API_HOST` | ✅ | 面板網址 | `https://v2board.com` |
| `API_KEY` | ✅ | 通訊密鑰 | `mysecretkey` |
| `NODE_IDS` | ✅ | 節點 ID，多個用逗號分隔 | `1` 或 `1,2,3` |
| `INSTALL_TYPE` | ✅ | 安裝類型 | `ss`, `v2ray`, `hy2` |
| `V2RAY_PROTOCOL` | ❌ | V2Ray 協議（僅 `INSTALL_TYPE=v2ray` 時有效） | `vmess`（預設）, `vless` |
| `IMAGE_NAME` | ❌ | 自訂 Docker 鏡像 | `tinyserve/v2bx:latest`（預設） |

---

## 🛠️ 管理與維護

### ⚡ 快捷管理指令

安裝完成後，系統會自動生成快捷指令，格式為 **`v2bx-{SITE_TAG}`**。

假設你的 `SITE_TAG` 為 `siteA`，直接執行：

```bash
v2bx-siteA
```

即可進入互動式管理面板：

```
================================================
   V2bX 管理面板 - 站點: siteA
================================================
 容器名稱: v2bx-ss-siteA
 配置目錄: /etc/V2bX_ss-siteA
------------------------------------------------
 1. 查看日誌 (Logs)
 2. 重啟服務 (Restart)
 3. 停止服務 (Stop)
 4. 更新鏡像 (Update)
 5. 卸載此節點 (Uninstall)
 0. 退出
------------------------------------------------
```

| 選項 | 動作 | 說明 |
|---|---|---|
| 1 | 查看日誌 | 即時查看最近 100 行日誌（`Ctrl+C` 退出） |
| 2 | 重啟服務 | 重啟該實例的 Docker 容器 |
| 3 | 停止服務 | 停止該實例 |
| 4 | 更新鏡像 | 拉取最新鏡像並重新建立容器 |
| 5 | 卸載節點 | 刪除容器、配置與快捷指令（需二次確認） |

---

## 🏗️ 部署架構

```
伺服器
├── /etc/V2bX_ss-siteA/          ← Site A 配置（Shadowsocks）
│   ├── config.json
│   └── sing_origin.json
├── /etc/V2bX_v2ray-siteB/       ← Site B 配置（V2Ray）
│   ├── config.json
│   └── sing_origin.json
├── /etc/V2bX_hy2-siteC/         ← Site C 配置（Hysteria2）
│   ├── config.json
│   └── sing_origin.json
├── /usr/bin/v2bx-siteA          ← Site A 管理指令
├── /usr/bin/v2bx-siteB          ← Site B 管理指令
└── /usr/bin/v2bx-siteC          ← Site C 管理指令
```

每個實例的 Docker 容器以 `v2bx-{type}-{tag}` 命名（例如 `v2bx-ss-siteA`），配置目錄以 `/etc/V2bX_{type}-{tag}` 隔離，實現完全獨立運行。

---

## ⚠️ 常見問題 (FAQ)

**Q: 腳本會自動安裝 Docker 嗎？**

A: 是的。若偵測到系統未安裝 Docker，腳本會自動呼叫官方安裝腳本（`get.docker.com`）並啟用服務。

**Q: 支援哪些作業系統？**

A: 支援基於 `apt`（Debian/Ubuntu）和 `yum`（CentOS/RHEL）的 Linux 發行版。

**Q: 如何在同一台機器上部署多個節點？**

A: 只需為每次安裝設定不同的 `SITE_TAG` 即可。容器名稱、配置路徑、管理指令皆會自動隔離。

**Q: 日誌太大會不會撐爆硬碟？**

A: 不會。容器已配置 Log Rotation（`max-size=10m`、`max-file=3`），日誌自動輪轉，最大佔用約 30MB。

**Q: Hysteria2 需要特殊權限嗎？**

A: 腳本已自動處理。當 `INSTALL_TYPE=hy2` 時，會自動加入 `--cap-add=NET_ADMIN` 權限。

---

## 📄 授權

MIT License
