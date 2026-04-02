# modules/budgets/outputs.tf

output "budget_ids" {
  description = "Map of budget IDs per account"
  value       = { for k, v in aws_budgets_budget.accounts : k => v.id }
}