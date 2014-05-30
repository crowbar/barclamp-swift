#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Barclamp
  module SwiftHelper
    def frontends_for_swift(selected)
      options_for_select(
        [
          ["uwsgi", "uwsgi"],
          ["native", "native"]
        ],
        selected.to_s
      )
    end

    def ssl_protocols_for_swift(selected)
      options_for_select(
        [
          ["HTTP", "false"],
          ["HTTPS", "true"]
        ],
        selected.to_s
      )
    end

    def nodes_for_swift(selected)
      options_for_select(
        ready_nodes.map { |node|
          [
            node.alias,
            node.name
          ]
        },
        selected.to_s
      )
    end

    def swift_report_status_for(report)
      led_class = case report["status"]
        when "passed"
          "led green"
        when "failed"
          "led red"
        else
          "led in_process"
      end

      status_link = if report["status"] == "running"
        t(report["status"], :scope => "barclamp.swift.dashboard.report_run.status")
      else
        link_to(
          t(report["status"], :scope => "barclamp.swift.dashboard.report_run.status"),
          swift_show_report_path(:id => report["uuid"])
        )
      end

      [
        content_tag(
          :span,
          "",
          :class => led_class
        ),
        status_link
      ].join("\n")
    end
  end
end
