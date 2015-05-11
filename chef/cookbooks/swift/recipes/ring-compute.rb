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

if node.roles.include?("swift-storage") && node[:swift][:devs].nil?
  # We can safely return here because if we're a storage node and have no
  # device yet, then it simply means that we haven't looked for devices yet. It
  # cannot mean that we just have no devices because we raise an exception in
  # that case (see disks recipe).
  Chef::Log.info("Not proceeding with ring compute yet; this chef run is only used to find disks on storage nodes.")
  return
end

include_recipe 'swift::rsync'

env_filter = " AND swift_config_environment:#{node[:swift][:config][:environment]}"

##
# Assumptions:
#  - The partitions to be used on each node are in node[:swift][:devs]
#  - only nodes which have the swift-storage role assigned are used.

=begin
  http://swift.openstack.org/howto_installmultinode.html

swift-ring-builder account.builder add z$ZONE-$STORAGE_LOCAL_NET_IP:6002/$DEVICE $WEIGHT
swift-ring-builder container.builder add z$ZONE-$STORAGE_LOCAL_NET_IP:6001/$DEVICE $WEIGHT
swift-ring-builder object.builder add z$ZONE-$STORAGE_LOCAL_NET_IP:6000/$DEVICE $WEIGHT

      command  "swift-ring-builder object.builder add z#{zone}-#{storage_ip_addr}:6000/#{disk[:name]} #{weight}"
=end


## collect the nodes that need to be notified when ring files are updated
target_nodes = []

####
# collect the current contents of the ring files.
nodes = search(:node, "roles:swift-storage#{env_filter}")

disks_a = []
disks_c = []
disks_o = []

disk_assign_expr = node[:swift][:disk_zone_assign_expr]

nodes.each { |node|
  storage_ip = Swift::Evaluator.get_ip_by_type(node, :storage_ip_expr)
  log ("Looking at node: #{storage_ip}") {level :debug}

  target_nodes << storage_ip

  disks=node[:swift][:devs]
  next if disks.nil?

  disks.each {|uuid,disk|
    Chef::Log.info("Swift - considering #{node[:fqdn]}:#{disk[:name]}")
    next unless disk[:state] == "Operational"

    # we need at least node for which we trying to predict zone to avoid odd searching across chef by disk uuid
    z_o, w_o = Swift::Evaluator.eval_with_params(disk_assign_expr, node(), :ring => "object",    :disk => disk, :target_node => node)
    z_c, w_c = Swift::Evaluator.eval_with_params(disk_assign_expr, node(), :ring => "container", :disk => disk, :target_node => node)
    z_a, w_a = Swift::Evaluator.eval_with_params(disk_assign_expr, node(), :ring => "account",   :disk => disk, :target_node => node)

    log("obj: #{z_o}/#{w_o} container: #{z_c}/#{w_c} account: #{z_a}/#{w_a}. count: #{$DISK_CNT}") {level :info}

    d = {:ip => storage_ip, :dev_name=> disk[:name], :port => 6000}

    if z_o
      d[:port] = 6000; d[:zone] = z_o ; d[:weight] = w_o
      disks_o << d
    end
    if z_c
      d = d.dup
      d[:port] = 6001; d[:zone] = z_c ; d[:weight] = w_c
      disks_c << d
    end
    if z_a
      d = d.dup
      d[:port] = 6002; d[:zone] = z_a ; d[:weight] = w_a
      disks_a << d
    end
  }
}

hash = node[:swift][:cluster_hash]
min_move = node[:swift][:min_part_hours]
parts = node[:swift][:partitions]
replicas = node[:swift][:replicas]
zones = node[:swift][:zones]

log ("cluster config: replicas:#{replicas} zones:#{zones} hash:#{hash}")

swift_ringfile "account.builder" do
  disks disks_a
  replicas replicas
  min_part_hours min_move
  partitions parts
  action [:apply, :rebalance]
end
swift_ringfile "container.builder" do
  disks disks_c
  replicas replicas
  min_part_hours min_move
  partitions parts
  action [:apply, :rebalance]
end
swift_ringfile "object.builder" do
  disks disks_o
  replicas replicas
  min_part_hours min_move
  partitions parts
  action [:apply, :rebalance]
end

proxy_nodes = search(:node, "roles:swift-proxy#{env_filter}")
proxy_nodes.each do |p|
  storage_ip = Swift::Evaluator.get_ip_by_type(p, :storage_ip_expr)
  target_nodes << storage_ip
end

target_nodes.uniq!
Chef::Log.debug("nodes to notify: #{target_nodes.join ' '}")

builder_ip = Swift::Evaluator.get_ip_by_type(node, :storage_ip_expr)

target_nodes.each {|t|
  # No point in pushing it to ourselves
  next if t == builder_ip

  execute "push account ring-to #{t}" do
    command "rsync account.ring.gz #{node[:swift][:user]}@#{t}::ring"
    cwd "/etc/swift"
    ignore_failure true
    action :nothing
    subscribes :run, resources(:swift_ringfile =>"account.builder")
  end
  execute "push container ring-to #{t}" do
    command "rsync container.ring.gz #{node[:swift][:user]}@#{t}::ring"
    cwd "/etc/swift"
    ignore_failure true
    action :nothing
    subscribes :run, resources(:swift_ringfile =>"container.builder")
  end
  execute "push object ring-to #{t}" do
    command "rsync object.ring.gz #{node[:swift][:user]}@#{t}::ring"
    cwd "/etc/swift"
    ignore_failure true
    action :nothing
    subscribes :run, resources(:swift_ringfile =>"object.builder")
  end
}
