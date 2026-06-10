#!/bin/bash
# XRK-AGT 安装脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"

REPO_URL="https://github.com/sunflowermm/XRK-AGT"
INSTALL_DIR="${INSTALL_DIR:-/root/cs/XRK-AGT}"

echo "=== XRK-AGT 安装 ==="
echo ""

# 检查是否已安装
if [[ -d "$INSTALL_DIR" ]]; then
    echo "错误: XRK-AGT 已存在于 $INSTALL_DIR"
    echo "如需重装请先卸载"
    exit 1
fi

# 检查并安装 git
for cmd in git; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "正在安装 $cmd..."
        if command -v apt &>/dev/null; then
            apt install -y "$cmd" 2>&1 || { echo "错误: 安装 $cmd 失败"; exit 1; }
        elif command -v yum &>/dev/null; then
            yum install -y "$cmd" 2>&1 || { echo "错误: 安装 $cmd 失败"; exit 1; }
        else
            echo "错误: 请先手动安装 $cmd"
            exit 1
        fi
    fi
done

# 检查 Node.js（优先使用 nvm，其次 NodeSource）
install_node() {
    if command -v node &>/dev/null; then
        local major
        major=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
        if [[ "$major" -ge 18 ]] 2>/dev/null; then
            echo "Node.js $(node -v) 已安装"
            return 0
        else
            echo "Node.js 版本过低 (当前: $(node -v), 需要 >= 18)"
        fi
    fi

    # 尝试 nvm
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        source "$HOME/.nvm/nvm.sh"
        nvm install 20
        return $?
    fi

    # 尝试 NodeSource
    if command -v curl &>/dev/null; then
        echo "正在通过 NodeSource 安装 Node.js 20..."
        if command -v apt &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 && \
            apt install -y nodejs 2>&1 || { echo "错误: NodeSource 安装失败"; return 1; }
        elif command -v yum &>/dev/null; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - 2>&1 && \
            yum install -y nodejs 2>&1 || { echo "错误: NodeSource 安装失败"; return 1; }
        else
            echo "错误: 不支持的包管理器，请手动安装 Node.js >= 18"
            return 1
        fi
    else
        # 兜底：apt/yum 安装 nodejs
        echo "正在尝试安装 nodejs..."
        if command -v apt &>/dev/null; then
            apt install -y nodejs npm 2>&1 || { echo "错误: 安装 nodejs 失败"; return 1; }
        elif command -v yum &>/dev/null; then
            yum install -y nodejs npm 2>&1 || { echo "错误: 安装 nodejs 失败"; return 1; }
        fi
    fi
}

echo "正在检查 Node.js..."
install_node || { echo "错误: Node.js 安装失败，请手动安装 Node.js >= 18"; exit 1; }
echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"

# 安装 pnpm（如未安装）
if ! command -v pnpm &>/dev/null; then
    echo "正在安装 pnpm..."
    npm install -g pnpm
fi

# 创建目录
mkdir -p "$(dirname "$INSTALL_DIR")"

# 克隆仓库
echo "正在克隆 XRK-AGT 仓库..."
if ! git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
    echo "错误: 克隆仓库失败"
    exit 1
fi

# 安装依赖
echo "正在安装依赖..."
cd "$INSTALL_DIR"

install_deps() {
    if [[ -f "pnpm-lock.yaml" || -f "package.json" ]]; then
        pnpm i
    elif [[ -f "yarn.lock" ]]; then
        yarn install
    else
        npm install
    fi
    return $?
}

if ! install_deps; then
    echo ""
    echo "警告: 依赖安装失败"
    read -p "是否尝试重新安装依赖？(y/N): " reinstall
    if [[ "$reinstall" =~ ^[Yy] ]]; then
        echo "正在重新安装依赖..."
        rm -rf node_modules pnpm-lock.yaml package-lock.json 2>/dev/null
        pnpm i
        if [[ $? -ne 0 ]]; then
            echo "错误: 重新安装依赖仍然失败，请检查网络或手动安装"
            exit 1
        fi
    else
        echo "错误: 依赖安装失败，XRK-AGT 无法正常运行"
        exit 1
    fi
