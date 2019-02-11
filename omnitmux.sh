#!/bin/bash

show_menu=0
do_multicast=0
menu_width=32
curr_id=0
omnipane=$TMUX_PANE
ids=()
hosts=()
panes=()
tagged_ids=()

RED="\033[1;31m"
GREEN="\033[1;32m"
BLINK="\033[1;38m"
NC="\033[0m" # No Color
ESC="27"

tmux set-option allow-rename off
tmux set-option automatic-rename off

print_text () {
    echo -e "$1$NC"
}

toggle_menu () {
    show_menu=$(($(($show_menu+1))%2))
}

toggle_mode() {
    mode=$(($(($mode+1))%2))
}

is_host_active() {
    host="$1"
    active=0
    active_hosts=`tmux list-panes -s -F "#T"`
    for h in `echo "$active_hosts"` ; do
        if [ "-$h" == "-$host" ]; then
            active=1
            break
        fi
    done

    echo "$active"
}

get_host_id() {
    host="$1"
    id=0
    for h in ${hosts[*]} ; do
        if [ "-$h" == "-$host" ]; then
            echo "$id"
            return
        fi
        ((id+=1))
    done
    echo "$id"
}

func_menu() {
    active_hosts=`tmux list-panes -s -F "#T"`
    clear
    if [ $show_menu = 1 ]; then
        echo "======[ omni-tmux v0.1 ]======"
        echo -e "$GREEN[j]$NC: go next host"
        echo -e "$GREEN[k]$NC: go previous host"
        echo -e "$GREEN[n]$NC: split right pane"
        echo -e "$GREEN[m]$NC: mark/unmark current host"
        echo -e "$GREEN[t]$NC: mark/unmark all hosts"
        echo -e "$GREEN[a]$NC: add new host"
        echo -e "$GREEN[d]$NC: delete current host"
        echo -e "$GREEN[q]$NC: enter type mode"
        echo -e "$GREEN[x]$NC: exit program"
        echo -e "$GREEN[F1]$NC: toggle multicast"
        echo -e "$GREEN[?]$NC: show/hide help menu"
        echo "============================"
    else
        echo -e "$GREEN[?]$NC: show/hide help info"
        echo "============================"
    fi

    host_id=0
    hid=1
    for host in ${hosts[@]}; do
        active=0
        tagged=0
        ((hid=host_id+1))
        line_text="[$hid] $host"

        for h in `echo "$active_hosts"` ; do
            if [ "-$h" == "-$host" ]; then
                active=1
                break
            fi
        done

        for id in ${tagged_ids[*]} ; do
            if [ "$id" == "$host_id" ] ; then
                tagged=1
                break
            fi
        done

        if [ $active -ne 1 ] ; then
            line_text="$line_text \tx"
        elif [ $tagged -eq 1 ] ; then
            line_text="$line_text \t*"
        fi

        if [ $host_id -eq $curr_id ] ; then
            line_text="$GREEN$line_text"
        elif [ $do_multicast = 1 ]; then
            line_text="$RED$line_text"
        fi
        print_text "$line_text"
        ((host_id+=1))
    done

    if [ $do_multicast = 1 ]; then
        print_text  "\n$BLINK!!! MULTICAST MODE !!!"
    fi
    tput sc;tput civis
}

get_keystroke () {
    old_stty_settings=`stty -g`
    stty -echo raw
    echo "`dd count=1 2> /dev/null`"
    stty $old_stty_settings
}

exit_omnitmux() {
    echo -e "\nclose all remote connections?"
    echo "([y]es/[n]o/[c]ancel) "
    n=`get_keystroke`
    if [ "$n" != "n" ] && [ "$n" != "y" ]; then
        return
    elif [ "$n" = "y" ]; then
        echo  "close windows ... "
        for pid in ${panes[*]} ; do
            tmux kill-pane -t "${pid}"
        done
        tput rc; tput cnorm
        exit 0
    fi
}

join_pane () {
    tmux join-pane -s $1 -h -d
    tmux resize-pane -t "{left}" -x "$menu_width"
}

connect_host () {
    host="$1"
    active=$(is_host_active $host)
    id=$(get_host_id $host)
    if [ $active -ne 1 ] ; then
        paneid=`tmux new-window -P -F "#D" -d -n "$host" "ssh $host"`
        ids[$id]=$id
        hosts[$id]="$host"
        panes[$id]="$paneid"
        tmux select-pane -T "$host" -t $paneid
        tmux select-pane -t $omnipane
    fi
}

switch_host () {
    sel_id=$1
    if [ $sel_id -eq $curr_id ] ; then
        return
    fi

    sel_pane="${panes[$sel_id]}"
    tmux swap-pane -d -t "{right}" -s "$sel_pane"
    curr_id=$sel_id
}

