get '/redmine_excel_connector' => 'redmine_excel_connector#index', as: 'redmine_excel_connector'
get '/redmine_excel_connector/api/test' => 'redmine_excel_connector#test'
post '/redmine_excel_connector/api/logged_in' => 'redmine_excel_connector#logged_in'
post '/redmine_excel_connector/api/logged_out' => 'redmine_excel_connector#logged_out'
get '/redmine_excel_connector/api/query_settings' => 'redmine_excel_connector#query_settings'
get '/redmine_excel_connector/api/queries' => 'redmine_excel_connector#queries'
get '/redmine_excel_connector/api/filter_values' => 'redmine_excel_connector#filter_values'
get '/redmine_excel_connector/api/issues' => 'redmine_excel_connector#issues'
post '/redmine_excel_connector/api/issues' => 'redmine_excel_connector#save_issues'
post '/redmine_excel_connector/api/after_load_issue' => 'redmine_excel_connector#after_load_issue'

get '/redmine_excel_connector/*react_path' => 'redmine_excel_connector#index'