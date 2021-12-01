module RedmineExcelConnectorHelper
  @@field_formats = { 'id': 'int', 'start_date': 'date', 'due_date': 'date', 'done_ratio': 'int', 'is_private': 'bool', 'estimated_hours': 'float', 'created_on': 'date', 'updated_on': 'date', 'closed_on': 'date', 'spent_hours': 'float', 'total_spent_hours': 'float' }

  def cors
    if Rails.env.development?
      headers['Access-Control-Allow-Origin'] = request.headers["Origin"].to_s
      headers['Access-Control-Allow-Credentials'] = 'true'
    end
  end

  def verify_authenticity_token

  end

  def current_user
    currentUser = User.current;
    projects = available_projects

    {
      :name => currentUser.name,
      :id => currentUser.id,
      :email => currentUser.mail,
      :projects => projects,
      :default_query => to_query_data(IssueQuery.new)
    }
  end

  def find_setting

  end

  def find_issue_fields

  end

  def find_project_members
    User.active.all.map do |user|
      {:id => user.id, :name => user.name, project_ids => user.members.map(&:project_id)}
    end
  end

  def available_projects
    projects = []
    currentUser = User.current
    index = 0
    Project.project_tree(Project.visible.active.select{|p| currentUser.allowed_to?(:view_issues, p)}) do |project, level|
      projects << {
        :id => project.id, :name => project.name, :level => level,
        :permission_add_issues =>  currentUser.allowed_to?(:add_issues, p),
        :permission_edit_issues =>  currentUser.allowed_to?(:edit_issues, p),
        :permission_edit_own_issues =>  currentUser.allowed_to?(:edit_own_issues, p),
        :permission_delete_issues =>  currentUser.allowed_to?(:delete_issues, p),
        :index => index
      }
      index += 1
    end
    projects
  end

  def json_invalid(fieldErrors)
    {:code => 500, :data => fieldErrors}
  end

  def json_error(error)
    {:code => 600, :data => error}
  end

  def json_ok(data = {})
    {:code => 0, :data => data}
  end

  def query_filters(query)
    ungrouped = []
    grouped = {}
    query.available_filters.map do |field, field_options|
      if field_options[:type] == :relation
        group = :label_relations
      elsif field_options[:type] == :tree
        group = query.is_a?(IssueQuery) ? :label_relations : nil
      elsif /^cf_\d+\./.match?(field)
        group = (field_options[:through] || field_options[:field]).try(:name)
      elsif field =~ /^(.+)\./
        # association filters
        group = "field_#{$1}".to_sym
      elsif %w(member_of_group assigned_to_role).include?(field)
        group = :field_assigned_to
      elsif field_options[:type] == :date_past || field_options[:type] == :date
        group = :label_date
      elsif %w(estimated_hours spent_time).include?(field)
        group = :label_time_tracking
      end
      if group
        (grouped[group] ||= []) << [field_options[:name], field]
      else
        ungrouped << [field_options[:name], field]
      end
    end

    grouped['ungrouped'] = ungrouped

    grouped
  end

  def get_query_settings(query)
    {
      :filterOptions => query_filters(query),
      :operatorLabels => Query.operators_labels,
      :operatorByType => Query.operators_by_filter_type,
      :availableFilters => query.available_filters_as_json,
      :availableColumns => query_selected_inline_columns_options(query) | query_available_inline_columns_options(query),
    }
  end

  def to_query_data(query)
    {
      :id => query.id, 
      :name => query.name, 
      :columns => (query.inline_columns & query.available_inline_columns).reject(&:frozen?).collect{|column| column.name},
      :filters => query.filters.collect{|f| {:fieldName => f[0], :operator => f[1][:operator], :values => f[1][:values]} }
    }
  end

  def field_settings()
    common_fields = []
    common_fields << {:label => '#', :name => 'id', :type => 'integer'}
    common_fields << {:label => '$', :name => 'row_id', :type => 'string'}
    common_fields << {:label => l(:field_project), :name => 'project_id', :type => 'string', :config_objects => Project}
    common_fields << {:label => l(:field_parent_issue), :name => 'parent', :key => 'parent_issue_id', :type => 'integer'}
    common_fields << {:label => l(:field_subject), :name => 'subject', :type => 'string'}
    common_fields << {:label => l(:label_tracker), :name => 'tracker', :key => 'tracker_id', :type => 'string', :config_objects => Tracker}
    common_fields << {:label => l(:field_status), :name => 'status', :key => 'status_id', :type => 'string', :possible_objects => IssueStatus.all.map{|i| {:id => i.id, :name => i.name}}}
    common_fields << {:label => l(:field_priority), :name => 'priority', :key => 'priority_id', :type => 'string', :possible_objects => IssuePriority.all.map{|i| {:id => i.id, :name => i.name}}}
    common_fields << {:label => l(:field_assigned_to), :name => 'assigned_to', :key => 'assigned_to_id', :type => 'string', :config_objects => User}
    common_fields << {:label => l(:field_category), :name => 'category', :key => 'category_id', :type => 'string', :config_objects => IssueCategory}

    common_fields << {:label => l(:field_start_date), :name => 'start_date', :type => 'date'}
    common_fields << {:label => l(:field_due_date), :name => 'due_date', :type => 'date'}
    common_fields << {:label => l(:field_estimated_hours), :name => 'estimated_hours', :type => 'double'}
    common_fields << {:label => l(:field_done_ratio), :name => 'done_ratio', :type => 'integer', :posibble_values => (0..10).to_a.collect {|r| {:name => "#{r*10}%", :id => r*10 }}}
    common_fields << {:label => l(:label_description), :name => 'description', :type => 'string'}

    relation_types = IssueRelation::TYPES
    relation_types_list = relation_types.keys.sort{|x,y| relation_types[x][:order] <=> relation_types[y][:order]}.collect{|k| {:name => l(relation_types[k][:name]), :id => k}}

    common_fields << {:label => l(:label_related_issues), :name => 'relations', :type => 'string', :possible_objects => relation_types_list}
    #common_fields << {:name => l(:label_attachment), :name => 'attachment', :type => 'string'}

    @custom_fields = CustomField.all().map do |cf|
      {:label => cf.name, :name => "cf_#{cf.id}", :type => cf.field_format == 'list' ? 'string' : cf.field_format, :possible_values => cf.possible_values}
    end
  

    [common_fields, @custom_fields].reduce([], :concat)
  end
end
