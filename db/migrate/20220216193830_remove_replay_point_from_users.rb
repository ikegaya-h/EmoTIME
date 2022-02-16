class RemoveReplayPointFromUsers < ActiveRecord::Migration[5.2]
  def change
    remove_column :users, :replay_point, :integer
  end
end
