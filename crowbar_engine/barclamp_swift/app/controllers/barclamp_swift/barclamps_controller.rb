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

class BarclampSwift::BarclampsController < BarclampsController
  def initialize
    @service_object = SwiftService.new logger
  end

  def raise_not_found
    raise ActionController::RoutingError.new('Not Found')
  end

  def dashboard
    @dispersion_reports = @service_object.get_dispersion_reports
    @ready_nodes = @service_object.get_ready_nodes
    @nodes_hash = SwiftService.get_all_nodes_hash
    render :template => "barclamp/#{@bc_name}/dashboard.html.haml"
  end

  def dispersion_reports
    # POST /swift/dispersion_reports/clear
    if (request.post? or request.put?) and params[:id] == 'clear'
      @service_object.clear_dispersion_reports
      flash[:notice] = t "barclamp.#{@bc_name}.dashboard.clear.success"
    # POST /swift/dispersion_reports
    elsif request.post? or request.put?
      begin
        report_run = @service_object.run_report params[:node]
        flash[:notice] = t "barclamp.#{@bc_name}.run.success", :node => params[:node]
      rescue SwiftService::ServiceError => error
        flash[:notice] = t "barclamp.#{@bc_name}.run.failure", :node => params[:node], :error => error
      end
      
      # supporting REST style interface
      render :text => "/#{@bc_name}/dispersion_reports/#{report_run["uuid"]}" if request.xhr?
    
    # GET /swift/dispersion_reports/<report-run-id>
    elsif uuid = params[:id] 
      @report_run = @service_object.get_report_run_by_uuid(uuid) or raise_not_found
      respond_to do |format|
        format.json { render :json => @report_run } 
        format.html { redirect_to "/#{@bc_name}/results/#{uuid}.html" }
      end
    
    # GET /swift/dispersion_reports
    else 
      @dispersion_reports = @service_object.get_dispersion_reports
      respond_to do |format|
        format.json { render :json => @dispersion_reports }
        format.html { nil } # redirect to dashboard
      end
    end 
    redirect_to "/#{@bc_name}/dashboard" unless request.xhr?
  end

  def _prepare_results_html(report_run)
    return if File.exist?(report_run['results.html'])
    
    json = JSON.parse(IO.read(report_run['results.json']))
    File.open(report_run['results.html'], "w") { |out| 
      out.write(
        render_to_string(:template => "barclamp/#{@bc_name}/_results.html.haml",
          :locals => {:json => json }, :layout => false))
    }
  end

  def results
    @report_run = @service_object.get_report_run_by_uuid(params[:id])
    raise_not_found if not @report_run or @report_run["status"] == "running"

    respond_to do |format|
      format.json { render :file => @report_run["results.json"] }
      format.html {
        _prepare_results_html @report_run
        render :template => "barclamp/#{@bc_name}/results.html.haml"
      }
    end
  end
end

