# redmine_excel_connector


## How to install
* cd your_redmine_installation_dir/plugins
* git clone -b main https://github.com/conveniencable/redmine_excel_connector
* bundle exec rake redmine:plugins:migrate RAILS_ENV=production  
* Restart Redmine

## How to use
please go to https://conveniencable.com/documents/excel/start


## Source code
The code in assets/react-dist is generate from another project which is written by Typescript + React: https://github.com/conveniencable/redmine-excel-react-app

When you run this plugin in development mode for debuging, you must change the configs/webpack/redmine_excel_connector to link to your_redmine_dir/plugins/redmine_excel_connector, which is normally in WSL or a remote linux.
