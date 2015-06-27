Sequel.migration do

  # http://obfuscurity.com/2011/11/Sequel-Migrations-on-Heroku

  change do

    create_table(:bookmarks, :ignore_index_errors => true) do
      primary_key :id

      String      :url,           :size => 255, :null => false
      String      :title,         :size => 100, :null => false
      String      :description,   :default => "", :size => 2000
      String      :tags,          :default => "", :size => 255
      DateTime    :create_at,     :default => Sequel::CURRENT_TIMESTAMP

      index [:url], :name => :ux_bookmarks_url, :unique => true
    end

    create_table(:workdays, :ignore_index_errors => true) do
      primary_key :id

      DateTime    :date,          :null => false
      String      :am_start,      :size => 5
      String      :am_end,        :size => 5
      String      :pm_start,      :size => 5
      String      :pm_end,        :size => 5
      Integer     :hours,         :default => 0
      String      :detail,        :text => true
      Integer     :duration,      :default => 0

      index [:date], :name => :ux_workdays_date, :unique => true
    end

  end

end
