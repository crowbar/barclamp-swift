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
define :swift_service, :action => :create do
  full_name = params[:name] # eg.: 'swift-comp-srv' || 'swift-comp'
  venv_path = params[:virtualenv]


  comp_name, srv_name = full_name.split('-').drop(1)
  service_name = "#{comp_name}-#{srv_name ? srv_name : "server"}"

  template "/etc/init/#{full_name}.conf" do
    cookbook "swift"
    source "upstart.conf.erb"
    mode 0644
    variables({
      :path => "/opt/swift", #TODO(agordeev): remove hardcoded value
      :comp_name => comp_name,
      :service_name => service_name,
      :virtualenv => venv_path
    })
  end
  execute "link_service_#{full_name}" do
    command "ln -s /lib/init/upstart-job /etc/init.d/#{full_name}"
    creates "/etc/init.d/#{full_name}"
  end

end

