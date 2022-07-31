# redmine_excel_connector

![Redmine Excel Connector](https://conveniencable.github.io/images/after_loaded.png)


## Features
* After login to Redmine on Excel, only operations allowed by current Redmine user permissions are visible or executable.
* Custom row index for head row and column index for every column to be compatible with various excel template.
* Filters to load issues to Excel, or just load new changes from Redmine to update the current excel rows, by Redmine ID(#).
* Save modified issues on Excel to redmine, history for every issue will be generated, same as saving from web.

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
