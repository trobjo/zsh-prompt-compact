# Simple Zsh prompt with Git status.

[ $SSH_TTY ] && _ssh="%B%m%b " m="%m:"

function xterm_title_preexec () {
    print -Pn -- "\e]2;$m %(5~|…/%3~|%~) – "${(q)1}"\a"
}

# Sets GITSTATUS_PROMPT to reflect the state of the current git repository. Empty if not
# in a git repository. In addition, sets GITSTATUS_PROMPT_LEN to the number of columns
# $GITSTATUS_PROMPT will occupy when printed.
#

function gitstatus_prompt_update() {
    emulate -L zsh
    typeset -g  GITSTATUS_PROMPT=''
    typeset -gi GITSTATUS_PROMPT_LEN=0

    # Call gitstatus_query synchronously. Note that gitstatus_query can also be called
    # asynchronously; see documentation in gitstatus.plugin.zsh.
    gitstatus_query 'MY'                  || return 1  # error
    [[ $VCS_STATUS_RESULT == 'ok-sync' ]] || return 0  # not a git repo

    local      clean='%242F'   # green foreground
    local   modified='%3F'  # yellow foreground
    local  untracked='%12F'   # blue foreground
    local conflicted='%2F'  # red foreground

    local p

    local where  # branch name, tag or commit
    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
        where=$VCS_STATUS_LOCAL_BRANCH
    elif [[ -n $VCS_STATUS_TAG ]]; then
        p+='%f#'
        where=$VCS_STATUS_TAG
    else
        p+='%f@'
        where=${VCS_STATUS_COMMIT[1,8]}
    fi

    (( $#where > 32 )) && where[13,-13]="…"  # truncate long branch names and tags
    p+="${clean}${where//\%/%%}"             # escape %

    # ⇣42 if behind the remote.
    (( VCS_STATUS_COMMITS_BEHIND )) && p+=" ${clean}⇣${VCS_STATUS_COMMITS_BEHIND}"
    # ⇡42 if ahead of the remote; no leading space if also behind the remote: ⇣42⇡42.
    (( VCS_STATUS_COMMITS_AHEAD && !VCS_STATUS_COMMITS_BEHIND )) && p+=" "
    (( VCS_STATUS_COMMITS_AHEAD  )) && p+="${clean}⇡${VCS_STATUS_COMMITS_AHEAD}"
    # ⇠42 if behind the push remote.
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" ${clean}⇠${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD && !VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" "
    # ⇢42 if ahead of the push remote; no leading space if also behind: ⇠42⇢42.
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && p+="${clean}⇢${VCS_STATUS_PUSH_COMMITS_AHEAD}"
    # *42 if have stashes.
    (( VCS_STATUS_STASHES        )) && p+=" ${clean}*${VCS_STATUS_STASHES}"
    # 'merge' if the repo is in an unusual state.
    [[ -n $VCS_STATUS_ACTION     ]] && p+=" ${conflicted}${VCS_STATUS_ACTION}"
    # ~42 if have merge conflicts.
    (( VCS_STATUS_NUM_CONFLICTED )) && p+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
    # +42 if have staged changes.
    (( VCS_STATUS_NUM_STAGED     )) && p+=" ${modified}+${VCS_STATUS_NUM_STAGED}"
    # !42 if have unstaged changes.
    (( VCS_STATUS_NUM_UNSTAGED   )) && p+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
    # ?42 if have untracked files. It's really a question mark, your font isn't broken.
    (( VCS_STATUS_NUM_UNTRACKED  )) && p+=" ${untracked}?${VCS_STATUS_NUM_UNTRACKED}"

    GITSTATUS_PROMPT="${p}%f"

    # The length of GITSTATUS_PROMPT after removing %f and %F.
    GITSTATUS_PROMPT_LEN="${(m)#${${GITSTATUS_PROMPT//\%\%/x}//\%(f|<->F)}}"
}

typeset -g __last_check=$(($(date +%s)))
typeset -g __current_git_dir=$HOME

preprompt() {
    print -Pn -- "\x1b[?25l\r\x1B[2K"            # hide the cursor while we update
    print -Pn -- '%B${_ssh}%b\e]2;$m %(8~|…/%6~|%~)\a' # sets ssh and pwd in terminal title

    gitstatus_prompt_update
    print -Pn -- '%{\e[3m%}%4F%$((-GITSTATUS_PROMPT_LEN-1))<…<%~%<<%f%{\e[0m%}'  # blue current working directory

    if [[ ${GITSTATUS_PROMPT} ]]; then
        print -nP -- '\033[6n' > /dev/tty          # ask the terminal for the position
        read -s -d\[ nonce > /dev/null 2>&1         # discard the first part of the response
        read -s -d R] position < /dev/tty 2> /dev/null          # store the position in bash variable 'foo'

        print -P -- ' ${GITSTATUS_PROMPT}\x1b[?25h'      # git status and show cursor
        (fetch "$__current_git_dir" &)
        __current_git_dir="${VCS_STATUS_WORKDIR}"
        __last_check=$(($(date +%s)))
    else
        print -P "\x1b[?25h"            # show the cursor again and add final newline
    fi
}

fetch() {
    gitstatus_query 'MY'                  || return 1  # error
    [[ $VCS_STATUS_RESULT == 'ok-sync' ]] || return 0  # not a git repo

    while pgrep -f "/usr/bin/git -C ${VCS_STATUS_WORKDIR} fetch" > /dev/null 2>&1; do
        sleep 0.2
    done
    gitstatus_prompt_update
    print -Pn -- '\x1B[s\x1B[${position}H\x1B[0K ${GITSTATUS_PROMPT}\x1B[u'

    if [[ "${VCS_STATUS_WORKDIR}" != "$1" ]] || [[ $(($(date +%s)-${__last_check})) -gt 60 ]]; then
        /usr/bin/git -C "${VCS_STATUS_WORKDIR}" fetch > /dev/null 2>&1 &&\
        gitstatus_prompt_update &&\
        print -Pn -- '\x1B[s\x1B[${position}H\x1B[0K ${GITSTATUS_PROMPT}\x1B[u'
    fi
    # save cursor, move one line up, go to position, write gitstatus, restore cursore
}

# sets prompt. PROMPT has issues with multiline prompts, see
# https://superuser.com/questions/382503/how-can-i-put-a-newline-in-my-zsh-prompt-without-causing-terminal-redraw-issues

# Start gitstatusd instance with name "MY". The same name is passed to
# gitstatus_query in gitstatus_prompt_update. The flags with -1 as values
# enable staged, unstaged, conflicted and untracked counters.
gitstatus_stop 'MY' && gitstatus_start -s -1 -u -1 -c -1 -d -1 'MY'

# On every prompt, fetch git status and set GITSTATUS_PROMPT.
autoload -Uz add-zsh-hook
add-zsh-hook preexec xterm_title_preexec
# add-zsh-hook precmd gitstatus_prompt_update
add-zsh-hook precmd preprompt

# Enable/disable the right prompt options.
setopt no_prompt_bang prompt_percent prompt_subst

# Customize prompt. Put $GITSTATUS_PROMPT in it to reflect git status.
#
# Example:
#
#   user@host ~/projects/skynet master ⇡42
#   % █
#
# The current directory gets truncated from the left if the whole prompt doesn't fit on the line.
PROMPT='%F{%(?.5.1)}%Bλ%b%f '                         # %/# (normal/root); green/red (ok/error)
