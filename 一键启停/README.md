## 准备步骤
1. 下载项目：https://github.com/nwcdlabs/kops-cn
2. 安装kops、kubectl、aws
3. 配置aws config
> aws configure --profile panda_beach
4. 公钥文件拷贝到 ~/.ssh/ 目录下
5. 在kops-cn-master目录下，替换Makefile
6. 在kops-cn-master目录下，添加文件temp-spec.yml
7. run.sh放到kops-cn-master同级的目录下面

## 运行
sudo ./run.sh start

## 终止
sudo ./stop.sh stop