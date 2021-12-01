Redmine::Plugin.register :redmine_excel_connector do
  name 'Redmine Excel Connector plugin'
  author 'Li Chan'
  description 'This is a plugin for Redmine'
  version '0.0.1'
  url 'https://github.com/conveniencable/redmine_excel_connector'
  author_url 'https://github.com/conveniencable'


  settings :default => {
  }, :partial => 'settings/redmine_excel_index.html.erb'
end
