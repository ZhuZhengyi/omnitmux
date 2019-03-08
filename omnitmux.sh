#!/usr/bin/env bash
#
# omnitmux.sh
# Copyright (C) 2019 Justice <justice_103@126.com>
#
# Distributed under terms of the MIT license.

app_name="omnitmux"
app_version="1.0"
debug=0
show_help=0
do_multicast=0
menu_width=32
left_pane=$TMUX_PANE
window_size=()
clusters=()         #clusters
hosts=()            #hosts
panes=()            #host panes
split_panes=()
ids=()              #host ids
tagged_ids=()       #tagged host ids
curr_hid=0          #current host_id
curr_cid=0          #current cluster_id
STAGE_CLUSTER="cluster"
STAGE_HOST="host"
stage="$STAGE_CLUSTER"     #cluster; host

RED="\033[1;31m"
GREEN="\033[1;32m"
BLINK="\033[1;38m"
NC="\033[0m" # No Color
ESC="27"

KEY_UP=$'\e[A'
KEY_DOWN=$'\e[B'
KEY_ESC=
KEY_ENTER=

TMUX_VERSION=$(tmux -V | awk '{print $2}')
RIGHT_PANE="{top-right}"
SPLIT_PANE="{bottom-right}"
case "$TMUX_VERSION" in
    1*)
        RIGHT_PANE="top-right"
        SPLIT_PANE="bottom-right"
        ;;
    *)
        ;;
esac


CLUSTER_PATH="$HOME/.config/omnitmux/clusters"


trap "exit_app" 1 2 3 15

hide_cursor() {
    tput sc;tput civis
}

show_cursor() {
    tput rc; tput cnorm
}

print_text () {
    echo -e "$1$NC"
}

toggle_menu () {
    show_help=$(($(($show_help+1))%2))
}


is_pane_active() {
    pane="$1"
    active=0
    active_panes=(  `tmux list-panes -s -F "#D"` )
    for p in ${active_panes[*]} ; do
        if [ "-$p" == "-$pane" ]; then
            active=1
            break
        fi
    done

    echo "$active"
}

is_host_active() {
    host="$1"
    id=$(get_host_id $host)
    paneid=${panes[$id]}
    echo $(is_pane_active $paneid)
}

# get host id from hosts use $host
# if $host in hosts, return host array id
# else return hosts size
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

load_cluster_hosts() {
    host_file=$1
    if [ ! -z $host_file ] && [ -f $host_file ]; then
        id=0
        for host in `cat $host_file | grep -v "^#" | grep -v "^$"`; do
            hosts[$id]=$host
            ((id+=1))
        done
    else
        add_hosts
    fi
}

connect_host() {
    host="$1"
    id=$(get_host_id $host)
    paneid=${panes[$id]}
    active=$(is_pane_active $paneid)
    if [ $active -ne 1 ] ; then
        paneid=`tmux new-window -P -F "#D" -d -n "$host" "ssh $host"`
        ids[$id]=$id
        panes[$id]="$paneid"
        tmux select-pane -t $left_pane
    fi
}

connect_hosts() {
    for host in ${hosts[*]} ; do
        connect_host $host
    done
}

close_hosts() {
    for pid in ${panes[*]} ; do
        tmux kill-pane -t "${pid}" 2>/dev/null
    done
    for pid in ${split_panes[*]} ; do
        tmux kill-pane -t "${pid}" 2>/dev/null
    done
    panes=()
    hosts=()
    ids=()
    split_panes=()
}

load_clusters() {
    id=0
    if [ -d $CLUSTER_PATH ] ; then
        for c in `ls -1 $CLUSTER_PATH` ; do
            clusters[$id]=$c
            ((id+=1))
        done
    fi
}

window_heigh=80
get_window_size() {
    window_size=( `stty size` )
    window_heigh=${window_size[0]}
    if [ $show_help -eq 0 ] ; then
        ((window_heigh-=4))
    else
        ((window_heigh-=16))
    fi
}

print_cluster_list() {
    id=0
    cid=0

    get_window_size
    hid0=0
    hid1=$window_heigh
    if [ $curr_cid -gt $hid1 ] ; then
        ((hid1=curr_cid+1))
        ((hid0=curr_cid-window_heigh+1))
    fi

    for cluster in `echo ${clusters[*]}`; do
        ((cid=id+1))
        line_text="[$cid] $cluster"
        if [ $id -eq $curr_cid ] ; then
            line_text="$GREEN$line_text"
        fi
        if [ $cid -gt $hid1 ] ; then
            break
        elif [ $cid -gt $hid0 ] ; then
            print_text "$line_text"
        fi
        ((id+=1))
    done
}

