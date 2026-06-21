# Hamster Script 初始化（由 /etc/profile.d/hamster-init.sh 加载）
# 条件：SSH 登录 + 未在 tmux + 交互 shell + hamster-tmux 已安装
# 关闭：export HAMSTER_NO_TMUX=1  或删除 /etc/profile.d/hamster-init.sh

if [ -z "${HAMSTER_NO_TMUX:-}" ] && \
   [ -n "${SSH_CONNECTION:-}" ] && [ -z "${TMUX:-}" ] && \
   [ -n "${PS1:-}" ] && command -v hamster-tmux >/dev/null 2>&1; then
    hamster-tmux
fi
