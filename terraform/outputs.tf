output "url" {
  description = "Address to share with your friends."
  value       = "https://${local.domain}"
}

output "app_id" {
  description = "Clever Cloud application ID (for `clever link <app_id>`, then `clever logs`, `clever restart --without-cache`, ...)."
  value       = clevercloud_linux.openfront.id
}
