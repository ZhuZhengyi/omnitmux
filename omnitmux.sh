#!/bin/sh

show_menu=1
do_multicast=0
tagged_pane=""
window_count=1
curr_id=1
declare -a hosts
declare -a hostids
declare -a pane_ids
declare -a tagged_ids

toggle_menu () {
    show_menu=$(($(($show_menu+1))%2))
}

func_menu () {
    clear
    if [ $show_menu = 1 ]; then
        echo "========[ omni-tmux v0.1 ]========"
        echo "[1;32m[F1][m: split right pane"
        echo "[1;32m[F2][m: go next window"
        echo "[1;32m[F3][m: go previous window"
        echo "[1;32m[F4][m: remove current window"
        echo "[1;32m[F5][m: tag/untag current window"
        echo "[1;32m[F6][m: tag/untag all windows"
        echo "[1;32m[F7][m: toggle multicast"
        echo "[1;32m[F8][m: add host"
        echo "[1;32m[F9][m: show/hide menu"
        echo "[1;32m[F10][m: quit program"
        echo "================================"
    else
        echo "[1;32m[F9][m: show/hide menu"
        echo "================================"
    fi

    host_id=0
    for host in ${hosts[@]}; do
        ((host_id+=1))
        found=0
        for id in ${tagged_ids[*]} ; do
            if [ "$id" == "$host_id" ] ; then
                found=1
            fi
        done

        if [ $host_id -eq $curr_id ] ; then
            if [ "$found" == "1" ] ; then
                echo "[1;32m[$host_id] $host * [m"
            else
                echo "[1;32m[$host_id] $host [m"
            fi
        elif [ "$found" == "1" ] ; then
            echo "[1;31m[$host_id] $host *[m"
        else
            echo "[$host_id] $host"
        fi
    done

    if [ $do_multicast = 1 ]; then
        echo  "\n[1;38m!!! MULTICAST MODE !!![m"
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
        tput rc; tput cnorm
        echo -n "close windows ... "
        while [ 1 ] ; do
            window_count=`tmux list-window | wc -l | awk '{print $1}'`
            if [ $window_count -le 1 ] ; then
                break
            fi
            tmux kill-window -t "{end}"
        done
        tmux kill-pane -t "{right}"
        exit 0
    fi
}

join_pane () {
    tmux join-pane -s $1 -h -d
    tmux resize-pane -t "{left}" -x "40"
}

create_window () {
    host="$1"
    id=${#hosts[*]}
    paneid=`tmux new-window -P -F "#D" -d -n "$host" "ssh $host"`
    ((id+=1))
    hostids[$id]=$id
    hosts[$id]="$host"
    pane_ids[$id]="$paneid"
}

prev_window () {
    window_count=`tmux list-windows | wc -l | awk '{print $1}'`
    ((prev_id=curr_id-1+window_count))
    ((prev_id%=window_count))
    if [ $prev_id -lt 1 ] ; then
        prev_id=$window_count
    fi
    curr_id=$prev_id
    curr_paneid=${pane_ids[$curr_id]}
    tmux swap-pane -t "{right}" -s "${curr_paneid}" -d
}


next_window () {
    window_count=`tmux list-windows | wc -l | awk '{print $1}'`
    ((next_id=curr_id+1))
    ((next_id%=window_count))
    if [ $next_id -lt 1 ] ; then
        next_id=$window_count
    fi
    curr_id=$next_id
    curr_paneid=${pane_ids[$curr_id]}
    tmux swap-pane -t "{right}" -s "${curr_paneid}" -d
}

del_window () {
    echo -n "\nremove this window? (y/n) "
    curr_pane=${pane_ids[$curr_id]}
    n=`get_keystroke`
    if [ "$n" = "y" ]; then
        tmux kill-pane -t $curr_pane
        if [ "$curr_pane" != "$prev_pane" ]; then
            curr_pane=$prev_pane
            join_pane $curr_pane
        elif [ "$curr_pane" != "$next_pane" ]; then
            curr_pane=$next_pane
            join_pane $curr_pane
        else
            curr_pane=""
        fi
    fi
}

add_window () {
    while [ 1 ]; do
        read -p "add a host: " host
        if [ "$host" != "" ]; then
            create_window "$host"
            break
        elif [ "$1" != "force" ]; then
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
join_pane "2.1"
func_menu


while [ 1 ]; do
    m=`get_keystroke`
    case "$m" in
        OP|\[11~) #F2
            split_pane
            ;;
        OQ|\[12~) #F2
            next_window
            ;;
        OR|\[13~) #F3
            prev_window
            ;;
        OS|\[14~) #F4
            del_window
            ;;
        \[15~) #F5
            tag_untag_window
            ;;
        \[17~) #F6
            tag_untag_all_windows
            ;;
        \[18~) #F7
            toggle_multicast
            ;;
        \[19~) #F8
            add_window
            ;;
        \[20~) #F9
            toggle_menu
            ;;
        \[21~) #F10
            close_window
            exit 0
            ;;
        \[22~) #F11
            split_pane
            ;;
        *)
            multicast "$m"
            continue
            ;;
    esac
    func_menu
done
