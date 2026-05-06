#!/usr/bin/env bash
# Argus DSPM agent — EC2 user_data bootstrap (Wave 4 Track J).
#
# Pulls the agent image from a public registry (no ECR auth needed),
# wires the enrollment token from SSM Parameter Store, and starts
# the container under systemd so a host reboot brings the agent
# back automatically.
#
# Variables substituted by Terraform:
#   ${argus_backend_url}, ${aws_region}, ${enrollment_token_param},
#   ${aws_role_arn}, ${aws_external_id}, ${agent_image}.
set -euo pipefail

# Install Docker (Amazon Linux 2 / 2023). Fail loudly so the EC2
# instance never silently boots without a runtime.
if ! command -v docker >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y docker
  else
    amazon-linux-extras install -y docker
  fi
  systemctl enable --now docker
fi

# Resolve the enrollment token from SSM. We never echo it.
ENROLLMENT_TOKEN="$(aws ssm get-parameter \
  --name "${enrollment_token_param}" \
  --with-decryption \
  --region "${aws_region}" \
  --query 'Parameter.Value' --output text)"

mkdir -p /etc/argus
cat > /etc/argus/agent.env <<EOF
ARGUS_BACKEND_URL=${argus_backend_url}
CLOUD_PROVIDER=aws
AWS_ROLE_ARN=${aws_role_arn}
AWS_EXTERNAL_ID=${aws_external_id}
ENROLLMENT_POOL=baseline
AGENT_CONCURRENT_JOBS=4
ENROLLMENT_TOKEN=$ENROLLMENT_TOKEN
EOF
chmod 600 /etc/argus/agent.env

# systemd unit pulls the public image and re-creates the container on
# upgrades. Restart=always keeps the agent alive across container
# crashes; the agent's own idle-retry loop handles transient backend
# outages without exiting.
cat > /etc/systemd/system/argus-agent.service <<EOF
[Unit]
Description=Argus DSPM agent
Wants=docker.service
After=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop argus-agent
ExecStartPre=-/usr/bin/docker rm argus-agent
ExecStartPre=/usr/bin/docker pull ${agent_image}
ExecStart=/usr/bin/docker run --rm --name argus-agent \\
  --env-file /etc/argus/agent.env \\
  ${agent_image}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now argus-agent.service

# Weekly image refresh — keeps the agent on the rolling `stable` tag
# without a redeploy. Customers who pinned a specific version override
# `agent_image` in the Terraform module and the cron is harmless (the
# tag won't move under them).
cat > /etc/cron.weekly/argus-agent-refresh <<'EOF'
#!/usr/bin/env bash
docker pull "$(grep '^ExecStartPre=/usr/bin/docker pull' /etc/systemd/system/argus-agent.service | awk '{print $NF}')" || exit 0
systemctl restart argus-agent.service
EOF
chmod +x /etc/cron.weekly/argus-agent-refresh
