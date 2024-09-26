provider "alicloud" {
    access_key = ""
    secret_key = ""
    region = "ap-southeast-3"
}

# Create vpc
resource "alicloud_vpc" "ben_vpc"{
    vpc_name ="ben_vpc"
    cidr_block="172.16.0.0/12"
}

data "alicloud_zones" "default" {
  available_instance_type = "ecs.g7.large"
}

# Create ben_vpc > VswitchAz1
resource "alicloud_vswitch" "vswitchAz1" {
  vpc_id            = alicloud_vpc.ben_vpc.id
  cidr_block        = "172.16.1.0/24"
  zone_id = data.alicloud_zones.default.zones.0.id
}
# Create ben_vpc > VswitchAz2
resource "alicloud_vswitch" "vswitchAz2" {
  vpc_id            = alicloud_vpc.ben_vpc.id
  cidr_block        = "172.16.0.0/24"
  zone_id = data.alicloud_zones.default.zones.1.id
}

# Create security group for DMZ
resource "alicloud_security_group" "DMZSecGrp" {
  name = "DMZSecGrp"
  description = "DMZsecurityGroup"
  vpc_id = alicloud_vpc.ben_vpc.id
}
#Set DMZ security group rules
resource "alicloud_security_group_rule" "dmz_secGrp_ingress_rule"{
    type = "ingress"
    ip_protocol = "icmp"
    nic_type = "intranet"
    policy = "accept"
    port_range = "-1/-1" 
    priority = 1
    security_group_id = alicloud_security_group.DMZSecGrp.id
    cidr_ip = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "dmz_secGrp_http_rule" {
    security_group_id = alicloud_security_group.DMZSecGrp.id
    type = "ingress"
    ip_protocol = "tcp"
    port_range = "80/80"
    cidr_ip = "0.0.0.0/0"
    policy = "accept"
}


#create ecs to switch 1
resource "alicloud_instance" "ecs_vs1" {
    count = 2
    instance_name = "ecs-vs1-${count.index+1}"
    instance_type = "ecs.u1-c1m1.large"
    vswitch_id = alicloud_vswitch.vswitchAz1.id
    security_groups = [alicloud_security_group.DMZSecGrp.id]
    image_id = "ubuntu_22_04_x64_20G_alibase_20240807.vhd"
    system_disk_category = "cloud_auto"
    instance_charge_type = "PostPaid"
    password = "Test!123"
    user_data = base64encode(local.user_data)
}

#create ecs to switch 2
resource "alicloud_instance" "ecs_vs2" {
    count = 2
    instance_name = "ecs-vs2-${count.index+1}"
    instance_type = "ecs.u1-c1m1.large"
    vswitch_id = alicloud_vswitch.vswitchAz2.id
    security_groups = [alicloud_security_group.DMZSecGrp.id]
    image_id = "ubuntu_22_04_x64_20G_alibase_20240807.vhd"
    system_disk_category = "cloud_auto"
    instance_charge_type = "PostPaid"
    user_data = base64encode(local.user_data2)
}

#user data  or can user "Provisioner" to remote access
locals {
  user_data = <<EOF
#!/bin/bash
apt update -y
apt install -y apache2
systemctl start apache2
systemctl enable apache2
echo "<h1>Hello World!!!!! from \$(hostname -f)</h1>" > /var/www/html/index.html
EOF
}

locals {
  user_data2 = <<EOF
#!/bin/bash
apt update -y
apt install -y apache2
systemctl start apache2
systemctl enable apache2
echo "<h1>Hello Ben! from \$(hostname -f)</h1>" > var/www/html/index.html
EOF
}


#SLB instance creation
resource "alicloud_slb_load_balancer" "ben_slb" {
  load_balancer_name = "ben_slb"
  address_type = "internet"
  internet_charge_type = "PayByTraffic"
  load_balancer_spec = "slb.s2.small"
}

#create Vserver group
resource "alicloud_slb_server_group" "ben_vserverGrp" {
  load_balancer_id = alicloud_slb_load_balancer.ben_slb.id
  name = "ben_vserverGrp"
}

#Attach servers to vserver group
resource "alicloud_slb_server_group_server_attachment" "ecs_vs1_server1" {
  server_group_id = alicloud_slb_server_group.ben_vserverGrp.id
  server_id = alicloud_instance.ecs_vs1[0].id
  port = 80
  weight = 100
}

resource "alicloud_slb_server_group_server_attachment" "ecs_vs1_server2" {
  server_group_id = alicloud_slb_server_group.ben_vserverGrp.id
  server_id = alicloud_instance.ecs_vs1[1].id
  port = 80
  weight = 100
}

resource "alicloud_slb_server_group_server_attachment" "ecs_vs2_server1" {
  server_group_id = alicloud_slb_server_group.ben_vserverGrp.id
  server_id = alicloud_instance.ecs_vs2[0].id
  port = 80
  weight = 100
}

resource "alicloud_slb_server_group_server_attachment" "ecs_vs2_server2" {
  server_group_id = alicloud_slb_server_group.ben_vserverGrp.id
  server_id = alicloud_instance.ecs_vs2[1].id
  port = 80
  weight = 100
}

#Create listener for SLB instance
resource "alicloud_slb_listener" "http_listener" {
   load_balancer_id = alicloud_slb_load_balancer.ben_slb.id
   frontend_port = 80
   backend_port = 80
   protocol = "http"
   server_group_id = alicloud_slb_server_group.ben_vserverGrp.id
   #other setting
    scheduler = "wrr"
    health_check = "on"
    health_check_http_code = "http_2xx"
    health_check_interval = 2
    health_check_timeout = 5
    healthy_threshold =2
    unhealthy_threshold =2
}

output "ecs_vs1_instance_id" {
  value = alicloud_instance.ecs_vs1[*].id
  description = "ID of ecs_vs1"
}

output "ecs_vs1_ins_ip" {
  value = alicloud_instance.ecs_vs1[*].private_ip
  description = "ecs IPS"
}

output "ecs_vs2_instance_id" {
  value = alicloud_instance.ecs_vs2[*].id
  description = "ID of ecs_vs2"
}

output "ecs_vs2_ins_ip" {
  value = alicloud_instance.ecs_vs2[*].private_ip
  description = "ecs2 IP"
}

#Create RAM role