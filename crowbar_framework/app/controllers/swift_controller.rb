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

class SwiftController < BarclampController
  helper_method :available_nodes
  helper_method :ready_nodes

  def dashboard
    @reports = reports_list
    render :template => "barclamp/#{@bc_name}/dashboard"
  end

  def clear
    @service_object.clear_dispersion_reports
    redirect_to swift_dashboard_path, :notice => I18n.t("barclamp.swift.clear.success")
  end

  def create
    if params[:node]
      report = nil

      begin
        report = @service_object.run_report params[:node]
        flash[:notice] = I18n.t("barclamp.swift.run.success", :node => params[:node])
      rescue SwiftService::ServiceError => error
        flash[:notice] = I18n.t("barclamp.swift.run.failure", :node => params[:node], :error => error)
      end

      if request.xhr?
        render :text => swift_show_report_path(:id => report["uuid"])
      else
        redirect_to swift_dashboard_path
      end
    else
      redirect_to swift_dashboard_path, :alert => I18n.t("barclamp.swift.run.no_node")
    end
  end

  def results
    @report = @service_object.get_report_run_by_uuid(params[:id])
    raise_not_found if not @report or @report["status"] == "running"

    generate_for(@report)

    respond_to do |format|
      format.html { render :template => "barclamp/swift/results" }
      format.json { render :file => Rails.root.join(@report["results.json"]) }
    end
  end

  protected

  def generate_for(report)
    return if File.exist? Rails.root.join(report["results.html"])

    begin
      json = JSON.parse(
        IO.read(
          Rails.root.join(report["results.json"])
        )
      )

      File.open(Rails.root.join(report["results.html"]), "w") do |out|
        out.write(
          render_to_string(
            :template => "barclamp/swift/_results.html",
            :layout => false,
            :locals => { :json => json }
          )
        )
      end
    rescue => e
      logger.info sprintf(
        "Failed to generate %s report: %s",
        report["uuid"],
        e.message
      )
    end
  end

  def reports_list
    @service_object.get_dispersion_reports.map do |report|
      report["alias"] = if available_nodes[report["node"]]
        available_nodes[report["node"]].alias
      else
        report["node"]
      end

      report
    end
  end

  def available_nodes
    @available_nodes ||= begin
      @service_object.get_all_nodes_hash
    end
  end

  def ready_nodes
    @ready_nodes ||= begin
      @service_object.get_ready_nodes
    end
  end

  def raise_not_found
    raise ActionController::RoutingError.new("Not found")
  end

  def initialize_service
    @service_object = SwiftService.new logger
  end
end
