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

include_recipe 'swift::disks'
#include_recipe 'swift::auth' 
include_recipe 'swift::rsync'

%w{ sqlite }.each do |pkg|
  package pkg do
    action :upgrade
  end
end

%w{swift-container swift-object swift-account}.each do |pkg|
  pkg = "openstack-#{pkg}" if node[:platform] == "suse"
  package pkg do
    action :upgrade
  end
end

storage_ip = Swift::Evaluator.get_ip_by_type(node,:storage_ip_expr)

%w{account-server object-server container-server}.each do |service|
  directory "/etc/swift/#{service}" do
    owner "swift"
    group "swift"
    action :create
  end
  
  template "/etc/swift/#{service}/#{service}.conf" do
    source "#{service}-conf.erb"
    owner "openstack-swift"
    group "openstack-swift"
    variables({ 
      :uid => node[:swift][:user],
      :gid => node[:swift][:group],
      :storage_net_ip => storage_ip,
      :server_num => 1,  ## could allow multiple servers on the same machine
      :admin_key => node[:swift][:cluster_admin_pw],
      :debug => node[:swift][:debug]      
    })    
  end
end


svcs = %w{swift-object swift-object-auditor swift-object-replicator swift-object-updater} 
svcs = svcs + %w{swift-container swift-container-auditor swift-container-replicator swift-container-updater}
svcs = svcs + %w{swift-account swift-account-reaper swift-account-auditor swift-account-replicator}

## make sure to fetch ring files from the ring compute node
env_filter = " AND swift_config_environment:#{node[:swift][:config][:environment]}"
compute_nodes = search(:node, "roles:swift-ring-compute#{env_filter}")
if (!compute_nodes.nil? and compute_nodes.length > 0 )
  compute_node_addr  = Swift::Evaluator.get_ip_by_type(compute_nodes[0],:storage_ip_expr)
  log("ring compute found on: #{compute_nodes[0][:fqdn]} using: #{compute_node_addr}") {level :debug}  
  %w{container account object}.each { |ring| 
    execute "pull #{ring} ring" do
      command "rsync #{node[:swift][:user]}@#{compute_node_addr}::ring/#{ring}.ring.gz ."
      cwd "/etc/swift"
      ignore_failure true
    end
  }
    
  svcs.each { |x| 
    x = "openstack-#{x}" if node[:platform] == "suse"
    service x do
      if (platform?("ubuntu") && node.platform_version.to_f >= 10.04)
        restart_command "status #{x} 2>&1 | grep -q Unknown || restart #{x}"
        stop_command "stop #{x}"
        start_command "start #{x}"
        status_command "status #{x} | cut -d' ' -f2 | cut -d'/' -f1 | grep start"
      end
      supports :status => true, :restart => true
      action [:enable, :start]
    end
  }
end
  
  
### 
# let the monitoring tools know what services should be running on this node.
node[:swift][:monitor] = {}
node[:swift][:monitor][:svcs] = svcs
node[:swift][:monitor][:ports] = {:object =>6000, :container =>6001, :account =>6002}
node.save


if node["swift"]["use_slog"]
  log ("installing slogging") {level :info}
  include_recipe "swift::slog"
end
