[ $SSH_TTY ] && _ssh="%B[%b%m%B]%b " m="%m: "

function xterm_title_preexec () {
    typeset -g cmd_exec_timestamp=$EPOCHSECONDS
    print -Pn -- "\e]2;$m%(5~|…/%3~|%~) – "${(q)1}"\a"
    if [ ! -z ${VCS_STATUS_WORKDIR} ]; then
        if [[ $__git_fetch_pwds[${VCS_STATUS_WORKDIR}] ]] && [[ $2 =~ git\ (.*\ )?(pull|push|fetch)(\ .*)?$ ]]; then
            kill $__git_fetch_pwds[${VCS_STATUS_WORKDIR}] > /dev/null 2>&1
            unset __git_fetch_pwds[${VCS_STATUS_WORKDIR}]
        fi
        [[ ! -z $pending_git_status_pid ]] && kill $pending_git_status_pid > /dev/null 2>&1 && unset pending_git_status_pid
    fi
}

# Sets GITSTATUS_PROMPT to reflect the state of the current git repository. Empty if not
# in a git repository. In addition, sets GITSTATUS_PROMPT_LEN to the number of columns
# $GITSTATUS_PROMPT will occupy when printed.
#

function gitstatus_prompt_update_branch_only() {
    emulate -L zsh
    typeset -g  GIT_BRANCH=''
    # typeset -gi GITSTATUS_PROMPT_LEN=0

    gitstatus_query -p 'MY'                  || return 1  # error
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

    GIT_BRANCH=" ${p}%f"

    # The length of GIT_BRANCH after removing %f and %F.
    # GITSTATUS_PROMPT_LEN="${(m)#${${GIT_BRANCH//\%\%/x}//\%(f|<->F)}}"
}

function gitstatus_prompt_update_changes_only() {
    emulate -L zsh
    typeset -g  GIT_CHANGES=''
    # typeset -gi GITSTATUS_PROMPT_LEN=0

    # Call gitstatus_query synchronously. Note that gitstatus_query can also be called
    # asynchronously; see documentation in gitstatus.plugin.zsh.
    gitstatus_query 'MY'                  || return 1  # error
    [[ $VCS_STATUS_RESULT == 'ok-sync' ]] || return 0  # not a git repo

    local      clean='%242F'   # green foreground
    local   modified='%3F'  # yellow foreground
    local  untracked='%12F'   # blue foreground
    local conflicted='%2F'  # red foreground

    local p

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

    GIT_CHANGES="${p}%f"

    # The length of GIT_CHANGES after removing %f and %F.
    # GITSTATUS_PROMPT_LEN="${(m)#${${GIT_CHANGES//\%\%/x}//\%(f|<->F)}}"
}

# taken from Sindre Sorhus
# https://github.com/sindresorhus/pretty-time-zsh
human_time_to_var() {
    local human total_seconds=$1 var=$2
    local days=$(( total_seconds / 60 / 60 / 24 ))
    local hours=$(( total_seconds / 60 / 60 % 24 ))
    local minutes=$(( total_seconds / 60 % 60 ))
    local seconds=$(( total_seconds % 60 ))
    (( days > 0 )) && human+="${days}d "
    (( hours > 0 )) && human+="${hours}h "
    (( minutes > 0 )) && human+="${minutes}m "
    human+="${seconds}s"

    # Store human readable time in a variable as specified by the caller
    typeset -g "${var}"=" ${human}"
}

# Stores (into exec_time) the execution
# time of the last command if set threshold was exceeded.
check_cmd_exec_time() {
    integer elapsed
    (( elapsed = EPOCHSECONDS - ${cmd_exec_timestamp:-$EPOCHSECONDS} ))
    typeset -g exec_time=
    (( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )) && {
        human_time_to_var $elapsed "exec_time"
    }
}


typeset -gA __last_checks
typeset -gA __git_fetch_pwds

