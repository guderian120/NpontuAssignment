


resource "aws_instance" "devsecops_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.devsecops_sg.id]

  # Configure root EBS volume to 16GB
  root_block_device {
    volume_size = 16 # 16GB as previously specified
    volume_type = "gp3"
    delete_on_termination = true
  }

  # User Data script to configure server with Docker
  user_data = <<EOF
#!/bin/bash
# Update system and install dependencies
apt-get update -y
apt-get upgrade -y
apt-get install -y nginx python3 python3-pip nodejs npm fail2ban

# Install Docker
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker

# Enable and start Nginx
systemctl enable nginx
systemctl start nginx

# Configure Nginx as reverse proxy
cat <<EOT > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /app {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOT
systemctl restart nginx

# Harden security
systemctl enable fail2ban
systemctl start fail2ban
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw allow 2222/tcp
ufw --force enable
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Run PostgreSQL in Docker
docker run -d --name postgres \
  -e POSTGRES_PASSWORD=securepassword \
  -e POSTGRES_USER=devsecops \
  -e POSTGRES_DB=app_db \
  -p 5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  postgres:15

# Run GitLab in Docker
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}')
docker run -d --name gitlab \
      --hostname $PUBLIC_IP \
      -p 8080:80 -p 443:443 -p 2222:22 \
      -v gitlab_config:/etc/gitlab \
      -v gitlab_logs:/var/log/gitlab \
      -v gitlab_data:/var/opt/gitlab \
      gitlab/gitlab-ee:latest

# Configure GitLab SSH port
docker exec gitlab bash -c "echo 'gitlab_rails['gitlab_shell_ssh_port'] = 22' >> /etc/gitlab/gitlab.rb"
docker exec gitlab gitlab-ctl reconfigure
EOF

  tags = {
    Name = "DevSecOps-Server"
  }
}

resource "aws_security_group" "devsecops_sg" {
  name        = "devsecops_sg"
  description = "Security group for DevSecOps server"

  # SSH access (restricted to your IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # GitLab SSH access
  ingress {
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP for web server and GitLab
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS for GitLab
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}