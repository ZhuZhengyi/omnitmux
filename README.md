# OmniTmux

A cluster operate tool base tmux as omnitty, inspired by tmuxbro.

## Feature

* cluster list
* cluster/host stage
* multicast mode
* like vim key bind

## Demo

![cluster_stage](/Volumes/data/code/github.com/omnitmux/assets/image-20190223221909576.png)



![host_stage](/Volumes/data/code/github.com/omnitmux/assets/image-20190223222257902.png)

## KeyMap

### cluster stage

* j/J/UP: next cluster
* k/K/DOWN: prev cluster
* <ENTER>: enter into stage host of current cluster
* x: exit

### host stage

* j/J/UP: next host
* k/K/DOWN: prev host
* t: tag current host
* T: tag all hosts
* c: enable multicast mode
* <ESC>: disable multicast mode
* 
* r: reconnect current host
* R: reconnect all hosts
* a: add hosts
* d: delete current host
* q: quit to stage cluster
* ?: toggle help info
* x: exit

## Config path

clusters config path:`~/.config/omnitmux/cluster/`

## Run

must start tmux first, then run with:

```shell
$ tmux
$ ./omnitmux.sh  ./nodes		# start by load file nodes which contain cluster hosts
$ ./omnitmux.sh  				# start with clusters under default config path 
```



