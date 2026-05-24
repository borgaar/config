autoload -Uz compinit && compinit

setopt INTERACTIVE_COMMENTS

export SSH_AUTH_SOCK=/run/user/1000/gnupg/S.gpg-agent.ssh
export TERM="xterm-256color"
export BROWSER=firefox

eval "$(starship init zsh)"

. "/home/borgar/.acme.sh/acme.sh.env"

. $HOME/.zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
. $HOME/.zsh_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
. $HOME/.zsh_plugins/zsh-vi-mode/zsh-vi-mode.zsh

. $HOME/.elan/env

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

alias vencord="sh -c \"\$(curl -sS https://vencord.dev/install.sh)\""
