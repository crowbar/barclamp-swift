# Copyright 2011-2013, Dell
# Copyright 2013, SUSE LINUX Products GmbH
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
# Author: Dell Crowbar Team
# Author: SUSE LINUX Products GmbH
#

module SwiftBarclampHelper
  def swift_role_contraints
    {
      "swift-storage" => {
        "unique" => false,
        "count" => -1
      },
      "swift-proxy" => {
        "unique" => false,
        "count" => -1
      },
      "swift-dispersion" => {
        "unique" => false,
        "count" => 1
      },
      "swift-ring-compute" => {
        "unique" => false,
        "count" => 1
      }
    }
  end

  def frontends_for_swift(selected)
    options_for_select(
      [
        ["apache","apache"], 
        ["native", "native"]
      ],
      selected.to_s
    )
  end
end