print_host_list() {
    host_id=0
    hid=1

    get_window_size
    hid0=0
    hid1=$window_heigh
    if [ $curr_hid -gt $hid1 ] ; then
        ((hid1=curr_hid+1))
        ((hid0=curr_hid-window_heigh+1))
    fi

    active_panes=(  `tmux list-panes -s -F "#D"` )
    for host in ${hosts[@]}; do
        active=0
        tagged=0
        ((hid=host_id+1))
        line_text="[$hid] $host"
        paneid=${panes[$host_id]}

        for p in ${active_panes[*]} ; do
            if [ "-$p" == "-$paneid" ]; then
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
        if [ $hid -gt $hid1 ] ; then
            break
        elif [ $hid -gt $hid0 ] ; then
            print_text "$line_text"
        fi
        ((host_id+=1))
    done

    if [ $do_multicast = 1 ]; then
        print_text  "\n$BLINK!!! MULTICAST MODE !!!"
    fi
}

print_menu() {
    active_hosts=`tmux list-panes -s -F "#T"`
    [ $debug -eq 0 ] && clear
    if [ $show_help = 1 ]; then
        echo "======[ $app_name v$app_version ]======"
        echo -e "$GREEN[j]$NC: go next host"
        echo -e "$GREEN[k]$NC: go previous host"
        echo -e "$GREEN[n]$NC: split right pane"
        echo -e "$GREEN[t]$NC: mark/unmark current host"
        echo -e "$GREEN[T]$NC: mark/unmark all hosts"
        echo -e "$GREEN[a]$NC: add new host"
        echo -e "$GREEN[d]$NC: delete current host"
        echo -e "$GREEN[r]$NC: reconnect current host"
        echo -e "$GREEN[q]$NC: quit host stage"
        echo -e "$GREEN[x]$NC: exit program"
        echo -e "$GREEN[?]$NC: toggle help info"
        echo -e "$GREEN[C-l]$NC: switch to right pane"
        echo -e "$GREEN[C-h]$NC: switch to left pane"
        echo -e "$GREEN[ESC]$NC: toggle multicast mode"
        echo -e "$GREEN[ENTER]$NC: enter host stage"
    else
        echo -e "$GREEN[?]$NC: toggle help info"
    fi
    if [ $stage == $STAGE_CLUSTER ] ; then
        echo "================================"
    else
        echo "--------------------------------"
    fi

    case $stage in
        $STAGE_CLUSTER) print_cluster_list ;;
        *) print_host_list ;;
    esac
    hide_cursor
}

get_keystroke () {
    old_stty_settings=`stty -g`
    stty -echo raw
    echo "`dd count=1 2> /dev/null`"
    stty $old_stty_settings
}

quit() {
    close_hosts
    show_cursor
    echo ""
    exit 0
}

exit_app() {
    echo -ne "exit $app_name? "
    echo "([y]es/[n]o/[c]ancel) "
    n=`get_keystroke`
    case $n in
        "y"|"Y") quit ;;
        *) ;;
    esac
}

join_pane () {
    target_pane="$1"
    tmux select-pane -t ${left_pane}
    tmux join-pane -s $target_pane -h -d
    tmux resize-pane -t "${left_pane}" -x "$menu_width"
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
    sel_host=${hosts[$sel_id]}
    active=$(is_host_active $sel_host)
    if [ "-$active" != "-1" ] ; then
        connect_host $sel_host
    fi

    sel_pane="${panes[$sel_id]}"
    if [ "-$sel_pane" == "-" ] ; then
        connect_host "$sel_host"
    fi
    pane_count=$( tmux list-panes | wc -l )
    if (( $pane_count > 1 ))  ; then
        tmux swap-pane -d -t "${RIGHT_PANE}" -s "$sel_pane"
    else
        join_pane $sel_pane
    fi

    curr_hid=$sel_id
}

