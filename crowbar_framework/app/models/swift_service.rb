# Copyright 2011, Dell 
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
require 'chef'

class SwiftService < ServiceObject

  def initialize(thelogger)
    @bc_name = "swift"
    @logger = thelogger
  end

  def self.allow_multiple_proposals?
    true
  end

  def proposal_dependencies(role)
    answer = []
    if role.default_attributes["swift"]["auth_method"] == "keystone"
      answer << { "barclamp" => "keystone", "inst" => role.default_attributes["swift"]["keystone_instance"] }
    end
    answer
  end

  def create_proposal
    base = super

    rand_d = rand(100000)    
    base[:attributes][:swift][:cluster_hash] = "%x" % rand_d
    
    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }


    base["attributes"]["swift"]["keystone_instance"] = ""
    base["attributes"]["swift"]["auth_method"] = "swauth"
    begin
      keystoneService = KeystoneService.new(@logger)
      keystones = keystoneService.list_active[1]
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals[1]
      end
      if !keystones.empty?
	base["attributes"]["swift"]["keystone_instance"] = keystones[0]
        base["attributes"]["swift"]["auth_method"] = "keystone"
      end
    rescue
      @logger.info("Swift create_proposal: no keystone found - will use swauth")
    end


    base["deployment"]["swift"]["elements"] = {
        "swift-proxy" => [  ],
        "swift-ring-compute" => [  ],
        "swift-storage" => []
    }

    if nodes.size == 1
      base["deployment"]["swift"]["elements"] = {
        "swift-proxy-acct" => [ nodes.first[:fqdn] ],
        "swift-ring-compute" => [ nodes.first[:fqdn] ],
        "swift-storage" => [ nodes.first[:fqdn] ]
      }
    elsif nodes.size > 1
      head = nodes.shift
      base["deployment"]["swift"]["elements"] = {
        "swift-proxy-acct" => [ head[:fqdn] ],
        "swift-ring-compute" => [ head[:fqdn] ],
        "swift-storage" => nodes.map { |x| x[:fqdn] }
      }
    end

    @logger.fatal("swift create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Swift apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Make sure that the front-end pieces have public ip addreses.
    net_svc = NetworkService.new @logger
    [ "swift-proxy", "swift-proxy-acct" ].each do |element|
      tnodes = role.override_attributes["swift"]["elements"][element]
      next if tnodes.nil? or tnodes.empty?
      tnodes.each do |n|
        next if n.nil?
        net_svc.allocate_ip "default", "public", "host", n
      end
    end

    all_nodes.each do |n|
      net_svc.allocate_ip "default", "storage", "host", n
    end
    @logger.debug("Swift apply_role_pre_chef_call: leaving")
  end

  def validate_proposal_after_save proposal
    super

    errors = []

    if proposal["attributes"]["swift"]["replicas"] <= 0
      errors << "Need at least 1 replica."
    end

    elements = proposal["deployment"]["swift"]["elements"]

    if not elements.has_key?("swift-storage") or elements["swift-storage"].length < 1
      errors << "Need at least one swift-storage node."
    else

      if elements["swift-storage"].length < proposal["attributes"]["swift"]["zones"]
        if elements["swift-storage"].length == 1
          errors << "Need at least as many swift-storage nodes as zones; only #{elements["swift-storage"].length} swift-storage node was set for #{proposal["attributes"]["swift"]["zones"]} zones."
        else
          errors << "Need at least as many swift-storage nodes as zones; only #{elements["swift-storage"].length} swift-storage nodes were set for #{proposal["attributes"]["swift"]["zones"]} zones."
        end
      end

      elements["swift-storage"].each do |n|
        node = NodeObject.find_node_by_name(n)

        roles = node.roles()
        ["ceph-store", "nova-multi-controller"].each do |role|
          if roles.include?(role)
            errors << "Node #{n} already has the #{role} role; nodes cannot have both swift-storage and #{role} roles."
          end
        end

        usable_disks = 0
        all_disks = eval(proposal["attributes"]["swift"]["disk_enum_expr"])

        all_disks.each do |k,v|
          usable_disks += 1 if eval(proposal["attributes"]["swift"]["disk_test_expr"])
        end

        if usable_disks == 0
          errors << "Node #{n} does not have any additional disk; swift-storage nodes need at least one."
        end
      end

    end

    if errors.length > 0
      raise Chef::Exceptions::ValidationFailed.new(errors.join("\n"))
    end
  end

end

