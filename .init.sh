# Hamster Script 初始化（SSH 登录时自动加载）
# 由 setup.sh 写入 ~/.bashrc: [[ -f /cs/.init.sh ]] && source /cs/.init.sh

if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ] && [ -n "$PS1" ] && command -v hamster-tmux >/dev/null 2>&1; then
    hamster-tmux
fi
