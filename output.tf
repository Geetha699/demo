# outputs.tf

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.demo.id
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}
