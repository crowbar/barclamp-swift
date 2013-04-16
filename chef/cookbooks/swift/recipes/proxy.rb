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
### middleware items
proxy_config[:clock_accuracy] = node[:swift][:middlewares][:ratelimit][:clock_accuracy]
proxy_config[:max_sleep_time_seconds] = node[:swift][:middlewares][:ratelimit][:max_sleep_time_seconds]
proxy_config[:log_sleep_time_seconds] = node[:swift][:middlewares][:ratelimit][:log_sleep_time_seconds]
proxy_config[:rate_buffer_seconds] = node[:swift][:middlewares][:ratelimit][:rate_buffer_seconds]
proxy_config[:account_ratelimit] = node[:swift][:middlewares][:ratelimit][:account_ratelimit]
proxy_config[:account_whitelist] = node[:swift][:middlewares][:ratelimit][:account_whitelist]
proxy_config[:account_blacklist] = node[:swift][:middlewares][:ratelimit][:account_blacklist]
proxy_config[:container_ratelimit_size] = node[:swift][:middlewares][:ratelimit][:container_ratelimit_size]
proxy_config[:lookup_depth] = node[:swift][:middlewares][:cname_lookup][:lookup_depth]
proxy_config[:storage_domain] = node[:swift][:middlewares][:cname_lookup][:storage_domain]
proxy_config[:storage_domain_remap] = node[:swift][:middlewares][:domain_remap][:storage_domain]
proxy_config[:path_root] = node[:swift][:middlewares][:domain_remap][:path_root]

%w{curl memcached python-dnspython}.each do |pkg|
  package pkg do
    action :install
  end 
end
package("swift-proxy") unless node[:swift][:use_gitrepo]

if node[:swift][:middlewares][:s3][:enabled]
  if node[:swift][:middlewares][:s3][:use_gitrepo]
    s3_path = "/opt/swift3"
    pfs_and_install_deps("swift3") do
      path s3_path
      reference node[:swift][:middlewares][:s3][:git_refspec]
      without_setup true
    end
    execute "setup_swift3" do
      cwd s3_path
      command "python setup.py develop"
      creates "#{s3_path}/swift3.egg-info"
    end
  else
    package("swift-plugin-s3")
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

     env_filter = " AND keystone_config_environment:keystone-config-#{node[:swift][:keystone_instance]}"
     keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
     if keystones.length > 0
       keystone = keystones[0]
     else
       keystone = node
     end

     unless node[:swift][:use_gitrepo]
       package "python-keystone" do
         action :install
       end 
     else
       if node[:swift][:use_virtualenv]
         pfs_and_install_deps "keystone" do
           cookbook "keystone"
           cnode keystone
           path "/opt/swift/keystone"
           virtualenv "/opt/swift/.venv"
         end
       else
         pfs_and_install_deps "keystone" do
           cookbook "keystone"
           cnode keystone
         end
       end
     end
     
     keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
     keystone_token = keystone["keystone"]["service"]["token"] rescue nil
     keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
     keystone_admin_port = keystone["keystone"]["api"]["admin_port"] rescue nil
     keystone_service_tenant = keystone["keystone"]["service"]["tenant"] rescue nil
     keystone_service_user = node["swift"]["keystone_service_user"]
     keystone_service_password = node["swift"]["keystone_service_password"]

     Chef::Log.info("Keystone server found at #{keystone_address}")
     proxy_config[:keystone_admin_token]  = keystone_token
     proxy_config[:keystone_vip] = keystone_address
     proxy_config[:keystone_admin_port] = keystone_admin_port
     proxy_config[:keystone_service_port] = keystone_service_port
     proxy_config[:keystone_service_port] = keystone_service_port
     proxy_config[:keystone_service_tenant] = keystone_service_tenant
     proxy_config[:keystone_service_user] = keystone_service_user
     proxy_config[:keystone_service_password] = keystone_service_password
     proxy_config[:reseller_prefix] = node[:swift][:reseller_prefix]

     keystone_register "register swift user" do
       host keystone_address
       port keystone_admin_port
       token keystone_token
       user_name keystone_service_user
       user_password keystone_service_password
       tenant_name keystone_service_tenant
       action :add_user
     end

     keystone_register "give swift user access" do
       host keystone_address
       port keystone_admin_port
       token keystone_token
       user_name keystone_service_user
       tenant_name keystone_service_tenant
       role_name "admin"
       action :add_access
     end

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
         endpoint_publicURL "https://#{public_ip}:8080/v1/#{node[:swift][:reseller_prefix]}$(tenant_id)s"
         endpoint_adminURL "https://#{local_ip}:8080/v1/"
         endpoint_internalURL "https://#{local_ip}:8080/v1/#{node[:swift][:reseller_prefix]}$(tenant_id)s"
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
  /usr/bin/openssl req -new -x509 -days 365 -nodes -out cert.crt -keyout cert.key -batch &>/dev/null 0</dev/null
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

venv_path = node[:swift][:use_virtualenv] ? "/opt/swift/.venv" : nil

if node[:swift][:frontend]=='native'
  if node[:swift][:use_gitrepo]
    swift_service "swift-proxy" do
      virtualenv venv_path
    end
  end
  service "swift-proxy" do
    restart_command "stop swift-proxy ; start swift-proxy"
    action [:enable, :start]
  end
elsif node[:swift][:frontend]=='apache'

  service "swift-proxy" do
    supports :status => true, :restart => true
    action [ :disable, :stop ]
    ignore_failure true
  end


  %w{nginx-extras uwsgi uwsgi-plugin-python}.each do |pkg|
    package pkg do
      action :install
    end
  end
  service "nginx" do
    supports :status => true, :restart => true
    action [ :start, :enable ]
  end
  service "uwsgi" do
    supports :status => true, :restart => true
    action [ :start, :enable ]
  end


  file "/etc/nginx/sites-enabled/default" do
    action :delete
    notifies :restart, resources(:service => "nginx")
  end

  template "/etc/nginx/sites-enabled/swift-proxy.conf" do
    source "nginx-swift-proxy.conf.erb"
    mode 0644
    notifies :restart, resources(:service => "nginx")
    variables(
      :port => 8080
    )
  end

  directory "/usr/lib/cgi-bin/swift/" do
    owner "swift"
    mode 0755
    action :create
    recursive true
  end

  template "/usr/lib/cgi-bin/swift/proxy.py" do
    source "swift-uwsgi-service.py.erb"
    mode 0755
    variables(
      :service => "proxy"
    )
    notifies :restart, resources(:service => "uwsgi")
  end

  template "/usr/share/uwsgi/conf/default.ini" do
    source "uwsgi-default.ini.erb"
    mode 0644
    variables(
      :uid => "swift",
      :gid => "www-data",
      :workers => 5
    )
    notifies :restart, resources(:service => "uwsgi")
  end
  template "/etc/uwsgi/apps-enabled/swift-proxy.xml" do
    source "uwsgi-swift-proxy.xml.erb"
    mode 0644
    variables(
      :uid => "swift",
      :gid => "www-data",
      :processes => 4,
      :virtualenv => venv_path
    )
    notifies :restart, resources(:service => "uwsgi")
  end
end

bash "restart swift proxy things" do
  code <<-EOH
EOH
  action :run
  notifies :restart, resources(:service => "memcached-swift-proxy")
  if node[:swift][:frontend]=='native'
    notifies :restart, resources(:service => "swift-proxy")
  end
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
