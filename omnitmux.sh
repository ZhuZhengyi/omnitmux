#!/bin/bash

debug=0
show_menu=0
do_multicast=0
menu_width=32
left_pane=$TMUX_PANE
ids=()
hosts=()
panes=()
tagged_ids=()
clusters=()
cluster_id=0
curr_hid=0
curr_cid=0
stage="cluster"      #0,cluster; 1,hosts

RED="\033[1;31m"
GREEN="\033[1;32m"
BLINK="\033[1;38m"
NC="\033[0m" # No Color
ESC="27"

CLUSTER_CONF="$HOME/.config/omnitmux/cluster.ini"
CLUSTER_PATH="$HOME/.config/omnitmux/clusters"

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

load_hosts() {
    host_file=$1
    if [ ! -z $host_file ] && [ -f $host_file ]; then
        id=0
        for host in `cat $host_file | grep -v "^#" | grep -v "^$"`; do
            hosts[$id]=$host
            ((id+=1))
        done
    fi
}

connect_host () {
    host="$1"
    active=$(is_host_active $host)
    id=$(get_host_id $host)
    if [ $active -ne 1 ] ; then
        paneid=`tmux new-window -P -F "#D" -d -n "$host" "ssh $host"`
        ids[$id]=$id
        panes[$id]="$paneid"
        tmux select-pane -T "$host" -t $paneid
        tmux select-pane -t $left_pane
    fi
}

connect_hosts() {
    id=0
    for host in ${hosts[*]} ; do
        connect_host $host
    done
}

close_hosts() {
    for pid in ${panes[*]} ; do
        tmux kill-pane -t "${pid}"
    done
}

load_clusters() {
    id=0
    for c in `ls -1 $CLUSTER_PATH` ; do
        clusters[$id]=$c
        ((id+=1))
    done
}

show_stage_clusters() {
    id=0
    cid=0
    for cluster in `echo ${clusters[*]}`; do
        ((cid=id+1))
        line_text="[$cid] $cluster"
        if [ $id -eq $curr_cid ] ; then
            line_text="$GREEN$line_text"
        fi
        print_text "$line_text"
        ((id+=1))
    done
}

show_stage_hosts() {
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

        if [ $host_id -eq $curr_hid ] ; then
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
}

func_menu() {
    active_hosts=`tmux list-panes -s -F "#T"`
    [ $debug -eq 0 ] && clear
    if [ $show_menu = 1 ]; then
        echo "======[ omni-tmux v0.1 ]======"
        echo -e "$GREEN[j]$NC: go next host"
        echo -e "$GREEN[k]$NC: go previous host"
        echo -e "$GREEN[n]$NC: split right pane"
        echo -e "$GREEN[t]$NC: mark/unmark current host"
        echo -e "$GREEN[T]$NC: mark/unmark all hosts"
        echo -e "$GREEN[a]$NC: add new host"
        echo -e "$GREEN[d]$NC: delete current host"
        echo -e "$GREEN[r]$NC: reconnect current host"
        echo -e "$GREEN[ESC]$NC: toggle multicast mode"
        echo -e "$GREEN[x]$NC: exit program"
        echo -e "$GREEN[?]$NC: toggle help info"
        echo "============================"
    else
        echo -e "$GREEN[?]$NC: toggle help info"
        echo "============================"
    fi

    case $stage in
        "cluster") show_stage_clusters ;;
        *) show_stage_hosts ;;
    esac
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
        close_hosts
        tput rc; tput cnorm
        exit 0
    fi
}

join_pane () {
    tmux join-pane -s $1 -h -d
    tmux resize-pane -t "{left}" -x "$menu_width"
}


reconnect_hosts() {
    for host in ${hosts[@]} ; do
        active=$(is_host_active $host)
        if [ $active -ne 1 ] ; then
            connect_host $host
        fi
    done
}

