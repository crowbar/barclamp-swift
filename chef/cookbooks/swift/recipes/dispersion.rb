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

# Note: if we're swift-ring-compute/swift-storage/swift-proxy, we're supposed
# to have the rings before we run dispersion. If we don't, then it simply means
# we're not at the point where we can do dispersion, and the last chef-client
# run for dispersion will be used instead.
if (node.roles.include?("swift-ring-compute") || node.roles.include?("swift-storage") || node.roles.include?("swift-proxy")) && !(::File.exists? "/etc/swift/object.ring.gz")
  Chef::Log.info("Not proceeding with dispersion yet; waiting for the rings.")
  return
end

if node.roles.include?("swift-storage") && !node["swift"]["storage_init_done"]
  Chef::Log.info("Not proceeding with dispersion yet; swift-{account,container,object} have not been setup yet.")
  return
end

if node.roles.include?("swift-proxy") && !node["swift"]["proxy_init_done"]
  Chef::Log.info("Not proceeding with dispersion yet; swift-proxy has not been setup yet.")
  return
end

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

service_tenant = node[:swift][:dispersion][:service_tenant]
service_user = node[:swift][:dispersion][:service_user]
service_password = node[:swift][:dispersion][:service_password]

keystone_register "swift dispersion wakeup keystone" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  action :wakeup
end

keystone_register "create tenant #{service_tenant} for dispersion" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  tenant_name service_tenant
  action :add_tenant
end

keystone_register "add #{service_user}:#{service_tenant} user" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name service_user
  user_password service_password
  tenant_name service_tenant
  action :add_user
end

keystone_register "add #{service_user}:#{service_tenant} user admin role" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name service_user
  role_name "admin"
  tenant_name service_tenant
  action :add_access
end

dispersion_cmd="swift-dispersion-populate"
if keystone_settings['insecure']
  swift_cmd="swift --insecure"
else
  swift_cmd="swift"
end

template "/etc/swift/dispersion.conf" do
  source     "dispersion.conf.erb"
  mode       "0640"
  owner       "root"
  group       node[:swift][:group]
  variables(
    :keystone_settings => keystone_settings
  )
  #only_if "swift-recon --md5 | grep -q '0 error'"
  #notifies :run, "execute[populate-dispersion]", :immediately
end

execute "populate-dispersion" do
  command "#{dispersion_cmd}"
  user node[:swift][:user]
  action :run
  ignore_failure true
  only_if "#{swift_cmd} -V 2.0 --os-tenant-name #{service_tenant} --os-username #{service_user} --os-password '#{service_password}' --os-auth-url #{keystone_settings['admin_auth_url']} --os-endpoint-type internalURL stat dispersion_objects 2>&1 | grep 'Container.*not found'"
end