jump_to_cluster_mid () {
    size=${#clusters[@]}
    ((curr_cid=(size-1)/2))
}

jump_to_cluster_end () {
    size=${#clusters[@]}
    ((curr_cid=size-1))
}

jump_to_host_end () {
    id=${#hosts[@]}
    ((id-=1))
    switch_host $id
}

jump_to_host_mid_low () {
    (( id=(curr_hid+1)/2 ))
    switch_host $id
}

jump_to_host_mid_high () {
    size=${#hosts[@]}
    (( id=(curr_hid+size)/2 ))
    switch_host $id
}

pre_cluster () {
    size=${#clusters[*]}
    ((curr_cid=(curr_cid-1+size)%size))
}

next_cluster () {
    size=${#clusters[*]}
    ((curr_cid=(curr_cid+1)%size))
}

pre_host () {
    size=${#hosts[*]}
    ((prev_id=(curr_hid-1+size)%size))
    switch_host $prev_id
}

next_host () {
    size=${#hosts[*]}
    ((next_id=(curr_hid+1)%size))
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
        hosts_size=${#hosts[*]}
        ((curr_hid%=hosts_size))
    fi
}

add_hosts() {
    echo -e "\nadd host: "
    host_id=${#hosts[*]}
    id=0
    while [ 1 ]; do
        ((id=host_id+1))
        read -p "[$id] " host
        if [ "$host" != "" ]; then
            hosts[$host_id]=$host
            connect_host "$host"
        elif [ "-$host" == "-" ]; then
            break
        fi
        ((host_id+=1))
    done
}

multicast() {
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
    host=$1
    paneid=""
    if [ "-$host" == "-" ] ; then
        paneid=`tmux split-window -v -t "${SPLIT_PANE}" -PF "#D"`
    else
        paneid=`tmux split-window -v -t "${SPLIT_PANE}" -PF "#D" "ssh $host"`
    fi
    if [ "-$paneid" != "-" ] ; then
        split_panes[${#split_panes[*]}]="$paneid"
    fi
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

load_stage_hosts() {
    stage=$STAGE_HOST
    cluster_path=$1
    curr_hid=0
    if [ -f $cluster_path ] ; then
        load_cluster_hosts $cluster_path
        connect_hosts
    else
        add_hosts
    fi

    join_pane ${panes[$curr_hid]}
}

switch_to_stage_hosts() {
    stage=$STAGE_HOST
    cluster_file=${clusters[$curr_cid]}
    cluster_file_path="$CLUSTER_PATH/$cluster_file"
    load_stage_hosts $cluster_file_path
}

switch_to_stage_clusters() {
    stage=$STAGE_CLUSTER
    close_hosts
    load_clusters

    cluster_count=${#clusters[*]}
    if [ $cluster_count -eq 0 ] ; then
        add_hosts
    fi
}

copy_ssh_key() {
    host=$1

    if [ ! -f `which ssh-copy-id` ]; then
        echo "$0: ssh-copy-id not found"
        return
    fi

    if [ "-$host" != "-" ] ; then
        ssh-copy-id $host
    elif [ -f `which sshpass` ] ; then
        read -p "password: " pass
        if [ "-$pass" != "-" ] ; then
            for h in ${hosts[*]} ; do
                sshpass -p $pass ssh-copy-id $h
            done
        fi
    else
        for h in ${hosts[*]} ; do
            ssh-copy-id $h
        done
    fi
}

key_with_stage_cluster() {
    m=$(get_keystroke)
    hid=0
    if `echo "$m" | grep -q -e "\d" ` && [ "$m" -ge 1  ] && [ "$m" -le ${#clusters[*]} ] ; then
        ((curr_cid=m-1))
    else
        case "$m" in
            "j"|$KEY_DOWN) next_cluster ;;
            "k"|$KEY_UP) pre_cluster ;;
            "e"|"E") jump_to_cluster_end ;;
            "m"|"M") jump_to_cluster_mid ;;
            "x"|"X"|"q") exit_app ;;
            "?") toggle_menu ;;
            $KEY_ENTER) switch_to_stage_hosts ;;
            *) continue ;;
        esac
    fi
}

key_with_stage_host() {
    m=$(get_keystroke)
    hid=0
    if [ $do_multicast -eq 0 ] ; then
        if `echo "$m" | grep -q -e "\d" ` && [ "$m" -ge 1  ] && [ "$m" -le ${#hosts[*]} ] ; then
            ((hid=m-1))
            switch_host "$hid"
        else
            case "$m" in
                "j"|$KEY_DOWN) next_host ;;
                "k"|$KEY_UP) pre_host ;;
                "n") split_pane ;;
                "N") split_pane ${hosts[$curr_hid]} ;;
                "a"|"A") add_hosts ;;
                "d"|"D") del_host ;;
                "R") reconnect_hosts ;;
                "t") toggle_tag_host ;;
                "T") toggle_tag_all_hosts ;;
                "c") toggle_multicast ;;
                "p") copy_ssh_key ${hosts[$curr_hid]} ;;
                "P") copy_ssh_key ;;
                "e") jump_to_host_end ;;
                "m") jump_to_host_mid_high ;;
                "M") jump_to_host_mid_low ;;
                "q") switch_to_stage_clusters ;;
                "?") toggle_menu ;;
                "x"|"X") exit_app ;;
                $KEY_ENTER) tmux select-pane -t "${RIGHT_PANE}" ;;
                *) continue ;;
            esac
        fi
    else
        case "$m" in
            $KEY_ESC) toggle_multicast ;;    #ESC
            *) multicast "$m"; continue ;;
        esac
    fi
}

run() {
    while [ 1 ]; do
        print_menu
        case $stage in
            $STAGE_CLUSTER) key_with_stage_cluster ;;
            *) key_with_stage_host ;;
        esac
    done
}

main() {
    if [ ! -f `which tmux` ]; then
        echo "$0: tmux not found"
        exit 1
    fi

    if [ "-$TMUX" == "-" ]; then
        tmux new-session -s omnitmux-$$ "bash $0 $*"
        #echo "$0: must run in tmux"
        exit
    fi
    left_pane=$TMUX_PANE

    #tmux set -g prefix2 C-a
    tmux bind-key -nr C-l select-pane -R
    tmux bind-key -nr C-h select-pane -L
    tmux bind-key -nr C-j select-pane -D
    tmux bind-key -nr C-k select-pane -U

    load_clusters

    host_file=$1
    if [ ! -z $host_file ] && [ -f $host_file ]; then
        load_stage_hosts $host_file
    elif [ ${#clusters[*]} -eq 0 ] ; then
        stage="host"
        add_hosts
    fi

    run
}

main "$*"
