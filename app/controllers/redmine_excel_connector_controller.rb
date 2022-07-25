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

    if Redmine::VERSION::MAJOR < 4
      params[:sort] = @query.sort_criteria if @query.sort_criteria.present?
      sort_init(@query.sort_criteria.empty? ? [['id', 'desc']] : @query.sort_criteria)
      sort_update(@query.sortable_columns)
      @query.sort_criteria = sort_criteria.to_a
    end

    if @query.valid?
      @offset, @limit = api_offset_and_limit
      @issue_count = @query.issue_count

      query_params = {:offset => @offset, :limit => @limit}
      if Redmine::VERSION::MAJOR < 4
        query_params[:order] = sort_clause
      end

      @issues = @query.issues(query_params)

      @relation_types_list = relation_types_list
      all_ids = @issues.map(&:id)
      need_relations = @query.columns.find{|column| column.name == :relations}

      relations = IssueRelation.where('issue_from_id in (?) or issue_to_id in (?)', all_ids, all_ids) if need_relations

      issues_data = @issues.map do |issue|
        issue_data = {:parent_id => issue.parent_id.to_s, :updated_on => issue.updated_on}
        @query.columns.each do |column|
          if column.name != :relations
            issue_data[column.name] = format_issue_value(column, issue)
          end
        end

        issue_data['relations'] = format_excel_relation(relations, issue.id) if need_relations

        issue_data
      end

      columnSettings = nil
      otherSettings = nil
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
            :read_only => field ? field[:readonly] : false,
            :multiple => field ? field[:multiple] : false,
            :relation_types => field ? field[:relation_types] : nil
          }

          col_data
        end

        otherSettings = {
          :date_format => date_format
        }
      end

      render :json => json_ok({
        :offset => @offset,
        :limit => @limit,
        :total_count => @issue_count,
        :issues => issues_data,
        :columnSettings => columnSettings,
        :otherSettings => otherSettings,
        :projectId => @project.present? ? @project.id : nil
      })
    else
      render :json => json_error('invalid query params')
    end
  end

  def after_load_issue
    issue_ids = params[:issue_ids] || []
    issue_ids = issue_ids.map{|v| v.to_i}

    deleted_ids = []
    if issue_ids && issue_ids.length > 0
      exist_ids = Issue.select(:id).where(:id => issue_ids).to_a.map {|s| s.id}
      deleted_ids = issue_ids.select { |v| !exist_ids.include? v }
    end

    render :json => json_ok({
                              :deleted_ids => deleted_ids
                            })
  end

  def save_issues
    fields = field_settings

    header_settings = []
    params[:headers].each do |field_name|
      field_setting = fields.find{|fs| fs[:name] == field_name}
      unless field_setting[:readonly]
        if field_setting.present?
          header_settings << field_setting
        else
          header_settings << nil
          logger.info("can't find field setting for name='#{field_name}'") if logger
        end
      else
        header_settings << nil
      end
    end

    load_field_setting_getter(header_settings)

    issue_datas = []
    partial_save_issue_line_nos = []
    id_to_line_no = {}
    line_no_to_id = {}
    params[:id_to_line_no].each do |k, v|
      k = k.to_i
      v = v.to_i
      id_to_line_no[k] = v
      line_no_to_id[v] = k
    end

    projects = {}

    errors = {}
    updated_issues = {}

    all_relations = []

    new_data_line_nos = []

    params[:issues].each do |issue_array_data|
      if issue_array_data.length <= 1
        next
      end

      line_no = issue_array_data[0].to_i
      issue_data = {:line_no => line_no}
      issue_errors = []

      header_settings.each_with_index do |field_setting, field_index|
        if field_setting
          error = parse_field_value(issue_data, issue_array_data[field_index + 1], field_setting)
          if error
            issue_errors.append(error)
          end
        end
      end

      unless issue_errors.empty?
        add_to_errors(errors, line_no, issue_errors)
        next
      end

      if !issue_data[:id] || issue_data[:id] <= 0
        new_data_line_nos << line_no
      end

      if @project.present? and not issue_data[:project_id].present?
        issue_data[:project_id] = @project.id
      end

      if issue_data[:project_id] && issue_data[:project_id].to_i > 0 && !projects[issue_data[:project_id]]
        project = Project.where(:id => issue_data[:project_id].to_i).first
        if project
          projects[issue_data[:project_id]] = [project, User.current.allowed_to?(:add_issues, project)]
        else
          add_to_errors(errors, line_no, [l(:project_not_exist)])
          next
        end
      end

      if issue_data[:relations]
        relations = issue_data.delete(:relations)
        relations.each do |r|
          r[:line_no] = line_no
          if issue_data[:id]
            issue_id = issue_data[:id].to_i
            r[:from_id] = issue_id
            r[:control_by_id] = issue_id
          end

          all_relations << r
        end
      end

      issue_datas << issue_data
    end

    need_to_update_parents = {}
    saving_datas = issue_datas
    while saving_datas.length > 0
      issue_data_save_later = []
      saving_datas.each do |issue_data|
        if issue_data[:parent_issue_id]
          if issue_data[:parent_issue_id].start_with?('#')
            issue_data[:parent_issue_id] = issue_data[:parent_issue_id][1..-1].to_i
          elsif issue_data[:parent_issue_id].downcase.start_with?('r')
            parent_line_no = issue_data[:parent_issue_id][1..-1].to_i
            if line_no_to_id[parent_line_no]
              issue_data[:parent_issue_id] = line_no_to_id[parent_line_no]
              need_to_update_parents[issue_data[:line_no]] = true
            else
              if new_data_line_nos.include?(parent_line_no)
                issue_data_save_later << issue_data
                next
              else
                partial_save_issue_line_nos << issue_data[:line_no]
                add_to_errors(errors, issue_data[:line_no], [l(:parent_target_not_found, "r#{parent_line_no}")])
              end
            end
          else
            issue_data[:parent_issue_id] = issue_data[:parent_issue_id].to_i
          end
        end

        line_no = issue_data.delete(:line_no)
        if issue_data[:id]
          id = issue_data.delete(:id)
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
                line_no_to_id[line_no] = issue_obj.id

                if need_to_update_parents[line_no]
                  updated_issues[issue_obj.id][:parent_id] = issue_obj.parent_issue_id
                end
              else
                add_to_errors(errors, line_no, issue_obj.errors.full_messages)
              end
            else
              add_to_errors(errors, line_no, [l(:issue_not_editable)])
            end
          end
        else
          project_info = projects[issue_data.delete(:project_id)]

          if project_info && (not project_info[1])
            add_to_errors(errors, line_no, [l(:issue_not_addable)])
          else
            issue_data = convert_issue_data(issue_data)
            issue_obj = Issue.new
            issue_obj.author = User.current
            issue_obj.project_id = project_info[0].id if project_info
            issue_obj.safe_attributes = issue_data
            if issue_obj.save
              issue_obj[:id] = issue_obj.id
              updated_issues[issue_obj.id] = {:line_no => line_no, :id => issue_obj.id, :created_on => format_time(issue_obj.created_on), :updated_on => format_time(issue_obj.updated_on), :author => issue_obj.author.name, :last_updated_by => issue_obj.author.name}
              id_to_line_no[issue_obj.id] = line_no
              line_no_to_id[line_no] = issue_obj.id

              if need_to_update_parents[line_no]
                updated_issues[issue_obj.id][:parent_id] = issue_obj.parent_issue_id
              end
            else
              add_to_errors(errors, line_no, issue_obj.errors.full_messages)
            end
          end

          new_data_line_nos.delete(line_no)
        end
      end
      saving_datas = issue_data_save_later
    end

    need_to_update_relations = {}

    all_relations.each do |r|
      unless line_no_to_id[r[:line_no]]
        next
      end

      if not r[:to_id]
        if r[:to_line_no]
          if line_no_to_id[r[:to_line_no]]
            r[:to_id] = line_no_to_id[r[:to_line_no]]
          end
        end

        unless r[:to_id]
          add_to_errors(errors, r[:line_no], [l(:relation_target_not_found, "r#{r[:to_line_no]}")])
          next
        end
      else

        if Issue.where(:id => r[:to_id]).count == 0
          add_to_errors(errors, r[:line_no], [l(:relation_target_issue_not_exist, :id => "#{r[:to_id]}")])
          next
        end
      end

      if not r[:from_id]
        issue_id = line_no_to_id[r[:line_no]]
        r[:from_id] = issue_id
        r[:control_by_id] = issue_id
      end

      to_line_no = r[:to_line_no]
      from_id = r[:from_id]
      result = save_relation(r)

      if result
        if result.errors && !result.errors.full_messages.empty?
          add_to_errors(errors, r[:line_no], result.errors.full_messages)
        else
          if to_line_no
            need_to_update_relations[from_id] = r[:line_no] unless need_to_update_relations.include? from_id
          end
        end
      end
    end

    need_to_update_relations.keys.each do |issue_id|
      updated_issue = nil
      if updated_issues.include? issue_id
        updated_issue = updated_issues[issue_id]
      else
        updated_issue = {:line_no => need_to_update_relations[issue_id]}
        updated_issues[issue_id] = updated_issue
      end
      updated_issue[:relations] = format_excel_relation(Issue.find(issue_id).relations, issue_id)
    end

    render :json => json_ok({
      :updated_issues => updated_issues,
      :errors => errors,
      :partial_save_issue_line_nos => partial_save_issue_line_nos
    })
  end

  def delete_issue
    id = params[:id]
    issue = Issue.find id

    error = ''
    if issue
      if (issue.respond_to?('deletable?') && !issue.deletable?)
        error = l(:not_authorized_to_delete)
      else
        issue.destroy
      end
    end

    render :json => json_ok(error)

  rescue ActiveRecord::RecordNotFound
    render :json => json_ok(nil)
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