switch_host () {
    sel_id=$1
    if [ $sel_id -eq $curr_hid ] ; then
        return
    fi

    sel_pane="${panes[$sel_id]}"
    tmux swap-pane -d -t "{right}" -s "$sel_pane"
    curr_hid=$sel_id
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

pre_cluster () {
    cluster_count=${#clusters[*]}
    ((prev_cid=curr_cid-1+cluster_count))
    ((prev_cid%=cluster_count))
    ((curr_cid=prev_cid))
}

next_cluster () {
    cluster_count=${#clusters[*]}
    ((next_cid=curr_cid+1))
    ((next_cid%=cluster_count))
    ((curr_cid=next_cid))
}

pre_host () {
    host_count=${#hosts[*]}
    ((prev_id=curr_hid-1+host_count))
    ((prev_id%=host_count))
    switch_host $prev_id
}

next_host () {
    host_count=${#hosts[*]}
    ((next_id=curr_hid+1))
    ((next_id%=host_count))
    switch_host $next_id
}

del_host () {
    echo -e "\nremove this host? (y/n) "
    n=`get_keystroke`
    if [ "$n" = "y" ]; then
        del_id=$curr_hid
        del_pane=${panes[$del_id]}
        delhost=${hosts[$del_id]}
        next_host
        tmux kill-pane -t $del_pane
        ids=( ${ids[@]/${#ids[@]}} )
        hosts=( ${hosts[@]/"$delhost"} )
        panes=( ${panes[@]/"$del_pane"} )
        curr_hid=$del_id
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
    curr_pane=${panes[$curr_hid]}
    tmux send-keys -t $curr_pane "$@"
    if [ $do_multicast = 1 ]; then
        for id in ${tagged_ids[*]} ; do
            if [ $id -ne $curr_hid ] ; then
                paneid=${panes[$id]}
                tmux send-keys -t $paneid "$@"
            fi
        done
    fi
}

split_pane () {
    host=${hosts[$curr_hid]}
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
        if [ "$id" == "$curr_hid" ]; then
            found=1
        else
            new_tagged_ids=( ${new_tagged_ids[*]}  $id )
        fi
    done

    if [ $found = 1 ]; then
        tagged_ids=( ${new_tagged_ids[*]} )
    else
        tagged_ids=( ${new_tagged_ids[*]} "$curr_hid")
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


switch_to_stage_hosts() {
    cluster_file=${clusters[$curr_cid]}
    cluster_file_path="$CLUSTER_PATH/$cluster_file"
    load_hosts $cluster_file_path
    curr_hid=0
    connect_hosts
    stage="hosts"

    tmux select-pane -t $left_pane
    join_pane ${panes[$curr_hid]}
}

switch_to_stage_clusters() {
    stage="cluster"
    close_hosts
    load_clusters
    curr_cid=0
}

stage_cluster() {
    m=$(get_keystroke)
    hid=0
    case "$m" in
        "j"|"J") next_cluster ;;
        "k"|"K") pre_cluster ;;
        ) switch_to_stage_hosts ;;
        "x"|"X") exit_omnitmux ;;
        "?") toggle_menu ;;
        *) continue ;;
    esac
}

stage_host() {
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
                "r") connect_host ${hosts[$curr_hid]} ;;
                "R") reconnect_hosts ;;
                "t") toggle_tag_host ;;
                "T") toggle_tag_all_hosts ;;
                "e") switch_host_end ;;
                "'") tmux select-pane -t "{right}" ;;
                "m") switch_host_mid ;;
                "x"|"X") exit_omnitmux ;;
                "c") toggle_multicast ;;
                "q") switch_to_stage_clusters ;;
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
}

run() {
    func_menu

    while [ 1 ]; do
        case $stage in
            "cluster") stage_cluster ;;
            *) stage_host ;;
        esac
        func_menu
    done
}


main() {
    if [ ! -f `which tmux` ]; then
        echo "$0: tmux not found"
        exit 1
    fi

    load_clusters

    host_file=$1
    if [ ! -z $host_file ] && [ -f $host_file ]; then
        stage="hosts"
        for host in `cat $host_file | grep -v "^#" | grep -v "^$"`; do
            connect_host "$host"
        done
    #else
    #    add_host force
    fi

    run
}


main "$*"
