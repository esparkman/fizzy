class AddParentIdToCards < ActiveRecord::Migration[8.2]
  def change
    add_reference :cards, :parent, type: :uuid, null: true, index: false
    add_index :cards, :parent_id
    add_index :cards, [ :board_id, :parent_id ]
  end
end
