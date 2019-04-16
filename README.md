
# OmniTmux [![Build Status](https://travis-ci.org/YOUR/PROJECT.svg?branch=master)](https://travis-ci.org/ZhuZhengyi/omnitmux)

A cluster operate tool base tmux as omnitty, inspired by tmuxbro.

## Feature

- cluster list

- cluster/host stage

- multicast mode

- like vim key bind

## Demo

![cluster_stage](assets/image-20190223221909576.png)

![host_stage](assets/image-20190223222257902.png)

## KeyMap

### cluster stage

- j/J/UP: next cluster

- k/K/DOWN: prev cluster

- m: jump to middle cluster

- - `

- x: exit

### host stage

- j/J/UP: next host

- k/K/DOWN: prev host

- t: tag current host

- T: tag all hosts

- c: enable multicast mode

- `

- `

- m: jump to middle host

- e: jump to end host

- r: reconnect current host

- R: reconnect all hosts

- a: add hosts

- d: delete current host

- q: quit to stage cluster

- ?: toggle help info

- x: exit

## Config path

clusters config path:`~/.config/omnitmux/clusters/`

```
$ ls ~/.config/omnitmux/clusters/
hb02  test  test2 ump01
$ cat ~/.config/omnitmux/clusters/test
# ma
171.21.240.67
171.20.240.94
171.20.240.95
# da
11.194.133.103
11.194.133.194
11.194.134.103
11.194.134.167
```

## Run

must start tmux first:

```
$ tmux
```

then run with:

```
$ ./omnitmux.sh  ./nodes        # start by load file nodes which contain cluster hosts
$ ./omnitmux.sh              # start with clusters under default config path
```

cluster hosts file must likes:

```
$ cat ./nodes
user1@172.20.240.95
10.194.133.103
10.194.133.194
10.194.134.103
10.194.134.167
10.194.135.8
```

all hosts should ssh config to be login in
