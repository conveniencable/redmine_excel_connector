class RedmineExcelConnectorController < ApplicationController
  helper :redmine_excel_connector
  include RedmineExcelConnectorHelper
  helper :queries
  include QueriesHelper

  before_action :cors

  before_action :require_login, :except => [:test, :logged_in, :index]
  before_action :find_optional_project, :only => [:issues, :save_issues]

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

      @relation_types_list = relation_types_list
      all_ids = @issues.map(&:id)
      relations = IssueRelation.where('issue_from_id in (?) or issue_to_id in (?)', all_ids, all_ids)

      issues_data = @issues.map do |issue|
        issue_data = {:parent_id => issue.parent_id.to_s, :updated_on => issue.updated_on}
        @query.columns.each do |column|
          issue_data[column.name] = csv_content(column, issue)
        end

        issue_relations = relations.select{|relation| relation.issue_from_id == issue.id}

        unless issue_relations.blank?
          issue_data['relations'] = issue_relations
        end

        issue_data['relations'] = issue_relations.map{|r| {:to_id => r.issue_to_id, :relation_type => r.relation_type, :delay => r.delay}}.to_json unless issue_relations.blank?

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
            :type => field ? field[:type] : 'string',
            :read_only => field ? field[:readonly] : false
          }

          col_data
        end

        columnSettings.insert(1, fields.find{|f| f[:name] == 'row_id'})

        columnSettings << fields.find{|f| f[:name] == 'relations'}
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

  def save_issues
    fields = field_settings
    unknown_parent_row_id_to_id = params[:unknown_parent_row_id_to_id]

    header_settings = []
    params[:headers].each do |label|
      field_setting = fields.find{|fs| fs[:label] == label}
      if field_setting[:readonly]
        if field_setting.present?
          header_settings << field_setting
        else
          header_settings << nil
          logger.info("can't find field setting for label '#{label}'") if logger
        end
      else
        header_settings << nil
      end
    end

    load_field_setting_getter(header_settings)

    issue_datas = []
    row_id_to_id = {}
    id_to_line_no = {}
    projects = {}

    errors = {}
    updated_issues = {}

    all_relations = []

    params[:issues].each do |issue_array_data|
      line_no = issue_array_data[0].to_i
      issue_data = {:line_no => line_no}
      issue_datas << issue_data

      header_settings.each_with_index do |field_setting, field_index|
        if field_index > 0 && field_setting
          parse_field_value(issue_data, issue_array_data[field_index], field_setting)
        end
      end

      if @project.present? and not issue_data[:project_id].present?
        issue_data[:project_id] = @project.id
      end

      unless projects[issue_data[:project_id]]
        project = Project.find(issue_data[:project_id])
        projects[issue_data[:project_id]] = [project, User.current.allowed_to?(:add_issues, project)]
      end

      if issue_data[:row_id] and issue_data[:id]
        row_id_to_id[issue_data[:row_id]] = issue_data[:id].to_i
      else
        row_id_to_id[issue_data[:row_id]] = 'new'
      end

      if issue_data[:relations]
        relations = issue_data.delete(:relations)
        relations.each do |r|
          r[:line_no] = line_no
          if issue_data[:id]
            r[:form_id] = issue_data[:id].to_i
          else
            r[:form_row_id] = issue_data[:row_id]
          end

          all_relations << r
        end
      end
    end

    saving_datas = issue_datas
    while saving_datas.length > 0
      issue_data_save_later = []
      saving_datas.each do |issue_data|
        if !issue_data[:project_id].present? && issue_data[:row_id].present?
          row_id_fragments = issue_data[:row_id].split('.')
          if row_id_fragments.length > 1
            parent_row_id = row_id_fragments[0..-2].join('.')

            parent_id = unknown_parent_row_id_to_id[parent_row_id].to_i if unknown_parent_row_id_to_id[parent_row_id]
            parent_id = row_id_to_id[parent_row_id] unless parent_id

            if parent_id
              if parent_id == 'new'
                issue_data_save_later << issue_data
                continue
              else
                issue_data[:parent_issue_id] = parent_id
              end
            end
          end
        end

        line_no = issue_data.delete(:line_no).to_i
        row_id = issue_data.delete(:row_id)
        if issue_data[:id]
          id = issue_data.delete(:id).to_i

          issue_obj = Issue.where(:id => id).first

          unless issue_obj
            add_to_errors(errors, line_no, [l(:issue_not_exists, :id => id)])
          else
            if issue_obj.attributes_editable?
              issue_obj.init_journal(User.current)
              issue_obj.safe_attributes = convert_issue_data(issue_data)

              if issue_obj.save
                updated_issues[issue_obj.id] = {:line_no => line_no, :updated_on => format_time(issue_obj.updated_on), :last_updated_by => issue_obj.last_updated_by && issue_obj.last_updated_by.name}
                id_to_line_no[issue_obj.id] = line_no
              else
                add_to_errors(errors, line_no, issue_obj.errors.full_messages)
              end
            else
              add_to_errors(errors, line_no, [l(:issue_not_editable)])
            end
          end
        else
          project_info = projects[issue_data.delete(:project_id)]
          unless project_info[1]
            add_to_errors(errors, line_no, [l(:issue_not_addable)])
          else
            issue_data = convert_issue_data(issue_data)
            issue_obj = Issue.new
            issue_obj.author = User.current
            issue_obj.project_id =project_info[0].id
            issue_obj.safe_attributes = issue_data
            if issue_obj.save
              issue_obj[:id] = issue_obj.id
              updated_issues[issue_obj.id] = {:line_no => line_no, :id => issue_obj.id, :created_on => format_time(issue_obj.created_on), :updated_on => format_time(issue_obj.updated_on), :author => issue_obj.author.name, :last_updated_by => issue_obj.author.name}
              row_id_to_id[row_id] = issue_obj.id if row_id
              id_to_line_no[issue_obj.id] = line_no
            else
              add_to_errors(errors, line_no, issue_obj.errors.full_messages)
            end
          end
        end
      end
      saving_datas = issue_data_save_later
    end

    all_relations.each do |r|
      if not r[:to_id]
        if r[:to_row_id]
          if row_id_to_id[r[:to_row_id]]
            if row_id_to_id[r[:to_row_id]] == 'new'
              continue
            end
            r[:to_id] = row_id_to_id[r[:to_row_id]]
          end

          if unknown_parent_row_id_to_id[r[:to_row_id]]
            r[:to_id] = unknown_parent_row_id_to_id[r[:to_row_id]].to_i
          end
        end

        unless r[:to_id]
          add_to_errors(errors, line_no, ["relation target '#{r[:to_row_id]}' error"])
          continue
        end
      end

      if not r[:from_id]
        if row_id_to_id[r[:from_row_id]]
          if row_id_to_id[r[:from_row_id]] == 'new'
            continue
          end
          r[:from_id] = row_id_to_id[r[:from_row_id]]
        end
      end

      result = save_relation(r)

      if result && result.errors && !result.errors.full_messages.empty?
        add_to_errors(errors, line_no, result.errors.full_messages)
      end
    end

    all_issue_ids = id_to_line_no.keys()

    Issue.where(:id => all_issue_ids).each do |issue|
      update_data = nil
      if updated_issues[issue.id]
        update_data = updated_issues[issue.id]
      elsif id_to_line_no[issue.id]
        update_data = {:line_no => id_to_line_no[issue.id]}
        updated_issues[issue.id] = update_data
      end

      if update_data
        update_data[:start_date] = format_date(issue.start_date)
        update_data[:due_date] = format_date(issue.due_date)
        update_data[:status] = issue.status.name
      end
    end

    render :json => {
      :updated_issues => updated_issues,
      :errors => errors
    }
  end

  def find_optional_project
    @project = Project.where('id = ? or identifier=?', params[:project_id].to_i, params[:project_id].to_s).first unless params[:project_id].blank?

    unless User.current.allowed_to?(:view_issues, @project)
      @project = nil
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
