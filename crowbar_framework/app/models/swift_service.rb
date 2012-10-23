# Copyright 2012, Dell 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class SwiftService < ServiceObject

  def proposal_dependencies(new_config)
    answer = []
    hash = new_config.config_hash
    if hash["swift"]["auth_method"] == "keystone"
      answer << { "barclamp" => "keystone", "inst" => hash["swift"]["keystone_instance"] }
    end
    answer
  end

  def create_proposal(name)
    base = super(name)

    hash = base.config_hash

    rand_d = rand(100000)    
    hash["swift"][:cluster_hash] = "%x" % rand_d

    hash["swift"]["keystone_instance"] = ""
    begin
      keystoneService = Barclamp.find_by_name("keystone")
      keystones = keystoneService.active_proposals
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals
      end
      if !keystones.empty?
        hash["swift"]["keystone_instance"] = keystones[0]
        hash["swift"]["auth_method"] = "keystone"
      end
    rescue
      @logger.info("Swift create_proposal: no keystone found - will use swauth")
    end
    hash["swift"]["keystone_service_password"] = '%012d' % rand(1e12)
    base.config_hash = hash

    nodes = Node.all
    nodes.delete_if { |n| n.nil? or n.is_admin? }

    if nodes.size == 1
      add_role_to_instance_and_node(nodes.first.name, base.name, "swift-proxy-acct")
      add_role_to_instance_and_node(nodes.first.name, base.name, "swift-ring-compute")
      add_role_to_instance_and_node(nodes.first.name, base.name, "swift-storage")
    elsif nodes.size > 1
      head = nodes.shift
      add_role_to_instance_and_node(head.name, base.name, "swift-proxy-acct")
      add_role_to_instance_and_node(head.name, base.name, "swift-ring-compute")
      nodes.each do |node|
        add_role_to_instance_and_node(node.name, base.name, "swift-storage")
      end
    end

    @logger.fatal("swift create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_config, new_config, all_nodes)
    @logger.debug("Swift apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Make sure that the front-end pieces have public ip addreses.
    net_svc = Barclamp.find_by_name("network").operations(@logger)
    [ "swift-proxy", "swift-proxy-acct" ].each do |element|
      tnodes = new_config.get_nodes_by_role(element)
      next if tnodes.nil? or tnodes.empty?
      tnodes.each do |n|
        next if n.nil?
        net_svc.allocate_ip "default", "public", "host", n.name
      end
    end

    all_nodes.each do |n|
      net_svc.allocate_ip "default", "storage", "host", n.name
    end
    @logger.debug("Swift apply_role_pre_chef_call: leaving")
  end

end

