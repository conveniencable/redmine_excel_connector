Redmine::Plugin.register :redmine_excel_connector do
  name 'Redmine Excel Connector plugin'
  author 'Li Chan'
  description 'This is a plugin for Excel to connect to a Redmine'
  version '1.0.6'
  url 'https://github.com/conveniencable/redmine_excel_connector'
  author_url 'https://conveniencable.com'


  settings :default => {
  }, :partial => 'settings/redmine_excel_index.html.erb'
end
