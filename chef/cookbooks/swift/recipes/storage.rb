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

skip_setup = node[:swift][:devs].nil?

include_recipe 'swift::disks'
#include_recipe 'swift::auth' 
# Note: we always want to setup rsync, even if we do not do anything else; this
# will allow the ring-compute node to push the rings.
include_recipe 'swift::rsync'

if skip_setup
  # If we have no device yet, then it simply means that we haven't looked for
  # devices yet, which also means that we won't have rings at this point in
  # time; we just need to discover the disks (with the recipes above).
  Chef::Log.info("Not setting up swift-{account,container,object} daemons; this chef run is only used to find disks.")
  return
end

if node.roles.include?("swift-ring-compute") && !(::File.exists? "/etc/swift/object.ring.gz")
  Chef::Log.info("Not setting up swift-{account,container,object} daemons; this chef run is only used to compute the rings.")
  return
end

case node[:platform]
when "suse", "centos", "redhat"
  %w{openstack-swift-container
     openstack-swift-object
     openstack-swift-account}.each do |pkg|
    package pkg do
      action :install
    end
  end
else
  %w{swift-container swift-object swift-account}.each do |pkg|
    pkg = "openstack-#{pkg}" if %w(redhat centos suse).include?(node.platform)
    package pkg do
      action :install
    end
  end
end

storage_ip = Swift::Evaluator.get_ip_by_type(node,:storage_ip_expr)

%w{account-server object-server container-server}.each do |service|
  template "/etc/swift/#{service}.conf" do
    source "#{service}.conf.erb"
    owner "root"
    group node[:swift][:group]
    variables({ 
      :uid => node[:swift][:user],
      :gid => node[:swift][:group],
      :storage_net_ip => storage_ip,
      :server_num => 1,  ## could allow multiple servers on the same machine
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
      user node[:swift][:user]
      group node[:swift][:group]
      command "rsync #{node[:swift][:user]}@#{compute_node_addr}::ring/#{ring}.ring.gz ."
      cwd "/etc/swift"
      ignore_failure true
    end
  }
    
  svcs.each { |x|
    ring = x.gsub("swift-", "").gsub(/-.*/, "")
    unless %w{container account object}.include? ring
      message = "Internal error: cannot find ring matching service \"#{x}\""
      Chef::Log.fatal(message)
      raise message
    end

    x = "openstack-#{x}" if %w(redhat centos suse).include?(node.platform)
    service x do
      if (platform?("ubuntu") && node.platform_version.to_f >= 10.04)
        restart_command "status #{x} 2>&1 | grep -q Unknown || restart #{x}"
        stop_command "stop #{x}"
        start_command "start #{x}"
        status_command "status #{x} | cut -d' ' -f2 | cut -d'/' -f1 | grep start"
      end
      supports :status => true, :restart => true
      action [:enable, :start]
      subscribes :restart, resources(:template => "/etc/swift/swift.conf")
      subscribes :restart, resources(:template => "/etc/swift/#{ring}-server.conf")
      only_if { ::File.exists? "/etc/swift/#{ring}.ring.gz" }
    end
  }
end

node["swift"]["storage_init_done"] = true

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
