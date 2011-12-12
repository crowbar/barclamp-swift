#
# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: andi abes
#

include_recipe 'apt'
include_recipe 'utils'
include_recipe 'swift::auth'


local_ip = Swift::Evaluator.get_ip_by_type(node, :admin_ip_expr)
public_ip = Swift::Evaluator.get_ip_by_type(node, :public_ip_expr)


### 
# bucket to collect all the config items that end up in the proxy config template
proxy_config = {}
proxy_config[:auth_method] = node[:swift][:auth_method]
proxy_config[:group] = node[:swift][:group]
proxy_config[:user] = node[:swift][:user]
proxy_config[:local_ip] = local_ip
proxy_config[:public_ip] = public_ip
proxy_config[:hide_auth] = false


%w{curl python-software-properties memcached swift-proxy}.each do |pkg|
  package pkg do
    action :install
  end 
end


case proxy_config[:auth_method]
   when "swauth"
     package "python-swauth" do
       action :install
     end 
     proxy_config[:admin_key] =node[:swift][:cluster_admin_pw]
     proxy_config[:account_management] = node[:swift][:account_management]

   when "keystone" 
     package "python-keystone" do
       action :install
     end 
  
     env_filter = " AND keystone_config_environment:keystone-config-#{node[:swift][:keystone_instance]}"
     keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
     if keystones.length > 0
       keystone = keystones[0]
     else
       keystone = node
     end

     keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
     keystone_token = keystone["keystone"]["admin"]['token']    rescue nil
     keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
     keystone_admin_port = keystone["keystone"]["api"]["admin_port"] rescue nil

     Chef::Log.info("Keystone server found at #{keystone_address}")
     proxy_config[:keystone_admin_token]  = keystone_token
     proxy_config[:keystone_vip] = keystone_address
     proxy_config[:keystone_port] = keystone_admin_port
     proxy_config[:reseller_prefix] = node[:swift][:reseller_prefix]

     keystone_register "register swift service" do
       host keystone_address
       token keystone_token
       port keystone_admin_port
       service_name "swift"
       service_type "object-store"
       service_description "Openstack Swift Object Store Service"
       action :add_service
     end                                                 

     keystone_register "register swift-proxy endpoint" do
         host keystone_address
         token keystone_token
         port keystone_admin_port
         endpoint_service "swift"
         endpoint_region "RegionOne"
         endpoint_adminURL "https://#{local_ip}:8080/v1/AUTH_%tenant_id%"
         endpoint_internalURL "https://#{local_ip}:/v1/AUTH_%tenant_id%"
         endpoint_publicURL "https://#{public_ip}:8080/v1/AUTH_%tenant_id%"
         #  endpoint_global true
         #  endpoint_enabled true
        action :add_endpoint_template
    end


   when "tempauth"
     ## uses defaults...
   end
                  

######
# extract some keystone goodness
## note that trying to use the <bash> resource fails in odd ways...
execute "create auth cert" do
  cwd "/etc/swift"
  creates "/etc/swift/cert.crt"
  group node[:swift][:group]
  user node[:swift][:user]
  command <<-EOH
  /usr/bin/openssl req -new -x509 -nodes -out cert.crt -keyout cert.key -batch &>/dev/null 0</dev/null
  EOH
  not_if  {::File.exist?("/etc/swift/cert.crt") } 
end

## Find other nodes that are swift-auth nodes, and make sure 
## we use their memcached!
servers =""
env_filter = " AND swift_config_environment:#{node[:swift][:config][:environment]}"
result= search(:node, "(roles:swift-proxy OR roles:swift-proxy-acct) #{env_filter}")
if !result.nil? and (result.length > 0)  
  memcached_servers = result.map {|x|
    s = Swift::Evaluator.get_ip_by_type(x, :admin_ip_expr)     
    s += ":11211 "   
  }
  log("memcached servers" + memcached_servers.join(",")) {level :debug}
  servers = memcached_servers.join(",")
else 
  log("found no swift-proxy nodes") {level :warn}
end
proxy_config[:memcached_ips] = servers



## Create the proxy server configuraiton file
template "/etc/swift/proxy-server.conf" do
  source     "proxy-server.conf.erb"
  mode       "0644"
  group       node[:swift][:group]
  owner       node[:swift][:user]
  variables   proxy_config
end

## install a default memcached instsance.
## default configuration is take from: node[:memcached] / [:memory], [:port] and [:user] 
node[:memcached][:listen] = local_ip
node[:memcached][:name] = "swift-proxy"
memcached_instance "swift-proxy" do
end


service "swift-proxy" do
  restart_command "/etc/init.d/swift-proxy stop ; /etc/init.d/swift-proxy start"
  action [:enable, :start]
end

bash "restart swift proxy things" do
  code <<-EOH
EOH
  action :run
  notifies :restart, resources(:service => "memcached-swift-proxy")
  notifies :restart, resources(:service => "swift-proxy")
end

### 
# let the monitoring tools know what services should be running on this node.
node[:swift][:monitor] = {}
node[:swift][:monitor][:svcs] = ["swift-proxy", "memcached" ]
node[:swift][:monitor][:ports] = {:proxy =>8080}
node.save

##
# only run slog init code if enabled, and the proxy has been fully setup
#(after the storage nodes have come up as well)
if node["swift"]["use_slog"] and node["swift"]["proxy_init_done"]
  log ("installing slogging") {level :info}
  include_recipe "swift::slog"
end

node["swift"]["proxy_init_done"] = true
