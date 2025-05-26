variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.large" # Suitable for GitLab; adjust if needed
}

variable "key_name" {
  description = "Name of the EC2 key pair"
  default     = "npontu_key" # Replace with your key pair name
}

variable "ami_id" {
  description = "AMI ID for Ubuntu 22.04"
  default     = "ami-0df368112825f8d8f" # Ubuntu 22.04 LTS in us-east-1; verify for your region
}

variable "my_ip" {
  description = "Your public IP for SSH access"
  default     = "154.161.174.0/24" # Replace with your public IP (e.g., curl ifconfig.me)
}