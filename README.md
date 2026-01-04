V2bX 全能部署脚本 (Google SRE Standard)
这是一个基于 Google SRE 运维标准 编写的高级 V2bX 节点部署脚本。不仅支持 Docker 自动化部署，还深度集成了系统级优化、多实例隔离、资源保护及容错机制。

✨ 核心特性
🛡️ 多实例隔离 (Multi-Instance)
通过 SITE_TAG 完美支持在同一台服务器上运行多个不同面板、不同协议的节点，互不干扰。

🚀 系统自动优化
自动配置 BBR + FQ 拥塞控制，并强制校准内核参数。

💾 智能内存管理
Smart Swap：自动检测并创建 Swap 分区（具备防重复创建逻辑）。
ZRAM 压缩：自动配置内存压缩技术，显著提升小内存 VPS 的高并发性能。

🔧 容错与自愈
自动检测并修复 dpkg/apt 锁死问题。
Docker 进程守护与日志自动轮转 (Log Rotation)，防止日志撑爆硬盘。
启动后自动检测端口冲突并发出警告。

🔍 快捷管理
内置实例查询功能与自动生成系统快捷管理指令。

📥 安装与使用
第一步：下载脚本
建议先将脚本下载到服务器本地，方便后续管理：

bash

wget -N https://raw.githubusercontent.com/nick0425-ops/Singbox-Fusion/main/install.sh
chmod +x install.sh

第二步：配置并安装 (多场景示例)

场景 1️⃣：安装 Shadowsocks 节点 (Site A)

适用于第一个网站或第一组节点：

bash
# 1. 定义变量
export SITE_TAG="siteA"           # [关键] 实例标签，用于隔离容器

export API_HOST="https://a.com"   # 面板地址

export API_KEY="通信密钥A"         # 面板 Key

export NODE_IDS="1,2"             # 节点 ID

export INSTALL_TYPE="ss"          # 设置类型为 ss

# 2. 运行脚本
bash install.sh

场景 2️⃣：安装 V2Ray (VMess/VLESS) 节点 (Site B)

适用于第二个网站，与 Site A 完美共存：

bash
# 1. 定义变量 (注意更换 SITE_TAG)
export SITE_TAG="siteB"       

export API_HOST="https://b.com"

export API_KEY="通信密钥B"

export NODE_IDS="3,4"

export INSTALL_TYPE="v2ray"      # 设置类型为 v2ray

export V2RAY_PROTOCOL="vmess"    # (可选) vmess 或 vless，默认 vmess

# 2. 运行脚本
bash install.sh

场景 3️⃣：安装 Hysteria2 节点 (Site C)
bash
# 1. 定义变量
export SITE_TAG="siteC"

export API_HOST="https://c.com"

export API_KEY="通信密钥C"

export NODE_IDS="5"

export INSTALL_TYPE="hy2"        # 设置类型为 hy2

# 2. 运行脚本
bash install.sh

📋 环境变量说明
变量名称	必填	说明	示例值
SITE_TAG	✅	实例标签 (多开核心)。用于隔离容器和配置，只允许字母/数字/下划线。	siteA, hk_node

API_HOST	✅	面板网址	https://v2board.com

API_KEY	✅	通信密钥	mysecretkey

NODE_IDS	✅	节点 ID (多个 ID 请用逗号分隔)	1 或 1,2,3

INSTALL_TYPE	✅	安装类型	ss, v2ray, hy2

V2RAY_PROTOCOL	❌	V2Ray 协议 (仅在 type=v2ray 时有效)	vmess (默认), vless

🛠️ 管理与维护

🔍 查询已安装实例 (List Mode)

想知道服务器上装了哪些节点？运行以下指令自动扫描所有由本脚本生成的实例：


bash
bash install.sh list
输出示例：

text
SITE_TAG    容器名称               运行状态    管理指令

siteA       v2bx-ss-siteA         running    v2bx_siteA

siteB       v2bx-v2ray-siteB      running    v2bx_siteB

⚡ 快捷管理指令

安装完成后，系统会自动生成快捷指令，格式为 v2bx_{SITE_TAG}。

假设你的 SITE_TAG 为 siteA：


动作	指令	说明
查看日志	v2bx_siteA logs	查看实时运行日志 (Ctrl+C 退出)

重启服务	v2bx_siteA restart	重启该实例的 Docker 容器

停止服务	v2bx_siteA stop	停止该实例

强制更新	v2bx_siteA update	拉取最新镜像并重建容器

⚠️ 常见问题 (FAQ)

Q: 启动后提示 "[严重警告] 启动失败：检测到端口冲突！" 怎么办？

A: 这意味着你面板上给节点分配的端口已经被本机其他程序（如 Nginx 或其他 V2bX 实例）占用了。请去面板修改节点端口，然后运行 v2bx_{TAG} restart 重启。


Q: 脚本会自动安装 Docker 吗？

A: 是的。如果检测到未安装 Docker，脚本会自动调用官方脚本安装，并尝试修复可能存在的 apt/dpkg 锁死问题。
