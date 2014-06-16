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

swift_path = "/opt/swift"
venv_path = node[:swift][:use_virtualenv] ? "#{swift_path}/.venv" : nil

unless node[:swift][:use_gitrepo]
  package "curl"

  case node[:platform]
  when "suse", "centos", "redhat"
    package "openstack-swift"
  else
    package "swift"
  end

else

  ["/etc/swift", "/var/run/swift"].each do |d|
    directory d do
      owner node[:swift][:user]
      group node[:swift][:group]
      mode "0755"
    end
  end

  directory "/var/cache/swift" do
    owner node[:swift][:user]
    group node[:swift][:group]
    mode "0700"
  end

  pfs_and_install_deps @cookbook_name do
    path swift_path
    virtualenv venv_path
    wrap_bins [ "swift", "swift-dispersion-report", "swift-dispersion-populate" ]
  end

  create_user_and_dirs(@cookbook_name) do
    user_name node[:swift][:user]
    dir_group node[:swift][:group]
  end
end

template "/etc/swift/swift.conf" do
  owner node[:swift][:user]
  group node[:swift][:group]
  source "swift.conf.erb"
 variables( {
       :swift_cluster_hash => node[:swift][:cluster_hash]
 })
end

rsyslog_version = `rsyslogd -v | head -1 | sed -e "s/^rsyslogd \(.*\), .*$/\1/"`
# log swift components into separate log files
template "/etc/rsyslog.d/11-swift.conf" do
  source     "11-swift.conf.erb"
  mode       "0755"
  group       node[:swift][:group]
  owner       node[:swift][:user]
  variables(:rsyslog_version => rsyslog_version)
  only_if     { node[:platform] == "suse" } # other distros might not have /var/log/swift
end
