#！ /bin/bash

if [ "$1" = "start" ];then
	echo "start"
	#start jenkins
	#aws ec2 start-instances --instance-ids i-039c81573bce1d87a --profile panda_beach
	#start sonar
	aws ecs update-service --cluster panda-test-cluster --service sonar --desired-count 1 --profile panda_beach
	sleep 20
	task_id=$(aws ecs list-tasks --profile panda_beach --cluster panda-test-cluster --service-name sonar --query 'taskArns | [0]')
	echo $task_id
	sonar_ip=$(eval "aws ecs describe-tasks --tasks $task_id --profile panda_beach --cluster panda-test-cluster --query 'tasks[0].attachments[0].details[? name==\`privateIPv4Address\`] | [0].value'")
	echo $sonar_ip
	aws elbv2 register-targets --profile panda_beach \
		    --target-group-arn arn:aws-cn:elasticloadbalancing:cn-northwest-1:955095959256:targetgroup/panda-sonar/b767b8e2727d260d \
		    --targets Id=$sonar_ip,Port=9000
	#start k8s
	cd ../kops-cn-master
	cp -r ../panda-k8s-config/一键启停/Makefile .
	make create-cluster

	#make edit-cluster
	export AWS_PROFILE=panda_beach
	export AWS_REGION=cn-northwest-1
	export AWS_DEFAULT_REGION=cn-northwest-1
	kops get cluster cluster.panda.k8s.local --state s3://cluster.k8s.local.panda -oyaml > temp-cluster.yml
	sed -i '' '/spec/r temp-spec.yml' temp-cluster.yml
	kops replace -f temp-cluster.yml --state s3://cluster.k8s.local.panda
	make update-cluster

	# add policy
	aws iam attach-role-policy --role-name nodes.cluster.panda.k8s.local --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

	#add listener on k8s cluster 9000
	load_balancer_name=$(aws elb describe-load-balancers --profile panda_beach --query 'LoadBalancerDescriptions[?contains(LoadBalancerName,`cluster-panda-k8s`)].LoadBalancerName | [0]')
	eval "aws elb create-load-balancer-listeners --load-balancer-name $load_balancer_name --listeners 'Protocol=TCP,LoadBalancerPort=9000,InstanceProtocol=TCP,InstancePort=443' --profile panda_beach"

	#edit sercurity group
	security_group_id=$(eval "aws elb describe-load-balancers --profile panda_beach --query 'LoadBalancerDescriptions[?LoadBalancerName==\`$load_balancer_name\`].SecurityGroups[0] | [0]'")
	eval "aws ec2 authorize-security-group-ingress --group-id $security_group_id --protocol tcp --port 9000 --cidr 0.0.0.0/0 --profile panda_beach"

	#edit kubectl config
	# cp ~/.kube/config ../kube-config/config
	sed -i '' 's/com.cn/com.cn:9000/' ~/.kube/config
	# export KUBECONFIG=~/Work/panda-beach/kube-config/config


	kubectl apply -f ../panda-k8s-config/jenkins-depliyment.yaml
	kubectl apply -f ./panda-k8s-config/jenkins-service.yaml

	jenkins_dns=$(kubectl get svc | grep jenkins | awk '{ print $4 }')
	jenkins_url="http://$jenkins_dns:8000/github-webhook/"
	curl --location --request PATCH 'https://api.github.com/repos/shmy/panda-ui/hooks/171899628' \
		--header 'Content-Type: application/json' \
		--header 'Authorization: Basic c2hteTo2NzBhMmM4ZjQzNTg5MWFkZmZhZWZiZTI1Y2Y2NWEzOTJhMzFiNTgy' \
		--data-raw "{
			\"config\" : {
				\"url\" : \"$jenkins_url\"
			}
		}"
	curl --location --request PATCH 'https://api.github.com/repos/shmy/panda-be/hooks/171907309' \
		--header 'Content-Type: application/json' \
		--header 'Authorization: Basic c2hteTo2NzBhMmM4ZjQzNTg5MWFkZmZhZWZiZTI1Y2Y2NWEzOTJhMzFiNTgy' \
		--data-raw "{
			\"config\" : {
				\"url\" : \"$jenkins_url\"
			}
		}"

elif [ "$1" = "stop" ];then
	echo "stopping..."
	#stop jenkins
	#aws ec2 stop-instances --instance-ids i-039c81573bce1d87a --profile panda_beach
	#stop sonar
	aws ecs update-service --cluster panda-test-cluster --service sonar --desired-count 0 --profile panda_beach
	old_sonar_ip=$(aws elbv2 describe-target-health --profile panda_beach --target-group-arn arn:aws-cn:elasticloadbalancing:cn-northwest-1:955095959256:targetgroup/panda-sonar/b767b8e2727d260d --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`].{Id:Target.Id,Port:Target.Port} | [0].Id')
	aws elbv2 deregister-targets --profile panda_beach \
		    --target-group-arn arn:aws-cn:elasticloadbalancing:cn-northwest-1:955095959256:targetgroup/panda-sonar/b767b8e2727d260d \
		    --targets Id=$old_sonar_ip,Port=9000
	#stop k8s
	cd ../kops-cn-master
	make delete-cluster
else
	echo "error arg"
fi