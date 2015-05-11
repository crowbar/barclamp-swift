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

package "curl"

case node[:platform]
when "suse", "centos", "redhat"
  package "openstack-swift"
else
  package "swift"
end

template "/etc/swift/swift.conf" do
  owner "root"
  group node[:swift][:group]
  source "swift.conf.erb"
 variables( {
       :swift_cluster_hash => node[:swift][:cluster_hash]
 })
end

rsyslog_version = `rsyslogd -v | head -1 | sed -e "s/^rsyslogd \\(.*\\), .*$/\\1/"`
# log swift components into separate log files
template "/etc/rsyslog.d/11-swift.conf" do
  source     "11-swift.conf.erb"
  mode       "0644"
  variables(:rsyslog_version => rsyslog_version)
  notifies   :restart, "service[rsyslog]"
  only_if    { node[:platform] == "suse" } # other distros might not have /var/log/swift
end
