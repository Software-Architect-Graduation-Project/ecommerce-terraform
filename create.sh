#/bin/bash

terraform apply --auto-approve

mv kubeconfig_ecommerce-eks ~/.kube/config

eksctl utils associate-iam-oidc-provider --region us-west-2 --cluster ecommerce-eks --approve

eksctl create iamserviceaccount \
  --cluster ecommerce-eks \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::377985789099:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

helm upgrade -i aws-load-balancer-controller \
    eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=ecommerce-eks \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set image.tag="${LBC_VERSION}"

kubectl apply -f k8s/namespace.yaml

sleep 20

kubectl apply -f k8s/ingress.yaml

echo "Change values on secret"

sleep 30

kubectl apply -f k8s/secret.yaml

kubectl apply -f k8s/deployment.yaml

kubectl apply -f k8s/service.yaml