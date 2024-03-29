module RedmineExcelConnectorHelper
  @@used_sym = ({ :value => true }.delete('value') == true)
  @@NULL_STR = '$_nu^ll_#'

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
      { :id => user.id, :name => user.name, project_ids => user.members.map(&:project_id) }
    end
  end

  def available_projects
    projects = []
    currentUser = User.current
    index = 0
    Project.project_tree(Project.visible.active.select { |p| currentUser.allowed_to?(:view_issues, p) }) do |project, level|
      projects << {
        :id => project.id, :name => project.name, :level => level,
        :permission_add_issues => currentUser.allowed_to?(:add_issues, p),
        :permission_edit_issues => currentUser.allowed_to?(:edit_issues, p),
        :permission_edit_own_issues => currentUser.allowed_to?(:edit_own_issues, p),
        :permission_delete_issues => currentUser.allowed_to?(:delete_issues, p),
        :index => index
      }
      index += 1
    end
    projects
  end

  def json_invalid(fieldErrors)
    { :code => 500, :data => fieldErrors }
  end

  def json_error(error)
    { :code => 600, :data => error }
  end

  def json_ok(data = {})
    { :code => 0, :data => data }
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
      :availableColumns => query.available_columns.select{ |column| ![:attachments].include?(column.name)}.collect {|column| [column.caption, column.name]},
    }
  end

  def to_query_data(query)
    {
      :id => query.id,
      :name => query.name,
      :columns => (query.inline_columns & query.available_inline_columns).reject(&:frozen?).collect { |column| column.name },
      :filters => query.filters.collect { |f| { :fieldName => f[0], :operator => f[1][:operator], :values => f[1][:values] } }
    }
  end

  def field_settings()
    bool_possible_values = [l(:general_text_Yes), l(:general_text_No)]
    common_fields = []
    common_fields << { :label => '#', :name => 'id', :type => 'integer' }
    common_fields << { :label => l(:field_project), :name => 'project', :key => 'project_id', :type => 'string', :possible_values => Project.all.map { |i| i.name }, :config_objects => Project }
    common_fields << { :label => l(:field_parent_issue), :name => 'parent', :key => 'parent_issue_id', :type => 'string' }
    common_fields << { :label => l(:field_subject), :name => 'subject', :type => 'string' }
    common_fields << { :label => l(:label_tracker), :name => 'tracker', :key => 'tracker_id', :type => 'string', :possible_values => Tracker.all.map { |i| i.name }, :config_objects => Tracker }
    common_fields << { :label => l(:field_status), :name => 'status', :key => 'status_id', :type => 'string', :possible_values => IssueStatus.all.map { |i| i.name }, :config_objects => IssueStatus }
    common_fields << { :label => l(:field_priority), :name => 'priority', :key => 'priority_id', :type => 'string', :possible_values => IssuePriority.all.map { |i| i.name }, :config_objects => IssuePriority }
    common_fields << { :label => l(:field_assigned_to), :name => 'assigned_to', :key => 'assigned_to_id', :type => 'string', :config_objects => User }
    common_fields << { :label => l(:field_category), :name => 'category', :key => 'category_id', :type => 'string', :possible_values => IssueCategory.all.map { |i| i.name }, :config_objects => IssueCategory }

    common_fields << { :label => l(:field_start_date), :name => 'start_date', :type => 'date' }
    common_fields << { :label => l(:field_due_date), :name => 'due_date', :type => 'date' }
    common_fields << { :label => l(:field_estimated_hours), :name => 'estimated_hours', :type => 'float' }
    common_fields << { :label => l(:field_total_estimated_hours), :name => 'total_estimated_hours', :type => 'float' }
    common_fields << { :label => l(:label_spent_time), :name => 'spent_hours', :type => 'float', :readonly => true }
    common_fields << { :label => l(:label_total_spent_time), :name => 'total_spent_hours', :type => 'float', :readonly => true }
    common_fields << { :label => l(:field_done_ratio), :name => 'done_ratio', :type => 'integer' }
    common_fields << { :label => l(:field_description), :name => 'description', :type => 'string' }

    common_fields << { :label => l(:field_is_private), :name => 'is_private', :type => 'bool', :possible_values => bool_possible_values }
    common_fields << { :label => l(:field_created_on), :name => 'created_on', :type => 'datetime', :readonly => true }
    common_fields << { :label => l(:field_updated_on), :name => 'updated_on', :type => 'datetime', :readonly => true }
    common_fields << { :label => l(:field_closed_on), :name => 'closed_on', :type => 'datetime', :readonly => true }
    common_fields << { :label => l(:field_author), :name => 'author', :type => 'string', :readonly => true }
    common_fields << { :label => l(:field_last_updated_by), :name => 'last_updated_by', :type => 'string', :readonly => true }

    common_fields << { :label => l(:label_related_issues), :name => 'relations', :type => 'string', :relation_types => relation_types_list }
    #common_fields << {:name => l(:label_attachment), :name => 'attachment', :type => 'string'}

    custom_fields = CustomField.all().map do |cf|
      type_str = cf.field_format
      possible_values = cf.possible_values
      config_objects = nil

      if cf.field_format == 'list'
        type_str = 'string'
      elsif cf.field_format == 'bool'
        possible_values = bool_possible_values
      elsif cf.field_format == 'enumeration'
        possible_values = cf.enumerations.all.map { |i| i.name }
        config_objects = cf.enumerations
        type_str = 'string'
      elsif cf.field_format == 'user'
        config_objects = User
        type_str = 'string'
      end
      { :label => cf.name, :description => cf.description, :multiple => cf.multiple, :name => "cf_#{cf.id}", :type => type_str, :possible_values => possible_values, :config_objects => config_objects }
    end

    [common_fields, custom_fields].reduce([], :concat)
  end

  def relation_types_list
    relation_types = IssueRelation::TYPES
    relation_types.keys.sort { |x, y| relation_types[x][:order] <=> relation_types[y][:order] }.collect { |k| { :name => l(relation_types[k][:name]), :id => k } }
  end

  def load_field_setting_getter(field_settings)
    field_settings.each do |field_setting|
      if field_setting
        if field_setting[:config_objects]
          field_setting[:possible_objects] = field_setting[:config_objects].all().map { |v| { :id => v.id, :name => v.name } }
        end
      end
    end
  end

  def parse_field_value(issue_data, field_value, field_setting)
    value = nil
    if (not field_value.nil?) && field_value != @@NULL_STR
      if field_setting[:name] == 'relations'
        relation_values = []
        field_value.split(/\r?\n/).each do |relation_value|
          match_data = /^(.+)?\s+([#r]\d+)$/.match(relation_value)
          if match_data
            relation_type_name = match_data[1]
            to_id = match_data[2]

            relation_type = field_setting[:relation_types].find { |rt| rt[:name] == relation_type_name }

            if relation_type
              relation_value = { :relation_type => relation_type[:id] }
              if to_id.start_with?('#')
                relation_value[:to_id] = to_id[1..-1].to_i
              elsif to_id.start_with?('r')
                relation_value[:to_line_no] = to_id[1..-1].to_i
              end

              relation_values << relation_value
            end
          else
            match_data = /^(.+)?\s+([#r]\d+)\s*,\s*delay (\d+)$/.match(relation_value)
            if match_data
              relation_type_name = match_data[1]
              to_id = match_data[2]
              delay_day = match_data[3]

              relation_type = field_setting[:relation_types].find { |rt| rt[:name] == relation_type_name }
              if relation_type
                relation_value = { :relation_type => relation_type[:id], :delay => delay_day.to_i }
                if to_id.start_with?('#')
                  relation_value[:to_id] = to_id[1..-1].to_i
                elsif to_id.start_with?('r')
                  relation_value[:to_line_no] = to_id[1..-1].to_i
                end
                relation_values << relation_value
              end
            end
          end
        end
        unless relation_values.empty?
          value = relation_values
        end
      elsif field_setting[:possible_objects].present?
        if field_setting[:multiple]
          values = []
          invalid_values = []
          field_value.split(', ').select {|v| v && v.strip}.each do |v|
            fs = field_setting[:possible_objects].find { |po| po[:name] == v || po[:name] == v.strip }
            if fs
              values << fs[:id] unless values.include?(fs[:id])
            else
              invalid_values << v
            end
          end

          unless invalid_values.empty?
            return l(:error_value_not_available, invalid_values.join(', '))
          end

          value = values
        else
          fs = field_setting[:possible_objects].find { |po| po[:name] == field_value || po[:name] == field_value.strip }
          if fs
            value = fs[:id]
          else
            return l(:error_value_not_available, field_value)
          end
        end

      elsif field_setting[:possible_values].present?
        if field_setting[:multiple]
          values = []
          invalid_values = []
          field_value.split(', ').each do |v|
            pv = field_setting[:possible_values].find { |tv| tv == v || tv == v.strip }
            if pv
              values << pv unless values.include?(pv)
            else
              invalid_values << v
            end
          end

          unless invalid_values.empty?
            return l(:error_value_not_available, invalid_values.join(', '))
          end

          value = values
        else
          value = field_value
        end
      elsif field_setting[:type] == 'bool'
        value = field_value && field_value.strip.downcase == l(:general_text_Yes) ? true : false
      else
        value = field_value
      end
    end

    if value
      if field_setting[:type] == 'integer'
        value = value.to_i
      elsif field_setting[:type] == 'date' or field_setting[:type] == 'datetime'
        value = parse_oa_date(value)
      end
    end

    if field_setting[:name].start_with? 'cf_'
      if issue_data[:custom_field_values].present?
        custom_field_values = issue_data[:custom_field_values]
      else
        custom_field_values = {}
        issue_data[:custom_field_values] = custom_field_values
      end
      custom_field_values[field_setting[:name][3..-1].to_i] = value
    else
      if field_setting[:key]
        issue_data[field_setting[:key].to_sym] = value
      else
        issue_data[field_setting[:name].to_sym] = value
      end
    end

    return nil
  end

  def convert_issue_data(issue_data)
    unless @@used_sym
      issue_data2 = {}
      issue_data.each_pair do |key, value|
        issue_data2[key.to_s] = value
      end

      issue_data = issue_data2
    end

    return issue_data
  end

  def parse_oa_date(val)
    Time.at((val.to_i - 25569) * 24 * 3600).to_date
  end

  def date_format_ruby()
    Setting.date_format.blank? ? l('date.formats.default') : Setting.date_format
  end

  def date_format()
    format = date_format_ruby

    format = format.gsub(/%[dmYbB]/) do
      {'%d' => 'dd', '%m' => 'mm', '%Y' => 'yyyy', '%b' => 'mmm', '%B' => 'mmmm'}[$&]
    end

    format
  end

  def save_relation(relation_data)
    reverse_relation_if_needed(relation_data)

    relation = IssueRelation.where(:issue_from_id => relation_data[:from_id], :issue_to_id => relation_data[:to_id]).first

    if relation
      return relation if relation.relation_type == relation_data[:relation_type] && relation.delay == relation_data[:delay]

      relation.delay = relation_data[:delay]
      relation.relation_type = relation_data[:relation_type]
      relation.control_by_id = relation_data[:control_by_id]

      relation.save
    else
      relation = IssueRelation.new
      relation.issue_from_id = relation_data[:from_id]
      relation.issue_to_id = relation_data[:to_id]
      relation.relation_type = relation_data[:relation_type]
      relation.delay = relation_data[:delay]
      relation.control_by_id = relation_data[:control_by_id]

      relation.save
    end

    relation
  end

  def reverse_relation_if_needed(relation_data)
    relation_type = relation_data[:relation_type]
    if IssueRelation::TYPES.has_key?(relation_type) && IssueRelation::TYPES[relation_type][:reverse]
      tmp_to_id = relation_data[:to_id]
      relation_data[:to_id] = relation_data[:from_id]
      relation_data[:from_id] = tmp_to_id
      relation_data[:relation_type] = IssueRelation::TYPES[relation_type][:reverse]

    elsif relation_type == IssueRelation::TYPE_RELATES && relation_data[:from_id] > relation_data[:to_id]
      tmp_to_id = relation_data[:to_id]
      relation_data[:to_id] = relation_data[:from_id]
      relation_data[:from_id] = tmp_to_id
    end
  end

  def format_excel_relation(relations, issue_id)
    issue_relations = relations.select{|relation| relation.control_by_id == issue_id or ((not relation.control_by_id) and relation.issue_from_id == issue_id)}
    result = []
    issue_relations.each do |r|
      issue_to_id = r.issue_to_id
      relation_type = r.relation_type
      if r.issue_from_id != issue_id
        issue_to_id = r.issue_from_id
        IssueRelation::TYPES.each_key do |type|
          if IssueRelation::TYPES[type][:reverse] == relation_type
            relation_type = type
            break
          end
        end

      end

      result << {:to_id => issue_to_id, :relation_type => relation_type, :delay => r.delay}
    end

    result.to_json
  end

  def add_to_errors(errors, line_no, data)
    errors[line_no] = [] unless errors[line_no]

    errors[line_no] += data
  end

  def format_issue_value(column, item)
    value = column.value_object(item)
    if value.is_a?(Array)
      value.collect {|v| csv_value(column, item, v)}.compact.join(', ')
    else
      value_class_name = value.class.name

      if value_class_name == 'Date'
        return value.strftime(date_format_ruby)
      elsif value_class_name == 'CustomValue' or value_class_name == 'CustomFieldValue'
        if value.custom_field and value.custom_field.field_format == 'date'
          f = value.custom_field.format.formatted_custom_value(self, value, false)
          return f.strftime(date_format_ruby) if f
        end
      end

      csv_value(column, item, value)
    end
  end
end
