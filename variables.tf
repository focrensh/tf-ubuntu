variable "aws_region" {
  default = "us-east-2"
}
variable "public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}
variable "aws_profile" {
  default = "default"
}
variable "prefix" {
  default = "demo"
}
variable "vpc_cidr" {
  default = "10.27.0.0/22"
}
variable "beacon_token" {
  default = "test"
}
variable "ub_hostname" {
  default = "demo"
}
variable "rdomain" {
  default = ""
}
variable "tlskey" {
  default = ""
}
variable "tlscert" {
  default = ""
}


