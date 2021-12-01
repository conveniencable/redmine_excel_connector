class RedmineExcelConnectorController < ApplicationController
  helper :redmine_excel_connector
  include RedmineExcelConnectorHelper
  helper :queries
  include QueriesHelper

  before_action :cors

  before_action :require_login, :except => [:test, :logged_in, :index]

  skip_before_action :check_if_login_required, :only => [:test, :logged_in, :index]

  layout false

  def logged_in
    user = User.try_to_login(params[:login], params[:password], false)

    if user.nil?
      render :json => json_invalid([{:name => 'login', :message => l(:notice_account_invalid_credentials)}])
    else
      # Valid user
      if user.active?
        reset_session
        User.current = user
        start_user_session(user)

        update_sudo_timestamp! # activate Sudo Mode
        render :json => json_ok(current_user)
      else
        render :json => json_invalid([{:name => 'login', :message => l(:notice_account_not_activated_yet, :url => activation_email_path)}])
      end
    end
  end

  def queries
    project = Project.where(:id => params[:project_id]).first if params[:project_id].present? && params[:project_id].to_i > 0
    queries = IssueQuery.visible.global_or_on_project(project).sorted.to_a
    result = []
    queries.select(&:is_private?).each do |q|
      result << to_query_data(q)
    end

    queries.reject(&:is_private?).each do |q|
      result << to_query_data(q)
    end

    render :json => json_ok(result)
  end

  def query_settings
    render :json => json_ok(get_query_settings(IssueQuery.new))
  end

  def filter_values
    q = IssueQuery.new
    if params[:project_id].present? and params[:project_id].to_i > 0
      q.project = Project.find(params[:project_id])
    end

    unless User.current.allowed_to?(q.class.view_permission, q.project, :global => true)
      raise Unauthorized
    end

    filter = q.available_filters[params[:name].to_s]
    values = filter ? filter.values : []

    render :json => json_ok(values)
  end

  def logged_out
    logout_user

    render :json => json_ok
  end

  def index
    headers['Access-Control-Allow-Origin'] = "*"
    headers['X-Frame-Options'] = 'ALLOWALL'
    headers['Access-Control-Allow-Credentials'] = 'true'
    headers['Vary'] = 'Origin'
  end

  def test
    headers['Access-Control-Allow-Origin'] = request.headers["Origin"].to_s
    #headers['Access-Control-Allow-Credentials'] = 'true'
    # headers['Vary'] = 'Origin'
    render :plain => 'ok'
  end

  def issues
    retrieve_query

    if @query.valid?
      @offset, @limit = api_offset_and_limit
      @issue_count = @query.issue_count
      @issues = @query.issues(:offset => @offset, :limit => @limit)

      relations = IssueRelation.where(:issue_to_id => @issues.map(&:id))

      issues_data = @issues.map do |issue|
        issue_data = {:id => issue.id, :parent_id => issue.parent_id, :updated_on => issue.updated_on}
        @query.columns.each do |column|
          issue_data[column.name] = csv_content(column, issue)
        end

        issue_relations = relations.select{|relation| relation.issue_to_id == issue.id}

        issue_data['relations'] = issue_relations.join(',') unless issue_relations.blank?

        issue_data
      end

      columnSettings = nil
      if @offset == 0
        fields = field_settings
        columnSettings = @query.columns.map do |column|
          field = fields.find{|f| column.name.to_s == f[:name]}

          col_data = {
            :name => column.name,
            :label => field ? field[:label] : column.caption,
            :possible_values => field ? field[:possible_values] : nil,
            :possible_objects => field ? field[:possible_objects] : nil,
            :type => field ? field[:type] : 'string'
          }

          col_data
        end
      end

      render :json => json_ok({
        :offset => @offset,
        :limit => @limit,
        :total_count => @issue_count,
        :issues => issues_data,
        :columnSettings => columnSettings
      })
    else
      render :json => json_error('invalid query params')
    end
  end
end
