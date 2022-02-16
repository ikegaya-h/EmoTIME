class AddVerificationPointToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :verification_point, :integer
  end
end
