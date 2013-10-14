#
# Copyright 2012, Dell
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

env_filter = " AND keystone_config_environment:keystone-config-#{node[:swift][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
else
  keystone = node
end

keystone_host = keystone[:fqdn]
keystone_protocol = keystone["keystone"]["api"]["protocol"]
keystone_token = keystone["keystone"]["service"]["token"] rescue nil
keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
keystone_admin_port = keystone["keystone"]["api"]["admin_port"] rescue nil
keystone_insecure = keystone_protocol == 'https' && keystone[:keystone][:ssl][:insecure]

service_tenant = node[:swift][:dispersion][:service_tenant]
service_user = node[:swift][:dispersion][:service_user]
service_password = node[:swift][:dispersion][:service_password]
keystone_auth_url = "#{keystone_protocol}://#{keystone_host}:#{keystone_admin_port}/v2.0"

keystone_register "swift dispersion wakeup keystone" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  action :wakeup
end

keystone_register "create tenant #{service_tenant} for dispersion" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  tenant_name service_tenant
  action :add_tenant
end

keystone_register "add #{service_user}:#{service_tenant} user" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  user_name service_user
  user_password service_password
  tenant_name service_tenant 
  action :add_user
end

keystone_register "add #{service_user}:#{service_tenant} user admin role" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  user_name service_user
  role_name "admin"
  tenant_name service_tenant 
  action :add_access
end

if keystone_insecure
  swift_cmd="swift --insecure"
  ##swift-dispersion-populate is not support for passing "insecure" also, so actualy it wont work in case of self-signed certs
  dispersion_cmd="swift-dispersion-populate"
else
  swift_cmd="swift"
  dispersion_cmd="swift-dispersion-populate"
end

execute "populate-dispersion" do
  command "#{dispersion_cmd}"
  user node[:swift][:user]
  action :run
  ignore_failure true
  only_if "#{swift_cmd} -V 2.0 --os-tenant-name #{service_tenant} --os-username #{service_user} --os-password '#{service_password}' --os-auth-url #{keystone_auth_url} --os-endpoint-type internalURL stat dispersion_objects 2>&1 | grep 'Container.*not found'"
end

template "/etc/swift/dispersion.conf" do
  source     "disperse.conf.erb"
  mode       "0600"
  group       node[:swift][:group]
  owner       node[:swift][:user]
  variables(
    :auth_url => keystone_auth_url
  )
  #only_if "swift-recon --md5 | grep -q '0 error'"
  #notifies :run, "execute[populate-dispersion]", :immediately
end
