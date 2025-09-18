output "coordinator_private_ip" {
  description = "Private IP address of WHPG Coordinator (server 1)."
  value       = aws_instance.server[0].private_ip
}

output "coordinator_standby_private_ip" {
  description = "Private IP address of WHPG Standby Coordinator (server 2)."
  value       = aws_instance.server[1].private_ip
}

output "segment_server_1_private_ip" {
  description = "Private IP address of WHPG segment server 1 (server 3)."
  value       = aws_instance.server[2].private_ip
}

output "segment_server_2_private_ip" {
  description = "Private IP address of WHPG segment server 2 (server 4)."
  value       = aws_instance.server[3].private_ip
}

output "ssh_command_for_whpg_coordinator" {
  description = "Command to SSH into the WHPG Coordinator (server 1)."
  value       = "ssh -i ${var.private_key_path} rocky@${aws_eip.public_ip[0].public_ip}"
}

output "ssh_command_for_whpg_coordinator_standby" {
  description = "Command to SSH into the WHPG Standby Coordinator (server 2)."
  value       = "ssh -i ${var.private_key_path} rocky@${aws_eip.public_ip[1].public_ip}"
}