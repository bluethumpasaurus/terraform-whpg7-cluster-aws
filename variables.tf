variable "aws_region" {
  description = "The AWS region where resources will be created."
  type        = string
  default     = "eu-west-2"
}

variable "instance_type" {
  description = "The EC2 instance type for the cluster nodes."
  type        = string
  default     = "t3a.medium"
}

variable "cluster_name" {
  description = "A unique name for the server cluster."
  type        = string
  default     = "whpg-rocky-cluster"
}

variable "public_key_path" {
  description = "Path to your SSH public key file (e.g., ~/.ssh/id_rsa.pub)."
  type        = string
  default     = "~/.ssh/aws_id_rsa.pub"
}

variable "private_key_path" {
  description = "Path to your SSH private key file (e.g., ~/.ssh/id_rsa.pub)."
  type        = string
  default     = "~/.ssh/aws_id_rsa"
}

variable "edb_repo_token" {
  description = "The EDB repository token for downloading WarehousePG."
  type        = string
  sensitive   = true # Marks the variable as sensitive in Terraform outputs
}

variable "jumpbox_ssh_ingress" {
  description = "The ip address of the host that you will ssh to the cluster from."
  type        = string
  sensitive   = true # Marks the variable as sensitive in Terraform outputs
}

variable "aws_profile" {
  description = "AWS IAM Profile Name."
  type        = string
  sensitive   = true # Marks the variable as sensitive in Terraform outputs
}

variable "project" {
  description = "The name of the project, used for tagging and identification."
  type        = string
  default     = "whpg-rocky-cluster"
}







