class CreateUsers < ActiveRecord::Migration[5.2]
  def change
    create_table :users do |t|
      t.string :user_id,          null: false, unique: true
      t.string :official_title,   null: false, default: 'emotime'
      t.integer :resending_point
      t.integer :replay_point
      t.string :file_id

      t.timestamps
    end
  end
end
