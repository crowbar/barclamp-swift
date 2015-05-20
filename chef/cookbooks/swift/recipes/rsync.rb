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

# This is referenced by rsyncd.conf and not part of the packages (since
# /var/run is volatile)
directory "/var/run/swift" do
  owner node[:swift][:user]
  group node[:swift][:group]
  mode 0755
  action :create
end

storage_ip = Swift::Evaluator.get_ip_by_type(node,:storage_ip_expr)
template "/etc/rsyncd.conf" do
  source "rsyncd.conf.erb"
  variables({
    :uid => node[:swift][:user],
    :gid => node[:swift][:group],
    :storage_net_ip => storage_ip
  })
end

case node[:platform]
when "suse", "centos", "redhat"
else
  cookbook_file "/etc/default/rsync" do
    source "default-rsync"
  end
end

unless %w(redhat centos).include?(node.platform)
  service "rsync" do
    action [:enable, :start]
    service_name "rsyncd" if %w(suse).include?(node.platform)
  end
else
  package "xinetd"
  service "xinetd" do
    action [ :start, :enable ]
  end
  cookbook_file "/etc/xinetd.d/rsync" do
    source "rsync_xinetd"
    notifies :restart, resources(:service => "xinetd")
  end
end