fi

echo ""
echo "依赖安装成功！"

# ─── 安装 Redis ───────────────────────────────────────────

install_redis() {
    if command -v redis-server &>/dev/null; then
        echo "Redis 已安装: $(redis-server --version)"
        return 0
    fi

    echo "正在安装 Redis..."
    if command -v apt &>/dev/null; then
        apt install -y redis-server 2>&1 || { echo "错误: Redis 安装失败"; return 1; }
    elif command -v yum &>/dev/null; then
        yum install -y redis 2>&1 || { echo "错误: Redis 安装失败"; return 1; }
    else
        echo "错误: 不支持的包管理器，请手动安装 Redis"
        return 1
    fi

    # 尝试启动
    if command -v systemctl &>/dev/null; then
        systemctl enable redis-server 2>/dev/null || systemctl enable redis 2>/dev/null
        systemctl start redis-server 2>/dev/null || systemctl start redis 2>/dev/null || true
    elif command -v redis-server &>/dev/null; then
        nohup redis-server --daemonize yes > /dev/null 2>&1 &
    fi
    sleep 1
    echo "Redis 安装完成"
}

# ─── 安装 MongoDB ────────────────────────────────────────

install_mongodb() {
    if command -v mongod &>/dev/null; then
        echo "MongoDB 已安装: $(mongod --version | head -1)"
        return 0
    fi

    echo "正在安装 MongoDB..."
    if command -v apt &>/dev/null; then
        # Ubuntu/Debian: 通过官方源安装
        if command -v curl &>/dev/null; then
            curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg 2>/dev/null || true
            echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs 2>/dev/null || echo jammy)/mongodb-org/7.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-7.0.list 2>/dev/null || true
            apt update 2>&1 | tail -1
        fi
        apt install -y mongodb-org 2>&1 || {
            # 官方源失败则尝试默认源的 mongodb
            echo "官方源不可用，尝试默认源..."
            apt install -y mongodb 2>&1 || { echo "错误: MongoDB 安装失败"; return 1; }
        }
    elif command -v yum &>/dev/null; then
        # RHEL/CentOS: 创建 yum 源
        cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<'YUMEOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/7.0/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
YUMEOF
        yum install -y mongodb-org 2>&1 || { echo "错误: MongoDB 安装失败"; return 1; }
    else
        echo "错误: 不支持的包管理器，请手动安装 MongoDB"
        return 1
    fi

    # 尝试启动
    if command -v systemctl &>/dev/null; then
        systemctl enable mongod 2>/dev/null
        systemctl start mongod 2>/dev/null || true
    elif command -v mongod &>/dev/null; then
        mkdir -p /tmp/mongodb /tmp/mongolog 2>/dev/null
        nohup mongod --dbpath /tmp/mongodb --logpath /tmp/mongolog/mongod.log --fork > /dev/null 2>&1 || true
    fi
    sleep 1
    echo "MongoDB 安装完成"
}

# 安装 Redis 和 MongoDB
echo ""
echo "=== 安装 XRK-AGT 依赖服务 ==="
install_redis || echo "警告: Redis 安装失败，XRK-AGT 可能无法正常运行，请手动安装"
install_mongodb || echo "警告: MongoDB 安装失败，XRK-AGT 可能无法正常运行，请手动安装"
echo ""

echo ""
echo "✅ XRK-AGT 安装成功！"
echo "安装目录: $INSTALL_DIR"
echo ""

read -p "是否现在启动 XRK-AGT？(y/N): " start_now
if [[ "$start_now" =~ ^[Yy] ]]; then
    cd "$INSTALL_DIR"
    nohup node app.js > /dev/null 2>&1 &
    sleep 2
    if kill -0 $! 2>/dev/null; then
        echo "XRK-AGT 已启动"
    else
        echo "错误: XRK-AGT 启动失败，请检查 Redis 和 MongoDB 是否正常运行"
    fi
fi
echo "使用 cs 项目管理菜单启动 XRK-AGT"