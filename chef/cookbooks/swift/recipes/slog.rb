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


if node["swift"]["install_slog_from_dev"] or true
   slog_ver = "slogging-1.1.3.dev"
   slog_pkg = "#{slog_ver}.tar.gz"
   cookbook_file "/opt/#{slog_pkg}" do 
     source "slogging-1.1.3.dev.tar.gz"
     not_if { File.exists?("/opt/#{slog_pkg}") }
   end
   
   execute "extract slogging" do
      cwd "/opt"
      command <<-EOH
      tar -xzvf #{slog_pkg}
      easy_install #{slog_ver}
      EOH
      not_if { File.exists?("/usr/local/bin/swift-access-log-delivery") }
   end
else
   package "python-slogging" do
     action :install
   end 
end


####
# create an account user and contianer for collecting stats.
#

config = {}
config["os_user"] = node["swift"]["user"]
config["os_group"] = node["swift"]["group"]
config["slog_user"] = node["swift"]["slog_user"]
config["slog_passwd"] = node["swift"]["slog_passwd"]
config["slog_account"] = node["swift"]["slog_account"]
# set the account hash to match the account (double check it works w/ keystone)
config["swift_account_hash"] = node["swift"]["reseller_prefix"]+ "_" +  node["swift"]["slog_account"]

roles = node['roles']
config["proxy"] =  roles.include?("swift-proxy")
config["storage"] = true if roles.include?("swift-storage")
config["hide_auth"] = false #true unless config["proxy"]


log("node role is #{config['storage'] ? 'storage' : 'not store'} is #{config['proxy'] ? 'proxy': 'not proxy'}") { level :warn }

case node["swift"]["auth_method"]
   when "swauth"

     cluster_pwd = node["swift"]["cluster_admin_pw"]
   
     ###
     #   make sure the swauth system is preped.
     #     swauth-prep -K swauth -U '.super_admin' -A https://127.0.0.1:8080/auth/
     #   add account
     #     swauth-add-account -K swaut -U '.super_admin' _stats 
     #   add user
     #      swauth-add-user -K swauth -U '.super_admin' -A https://127.0.0.1:8080/auth/ stats stat_user passwd

      execute "prep swauth" do
        cwd "/etc/swift"
        group node[:swift][:group]
        user node[:swift][:user]
        command <<-EOH
          /usr/bin/swauth-prep -K #{cluster_pwd} -U '.super_admin' -A https://127.0.0.1:8080/auth
        EOH
        #not_if { `/usr/bin/swauth-list -K #{cluster_pwd}  -U '.super_admin' -A https://127.0.0.1:8080/auth/` } 
      end

      execute "prep stats accountswaut" do
        cwd "/etc/swift"
        group node[:swift][:group]
        user node[:swift][:user]
        command <<-EOH
          /usr/bin/swauth-add-account -K #{cluster_pwd} -U '.super_admin' -A https://127.0.0.1:8080/auth/  #{config['slog_account']} && 
          /usr/bin/swauth-add-user -K #{cluster_pwd} -U '.super_admin' -A https://127.0.0.1:8080/auth/ -a #{config['slog_account']}  #{config['slog_user']} #{config['slog_passwd']}
        EOH
      end

      %w{log_data container-stats account-stats}.each { |x|
        execute "create container for #{x} " do
            cwd "/etc/swift"
            group node[:swift][:group]
            user node[:swift][:user]
            command <<-EOH
              swift -K #{cluster_pwd} -U '.super_admin' -A https://127.0.0.1:8080/auth/v1.0 -U #{config['slog_account']}:#{config['slog_user']} -K #{config['slog_passwd']} post #{x}
           EOH
        end
      }

       ruby_block "Collect acct info" do 
        block do
          acct_info=`/usr/bin/swauth-list -K #{cluster_pwd}  -U '.super_admin' -A https://127.0.0.1:8080/auth/  #{config['swift_account']}` 
          parsed_account =JSON.parse(acct_info)
          puts "stats account hash #{parsed_account['account_id']}"
          config["swift_account_hash"]= parsed_account["account_id"]
        end
       end
  
   when "keystone" 
end  if config["proxy"] == true



#  swift log locations
template "/etc/rsyslog.d/30-swift.conf" do
  source     "30-swift.conf.erb"
  mode       "0755"
  group       "adm"
  owner       "syslog"
  variables   config
end

directory "/var/log/swift/hourly" do 
  group       node[:swift][:group]
  group       "adm"
  owner       "syslog"
  mode        "0755"
  recursive  true
end
directory "/var/log/swift/stats" do 
  group       node[:swift][:group]
  group       node[:swift][:group]
  owner       node[:swift][:user]
  mode        "0755"
 recursive  true
end


# slog processing config
template "/etc/swift/log-processor.conf" do
  source     "log-processor.conf.erb"
  mode       "0644"
  variables   config
end

# cron entries...
template "/etc/cron.d/slog.conf" do
  source     "slog-cron.conf.erb"
  mode       "0644"
  variables   config
end

## Create the proxy server configuraiton file on storage nodes
## (the uploader needs it)
template "/etc/swift/proxy-server.conf" do
  source     "proxy-server.conf.erb"
  mode       "0644"
  group       node[:swift][:group]
  owner       node[:swift][:user]
  variables   config
end unless config["proxy"]

