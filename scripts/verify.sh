#!/usr/bin/env bash
# End-to-end check of the running platform: a request through the load balancer reaches the pods on the nodes,
# every node in the Auto Scaling group is healthy behind it, and the observability layer exists.
set -euo pipefail
url=$(terraform output -raw app_url)
asg=$(terraform output -raw asg_name)
cluster=$(terraform output -raw cluster_name)

echo "== Load balancer -> nodes -> pods"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
  [ "$code" = 200 ] && break
  [ "$i" = 60 ] && { echo "FAIL $url never returned 200 (last: $code)"; exit 1; }
  sleep 5
done
echo "PASS $url returned 200 ($(curl -s "$url" | grep -o '<title>[^<]*' | sed 's/<title>//'))"

echo "== Auto Scaling group behind the load balancer"
tg=$(aws elbv2 describe-target-groups --names eks-platform-app --query 'TargetGroups[0].TargetGroupArn' --output text)
healthy=$(aws elbv2 describe-target-health --target-group-arn "$tg" --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])')
size=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg" --query 'AutoScalingGroups[0].length(Instances)')
echo "$healthy of $size nodes in $asg are healthy targets"
[ "$healthy" -ge 2 ] && [ "$healthy" = "$size" ]

echo "== Observability"
addon=$(aws eks describe-addon --cluster-name "$cluster" --addon-name amazon-cloudwatch-observability --query 'addon.status' --output text)
echo "Container Insights add-on: $addon"
[ "$addon" = ACTIVE ]
aws cloudwatch get-dashboard --dashboard-name "$(terraform output -raw dashboard)" --query DashboardName --output text | sed 's/^/Dashboard: /'
aws cloudwatch describe-alarms --alarm-name-prefix "$cluster-" --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
[ "$(aws cloudwatch describe-alarms --alarm-name-prefix "$cluster-" --query 'length(MetricAlarms)')" = 3 ]
echo "PASS platform verified end to end"
