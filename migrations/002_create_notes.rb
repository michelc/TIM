Sequel.migration do

  change do

    create_table(:notes, :ignore_index_errors => true) do
      primary_key :id

      String      :title,         :size => 100, :null => false
      String      :content,       :text => true
      String      :tags,          :default => "", :size => 255
      DateTime    :create_at,     :default => Sequel::CURRENT_TIMESTAMP
    end

  end

end
