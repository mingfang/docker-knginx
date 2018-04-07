confd --onetime --log-level info --confdir /etc/confd --backend etcd --node http://$ETCD_HOST:4001 --watch -keep-stage-file 
