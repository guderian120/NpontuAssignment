output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.devsecops_server.public_ip
}