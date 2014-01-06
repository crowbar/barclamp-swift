# Copyright 2013, Dell 
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

class BarclampSwift::Barclamp < Barclamp
  class ServiceError < StandardError
  end

  def initialize(thelogger)
    @bc_name = "swift"
    @logger = thelogger
  end

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  def proposal_dependencies(role)
    answer = []
    hash = new_config.config_hash
    if hash["swift"]["auth_method"] == "keystone"
      answer << { "barclamp" => "keystone", "inst" => hash["swift"]["keystone_instance"] }
    end
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end
    answer
  end

  def create_proposal(name)
    base = super(name)

    hash = base.config_hash

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
      base["deployment"]["swift"]["elements"] = {
        "swift-proxy" => [ nodes.first[:fqdn] ],
        "swift-dispersion" => [ nodes.first[:fqdn] ],
        "swift-ring-compute" => [ nodes.first[:fqdn] ],
        "swift-storage" => [ nodes.first[:fqdn] ]
      }
    elsif nodes.size > 1
      head = nodes.shift
      base["deployment"]["swift"]["elements"] = {
        "swift-dispersion" => [ head[:fqdn] ],
        "swift-proxy" => [ head[:fqdn] ],
        "swift-ring-compute" => [ head[:fqdn] ],
        "swift-storage" => nodes.map { |x| x[:fqdn] }
      }
    end

    @logger.fatal("swift create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_config, new_config, all_nodes)
    @logger.debug("Swift apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Make sure that the front-end pieces have public ip addreses.
    net_svc = NetworkService.new @logger
    tnodes = role.override_attributes["swift"]["elements"]["swift-proxy"]
    tnodes.each do |n|
      next if n.nil?
      net_svc.allocate_ip "default", "public", "host", n
    end

    all_nodes.each do |n|
      net_svc.allocate_ip "default", "storage", "host", n.name
    end
    @logger.debug("Swift apply_role_pre_chef_call: leaving")
  end

  def get_report_run_by_uuid(uuid)
    get_dispersion_reports.each do |r|
        return r if r['uuid'] == uuid
    end
    nil
  end

  def self.get_all_nodes_hash
    Hash[ NodeObject.find_all_nodes.map {|n| [n.name, n]} ]
  end

  def get_ready_nodes
    nodes = get_ready_proposals.collect { |p| p.elements["#{@bc_name}-dispersion"] }.flatten
    NodeObject.find_all_nodes.select { |n| nodes.include?(n.name) and n.ready? }
  end

  def get_ready_proposals
    ProposalObject.find_proposals(@bc_name).select {|p| p.status == 'ready'}.compact
  end

  def _get_or_create_db
    db = ProposalObject.find_data_bag_item "crowbar/swift"
    if db.nil?
      begin
        lock = acquire_lock @bc_name
      
        db_item = Chef::DataBagItem.new
        db_item.data_bag "crowbar"
        db_item["id"] = "swift"
        db_item["dispersion_reports"] = []
        db = ProposalObject.new db_item
        db.save
      ensure
        release_lock lock
      end
    end
    db
  end

  def get_dispersion_reports
    _get_or_create_db["dispersion_reports"]
  end

  def clear_dispersion_reports
    def delete_file(file_name)
      File.delete(file_name) if File.exist?(file_name)
    end

    def process_exists(pid)
      begin
        Process.getpgid( pid )
        true
      rescue Errno::ESRCH
        false
      end
    end

    swift_db = _get_or_create_db

    @logger.info('cleaning out report runs and results')
    swift_db['dispersion_reports'].delete_if do |report_run|
      if report_run['status'] == 'running'
        if report_run['pid'] and not process_exists(report_run['pid'])
          @logger.warn("running dispersion run #{report_run['uuid']} seems to be stale")
        elsif Time.now.utc.to_i - report_run['started'] > 60 * 60 * 4 # older than 4 hours
          @logger.warn("running dispersion run #{report_run['uuid']} seems to be outdated, started at #{Time.at(report_run['started']).to_s}")
        else
          @logger.debug("omitting running dispersion run #{report_run['uuid']} while cleaning")
          next
        end
      else
        delete_file(report_run['results.html'])
        delete_file(report_run['results.json'])
      end
      @logger.debug("removing dispersion run #{report_run['uuid']}")
      true
    end

    lock = acquire_lock(@bc_name)
    swift_db.save
    release_lock(lock)
  end

  def run_report(node)
    raise "unable to look up a #{@bc_name} proposal applied to #{node.inspect}" if (proposal = _get_proposal_by_node node).nil?
    
    report_run_uuid = `uuidgen`.strip
    report_run = { 
      "uuid" => report_run_uuid, "started" => Time.now.utc.to_i, "ended" => nil, "pid" => nil,
      "status" => "running", "node" => node, "results.json" => "log/#{report_run_uuid}.json",
      "results.html" => "log/#{report_run_uuid}.html"}

    swift_db = _get_or_create_db

    swift_db['dispersion_reports'].each do |dr|
      raise ServiceError, I18n.t("barclamp.#{@bc_name}.run.duplicate") if dr['node'] == node and dr['status'] == 'running'
    end

    lock = acquire_lock(@bc_name)
    swift_db["dispersion_reports"] << report_run
    swift_db.save
    release_lock(lock)

    nobj = NodeObject.find_node_by_name(node)
    swift_user = nobj[@bc_name]["user"]
    @logger.info("starting dispersion-report on node #{node}, report run uuid #{report_run['uuid']}")

    pid = fork do
      command_line = "sudo -u #{swift_user} EVENTLET_NO_GREENDNS=yes swift-dispersion-report -j 2>/dev/null"
      Process.waitpid run_remote_chef_client(node, command_line, report_run["results.json"])

      report_run["ended"] = Time.now.utc.to_i
      report_run["status"] = $?.exitstatus.equal?(0) ? "passed" : "failed"
      report_run["pid"] = nil 

      lock = acquire_lock(@bc_name)
      swift_db.save
      release_lock(lock)

      @logger.info("report run #{report_run['uuid']} complete, status '#{report_run['status']}'")
    end
    Process.detach pid

    # saving the PID to prevent 
    report_run['pid'] = pid
    lock = acquire_lock(@bc_name)
    swift_db.save
    release_lock(lock)
    report_run
  end

  def _get_proposal_by_node(node)
    get_ready_proposals.each do |p|
      return p if p.elements["#{@bc_name}-dispersion"].include? node
    end
    nil
  end

  def validate_proposal_after_save proposal
    super

    if proposal["attributes"][@bc_name]["use_gitrepo"]
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1].to_a
      if not gits.include?proposal["attributes"][@bc_name]["git_instance"]
        raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "git"))
      end
    end

    errors = []

    if proposal["attributes"]["swift"]["replicas"] <= 0
      errors << "Need at least 1 replica"
    end

    elements = proposal["deployment"]["swift"]["elements"]

    if not elements.has_key?("swift-storage") or elements["swift-storage"].length < 1
      errors << "Need at least one swift-storage node"
    end

    if elements["swift-storage"].length < proposal["attributes"]["swift"]["zones"]
      if elements["swift-storage"].length == 1
        errors << "Need at least as many swift-storage nodes as zones; only #{elements["swift-storage"].length} swift-storage node was set for #{proposal["attributes"]["swift"]["zones"]} zones"
      else
        errors << "Need at least as many swift-storage nodes as zones; only #{elements["swift-storage"].length} swift-storage nodes were set for #{proposal["attributes"]["swift"]["zones"]} zones"
      end
    end

    if errors.length > 0
      raise Chef::Exceptions::ValidationFailed.new(errors.join("\n"))
    end
  end

end

