#/bin/bash

kubectl delete ingress ingress-ecommerce -n ecommerce

eksctl delete iamserviceaccount \
    --cluster ecommerce-eks \
    --name aws-load-balancer-controller \
    --namespace kube-system \
    --wait

terraform destroy -auto-approve