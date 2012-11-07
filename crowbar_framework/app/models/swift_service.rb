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
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end
    answer
  end

  def create_proposal
    base = super

    rand_d = rand(100000)    
    base[:attributes][:swift][:cluster_hash] = "%x" % rand_d
    
    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }

    base["attributes"][@bc_name]["git_instance"] = ""
    begin
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1]
      if gits.empty?
        # No actives, look for proposals
        gits = gitService.proposals[1]
      end
      unless gits.empty?
        base["attributes"][@bc_name]["git_instance"] = gits[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no git found")
    end

    base["attributes"]["swift"]["keystone_instance"] = ""
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
    base["attributes"]["swift"]["keystone_service_password"] = '%012d' % rand(1e12)


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

end

