class AddRoadmapViewToUserSettings < ActiveRecord::Migration[8.2]
  def change
    add_column :user_settings, :roadmap_view, :string, null: false, default: "list"
  end
end
