# User specific aliases and functions

if [ -n "$SSH_CLIENT" ]; then text=" ssh"

fi

export PS1='\[\e[0;31m\]\u@\h:\w${text}$\[\e[m\] '



if [ -f /etc/bashrc ]; then

        . /etc/bashrc

fi



if [ -f ~/.bash_aliases ]; then

. ~/.bash_aliases

fi