switch_host_end () {
    id=${#hosts[@]}
    ((id-=1))
    switch_host $id
}

switch_host_mid () {
    id=${#hosts[@]}
    ((id-=1))
    ((id/=2))
    switch_host $id
}

pre_host () {
    host_count=${#hosts[*]}
    ((prev_id=curr_id-1+host_count))
    ((prev_id%=host_count))
    switch_host $prev_id
}

next_host () {
    host_count=${#hosts[*]}
    ((next_id=curr_id+1))
    ((next_id%=host_count))
    switch_host $next_id
}

del_host () {
    echo "\nremove this host? (y/n) "
    n=`get_keystroke`
    if [ "$n" = "y" ]; then
        del_id=$curr_id
        del_pane=${panes[$del_id]}
        delhost=${hosts[$del_id]}
        next_host
        tmux kill-pane -t $del_pane
        ids=( ${ids[@]/${#ids[@]}} )
        hosts=( ${hosts[@]/"$delhost"} )
        panes=( ${panes[@]/"$del_pane"} )
        curr_id=$del_id
    fi
}

add_host () {
    echo -e "\nadd host: "
    host_id=${#hosts[*]}
    while [ 1 ]; do
        ((host_id+=1))
        read -p "[$host_id] " host
        if [ "$host" != "" ]; then
            connect_host "$host"
        elif [ "-$host" == "-" ]; then
            break
        fi
    done
}

multicast () {
    curr_pane=${panes[$curr_id]}
    tmux send-keys -t $curr_pane "$@"
    if [ $do_multicast = 1 ]; then
        for id in ${tagged_ids[*]} ; do
            if [ $id -ne $curr_id ] ; then
                paneid=${panes[$id]}
                tmux send-keys -t $paneid "$@"
            fi
        done
    fi
}

split_pane () {
    host=${hosts[$curr_id]}
    tmux split-window -v -t "{right}" "ssh $host"
}

toggle_tag_all_hosts () {
    tagged_ids_count=${#tagged_ids[*]}
    if [ $tagged_ids_count -eq 0 ] ; then
        tagged_ids=( ${ids[*]} )
    else
        tagged_ids=()
    fi
    echo "tagged count: $tagged_ids_count  ${tagged_ids[*]} "
}

toggle_tag_host () {
    found=0

    declare -a new_tagged_ids
    for id in ${tagged_ids[@]} ; do
        if [ "$id" == "$curr_id" ]; then
            found=1
        else
            new_tagged_ids=( ${new_tagged_ids[*]}  $id )
        fi
    done

    if [ $found = 1 ]; then
        tagged_ids=( ${new_tagged_ids[*]} )
    else
        tagged_ids=( ${new_tagged_ids[*]} "$curr_id")
    fi
}

toggle_multicast () {
    do_multicast=$(($(($do_multicast+1))%2))
    if [ $do_multicast = 1 ]; then
        tmux set-window-option status-bg red 1>/dev/null
    else
        tmux set-window-option status-bg green 1>/dev/null
    fi
}

if [ ! -f `which tmux` ]; then
    echo "$0: tmux not found"
    exit 1
fi

host_file=$1

if [ ! -z $host_file ] && [ -f $host_file ]; then
    for host in `cat $host_file`; do
        connect_host "$host"
    done
else
    add_host force
fi

tmux select-window -t 1
join_pane ${panes[$curr_id]}
func_menu

while [ 1 ]; do
    m=$(get_keystroke)
    hid=0
    if [ $do_multicast -eq 0 ] ; then
        if `echo "$m" | grep -q -e "\d" ` && [ "$m" -ge 1  ] && [ "$m" -le ${#hosts[*]} ] ; then
            ((hid=m-1))
            switch_host "$hid"
        else
            case "$m" in
                "j"|"J") next_host ;;
                "k"|"K") pre_host ;;
                "n"|"N") split_pane ;;
                "a"|"A") add_host ;;
                "d"|"D") del_host ;;
                "r") connect_host ${hosts[$curr_id]} ;;
                "t") toggle_tag_host ;;
                "T") toggle_tag_all_hosts ;;
                "e") switch_host_end ;;
                "m") switch_host_mid ;;
                "x"|"X") exit_omnitmux ;;
                "c"|"C") toggle_multicast ;;
                "?") toggle_menu ;;
                *) continue ;;
            esac
        fi
    else
        case "$m" in
            ) toggle_multicast ;;    #ESC
            *) multicast "$m"; continue ;;
        esac
    fi
    func_menu
done
