dtrace
======

Installing dependencies
-----------------------

Install git
-----------
pkgin install scmgit-base

Install gcc
-----------
```bash
pkgin install gcc47-4.7.2nb3 gmake
```

Install protobuf
----------------
```bash
curl -klO https://protobuf.googlecode.com/files/protobuf-2.5.0.tar.gz
tar zxvf protobuf-2.5.0.tar.gz
cd protobuf-2.5.0
./configure --prefix /opt/local
make
make install
```

Install 0mq
-----------
```bash
curl -klO http://download.zeromq.org/zeromq-2.2.0.tar.gz
tar zxf zeromq-2.2.0.tar.gz
cd zeromq-2.2.0
./configure --prefix /opt/local
make
make install
```
