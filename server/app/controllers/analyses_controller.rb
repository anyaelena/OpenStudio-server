class AnalysesController < ApplicationController
  # GET /analyses
  # GET /analyses.json
  def index
    if params[:project_id].nil?
      @analyses = Analysis.all
    else
      @analysis = Project.find(params[:project_id]).analyses
    end

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @analyses }
    end
  end

  # GET /analyses/1
  # GET /analyses/1.json
  def show
    @analysis = Analysis.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: {:analysis => @analysis, :metadata => @analysis[:os_metadata]} }
    end
  end

  # GET /analyses/new
  # GET /analyses/new.json
  def new
    @analysis = Analysis.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @analysis }
    end
  end

  # GET /analyses/1/edit
  def edit
    @analysis = Analysis.find(params[:id])
  end

  # POST /analyses
  # POST /analyses.json
  def create
    project_id = params[:project_id]
    params[:analysis].merge!(:project_id => project_id)

    # save off the metadata as a child of the analysis right now... eventually move analysis
    # underneath metadata
    params[:analysis].merge!(:os_metadata => params[:metadata])

    @analysis = Analysis.new(params[:analysis])
    respond_to do |format|
      if @analysis.save
        format.html { redirect_to @analysis, notice: 'Analysis was successfully created.' }
        format.json { render json: @analysis, status: :created, location: @analysis }
      else
        format.html { render action: "new" }
        format.json { render json: @analysis.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /analyses/1
  # PUT /analyses/1.json
  def update
    @analysis = Analysis.find(params[:id])

    respond_to do |format|
      if @analysis.update_attributes(params[:analysis])
        format.html { redirect_to @analysis, notice: 'Analysis was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @analysis.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /analyses/1
  # DELETE /analyses/1.json
  def destroy
    @analysis = Analysis.find(params[:id])
    project_id = @analysis.project
    @analysis.destroy

    respond_to do |format|
      format.html { redirect_to project_path(project_id) }
      format.json { head :no_content }
    end
  end

  # Controller for submitting the action via post.  This right now only works with the API
  # and will only return a JSON response based on whether or not the analysis has been
  # queued into Delayed Jobs
  def action
    @analysis = Analysis.find(params[:id])
    logger.info("action #{params.inspect}")
    params[:analysis_type].nil? ? @analysis_type = 'batch_run' : @analysis_type = params[:analysis_type]

    result = {}
    if params[:analysis_action] == 'start'

      params[:without_delay] == 'true' ? no_delay = true : no_delay = false

      res = @analysis.run_r_analysis(no_delay, @analysis_type)
      if res[0]
        result[:code] = 200
        result[:analysis] = @analysis
      else
        result[:code] = 500
        result[:error] = res[1]
      end

      respond_to do |format|
        #  format.html # new.html.erb
        format.json { render json: result }
        if result[:code] == 200
          format.html { redirect_to @analysis, notice: 'Analysis was started.' }
        else
          format.html { redirect_to @analysis, notice: 'Analysis was NOT started.' }
        end
      end
    elsif params[:analysis_action] == 'stop'
      if @analysis.stop_analysis
        result[:code] = 200
        result[:analysis] = @analysis
      else
        result[:code] = 500
        # TODO: save off the error
      end


      respond_to do |format|
        #  format.html # new.html.erb
        format.json { render json: result }
        if result[:code] == 200
          format.html { redirect_to @analysis, notice: 'Analysis flag changed to stop. Will wait until the last run finishes.' }
        else
          format.html { redirect_to @analysis, notice: 'Analysis flag did NOT change.' }
        end
      end
    end

  end

  def status
    @analysis = Analysis.find(params[:id])

    dps = nil
    if params[:jobs].nil?
      dps = @analysis.data_points
    else
      dps = @analysis.data_points.where(status: params[:jobs])
    end

    respond_to do |format|
      #  format.html # new.html.erb
      format.json { render json: {:analysis => {:status => @analysis.status}, data_points: dps.map { |k| {:_id => k.id, :status => k.status} }} }
    end
  end

  def download_status
    @analysis = Analysis.find(params[:id])

    dps = nil
    if params[:downloads].nil?
      dps = @analysis.data_points.where(download_status: 'completed')
    else
      dps = @analysis.data_points.where(download_status: params[:downloads])
    end

    respond_to do |format|
      #  format.html # new.html.erb
      format.json { render json: {:analysis => {status: @analysis.status}, data_points: dps.map { |k| {:_id => k.id, :status => k.status, :download_status => k.download_status} }} }
    end
  end

  def upload
    @analysis = Analysis.find(params[:id])

    @analysis.seed_zip = params[:file]

    respond_to do |format|
      if @analysis.save
        format.json { render json: @analysis, status: :created, location: @analysis }
      else
        format.json { render json: @analysis.errors, status: :unprocessable_entity }
      end
    end

  end

  def debug_log
    @analysis = Analysis.find(params[:id])

    @log_message = []
    @analysis.data_points.each do |dp|
      unless dp.run_time_log.nil?
        @log_message << [dp.name] + dp.run_time_log
      end
    end
    @rserve_log = File.read(File.join(Rails.root, 'log', 'Rserve.log'))

    exclude_fields = [:_id,:user,:password]
    @workers = WorkerNode.all.map{|n| n.as_json(:except => exclude_fields) }
    if MasterNode.count > 0
      @server = MasterNode.first.as_json(:except => exclude_fields)
    end


    respond_to do |format|
      format.html # oh_shit.html.erb
      format.json { render json: log_message }
    end

  end

  def page_data
    @analysis = Analysis.find(params[:id])

    # once we know that for all the buildings.
    #@time_zone = "America/Denver"
    #@data.each do |d|
    #  time, tz_abbr = Util::Date.fake_zone_in_utc(d[:time].to_i / 1000, @time_zone)
    #  d[:fake_tz_time] = time.to_i * 1000
    #  d[:tz_abbr] = tz_abbr
    #end

    respond_to do |format|
      format.json do
        fields = [
            :name,
            :data_points,
            :analysis_type,
            :status,
            :start_time,
            :end_time,
            :seed_zip,
            :results,
            :run_start_time,
            :run_end_time,
            :openstudio_datapoint_file_name
        ]

        render json: {:analysis => @analysis.as_json(:only => fields, :include => :data_points ) }
        #render json: {:analysis => @analysis.as_json(:only => fields, :include => :data_points ), :metadata => @analysis[:os_metadata]}
      end
    end
  end

end