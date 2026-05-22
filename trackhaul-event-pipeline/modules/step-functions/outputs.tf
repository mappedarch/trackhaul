output "state_machine_arn" {
  description = "ARN of the incident orchestration state machine"
  value       = aws_sfn_state_machine.incident.arn
}