preprompt() {
    if [[ $1 != true ]]; then
        printf -- "\x1b[?25l"            # hide the cursor while we update

        check_cmd_exec_time
        unset cmd_exec_timestamp

        [ ! -w $PWD ] && local _read_only=' '

        print -Pn -- '\e]2;$m %(8~|…/%6~|%~)\a' # sets ssh and pwd in terminal title

        gitstatus_prompt_update_branch_only
        print -Pn -- '%6F${_read_only}%{\e[3m%}%4F%~%<<%f%{\e[0m%}%5F${exec_time}%f${GIT_BRANCH}'
        if [[ ${GIT_BRANCH} ]]; then
            printf '\033[6n'                   # ask term for position
            read -s -d\[ __nonce                 # discard first part
            read -s -d R] __position < /dev/tty  # store the position
        fi
        print -Pn -- '\n${_ssh}\x1b[?25h'   # show the cursor again and add final newline
    fi

    if [[ ${GIT_BRANCH} ]]; then
        ({
        gitstatus_prompt_update_changes_only
        print -Pn -- '\x1B[s\x1B[${__position}H\x1B[B\x1B[A\x1B[0K${GIT_CHANGES}\x1B[u'
        } & )

        if [[ $__UPDATE_GIT == true ]]; then
            if [[ $(($EPOCHSECONDS - ${__last_checks[$VCS_STATUS_WORKDIR]:-0})) -gt 60 ]]; then
                __last_checks[$VCS_STATUS_WORKDIR]="$EPOCHSECONDS"
                setopt LOCAL_OPTIONS NO_NOTIFY NO_MONITOR
                    { env GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o ConnectTimeout=59 -o BatchMode=yes" GIT_TERMINAL_PROMPT=0 /usr/bin/git -c gc.auto=0 -C "${VCS_STATUS_WORKDIR}" fetch --no-tags --recurse-submodules=no > /dev/null 2>&1 & disown }
                    __git_fetch_pwds[${VCS_STATUS_WORKDIR}]="$!"
            fi
            if [[ $__git_fetch_pwds[${VCS_STATUS_WORKDIR}] ]] && [ -e /proc/${__git_fetch_pwds[${VCS_STATUS_WORKDIR}]} ]; then
                { pending_git_status_pid=$(write_git_status >&3 3>&- & printf "$!"); } 3>&1
            else
                unset __git_fetch_pwds[${VCS_STATUS_WORKDIR}] pending_git_status_pid
            fi
        fi
    fi
}

write_git_status() {
    while [[ -e /proc/${__git_fetch_pwds[${VCS_STATUS_WORKDIR}]} ]]; do
        sleep 0.5
    done
    gitstatus_prompt_update_changes_only
    # save cursor, go to __position, move line down, move line up, write gitstatus, restore cursor
    print -Pn -- '\x1B[s\x1B[${__position}H\x1B[B\x1B[A\x1B[0K${GIT_CHANGES}\x1B[u'
}

# sets prompt. PROMPT has issues with multiline prompts, see
# https://superuser.com/questions/382503/how-can-i-put-a-newline-in-my-zsh-prompt-without-causing-terminal-redraw-issues

# Start gitstatusd instance with name "MY". The same name is passed to
# gitstatus_query in gitstatus_prompt_update_changes_only. The flags with -1 as values
# enable staged, unstaged, conflicted and untracked counters.
gitstatus_stop 'MY' && gitstatus_start -s -1 -u -1 -c -1 -d -1 'MY'

# On every prompt, fetch git status and set GITSTATUS_PROMPT.
autoload -Uz add-zsh-hook
add-zsh-hook preexec xterm_title_preexec
add-zsh-hook precmd preprompt

# Enable/disable the right prompt options.
# setopt no_prompt_bang prompt_percent prompt_subst

PROMPT='%F{%(?.none.1)}%%%f '     # %/# (normal/root); green/red (ok/error)
