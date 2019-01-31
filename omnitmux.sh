#!/bin/sh

show_menu=0
do_multicast=0
menu_width=32
curr_id=1
declare -a hosts
declare -a hostids
declare -a pane_ids
declare -a tagged_ids

RED="\033[1;31m"
GREEN="\033[1;32m"
BLINK="\033[1;38m"
NC="\033[0m" # No Color

print_text () {
    echo "$1$NC"
}

toggle_menu () {
    show_menu=$(($(($show_menu+1))%2))
}

func_menu () {
    clear
    if [ $show_menu = 1 ]; then
        echo "======[ omni-tmux v0.1 ]======"
        echo "$GREEN[F1]$NC: split right pane"
        echo "$GREEN[F2]$NC: go next window"
        echo "$GREEN[F3]$NC: go previous window"
        echo "$GREEN[F4]$NC: tag/untag current window"
        echo "$GREEN[F5]$NC: tag/untag all windows"
        echo "$GREEN[F6]$NC: toggle multicast"
        echo "$GREEN[F7]$NC: add host"
        echo "$GREEN[F8]$NC: remove current window"
        echo "$GREEN[F9]$NC: show/hide menu"
        echo "$GREEN[F10]$NC: quit program"
        echo "================================"
    else
        echo "$GREEN[F9]$NC: show/hide menu"
        echo "================================"
    fi

    host_id=0
    for host in ${hosts[@]}; do
        ((host_id+=1))
        line_text="[$host_id] $host"
        for id in ${tagged_ids[*]} ; do
            if [ "$id" == "$host_id" ] ; then
                line_text="$line_text *"
                break
            fi
        done

        if [ $host_id -eq $curr_id ] ; then
            line_text="$GREEN$line_text"
        elif [ $do_multicast = 1 ]; then
            line_text="$RED$line_text"
        fi
        print_text "$line_text"
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

close_window() {
    echo "\nclose all remote connections?"
    echo -n "([y]es/[n]o/[c]ancel) "
    n=`get_keystroke`
    if [ "$n" != "n" ] && [ "$n" != "y" ]; then
        return
    elif [ "$n" = "y" ]; then
        echo  "close windows ... "
        for pid in ${pane_ids[*]} ; do
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

create_window () {
    host="$1"
    id=${#hosts[*]}
    paneid=`tmux new-window -P -F "#D" -d -n "$host" "ssh $host"`
    if [ "-$paneid" != "-" ] ; then
        ((id+=1))
        hostids[$id]=$id
        hosts[$id]="$host"
        pane_ids[$id]="$paneid"
    fi
}

prev_window () {
    host_count=${#hosts[*]}
    ((prev_id=curr_id-1+host_count))
    ((prev_id%=host_count))
    if [ $prev_id -lt 1 ] ; then
        prev_id=$host_count
    fi
    curr_id=$prev_id
    curr_paneid=${pane_ids[$curr_id]}
    tmux swap-pane -t "{right}" -s "${curr_paneid}" -d
}

next_window () {
    host_count=${#hosts[*]}
    ((next_id=curr_id+1))
    ((next_id%=host_count))
    if [ $next_id -lt 1 ] ; then
        next_id=$host_count
    fi
    curr_id=$next_id
    curr_paneid=${pane_ids[$curr_id]}
    tmux swap-pane -t "{right}" -s "${curr_paneid}" -d
}

del_window () {
    echo "\nremove this window? (y/n) "
    n=`get_keystroke`
    if [ "$n" = "y" ]; then
        del_id=$curr_id
        next_window
        del_pane=${pane_ids[$del_id]}
        hostids=( ${hostids[*]/${hostids[$del_id]}} )
        hosts=( ${hosts[*]/${hosts[$del_id]}} )
        pane_ids=( ${pane_ids[*]/${pane_ids[$del_id]}} )
        tmux kill-pane -t $del_pane
        curr_id=$del_id
    fi
}

add_window () {
    echo "add a host: "
    host_id=${#hosts[*]}
    while [ 1 ]; do
        ((host_id+=1))
        read -p "[$host_id] " host
        if [ "$host" != "" ]; then
            create_window "$host"
        elif [ "-$host" == "-" ]; then
            break
        fi
    done
}

multicast () {
    curr_pane=${pane_ids[$curr_id]}
    tmux send-keys -t $curr_pane "$@"
    if [ $do_multicast = 1 ]; then
        for id in ${tagged_ids[*]} ; do
            if [ $id -ne $curr_id ] ; then
                paneid=${pane_ids[$id]}
                tmux send-keys -t $paneid "$@"
            fi
        done
    fi
}

split_pane () {
    host=${hosts[$curr_id]}
    tmux split-window -v -t "{right}" "ssh $host"
}

tag_untag_all_windows () {
    tagged_ids_count=${#tagged_ids[*]}
    if [ $tagged_ids_count -eq 0 ] ; then
        tagged_ids=( ${hostids[*]} )
    else
        tagged_ids=()
    fi
    echo "tagged count: $tagged_ids_count  ${tagged_ids[*]} "
}

tag_untag_window () {
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
        create_window "$host"
    done
else
    add_window force
fi

tmux select-window -t 1
join_pane ${pane_ids[$curr_id]}
func_menu

while [ 1 ]; do
    m=`get_keystroke`
    case "$m" in
        OP|\[11~) split_pane ;;
        OQ|\[12~) next_window ;;
        OR|\[13~) prev_window ;;
        OS|\[14~) tag_untag_window ;;
        \[15~) tag_untag_all_windows ;;
        \[17~) toggle_multicast ;;
        \[18~) add_window ;;
        \[19~) del_window;;
        \[20~) toggle_menu ;;
        \[21~) close_window ;;
        \[22~) split_pane ;;
        *) multicast "$m"; continue ;;
    esac
    func_menu
done
