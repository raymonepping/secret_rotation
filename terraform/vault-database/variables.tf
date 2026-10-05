variable "postgres_host" {
  description = "PostgreSQL address as seen from vault-1"
  type        = string
  default     = "srot-postgres:5432"
}

variable "db_name" {
  type    = string
  default = "hospital"
}

variable "connection_name" {
  type    = string
  default = "hospital-postgres"
}

variable "mgmt_user" {
  description = "Vault's connection user (CREATEROLE, not a superuser)"
  type        = string
  default     = "vault_mgmt"
}

variable "mgmt_password" {
  description = "Initial password of mgmt_user (.secrets/postgres.env). Irrelevant after make db-rotate-root."
  type        = string
  sensitive   = true
}

variable "dynamic_role" {
  type    = string
  default = "patient-readonly"
}

variable "static_role" {
  type    = string
  default = "surgeon"
}

variable "static_user" {
  type    = string
  default = "surgeon_svc"
}

# Short on purpose (decision D8): the UI shows these countdowns.
variable "dynamic_ttl" {
  type    = number
  default = 60
}

variable "dynamic_max_ttl" {
  type    = number
  default = 120
}

variable "static_rotation_period" {
  type    = number
  default = 120
}
